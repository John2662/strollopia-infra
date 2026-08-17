import pytest
from django.urls import reverse
from django.utils import timezone
from datetime import timedelta

from core.sandbox.models import Sandbox, DemoRequest


@pytest.fixture
def sandbox(db):
    return Sandbox.objects.create(
        domain="sb_1.strollopia.com",
        is_active=True,
        lease_expires_at=timezone.now() + timedelta(minutes=15),
    )


@pytest.mark.django_db
def test_free_sandbox_admin_action(admin_client, sandbox):
    """
    Ensure the 'Free sandboxes immediately' admin action marks sandbox inactive.
    """
    url = reverse("admin:core_sandbox_sandbox_changelist")
    data = {
        "action": "free_sandboxes",
        "_selected_action": [sandbox.pk],
    }
    response = admin_client.post(url, data, follow=True)
    assert response.status_code == 200

    sandbox.refresh_from_db()
    assert sandbox.is_active is False
    assert sandbox.last_reset is not None


@pytest.mark.django_db
def test_extend_sandbox_lease_admin_action(admin_client, sandbox):
    """
    Ensure the 'Extend sandbox lease' admin action adds time.
    """
    old_expiry = sandbox.lease_expires_at
    url = reverse("admin:core_sandbox_sandbox_changelist")

    # First call shows form
    response = admin_client.post(
        url, {"action": "extend_sandbox_lease", "_selected_action": [sandbox.pk]}
    )
    assert response.status_code == 200
    assert b"Extend selected sandbox leases" in response.content

    # Now submit with minutes=45
    response = admin_client.post(
        url,
        {
            "action": "extend_sandbox_lease",
            "_selected_action": [sandbox.pk],
            "apply": "1",
            "minutes": 45,
        },
        follow=True,
    )
    assert response.status_code == 200

    sandbox.refresh_from_db()
    assert sandbox.lease_expires_at > old_expiry


@pytest.mark.django_db
def test_extend_demo_request_admin_action(admin_client, sandbox):
    """
    Ensure the 'Extend demo' admin action adds time to DemoRequest.
    """
    demo = DemoRequest.objects.create(
        email="demo@example.com",
        sandbox=sandbox,
        created_at=timezone.now(),
        expires_at=timezone.now() + timedelta(minutes=15),
    )

    old_expiry = demo.expires_at
    url = reverse("admin:core_sandbox_demorequest_changelist")

    # First call shows form
    response = admin_client.post(
        url, {"action": "extend_demo", "_selected_action": [demo.pk]}
    )
    assert response.status_code == 200
    assert b"Extend selected demos" in response.content

    # Now submit with minutes=60
    response = admin_client.post(
        url,
        {
            "action": "extend_demo",
            "_selected_action": [demo.pk],
            "apply": "1",
            "minutes": 60,
        },
        follow=True,
    )
    assert response.status_code == 200

    demo.refresh_from_db()
    assert demo.expires_at > old_expiry


@pytest.mark.django_db
def test_end_demo_now_admin_action(admin_client, sandbox):
    """
    Ensure the 'End demo now' admin action ends a demo immediately
    and frees the sandbox.
    """
    demo = DemoRequest.objects.create(
        email="demo@example.com",
        sandbox=sandbox,
        created_at=timezone.now(),
        expires_at=timezone.now() + timedelta(minutes=30),
    )

    assert demo.ended_at is None
    assert sandbox.is_active is True

    url = reverse("admin:core_sandbox_demorequest_changelist")
    data = {
        "action": "end_demo_now",
        "_selected_action": [demo.pk],
    }

    response = admin_client.post(url, data, follow=True)
    assert response.status_code == 200

    demo.refresh_from_db()
    sandbox.refresh_from_db()

    # Demo is ended
    assert demo.ended_at is not None

    # Sandbox released
    assert sandbox.is_active is False
    assert sandbox.last_reset is not None
