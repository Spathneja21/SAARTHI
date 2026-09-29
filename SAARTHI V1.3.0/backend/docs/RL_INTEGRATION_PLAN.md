# RL Integration — Phase 0 (done) and Phase 1 (core built)

Companion to `PIPELINE.md` and (if you have it) `RL_APPROACHES.md`, which has the full
mathematical derivation for everything summarized here. This file exists to be
self-contained even without that document on hand.

**Goal:** replace AURA's hand-tuned slot-scoring weights with a policy that learns from
how a specific user actually behaves — a contextual bandit, not full reinforcement
learning (see "Why a bandit, not an MDP" below).

**Status at a glance:**

| Phase | Scope | State |
|---|---|---|
| 0 | Fix the data pipe so the RL loop receives real signal | ✅ done (the `/move` half landed with Phase 1 — see below) |
| 1 | Replace the tabular bias with Thompson Sampling | 🔨 policy built, wired and unit-tested; evaluation not started |

---

## Why Phase 0 came first

The scaffold for learning already existed — a `SlotPreferenceFeedback` table, a Celery
job (`update_rl_rewards`), and a consumer (`get_user_slot_preference_bias`) — but it
could not learn anything. Checked against the live database before any of this work:

```
users: 4        tasks: 1 (still draft)      slot_preference_feedback: 0 rows
task_events: 1  scheduled_slots: 1
```

Zero feedback rows, and the one task never left `draft`. Writing a bandit against this
would train on nothing. Phase 0 is entirely about making the existing loop actually
produce data — no new algorithm, just fixing five ways the instrumentation was broken.

---

## Phase 0 — done

Commits `9cf17f8`, `a98e446`/`bbabd61` (parallel fix by a teammate, reconciled),
`30c23bd`, `ed233a0`. The `main.py` half of #2 and all of #3 were listed here as commit
`ce21696`, but that commit never reached the repository — `main.py` on `main` still
inserted a second `was_kept=False` row at the moved-to hour. It was implemented as step
1 of Phase 1, since Phase 1 trains directly on those rows.

### 1. Planning never marked a task as scheduled

**File:** `services/cpsat_bridge.py`, `save_assignments`

**What:** After CP-SAT places a task and its slot is committed, the task is now
transitioned to `SCHEDULED` via the existing `task_service.transition_task` (so it also
gets the `TaskEvent` log row and the `reschedule_count` side effect for free). A task
that was fully dropped by the solver keeps its current status, so it's retried on the
next plan.

**Why:** Without this, a scheduled task stayed `draft` forever. No task ever reached a
terminal status (`completed`/`abandoned`), so `update_rl_rewards` had no outcome to
score, period — this was reason 5 of "why the loop can't learn."

### 2. The only feedback row ever created was a rejection

**Files:** `services/cpsat_bridge.py` (`save_assignments`), `main.py`
(`/schedule/preference/move`)

**What:** `save_assignments` now inserts a `SlotPreferenceFeedback` row for *every*
slot CP-SAT places — `was_kept=True` by default, `suggested_score` filled with the
real computed behavioral score (previously hardcoded `0.0` with a comment saying "will
be filled by RL trainer" — nothing ever filled it). `/schedule/preference/move` now
looks up that existing row (by `task_id` + `suggested_start`, which match exactly) and
flips it to `was_kept=False`, instead of always inserting a brand-new row.

**Why:** The only site that ever created a feedback row was the move endpoint, with
`was_kept=False` hardcoded. The dataset was 100% negative by construction — the reward
job's positive branches were dead code.

### 3. The reward was credited to the wrong hour

**File:** `main.py`, `/schedule/preference/move` (same edit as #2)

**What:** `hour_of_day` on the feedback row is no longer overwritten by `/move`. It
keeps the value set when the slot was first suggested (`assignment.start.hour`).

**Why:** The old code stored `new_start.hour` — the hour the user moved *to*. Rejecting
a 14:00 suggestion in favor of 09:00 credited the rejection to 09:00, i.e. exactly
backwards. A learner trained on this would learn to avoid the hours the user actually
prefers.

### 4. Rewards froze before the outcome was known

**File:** `workers/tasks.py`, `update_rl_rewards`

**What:** A reward is now written only when `task.status` is `COMPLETED` or
`ABANDONED`. Any other status is skipped (`continue`), leaving `reward` as `NULL` so
the row is re-evaluated on the next run. The four reward values from the original
design are preserved, just correctly gated:

```
COMPLETED & kept AURA's slot     → +20
COMPLETED & moved, still done    → +10
ABANDONED & kept AURA's slot     →  -5
ABANDONED & moved (rescheduled)  → -10
```

**Why:** The job runs nightly and selects `WHERE reward IS NULL`, never revisiting a
scored row. The old code assigned `-5` to any moved-but-unresolved task the moment it
was checked — usually hours after the move, long before the task had a chance to be
completed or abandoned. Almost every moved-slot row froze at `-5` before its real
outcome existed.

### 5. A negative learned bias could make a free slot unusable

**File:** `services/cpsat_bridge.py`, `compute_slot_scores`

**What:** The blended per-hour score — `0.35·energy_match + 0.30·completion_prob +
0.20·(1-procrastination_risk) + 0.15·rl_bias` — is now affine-remapped from its true
range `[-0.15, 1.00]` onto `[0, 100]`, instead of just being multiplied by 100.

**Why:** `rl_bias` (the per-hour learned preference) ranges over `[-1, 1]`, unlike the
other three terms which are each in `[0, 1]`. The blend can therefore go negative. That
value feeds `saarthi/packer.py`, which declares the CP-SAT quality variable as
`new_int_var(0, max_score, ...)` — a variable with a lower bound of 0 — and constrains
it to *equal* the score via `add_element`. A negative score makes that equation
infeasible, so any hour that blends negative doesn't just score low, it becomes an
**unusable start for that chunk**, even on an otherwise free slot. Remapping (rather
than clipping to 0) preserves the ordering between a "slightly bad" hour and a "very
bad" one, which clipping would destroy — the whole point of the learned signal.

---

## Data now flowing

With #1 in place, tasks actually resolve. With #2–3, every AI-placed slot logs a real
`SlotPreferenceFeedback` row with the correct suggested hour and score, updated (not
duplicated) if the user moves it. With #4, that row's `reward` is only ever set once
its true outcome exists. This is the prerequisite for everything in Phase 1 — a week
of real usage should now produce inspectable rows in `slot_preference_feedback` with
non-null rewards.

---

## Phase 1 — design

**Question the policy answers:** given this kind of task, what time of day does this
particular user actually do it?

### Why a bandit, not an MDP

Scheduling looks sequential (today's placement changes tomorrow's calendar), but:

- CP-SAT — an exact solver — handles all state transitions (overlaps, deadlines,
  ordering). The learner never predicts consequences of an action; it only answers a
  preference question, which is contextual, not sequential.
- The horizon is short (7 days) and re-planned from scratch each run — weak coupling
  across days.
- **Sample complexity is decisive.** A single user generates on the order of 10²
  observations/month. Deep RL (DQN/PPO) needs 10⁵–10⁶ samples. A linear contextual
  bandit needs 10¹–10². Anything heavier is off by 3–4 orders of magnitude for this
  data rate.

### Algorithm: Bayesian linear Thompson Sampling

- **Feature map** — a Fourier basis over hour-of-day (not a 24-way one-hot):
  `[1, sin(2πh/24), cos(2πh/24), sin(4πh/24), cos(4πh/24), is_weekend, ...,
  onehot(category), energy_requirement]` — roughly 12 dimensions. A one-hot needs ~72
  samples (24 hours × 3 minimum each) before it says anything, learned independently
  per hour. The Fourier basis generalizes across adjacent hours and wraps correctly
  at midnight, and needs only ~30 samples.
- **Posterior** — conjugate Bayesian linear regression on the *residual* reward
  (prior mean zero): closed-form rank-1 update, `A ← A + φφᵀ`, `b ← b + φr`. Cheap
  enough to refit nightly rather than maintain incrementally. A daily discount
  (`γ ≈ 0.98`) lets old preferences fade (~50-day effective window) since chronotypes
  drift over a semester.
- **Design principle — residual-on-heuristic:**
  `score(a|x) = current_heuristic(a|x) + κ · learned_residual(a|x)`, with the residual
  having prior mean zero. At `n=0` this reproduces today's behavior exactly (cold
  start solved for free), `κ=0` is a kill switch back to the pre-RL scheduler, and a
  missing/erroring model just returns a zero residual.
- **Action selection** — one posterior sample per *scheduling run* (not per slot), so
  a single day's plan is internally consistent rather than acting on contradictory
  hypotheses about adjacent hours.
- **Integration point** — a new function with the identical signature and return type
  as the thing it replaces:
  `sample_bias(user_id, context, db) -> dict[int, float]`, matching
  `get_user_slot_preference_bias`'s current signature, so `compute_slot_scores`
  changes by one line and nothing else in the pipeline needs to move.

### Prerequisite this design calls out explicitly

Thompson Sampling's `rl_bias` output stays in `[-1, 1]`, same as today's tabular
version — so Phase 0 change #5 (the affine remap) is a hard prerequisite, not
optional, before this ships. Without it, increasing κ beyond a small value makes the
infeasible-slot bug bite harder, not just occasionally.

### Open decision — not yet made

How to evaluate this without real usage data yet:

- **A. Build a synthetic-user simulator** (trait vector: chronotype offset,
  procrastination probability, estimation bias, volatility, drift) and report
  cumulative regret against baselines. Gives a real regret curve and lets you ablate
  design choices (Fourier vs one-hot, TS vs UCB, decay on/off) — the strongest
  evidence available this semester. Costs a few hundred lines and comes with real
  limitations to state honestly (train/serve hour mismatch inherited from
  `ml_features.py`, domain gap from the training dataset, open-loop simulated users).
- **B. Run it on yourself for real**, `n=1`, and present it as a single-case ABAB
  design (policy on/off in week-long blocks, interrupted time series) — honest about
  what `n=1` can and can't support, but only as strong as the weeks you actually log.

Recommendation stands at: do both, simulator for the regret-curve evidence, real usage
in parallel once Phase 0's data starts accumulating — but this needs a decision before
Phase 1 code gets written.

---

## Phase 1 — built so far

| Step | What | Files |
|---|---|---|
| 1 | Missing Phase 0 `/move` fix: flip the existing row, keep the suggested hour | `main.py` |
| 2 | Thompson-sampling policy: features, posterior, sampling (pure numpy, no DB) | `ml/slot_bandit.py` (new) |
| 3 | Unit tests: contract, learning, credit assignment, sampler correctness | `test_slot_bandit.py` (new) |
| 4 | Wired in: `sample_slot_policy` replaces `get_user_slot_preference_bias` | `services/cpsat_bridge.py` |
| 5 | Docs + kill switch: `RL_KAPPA` env var | `PIPELINE.md`, `.env.example` |

### Where the build refines the design, and why

- **Hour × energy interaction (17 dims, not ~12).** The planned features are purely
  additive. An additive model gives every task the *same* hour curve, and category and
  energy only move its level, so it cannot answer "given this kind of task, what time?"
  Adding `energy · harmonics(h)` (4 terms) lets demanding and light tasks have
  different curves. Hour × category would cost 24 terms, too many for ~100 rows/month.
- **Context terms are controls, left out of the output.** Intercept, `is_weekend`,
  category and energy soak up base rates, so a category that is finished less often and
  usually lands in the evening doesn't teach "evenings are bad". They're excluded from
  `rl_bias` because they shift every hour of a task equally. Inside CP-SAT, that would
  only change *which task* gets dropped, and learning task priority is out of scope.
  This also answers how `is_weekend` fits a bias keyed by hour alone: it's a control.
- **One draw per run, split into two calls.** The planned
  `sample_bias(user_id, context, db)` would draw once per task. It's now
  `sample_slot_policy(user_id, db)` (one draw per run) plus `policy.bias(energy)` (per
  task, pure). `compute_slot_scores` is unchanged; its caller changes by one argument.
- **Credit only the plan the user acted on.** Every "plan my day" re-places every
  pending task and logs new rows, and `update_rl_rewards` credits them all with the
  final outcome. So a task re-planned from 20:00 to 09:00 and then finished would credit
  20:00 too. Training keeps only each task's latest run (rows share `created_at`) and
  gives a task's k chunks weight 1/k each, so one outcome counts once.
- **Refit per plan, not nightly.** Rewards only change nightly, but the fit takes about
  6 ms for 600 rows, so refitting on each call avoids a stored-model table, a migration
  (there's no Alembic) and a new Celery job. It's the same one query per plan that the
  tabular version made.
- **Cold start is exploration, not a no-op.** Only the posterior *mean* is exactly zero
  at n=0. A Thompson draw from the prior is not zero, and that draw is the exploration.
  With `HOUR_PRIOR_STD = 0.25`, a no-data draw's most-moved hour sits around ±0.55 for
  medium-energy tasks and ±0.75 for very_low/peak, about 7–10 slot-score points out of
  100. For a no-op before data exists, use `RL_KAPPA=0`.

### Starting hyperparameters (untuned; tuning is what evaluation is for)

`HOUR_PRIOR_STD=0.25`, `CONTEXT_PRIOR_STD=1.0`, `NOISE_VAR=0.25`, `DAILY_DISCOUNT=0.98`,
`REWARD_SCALE=20`, `RL_KAPPA=1.0`. `HOUR_PRIOR_STD` is the main knob: it sets both the
cold-start exploration size and how many resolved tasks it takes to override the
heuristic (about 10 for the main curve).

### One-time cleanup before trusting the model

Any `/move` made before step 1 inserted an extra row with the wrong hour and left the
original counted as kept. Those rows are the only ones with `suggested_score = 0`, since
`save_assignments` always writes a real score (≥ 5). Check first:

```sql
SELECT count(*) FROM slot_preference_feedback WHERE suggested_score = 0 AND was_kept = false;
```

If non-zero, move each legacy move onto its original row, reset that row's reward so
the nightly job rescores it, and then delete the legacy rows:

```sql
UPDATE slot_preference_feedback AS orig
   SET was_kept = false, user_chosen_start = legacy.user_chosen_start,
       reward = NULL, was_completed = NULL
  FROM slot_preference_feedback AS legacy
 WHERE legacy.suggested_score = 0 AND legacy.was_kept = false
   AND orig.id <> legacy.id
   AND orig.task_id = legacy.task_id
   AND orig.suggested_start = legacy.suggested_start;

DELETE FROM slot_preference_feedback WHERE suggested_score = 0 AND was_kept = false;
```

### Verified

- `python test_slot_bandit.py`: 14 tests. Covers the [-1, 1] contract, zero at cold
  start and under the kill switch, learning a chronotype, generalising to an unseen
  neighbouring hour, energy-dependent curves, uniform success teaching no hour
  preference, latest-run credit, 1/k chunk weights, discount half-life, uncertainty
  shrinking, and sampled spread matching the exact posterior covariance.
- Smoke test of `sample_slot_policy`'s real query against the ORM tables on in-memory
  SQLite (Postgres and OR-Tools weren't available). Checks the join, reward and user
  filters, a learned morning preference raising `compute_slot_scores` at 10:00 (70→82),
  and `RL_KAPPA=0` short-circuiting without a query.
- **Written, not yet run** (needs Postgres + OR-Tools): `test_rl_loop.py`, the whole
  loop end to end against the dev DB. Plan → feedback rows → move (twice, plus a
  hand-booked slot) → resolve → the real `update_rl_rewards` job → the policy's training
  rows and fit. It runs under a throwaway user and cleans up, like `test_replan.py`.

### Next

The evaluation decision above (simulator, n=1 ABAB, or both) is still open. `RL_KAPPA`
already supports the ABAB on/off blocks without code changes.

---

## Not touched in this pass, deliberately

- **Nudge selection and focus-limit length** — designed but explicitly deferred (no
  biometric data source for nudges; focus-limit rewards arrive too rarely per week to
  converge this semester). Design sketches exist for both if a data source appears.
- **Learning the CP-SAT objective weights themselves** (`w_schedule`, `w_overrun`,
  `w_slot_quality`, ...) — explicitly out of scope. `w_slot_quality` can already
  outweigh `w_overrun` by the equivalent of 12.5 hours of deadline overrun; a learned
  controller over these weights would start missing deadlines before it learned
  anything, with the "you missed a deadline" signal arriving days later — a genuinely
  hard credit-assignment problem, not a phase of work. Fixing the ratio by hand is a
  one-line change and was flagged separately, not yet done.
