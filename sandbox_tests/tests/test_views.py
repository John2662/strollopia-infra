import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
from core.sandbox.models import Sandbox, Invite, DemoRequest

User = get_user_model()


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def superuser(db):
    return User.objects.create_superuser(
        username="superadmin", email="super@example.com", password="pass123"
    )


@pytest.fixture
def staff_user(db):
    return User.objects.create_user(
        username="staff", email="staff@example.com", password="pass123", is_staff=True
    )


@pytest.fixture
def normal_user(db):
    return User.objects.create_user(
        username="normal", email="normal@example.com", password="pass123"
    )


@pytest.fixture
def sandbox(db):
    return Sandbox.objects.create(domain="sb_1.strollopia.com", is_active=False)


@pytest.fixture
def invite(db):
    return Invite.objects.create(email="demo@example.com", code="INVITE123")


# ------------------------
# Sandbox Tests
# ------------------------
@pytest.mark.django_db
def test_superuser_can_list_sandboxes(api_client, superuser, sandbox):
    api_client.force_authenticate(superuser)
    response = api_client.get("/api/sandbox/")
    assert response.status_code == status.HTTP_200_OK
    assert response.json()[0]["domain"] == sandbox.domain


@pytest.mark.django_db
def test_staff_can_list_sandboxes(api_client, staff_user, sandbox):
    api_client.force_authenticate(staff_user)
    response = api_client.get("/api/sandbox/")
    assert response.status_code == status.HTTP_200_OK


@pytest.mark.django_db
def test_normal_user_cannot_list_sandboxes(api_client, normal_user, sandbox):
    api_client.force_authenticate(normal_user)
    response = api_client.get("/api/sandbox/")
    assert response.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.django_db
def test_superuser_can_create_invite(api_client, superuser):
    api_client.force_authenticate(superuser)
    response = api_client.post(
        "/api/invites/", {"email": "new@example.com", "code": "NEWCODE123"}
    )
    assert response.status_code == status.HTTP_201_CREATED
    assert Invite.objects.filter(email="new@example.com").exists()


@pytest.mark.django_db
def test_staff_cannot_create_invite(api_client, staff_user):
    api_client.force_authenticate(staff_user)
    response = api_client.post(
        "/api/invites/", {"email": "staff@example.com", "code": "STAFF123"}
    )
    assert response.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.django_db
def test_superuser_can_create_demo_request(api_client, superuser, sandbox, invite):
    api_client.force_authenticate(superuser)
    response = api_client.post(
        "/api/demo-requests/",
        {
            "email": "demo@example.com",
            "invite": invite.id,
            "sandbox": sandbox.id,
        },
    )
    assert response.status_code == status.HTTP_201_CREATED
    assert DemoRequest.objects.filter(email="demo@example.com").exists()


@pytest.mark.django_db
def test_normal_user_cannot_create_demo_request(api_client, normal_user, sandbox, invite):
    api_client.force_authenticate(normal_user)
    response = api_client.post(
        "/api/demo-requests/",
        {
            "email": "demo@example.com",
            "invite": invite.id,
            "sandbox": sandbox.id,
        },
    )
    assert response.status_code == status.HTTP_403_FORBIDDEN
