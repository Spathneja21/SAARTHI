"""Guards the Thompson-sampling slot policy (ml/slot_bandit.py).

Pure numpy: needs no database and no OR-Tools. Covers the contract
cpsat_bridge relies on (bias in [-1, 1], zero at cold start and with the kill
switch) and that the model learns a preference it is shown.
"""
from datetime import datetime, timedelta

import numpy as np

from core.tz import IST
from ml.slot_bandit import (
    D, HOUR_TERMS, ZERO_POLICY, Observation, SlotPolicy,
    _hour_terms, features, fit_posterior, weight_observations,
)

NOW = datetime(2026, 9, 29, 12, 0, tzinfo=IST)
MORNING, EVENING = range(8, 12), range(17, 22)


def _obs(task, hour, reward, *, energy=0.6, days_ago=1, run=0, weekday=1):
    return Observation(
        task_id  = task,
        run_at   = NOW - timedelta(days=days_ago, minutes=run),
        hour     = hour,
        weekday  = weekday,
        category = "deep_work",
        energy   = energy,
        reward   = reward,
    )


def _chronotype(n_days=20, energy=0.6, good=MORNING, bad=EVENING):
    """A user who finishes what lands in `good` hours and abandons `bad` ones."""
    rows = []
    for d in range(n_days):
        rows.append(_obs(f"g{d}", good[d % len(good)], 20.0, energy=energy, days_ago=d))
        rows.append(_obs(f"b{d}", bad[d % len(bad)],  -5.0, energy=energy, days_ago=d))
    return rows


def _mean_policy(rows):
    return SlotPolicy(fit_posterior(rows, NOW).mean)


def test_hour_basis_wraps_at_midnight():
    f = lambda h: features(h, 1, "admin", 0.6)
    assert np.allclose(f(0), f(24))
    assert np.linalg.norm(f(23) - f(0)) < np.linalg.norm(f(12) - f(0))
    assert len(f(9)) == D


def test_cold_start_reproduces_the_heuristic():
    # Prior mean is zero, so with no data the learned term contributes nothing.
    posterior = fit_posterior([], NOW)
    assert np.all(posterior.mean == 0)
    assert all(v == 0 for v in SlotPolicy(posterior.mean).bias(0.8).values())


def test_kill_switch_zeroes_the_bias():
    theta = np.random.default_rng(0).normal(size=D) * 5
    assert all(v == 0 for v in SlotPolicy(theta, kappa=0.0).bias(1.0).values())
    assert all(v == 0 for v in ZERO_POLICY.bias(0.2).values())


def test_bias_stays_in_range():
    # compute_slot_scores' remap assumes [-1, 1]; an extreme draw must not escape it.
    theta = np.random.default_rng(1).normal(size=D) * 50
    for energy in (0.2, 0.6, 1.0):
        bias = SlotPolicy(theta, kappa=3.0).bias(energy)
        assert set(bias) == set(range(24))
        assert all(-1.0 <= v <= 1.0 for v in bias.values())


def test_learns_a_morning_chronotype():
    bias = _mean_policy(_chronotype()).bias(0.6)
    assert min(bias[h] for h in MORNING) > 0 > max(bias[h] for h in EVENING)


def test_generalises_to_unseen_neighbouring_hours():
    # 12:00 is never observed, but sits next to the rewarded mornings. A
    # per-hour table would stay silent there; the smooth basis should not.
    bias = _mean_policy(_chronotype()).bias(0.6)
    assert bias[12] > bias[19]


def test_hour_curve_depends_on_task_energy():
    # Demanding tasks get done in the morning, light ones in the evening.
    rows = _chronotype(energy=1.0) + [
        Observation(**{**o.__dict__, "task_id": f"light_{o.task_id}", "energy": 0.2})
        for o in _chronotype(good=EVENING, bad=MORNING)
    ]
    policy = _mean_policy(rows)
    peak, very_low = policy.bias(1.0), policy.bias(0.2)
    assert peak[9]      > peak[19]
    assert very_low[19] > very_low[9]


def test_uniform_success_teaches_no_hour_preference():
    # Finishing everything, everywhere, is a base rate, not a time-of-day
    # signal; the intercept should absorb it rather than the hour curve.
    rows = [_obs(f"t{i}", 8 + i % 14, 20.0, days_ago=i % 20) for i in range(60)]
    bias = _mean_policy(rows).bias(0.6)
    assert max(abs(v) for v in bias.values()) < 0.1


def test_only_the_latest_plan_is_credited():
    # Planned at 20:00, re-planned to 09:00, then completed: only 09:00 was
    # the suggestion the user acted on.
    old = _obs("t", 20, 20.0, run=60)
    new = _obs("t", 9, 20.0, run=0)
    weighted = weight_observations([old, new])
    assert [(o.hour, w) for o, w in weighted] == [(9, 1.0)]


def test_chunks_of_one_task_share_one_unit_of_evidence():
    chunks = [_obs("t", 9, 20.0), _obs("t", 14, 20.0), _obs("u", 10, -5.0)]
    weights = {(o.task_id, o.hour): w for o, w in weight_observations(chunks)}
    assert weights == {("t", 9): 0.5, ("t", 14): 0.5, ("u", 10): 1.0}


def test_old_evidence_fades():
    fresh = fit_posterior([_obs("t", 9, 20.0, days_ago=0)], NOW).effective_n
    stale = fit_posterior([_obs("t", 9, 20.0, days_ago=34)], NOW).effective_n
    assert abs(fresh - 1.0) < 1e-3
    assert abs(stale - 0.5) < 0.01          # 0.98 ** 34 ~= 0.5


def _bias_std(posterior, hour=9, energy=0.6):
    """Exact posterior std of the bias at one hour, from the covariance."""
    cov = np.linalg.inv(posterior.precision)[HOUR_TERMS, HOUR_TERMS]
    phi = _hour_terms(hour, energy)
    return float(np.sqrt(phi @ cov @ phi))


def test_uncertainty_shrinks_as_evidence_accumulates():
    cold = _bias_std(fit_posterior([], NOW))
    warm = _bias_std(fit_posterior(_chronotype(n_days=60), NOW))
    assert abs(cold - 0.354) < 0.001         # documented cold-start std ~0.35
    # Discounting caps the effective sample size (~50 days), so uncertainty
    # levels off rather than going to zero; exploration never fully stops.
    assert warm < 0.6 * cold


def test_sampler_matches_the_posterior():
    # Checks the Cholesky draw: sampled spread must match the exact covariance.
    rng = np.random.default_rng(2)
    for rows in ([], _chronotype()):
        posterior = fit_posterior(rows, NOW)
        draws = [SlotPolicy(posterior.sample(rng)).bias(0.6)[9] for _ in range(4000)]
        assert abs(np.std(draws) / _bias_std(posterior) - 1) < 0.05
        assert abs(np.mean(draws) - SlotPolicy(posterior.mean).bias(0.6)[9]) < 0.02


def test_fixed_seed_gives_a_fixed_draw():
    posterior = fit_posterior(_chronotype(), NOW)
    a = posterior.sample(np.random.default_rng(7))
    b = posterior.sample(np.random.default_rng(7))
    assert np.array_equal(a, b)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
