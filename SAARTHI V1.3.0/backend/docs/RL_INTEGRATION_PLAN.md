# RL Integration — Phase 0 (done) and Phase 1 (planned)

Companion to `PIPELINE.md` and (if you have it) `RL_APPROACHES.md`, which has the full
mathematical derivation for everything summarized here. This file exists to be
self-contained even without that document on hand.

**Goal:** replace AURA's hand-tuned slot-scoring weights with a policy that learns from
how a specific user actually behaves — a contextual bandit, not full reinforcement
learning (see "Why a bandit, not an MDP" below).

**Status at a glance:**

| Phase | Scope | State |
|---|---|---|
| 0 | Fix the data pipe so the RL loop receives real signal | ✅ done, on `main` |
| 1 | Replace the tabular bias with Thompson Sampling | ⏳ not started — design only |

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

All five changes are on `main` (commits `ce21696`, `a98e446`/`bbabd61` (parallel fix by
a teammate, reconciled), `30c23bd`, `ed233a0`).

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

## Phase 1 — planned, not yet built

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
