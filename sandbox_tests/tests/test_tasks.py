import pytest
from django.utils import timezone
from datetime import timedelta

from core.sandbox.models import Sandbox, DemoRequest, Invite
from core.tasks import cleanup_expired_sandboxes
from org.models import OwningOrg


@pytest.fixture
def sandbox(db):
    return Sandbox.objects.create(domain="sb_1.strollopia.com", is_active=True)


@pytest.fixture
def invite(db):
    return Invite.objects.create(email="demo@example.com", code="INV123", used=False)


@pytest.fixture
def owning_org(db):
    return OwningOrg.objects.create(org_domain_name="sb_1.strollopia.com")


@pytest.mark.django_db
def test_cleanup_expired_demo_request(sandbox, invite, owning_org):
    # Create expired demo
    expired_time = timezone.now() - timedelta(minutes=5)
    demo = DemoRequest.objects.create(
        email="demo@example.com",
        invite=invite,
        sandbox=sandbox,
        owning_org=owning_org,
        created_at=timezone.now() - timedelta(minutes=30),
        expires_at=expired_time,
    )

    assert sandbox.is_active is True
    assert DemoRequest.objects.count() == 1
    assert OwningOrg.objects.count() == 1

    # Run Celery cleanup task
    cleanup_expired_sandboxes()

    # Refresh objects
    demo.refresh_from_db()
    sandbox.refresh_from_db()

    # OwningOrg should be gone
    assert OwningOrg.objects.count() == 0

    # Sandbox freed
    assert sandbox.is_active is False
    assert sandbox.last_reset is not None

    # DemoRequest ended
    assert demo.ended_at is not None


@pytest.mark.django_db
def test_cleanup_ignores_active_demo(sandbox, invite, owning_org):
    # Create active demo (expires in future)
    future_time = timezone.now() + timedelta(minutes=30)
    demo = DemoRequest.objects.create(
        email="active@example.com",
        invite=invite,
        sandbox=sandbox,
        owning_org=owning_org,
        created_at=timezone.now(),
        expires_at=future_time,
    )

    cleanup_expired_sandboxes()

    demo.refresh_from_db()
    sandbox.refresh_from_db()

    # Still active
    assert sandbox.is_active is True
    assert demo.ended_at is None
    assert OwningOrg.objects.count() == 1
