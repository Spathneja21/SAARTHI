"""
Thompson-sampling slot preference: Phase 1 of docs/RL_INTEGRATION_PLAN.md.

Answers one question: given this kind of task, at which hours does this user
actually follow through? It replaces the tabular per-hour average cpsat_bridge
used to compute (avg(reward)/20 per hour, silent until an hour had 3 samples)
with Bayesian linear regression over a smooth hour-of-day basis, so evidence at
10:00 also informs 09:00 and 11:00, and the posterior's own uncertainty decides
how much to explore.

Pure numpy, no DB or solver imports: cpsat_bridge loads the observations, this
module turns them into a per-hour bias. That keeps it testable without Postgres
or OR-Tools, and importable by an offline simulator.

Output contract, the same as the tabular version it replaces:
    {hour: bias}, bias in [-1, 1], 0 meaning "no learned opinion".
compute_slot_scores' affine remap (Phase 0, change #5) is built on that range.
"""
from __future__ import annotations

import math
from collections import Counter
from collections.abc import Hashable, Iterable
from dataclasses import dataclass
from datetime import datetime

import numpy as np


# ── Feature map ──────────────────────────────────────────────────────────────
#
#   [ 1, is_weekend, onehot(category) x6, energy,      context: 9 terms
#     harmonics(h) x4, energy * harmonics(h) x4 ]      hour-dependent: 8 terms
#
# Only the hour-dependent terms become the bias. The context terms are control
# variables: they soak up this user's base completion rate, their weekend rate
# and per-category rates, so those don't leak into the hour curve. Without them,
# a category that is both finished less often and usually scheduled in the
# evening would teach the model that evenings are bad. They are left out of the
# bias because they shift every hour of a task equally, which says nothing about
# time of day; inside CP-SAT they would instead change which *task* gets dropped
# under a full calendar, and learning task priority is out of scope for Phase 1.
#
# The energy x harmonics block is what lets the hour curve differ by kind of
# task. Without an interaction, every task gets the same hour curve and
# category/energy only move its level.

CATEGORIES = ("deep_work", "admin", "learning", "meeting", "personal", "health")

# Energy requirements run 0.2 (very_low) .. 1.0 (peak). Centring on medium and
# scaling to [-1, 1] puts their coefficients on the same footing as the others.
ENERGY_CENTER     = 0.6
ENERGY_HALF_RANGE = 0.4

N_CONTEXT = 3 + len(CATEGORIES)          # intercept, weekend, categories, energy
N_HOUR    = 8
D         = N_CONTEXT + N_HOUR
HOUR_TERMS = slice(N_CONTEXT, D)


def _harmonics(hour: float) -> np.ndarray:
    """First two Fourier harmonics of the 24h day.

    Periodic, so 23:00 and 00:00 are neighbours rather than opposite ends of a
    one-hot, and 4 numbers describe a whole day's curve instead of 24
    independent ones. Two harmonics allow up to two peaks (e.g. morning and
    late evening), which is about as much shape as ~100 rows a month supports.
    """
    angle = 2 * math.pi * hour / 24
    return np.array([
        math.sin(angle),     math.cos(angle),
        math.sin(2 * angle), math.cos(2 * angle),
    ])


def _scaled_energy(energy: float) -> float:
    return (energy - ENERGY_CENTER) / ENERGY_HALF_RANGE


def _hour_terms(hour: float, energy: float) -> np.ndarray:
    h = _harmonics(hour)
    return np.concatenate([h, _scaled_energy(energy) * h])


def features(hour: float, weekday: int, category: str, energy: float) -> np.ndarray:
    """φ(context, hour): the full D-dimensional feature vector for one slot."""
    category_onehot = [1.0 if category == c else 0.0 for c in CATEGORIES]
    context = [1.0, 1.0 if weekday >= 5 else 0.0, *category_onehot, _scaled_energy(energy)]
    return np.concatenate([context, _hour_terms(hour, energy)])


# ── Priors and constants ─────────────────────────────────────────────────────
# Starting values, not tuned yet; the evaluation step in the plan exists to tune
# them.

# +20 (kept and completed, the best outcome) maps to 1.0, as in the tabular
# version, so both put the bias on the same scale.
REWARD_SCALE = 20.0

# Scaled rewards take four values (1, 0.5, -0.25, -0.5). Their variance for a
# user who finishes most tasks is around 0.3; 0.25 treats one row as noisy
# evidence, not a verdict.
NOISE_VAR = 0.25

# Context terms get a wide prior so they absorb base rates easily. Hour terms
# get a narrow one: time of day is assumed to be a modest correction to the
# heuristic until the data says otherwise.
#
# HOUR_PRIOR_STD is also the cold-start exploration budget, since with no data
# Thompson sampling draws from the prior: only the posterior *mean* is exactly
# zero at n=0, not a draw. Per hour, a no-data draw has std 0.35 (0.5 for
# very_low/peak tasks); across a whole day, the most-moved hour typically sits
# around +/-0.55 (+/-0.75), i.e. 7-10 points of slot score out of 100. About ten
# resolved tasks outweigh this prior on the main hour curve; the energy
# interaction needs more, as only tasks away from medium energy inform it.
CONTEXT_PRIOR_STD = 1.0
HOUR_PRIOR_STD    = 0.25
PRIOR_VAR = np.array([CONTEXT_PRIOR_STD ** 2] * N_CONTEXT + [HOUR_PRIOR_STD ** 2] * N_HOUR)

# Per-day weight decay: evidence 34 days old counts half, ~50-day effective
# window. Chronotypes drift over a semester (exam weeks, a new timetable).
DAILY_DISCOUNT = 0.98


# ── Training data ────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Observation:
    """One rewarded SlotPreferenceFeedback row, joined to its task."""
    task_id  : Hashable
    run_at   : datetime   # created_at, shared by every row one planning run wrote
    hour     : int        # the hour AURA suggested, not where the user moved it
    weekday  : int        # 0 = Monday
    category : str
    energy   : float      # ENERGY_REQUIREMENT value, 0.2 .. 1.0
    reward   : float      # update_rl_rewards' raw reward: +20 / +10 / -5 / -10


def weight_observations(
    observations: Iterable[Observation],
) -> list[tuple[Observation, float]]:
    """Keep only the suggestions an outcome actually judged, one unit per task.

    Every "plan my day" re-places every pending task and logs a fresh row for
    each, so a task re-planned three times before it is done has three rows at
    up to three different hours, and update_rl_rewards credits all three with
    the one outcome. Only the last plan before the outcome is the one the user
    acted on; the earlier ones were replaced by the scheduler, not judged by the
    user. So only each task's latest run is kept.

    A chunked task leaves one row per chunk in that run, all sharing one
    outcome. Each gets weight 1/k, so a task split in three doesn't count as
    three times the evidence of an unsplit one.
    """
    observations = list(observations)
    latest: dict[Hashable, datetime] = {}
    for o in observations:
        if o.task_id not in latest or o.run_at > latest[o.task_id]:
            latest[o.task_id] = o.run_at

    kept   = [o for o in observations if o.run_at == latest[o.task_id]]
    chunks = Counter(o.task_id for o in kept)
    return [(o, 1.0 / chunks[o.task_id]) for o in kept]


# ── Posterior ────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Posterior:
    """Gaussian posterior over θ: N(mean, precision⁻¹)."""
    mean        : np.ndarray
    precision   : np.ndarray
    effective_n : float        # sum of weights after discounting, for inspection

    def sample(self, rng: np.random.Generator) -> np.ndarray:
        # precision = L Lᵀ  ⇒  L⁻ᵀ z ~ N(0, precision⁻¹) for z ~ N(0, I)
        chol = np.linalg.cholesky(self.precision)
        z    = rng.standard_normal(len(self.mean))
        return self.mean + np.linalg.solve(chol.T, z)


def fit_posterior(
    observations : Iterable[Observation],
    now          : datetime,
    discount     : float = DAILY_DISCOUNT,
) -> Posterior:
    """Conjugate Bayesian linear regression of scaled reward on φ.

    Prior θ ~ N(0, diag(PRIOR_VAR)), so with no data the mean is exactly zero,
    i.e. the pre-RL scheduler; draws from it explore (see HOUR_PRIOR_STD).
    Each row is a weighted rank-1 update, A += w·φφᵀ/σ², b += w·φ·r/σ², with
    w = its weight_observations weight times discount^age_in_days. Refit from scratch
    on every call: at a few hundred rows and D=17 that costs milliseconds, and
    there is no stored model to go stale or migrate.
    """
    precision = np.diag(1.0 / PRIOR_VAR)
    b         = np.zeros(D)
    n_eff     = 0.0

    for obs, weight in weight_observations(observations):
        age_days = max((now - obs.run_at).total_seconds() / 86400, 0.0)
        w   = weight * discount ** age_days
        phi = features(obs.hour, obs.weekday, obs.category, obs.energy)
        precision += (w / NOISE_VAR) * np.outer(phi, phi)
        b         += (w / NOISE_VAR) * phi * (obs.reward / REWARD_SCALE)
        n_eff     += w

    return Posterior(np.linalg.solve(precision, b), precision, n_eff)


# ── Policy ───────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class SlotPolicy:
    """One θ, held fixed for a whole scheduling run.

    Drawing once per run, not per task or per slot, keeps a plan internally
    consistent: every task in it is scored under the same hypothesis about
    the user, instead of 09:00 being judged good for one task and bad for the
    next by two contradictory samples.

    `kappa` scales the learned term; 0 is the kill switch back to the pre-RL
    scheduler.
    """
    theta : np.ndarray
    kappa : float = 1.0

    def bias(self, energy: float) -> dict[int, float]:
        """{hour: bias in [-1, 1]} for a task with this energy requirement."""
        w = self.theta[HOUR_TERMS]
        return {
            h: round(max(-1.0, min(1.0, self.kappa * float(_hour_terms(h, energy) @ w))), 4)
            for h in range(24)
        }


ZERO_POLICY = SlotPolicy(theta=np.zeros(D), kappa=0.0)
