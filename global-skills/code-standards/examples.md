# code-standards — worked examples

Read this only when a concrete example clarifies a rule. Python (the default
backend); the same shapes apply in JavaScript.

## Single Responsibility — before / after

**Before** — one function fetches, validates, persists, and notifies:

```python
def register_user(payload):
    if "@" not in payload["email"]:        # validation
        raise ValueError("bad email")
    user = db.insert("users", payload)     # persistence
    smtp.send(payload["email"], "welcome") # notification
    return user
```

**After** — each reason-to-change lives in its own unit; `register_user` only
orchestrates:

```python
def register_user(payload, validator, repo, notifier):
    """Register a user: validate, persist, then notify. Orchestration only."""
    validator.check(payload)
    user = repo.add(payload)
    notifier.welcome(user)
    return user
```

## Dependency Inversion — depend on an abstraction

**Before** — the service news a concrete Postgres client (hard to test, locked
to one backend):

```python
class OrderService:
    def __init__(self):
        self._db = PostgresClient(os.environ["DSN"])  # concretion
```

**After** — inject a repository abstraction; the caller chooses the concretion:

```python
class OrderService:
    def __init__(self, repo: OrderRepository):  # abstraction, injected
        self._repo = repo
```

## Open/Closed — extend without modifying

**Before** — adding a payment method edits a growing `if/elif` chain. **After** —
each method is a strategy registered against a key:

```python
PROCESSORS: dict[str, PaymentProcessor] = {}

def register(name): 
    def deco(cls): PROCESSORS[name] = cls(); return cls
    return deco

@register("stripe")
class StripeProcessor(PaymentProcessor): ...
# A new method adds a class — no existing code changes.
```

## Facade — route through, don't bypass

```python
# GOOD: new route plugs into the existing auth facade
from auth import require_mfa

@router.post("/transfer")
async def transfer(user = Depends(require_mfa)): ...

# BAD: route reaches around the facade into internals
from auth.token import verify_id_token   # bypasses require_auth/require_mfa
```
