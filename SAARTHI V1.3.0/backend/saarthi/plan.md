# Plan — implementing methodology.md

Source: [methodology.md](methodology.md). Three asks:
1. Load `fixed_tasks.json` into real calendar blocks, placed **before** any scoring/scheduling work happens.
2. Score only *after* fixed tasks are placed (avoid wasted ML scoring on slots that are already blocked).
3. Adaptive slot resolution — fine-grained (15 min) grid on packed days, coarse (60 min) grid on open days, to cut solver search space.

Also folds in the already-diagnosed CP-SAT `add_element` fix (see prior conversation) since it touches the same file (`packer.py`) as change #3 — doing them together avoids a second pass through the solver internals.

---

## Current state (for reference)

- `fixed_tasks.json` exists but **nothing reads it yet** — only `services/cpsat_bridge.py:load_fixed_events()` pulls fixed events, and only from the DB (`scheduled_slots` table). The json file is dead data right now.
- Ordering today (`cpsat_bridge.run_cpsat_schedule`): load DB fixed events → `set_calendar()` (computes free windows) → add tasks → **compute slot scores** → `_replan()`. So DB-based fixed events are already placed before scoring — the gap is specifically the json file never entering this pipeline.
- `grid_minutes` is a single global constant (`config.py`) used uniformly across the whole horizon in `packer.py`'s `to_slot`/`from_slot` — there's no notion of "this day is busier, use a finer grid."

---

## Change 1 — Load `fixed_tasks.json` as recurring weekly blocks

**New file:** `saarthi/fixed_tasks_loader.py`

- Parse `fixed_tasks.json` (`Day`, `Start`, `End`, `Task` columns).
- Map `Day` (Monday…Friday) → Python weekday index.
- Given a `horizon_start`/`horizon_end`, expand each row into concrete `FixedEvent` instances for every matching weekday inside the horizon (recurs weekly — a Monday 08:50–09:40 class becomes one `FixedEvent` per Monday in the horizon window).
- Return `list[FixedEvent]`, same type already used by `calendar_.compute_free_windows`.

**Open question for you:** should this loader live in `saarthi/` (engine-side, framework-agnostic) or `services/` (since it's AURA-specific data)? I'd lean `saarthi/` since it's pure calendar logic with no DB/ORM dependency — keeps `saarthi` reusable/testable standalone (matches how `calendar_.py` and `chunker.py` are already structured).

## Change 2 — Merge json fixed events into the pipeline, before scoring

**File:** `services/cpsat_bridge.py`

- In `run_cpsat_schedule`, call the new loader alongside `load_fixed_events(user_id, db)` and merge the two lists before `scheduler.set_calendar(...)`.
- No reordering needed beyond that — scoring (`compute_slot_scores`) already runs after `set_calendar()`/`add_task()`, so once json events are merged into `fixed_events`, they're automatically excluded from `free_windows` before any ML scoring happens. This satisfies methodology point 2 for free.
- Add a config flag (e.g. `use_fixed_tasks_json: bool`) so this can be toggled/tested independently of DB-based events, and a path override so `fixed_tasks.json`'s location isn't hardcoded relative to cwd.

## Change 3 — Adaptive slot resolution

This is the largest change and has two viable depths — recommend doing Phase A first, and only going to Phase B if Phase A's solve times aren't good enough in practice.

### Phase A (simpler): one global grid, chosen from overall free-time density
- **File:** `services/cpsat_bridge.py` (or `saarthi/scheduler.py`) — before calling `pack()`, compute average free hours/day across the horizon from the already-computed `free_windows`, and pick `grid_minutes` (15 vs 60, or a small tiered table) once for the whole run.
- **File:** `saarthi/config.py` — replace the hardcoded `grid_minutes: int = 15` default with this computed value passed in per-run (keep the field, just stop treating it as fixed).
- Low risk, small diff, but doesn't help a horizon that mixes one packed day with several open days — coarse grid still applies everywhere or fine grid still applies everywhere.

### Phase B (matches methodology.md literally): per-day resolution
- **File:** `saarthi/packer.py` — `to_slot`/`from_slot` currently assume a uniform step size (`grid_minutes`) for the entire horizon. To let Monday use 15-min slots and Tuesday use 60-min slots, these need to become lookups against a **non-uniform slot table**: a precomputed sorted list of slot-boundary datetimes (fine-grained inside busy days, coarse inside open days), with `to_slot`/`from_slot` doing a bisect into that table instead of arithmetic division.
- **File:** `saarthi/calendar_.py` — `compute_free_windows` would need to tag each `FreeWindow` (or each day) with its chosen resolution, likely by first computing free hours per calendar day (from fixed events alone, before touching chunks), then building the slot table.
- **File:** `saarthi/config.py` — add the density thresholds as config (e.g. `dense_day_threshold_hours: int = 8`, `dense_grid_minutes: int = 15`, `sparse_grid_minutes: int = 60`), replacing the single `grid_minutes` field.
- **File:** `saarthi/chunker.py` — `dur_slots`/`brk_slots` conversions in `packer.py` (lines 67-68) currently assume 1 slot = `GRID` minutes uniformly; with a non-uniform table, "how many slots does a 90-minute chunk occupy starting here" depends on *where* it starts, which complicates `new_optional_interval_var` sizing (CP-SAT interval lengths need to be fixed integers, not resolution-dependent). This needs a careful design pass — likely working entirely in **minutes** as the CP-SAT unit instead of "slots" (a much bigger refactor), or restricting variable resolution to whole free-window boundaries only (each window is uniformly fine or uniformly coarse, chunks don't span a resolution change). I'd want to lock down this design with you before writing code — it's the one piece with real ambiguity.

## Change 4 — CP-SAT `add_element` fix (from the earlier bug)

**File:** `saarthi/packer.py`, objective section (`build_objective`, currently ~line 218-260)

- Replace the per-chunk dense `add_element` slot-quality lookup with sparse boolean start-literals (drafted already as `packer_v2.py`, not yet merged): one bool per *allowed* start slot, `start = Σ s·literal(s)`, quality bonus = `Σ score(s)·literal(s)`.
- This directly benefits Change 3 too — fewer/coarser slots per day (Phase A or B) shrinks the boolean-literal count further, compounding the speedup.
- Recommend doing this **before** Change 3, since it's already diagnosed, isolated, and benchmarked (3s timeout/0 scheduled → ~9s/OPTIMAL at 60s limit; sparse version should resolve well inside the 3s budget even before any grid changes).

---

## Suggested order of implementation

1. **Change 4** (packer.py `add_element` → sparse literals) — standalone, already validated, unblocks correct scheduling today regardless of the other changes.
2. **Change 1 + 2** (fixed_tasks.json loader + merge into bridge) — standalone, no dependency on solver internals.
3. **Change 3 Phase A** (global adaptive grid) — quick win, layers cleanly on top of 1/2/4.
4. **Change 3 Phase B** (per-day resolution) — only after A ships and you've seen whether A's solve times are good enough; needs the design decision above locked down first.

## Files touched (summary)

| File | Changes |
|---|---|
| `saarthi/fixed_tasks_loader.py` | **new** — parses & expands `fixed_tasks.json` |
| `saarthi/packer.py` | sparse quality objective (4); non-uniform `to_slot`/`from_slot` (3B) |
| `saarthi/calendar_.py` | per-day free-hours computation + resolution tagging (3B) |
| `saarthi/config.py` | replace fixed `grid_minutes` with density-based thresholds (3A/3B) |
| `saarthi/chunker.py` | possible rework if switching slot↔minutes accounting (3B) |
| `services/cpsat_bridge.py` | merge json fixed events before `set_calendar()` (1/2); compute adaptive grid before `pack()` (3A) |

Nothing here is implemented yet — flagging for your review before I start writing code, especially the Phase B design question in Change 3.
