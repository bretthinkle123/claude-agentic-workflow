import pytest

from src.quota_service import SafeError, FakeSession, delete_quota


def test_delete_fails_closed_on_internal_error(monkeypatch):
    # AC: a forced internal error during DELETE returns the safe error and fails
    # closed — the quota row survives.
    session = FakeSession()

    def boom(customer_id):
        raise RuntimeError("db exploded")

    # Force the internal error during the delete.
    monkeypatch.setattr(session, "execute_delete", boom)

    with pytest.raises(SafeError):
        delete_quota(session, "cust-1")

    # Fail-closed: the quota row must survive the failed delete.
    assert session.rows == {"cust-1": 100}
