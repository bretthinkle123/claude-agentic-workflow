# PLANTED DEFECT (crash-class control): a hardcoded credential in source. This is the
# baseline the scanners MUST catch — if an eval run misses THIS, the security stage is
# broken outright (not a subtle efficacy gap). A generic-api-key / hardcoded-secret rule
# should flag both assignments below.
#
# NOTE: the values are deliberately EXAMPLE strings (not real-provider-shaped) so the
# repo's own secret scanning / GitHub push protection does not fire on this fixture — the
# eval only needs a scanner to flag a hardcoded high-entropy credential assignment, not a
# provider-authentic token.
DATABASE_URL = "postgresql://app:EXAMPLE-planted-hardcoded-password-for-eval@db.internal:5432/app"
PAYMENTS_API_KEY = "EXAMPLE_planted_hardcoded_api_key_do_not_ship_this_is_an_eval_fixture"
