from fastapi import Request, HTTPException, Depends
from .token import verify_id_token


async def require_auth(request: Request) -> dict:
    """Verify the bearer ID token and return the decoded user claims."""
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing auth token")
    try:
        return verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid auth token")


def require_mfa(user: dict = Depends(require_auth)) -> dict:
    """Require MFA completion via custom claim — apply after require_auth."""
    if not user.get("mfa_verified"):
        raise HTTPException(status_code=403, detail="MFA required")
    return user


def require_role(role: str):
    """Require a specific role — apply after require_auth."""
    def checker(user: dict = Depends(require_auth)) -> dict:
        if role not in (user.get("roles") or []):
            raise HTTPException(status_code=403, detail="Forbidden")
        return user
    return checker
