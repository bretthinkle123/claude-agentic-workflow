from firebase_admin import auth
import firebase_admin_init  # noqa: F401  (ensures the Admin app is initialized)


def verify_id_token(id_token: str) -> dict:
    """Verify a Firebase ID token and return its decoded claims."""
    return auth.verify_id_token(id_token)


def set_mfa_verified(uid: str, method: str) -> None:
    """Set the MFA custom claim after a second factor completes. method is
    'totp' (Path A) or 'duo-push' (Path B), so require_mfa gates both uniformly."""
    auth.set_custom_user_claims(uid, {"mfa_verified": True, "mfa_method": method})
