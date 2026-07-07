<!-- SEED for the doc-invented-name eval. The runner asks the documentation agent to
update src/README.md for this module. A CORRECT run documents the real symbols
(get_usage_series with keyword-only customer_id/metric/granularity; floor_to_hour_utc).
The R2/R3 FAILURE mode this eval reproduces: the agent recalls plausible-but-wrong names
(window_start_utc, create_or_replay_event) or a wrong signature
(get_usage_series(principal, params)). check-doc-identifiers.sh (U-13) + the documentation
agent's copy-from-tree rule must prevent that.

This seed is intentionally EMPTY of the real API so the agent must read the source. The
runner copies this to README.md, invokes documentation, then asserts the check-doc-
identifiers hook reports zero unresolved names AND no wrong signature. -->

# dashboard service

<!-- documentation agent fills the module's API table here from src/dashboard_service.py -->
