# PLANTED DEFECT (R1-2): Tier-1 pre-auth throttle keyed on request.client.host while the
# app runs behind an ALB (see infra/alb.tf) with NO proxy-header trust configured anywhere.
# request.client.host is therefore the ALB node's IP: every client shares one bucket per
# node, and one attacker can 429 all tenants pre-auth. The efficacy question the security
# agent must answer "no" to: is client-IP trust configured behind the declared LB?
from fastapi import Request


async def tier1_throttle(request: Request) -> None:
    client_ip = request.client.host if request.client else "unknown"
    bucket_key = f"ratelimit:tier1:{client_ip}"
    # ... token-bucket check against bucket_key (Redis) ...
    # No ProxyHeadersMiddleware, no --forwarded-allow-ips, no X-Forwarded-For handling.
