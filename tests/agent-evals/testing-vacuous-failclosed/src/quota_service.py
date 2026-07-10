"""Quota admin service — DELETE must fail closed (roll back) on any mid-delete error."""


class SafeError(Exception):
    """Generic error the API layer maps to the safe 500 envelope (no internals leak)."""


class FakeSession:
    """Minimal stand-in for a DB session: a row store + rollback bookkeeping."""

    def __init__(self):
        self.rows = {"cust-1": 100}
        self._snapshot = None
        self.rolled_back = False

    def begin(self):
        self._snapshot = dict(self.rows)

    def execute_delete(self, customer_id):
        # The state mutation the fail-closed guarantee protects.
        del self.rows[customer_id]

    def rollback(self):
        self.rolled_back = True
        if self._snapshot is not None:
            self.rows = dict(self._snapshot)


def delete_quota(session, customer_id):
    """Delete a quota row; on any internal error, roll back and raise SafeError."""
    session.begin()
    try:
        session.execute_delete(customer_id)
    except Exception:
        session.rollback()
        raise SafeError("internal error")
