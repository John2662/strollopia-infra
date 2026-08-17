# Challenges Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `challenges` Django app and supporting core models that back the place-based learning platform — route challenges, stops, activities, enrollment, and progress tracking — plus the plugin registry.

**Architecture:** New `challenges` app sits alongside existing Django apps in `strollopia-api`. Three new models land in `core` (`Plugin`, `OrgPlugin`, `OrgSiteConfig`). Two fields added to `User`. One new `UiType` choice (`SG`). All endpoints follow the existing DRF + token auth + `BaseOrgModel` queryset isolation pattern.

**Tech Stack:** Django, Django REST Framework, drf-spectacular, PostgreSQL, Docker (tests run inside container via `make test`)

**Spec:** `docs/superpowers/specs/2026-08-06-place-based-learning-design.md`

**Note:** This is Plan 1 of 2. The frontend (`strollopia-guide`) is Plan 2, written after this plan is complete and the API endpoints are testable.

---

## Test runner

All test commands run inside Docker:

```bash
# Run all tests
make test

# Run a specific module
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models"
```

## Existing patterns to follow

- Models inherit from `core.models.BaseOrgModel` (abstract, adds `owning_org FK`, `created_at`, `updated_at`)
- Test orgs: `OwningOrg.create_org(domain)` + `increment_test_url()` for unique domains
- API tests: `django.test.TestCase` + `rest_framework.test.APIClient`
- Auth: `self.client.force_authenticate(user=self.user)`
- URL namespaces: declared in `urls.py` as `app_name`, registered in `app/app/urls.py`

---

## Task 1: Add `is_producer` / `is_consumer` to User + `SG` to UiType

**Files:**
- Modify: `app/core/models.py` — User class (add two fields)
- Modify: `app/ui_support/models.py` — UiType choices (add SG)
- Modify: `app/ui_support/models.py` — UI_TYPE_LIST (add 'SG')
- Test: `app/core/tests/test_models.py`
- Migration: `app/core/migrations/`

- [ ] **Write the failing tests**

Add to `app/core/tests/test_models.py` inside the existing `ModelTests` class:

```python
def test_user_defaults_not_producer_or_consumer(self):
    """New users are neither producer nor consumer by default."""
    org_domain = increment_test_url()
    OwningOrg.create_org(org_domain)
    user = get_user_model().objects.create_user(
        org_domain_name=org_domain,
        email='newuser@example.com',
        password='pass123',
    )
    self.assertFalse(user.is_producer)
    self.assertFalse(user.is_consumer)

def test_user_can_be_both_producer_and_consumer(self):
    """A user can hold both roles simultaneously."""
    org_domain = increment_test_url()
    OwningOrg.create_org(org_domain)
    user = get_user_model().objects.create_user(
        org_domain_name=org_domain,
        email='dual@example.com',
        password='pass123',
        is_producer=True,
        is_consumer=True,
    )
    self.assertTrue(user.is_producer)
    self.assertTrue(user.is_consumer)
```

- [ ] **Run tests to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_models.ModelTests.test_user_defaults_not_producer_or_consumer"
```

Expected: `AttributeError: type object 'User' has no attribute 'is_producer'`

- [ ] **Add fields to User model**

In `app/core/models.py`, inside the `User` class after `is_staff`:

```python
is_producer = models.BooleanField(default=False)
# True for teachers, guides, trainers — label set by the active plugin manifest
is_consumer = models.BooleanField(default=False)
# True for students, visitors, trainees — label set by the active plugin manifest
```

- [ ] **Add SG to UiType**

In `app/ui_support/models.py`:

```python
# Change:
UI_TYPE_LIST = ['BL', 'VW', 'ED', 'DL']
# To:
UI_TYPE_LIST = ['BL', 'VW', 'ED', 'DL', 'SG']

# Inside UiType(models.TextChoices), add after LOGGER:
GUIDE = ("SG", _("Guide"))
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations core"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run tests to verify they pass**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_models.ModelTests.test_user_defaults_not_producer_or_consumer core.tests.test_models.ModelTests.test_user_can_be_both_producer_and_consumer"
```

Expected: `OK (2 tests)`

- [ ] **Commit**

```bash
git add app/core/models.py app/ui_support/models.py app/core/migrations/ app/core/tests/test_models.py
git commit -m "feat: add is_producer/is_consumer to User; add SG UiType for strollopia-guide"
```

---

## Task 2: Plugin + OrgPlugin models in core

**Files:**
- Modify: `app/core/models.py` — add Plugin, OrgPlugin
- Create: `app/core/tests/test_plugin_models.py`
- Migration: `app/core/migrations/`

- [ ] **Create the test file**

Create `app/core/tests/test_plugin_models.py`:

```python
"""Tests for Plugin and OrgPlugin models."""
from django.test import TestCase
from django.contrib.auth import get_user_model
from django.db.utils import IntegrityError

from core.models import OwningOrg, Plugin, OrgPlugin
from core.tests.test_url_resolution import increment_test_url


def make_org():
    domain = increment_test_url()
    return OwningOrg.create_org(domain)


def make_plugin(key='learning', name='Place-Based Learning'):
    return Plugin.objects.create(key=key, name=name, description='Test plugin')


class PluginModelTests(TestCase):

    def test_plugin_key_is_unique(self):
        make_plugin(key='learning')
        with self.assertRaises(IntegrityError):
            make_plugin(key='learning')

    def test_plugin_defaults_available(self):
        p = make_plugin()
        self.assertTrue(p.is_available)

    def test_plugin_str(self):
        p = make_plugin(key='learning', name='Place-Based Learning')
        self.assertIn('learning', str(p))


class OrgPluginModelTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.plugin = make_plugin()

    def test_orgplugin_defaults_active(self):
        op = OrgPlugin.objects.create(owning_org=self.org, plugin=self.plugin)
        self.assertEqual(op.status, 'active')

    def test_orgplugin_unique_per_org(self):
        OrgPlugin.objects.create(owning_org=self.org, plugin=self.plugin)
        with self.assertRaises(IntegrityError):
            OrgPlugin.objects.create(owning_org=self.org, plugin=self.plugin)

    def test_cannot_delete_plugin_with_active_orgplugin(self):
        OrgPlugin.objects.create(owning_org=self.org, plugin=self.plugin)
        from django.db.models import ProtectedError
        with self.assertRaises(ProtectedError):
            self.plugin.delete()

    def test_orgplugin_suspend(self):
        op = OrgPlugin.objects.create(owning_org=self.org, plugin=self.plugin)
        op.status = 'suspended'
        op.save()
        op.refresh_from_db()
        self.assertEqual(op.status, 'suspended')
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_plugin_models"
```

Expected: `ImportError: cannot import name 'Plugin' from 'core.models'`

- [ ] **Add Plugin and OrgPlugin to core/models.py**

At the end of `app/core/models.py`, before the `User` class (so Plugin exists when OrgPlugin references it):

```python
class Plugin(models.Model):
    """System registry of available frontend plugins. Managed by superadmin only."""
    key          = models.CharField(max_length=20, unique=True)
    # Must exactly match the `id` field in the frontend plugin manifest.
    name         = models.CharField(max_length=100)
    description  = models.TextField()
    is_available = models.BooleanField(default=True)

    # Onboarding content — rendered in admin when an org activates this plugin
    quick_start  = models.TextField(blank=True)   # markdown setup guide
    how_to       = models.TextField(blank=True)   # markdown usage guide
    demo_url     = models.URLField(blank=True)
    support_url  = models.URLField(blank=True)
    version      = models.CharField(max_length=20, blank=True)
    changelog    = models.TextField(blank=True)   # markdown

    def __str__(self):
        return f'{self.key} ({self.name})'

    class Meta:
        ordering = ['key']


class OrgPlugin(BaseOrgModel):
    """One row per plugin per org. Replaces the old active_plugins JSON array."""
    MODEL_ORG_LOOKUP = 'owning_org'

    ACTIVE         = 'active'
    SUSPENDED      = 'suspended'
    DECOMMISSIONED = 'decommissioned'
    STATUS_CHOICES = [
        (ACTIVE,         'Active'),
        (SUSPENDED,      'Suspended'),
        (DECOMMISSIONED, 'Decommissioned'),
    ]

    plugin       = models.ForeignKey(Plugin, on_delete=models.PROTECT, related_name='org_plugins')
    status       = models.CharField(max_length=20, choices=STATUS_CHOICES, default=ACTIVE)
    settings     = models.JSONField(default=dict)
    activated_by = models.ForeignKey(
        'core.User', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='activated_plugins'
    )
    suspended_at = models.DateTimeField(null=True, blank=True)
    suspended_by = models.ForeignKey(
        'core.User', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='suspended_plugins'
    )

    class Meta:
        unique_together = ('owning_org', 'plugin')

    def __str__(self):
        return f'{self.owning_org.org_domain_name} / {self.plugin.key} [{self.status}]'
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations core"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run tests to verify they pass**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_plugin_models"
```

Expected: `OK (5 tests)`

- [ ] **Commit**

```bash
git add app/core/models.py app/core/migrations/ app/core/tests/test_plugin_models.py
git commit -m "feat: add Plugin and OrgPlugin models to core"
```

---

## Task 3: OrgSiteConfig model in core

**Files:**
- Modify: `app/core/models.py` — add OrgSiteConfig
- Create: `app/core/tests/test_org_site_config.py`
- Migration: `app/core/migrations/`

- [ ] **Create the test file**

Create `app/core/tests/test_org_site_config.py`:

```python
"""Tests for OrgSiteConfig model."""
from django.test import TestCase
from django.db.utils import IntegrityError

from core.models import OwningOrg, OrgSiteConfig
from core.tests.test_url_resolution import increment_test_url


def make_org():
    return OwningOrg.create_org(increment_test_url())


class OrgSiteConfigTests(TestCase):

    def test_create_site_config(self):
        org = make_org()
        config = OrgSiteConfig.objects.create(owning_org=org)
        self.assertEqual(config.owning_org, org)

    def test_one_config_per_org(self):
        org = make_org()
        OrgSiteConfig.objects.create(owning_org=org)
        with self.assertRaises(IntegrityError):
            OrgSiteConfig.objects.create(owning_org=org)

    def test_access_via_reverse_relation(self):
        org = make_org()
        OrgSiteConfig.objects.create(owning_org=org, google_analytics_id='G-ABC123')
        self.assertEqual(org.site_config.google_analytics_id, 'G-ABC123')

    def test_all_fields_blank_by_default(self):
        org = make_org()
        config = OrgSiteConfig.objects.create(owning_org=org)
        self.assertEqual(config.meta_description, '')
        self.assertEqual(config.google_analytics_id, '')
        self.assertEqual(config.custom_head_html, '')
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_org_site_config"
```

Expected: `ImportError: cannot import name 'OrgSiteConfig' from 'core.models'`

- [ ] **Add OrgSiteConfig to core/models.py**

After `OrgPlugin` in `app/core/models.py`:

```python
class OrgSiteConfig(models.Model):
    """
    Site-level config for an org's white-label instance.
    OneToOne with OwningOrg — domain/DNS lives on OwningOrg.org_domain_name, not here.
    """
    owning_org = models.OneToOneField(
        OwningOrg, on_delete=models.CASCADE, related_name='site_config'
    )

    # SEO
    meta_description = models.TextField(blank=True)
    og_image         = models.URLField(blank=True)
    favicon_url      = models.URLField(blank=True)

    # Analytics
    google_analytics_id   = models.CharField(max_length=50, blank=True)
    google_tag_manager_id = models.CharField(max_length=50, blank=True)
    facebook_pixel_id     = models.CharField(max_length=50, blank=True)

    # Legal
    privacy_policy_url = models.URLField(blank=True)
    cookie_policy_url  = models.URLField(blank=True)
    terms_url          = models.URLField(blank=True)

    # Social
    twitter_handle   = models.CharField(max_length=100, blank=True)
    facebook_page    = models.URLField(blank=True)
    instagram_handle = models.CharField(max_length=100, blank=True)

    # Escape hatch — raw HTML injected into <head> by strollopia-guide layout
    custom_head_html = models.TextField(blank=True)

    def __str__(self):
        return f'SiteConfig: {self.owning_org.org_domain_name}'
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations core"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run tests to verify they pass**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test core.tests.test_org_site_config"
```

Expected: `OK (4 tests)`

- [ ] **Commit**

```bash
git add app/core/models.py app/core/migrations/ app/core/tests/test_org_site_config.py
git commit -m "feat: add OrgSiteConfig OneToOne model to core"
```

---

## Task 4: Create the `challenges` app skeleton

**Files:**
- Create: `app/challenges/__init__.py`
- Create: `app/challenges/models.py`
- Create: `app/challenges/serializers.py`
- Create: `app/challenges/urls.py`
- Create: `app/challenges/admin.py`
- Create: `app/challenges/tests/__init__.py`
- Modify: `app/app/settings.py` — INSTALLED_APPS
- Modify: `app/app/urls.py` — register route

- [ ] **Create app skeleton**

```bash
docker compose run --rm app sh -c "python manage.py startapp challenges"
```

Then move the created directory into `app/challenges/` if it was created at the wrong level. Verify with:

```bash
ls app/challenges/
```

Expected: `__init__.py  admin.py  apps.py  migrations/  models.py  tests.py  views.py`

- [ ] **Create tests directory**

```bash
mkdir app/challenges/tests
touch app/challenges/tests/__init__.py
rm app/challenges/tests.py   # replaced by tests/ package
```

- [ ] **Register in INSTALLED_APPS**

In `app/app/settings.py`, add `'challenges'` to `INSTALLED_APPS` after `'core'`:

```python
INSTALLED_APPS = [
    ...
    'core',
    'core.sandbox',
    'challenges',   # <-- add here
    ...
]
```

- [ ] **Register URL namespace**

In `app/app/urls.py`, add after existing `api/` paths:

```python
path('api/challenges/', include('challenges.urls', namespace='challenges')),
```

- [ ] **Create stub urls.py**

Replace `app/challenges/urls.py` with:

```python
from django.urls import path, include
from rest_framework.routers import DefaultRouter

app_name = 'challenges'

router = DefaultRouter()

urlpatterns = [
    path('', include(router.urls)),
]
```

- [ ] **Verify app loads cleanly**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py check"
```

Expected: `System check identified no issues (0 silenced).`

- [ ] **Commit**

```bash
git add app/challenges/ app/app/settings.py app/app/urls.py
git commit -m "feat: scaffold challenges Django app"
```

---

## Task 5: RouteChallenge + ChallengeStop models

**Files:**
- Modify: `app/challenges/models.py`
- Create: `app/challenges/tests/test_models.py`
- Migration: `app/challenges/migrations/`

- [ ] **Create the test file**

Create `app/challenges/tests/test_models.py`:

```python
"""Tests for challenges models."""
from django.test import TestCase
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop


def make_org():
    domain = increment_test_url()
    return OwningOrg.create_org(domain)


def make_user(org):
    return get_user_model().objects.create_user(
        org_domain_name=org.org_domain_name,
        email='teacher@example.com',
        password='pass123',
        is_producer=True,
    )


def make_challenge(org, user, **kwargs):
    defaults = dict(
        owning_org=org,
        title='Train Station to Café',
        language='de',
        level='A1',
        created_by=user,
    )
    defaults.update(kwargs)
    return RouteChallenge.objects.create(**defaults)


class RouteChallengeTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)

    def test_create_challenge(self):
        c = make_challenge(self.org, self.user)
        self.assertEqual(c.status, 'draft')
        self.assertEqual(c.language, 'de')
        self.assertIsNotNone(c.join_code)

    def test_join_code_auto_generated(self):
        c = make_challenge(self.org, self.user)
        self.assertTrue(len(c.join_code) > 0)

    def test_join_code_unique(self):
        c1 = make_challenge(self.org, self.user)
        org2 = make_org()
        user2 = make_user(org2)
        c2 = make_challenge(org2, user2)
        self.assertNotEqual(c1.join_code, c2.join_code)

    def test_ux_mode_defaults_null(self):
        c = make_challenge(self.org, self.user)
        self.assertIsNone(c.ux_mode)

    def test_str(self):
        c = make_challenge(self.org, self.user)
        self.assertIn('Train Station', str(c))


class ChallengeStopTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.challenge = make_challenge(self.org, self.user)

    def test_create_stop(self):
        stop = ChallengeStop.objects.create(
            owning_org=self.org,
            challenge=self.challenge,
            order=1,
            name='Hauptbahnhof',
            lat=47.26303,
            lng=11.40048,
        )
        self.assertEqual(stop.radius_m, 50)
        self.assertIsNone(stop.poi)

    def test_stop_str(self):
        stop = ChallengeStop.objects.create(
            owning_org=self.org,
            challenge=self.challenge,
            order=1,
            name='Triumphpforte',
            lat=47.26312,
            lng=11.39672,
        )
        self.assertIn('Triumphpforte', str(stop))
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models"
```

Expected: `ImportError: cannot import name 'RouteChallenge' from 'challenges.models'`

- [ ] **Implement models**

Replace `app/challenges/models.py` with:

```python
import secrets
from django.db import models
from django.conf import settings

from core.models import BaseOrgModel


def _generate_join_code():
    return secrets.token_urlsafe(8)[:12]


class RouteChallenge(BaseOrgModel):
    MODEL_ORG_LOOKUP = 'owning_org'

    DRAFT     = 'draft'
    PUBLISHED = 'published'
    ARCHIVED  = 'archived'
    STATUS_CHOICES = [
        (DRAFT,     'Draft'),
        (PUBLISHED, 'Published'),
        (ARCHIVED,  'Archived'),
    ]

    title       = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    language    = models.CharField(max_length=10)
    level       = models.CharField(max_length=10, blank=True)
    ux_mode     = models.CharField(max_length=20, null=True, blank=True)
    # null = use org's OrgPlugin.settings default_ux_mode
    status      = models.CharField(max_length=20, choices=STATUS_CHOICES, default=DRAFT)
    join_code   = models.CharField(max_length=12, unique=True, blank=True)
    created_by  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, related_name='created_challenges'
    )

    def save(self, *args, **kwargs):
        if not self.join_code:
            self.join_code = _generate_join_code()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.title} [{self.status}]'

    class Meta:
        ordering = ['-created_at']


class ChallengeStop(BaseOrgModel):
    MODEL_ORG_LOOKUP = 'owning_org'

    challenge = models.ForeignKey(
        RouteChallenge, on_delete=models.CASCADE, related_name='stops'
    )
    order    = models.PositiveIntegerField()
    name     = models.CharField(max_length=200)
    lat      = models.FloatField()
    lng      = models.FloatField()
    radius_m = models.IntegerField(default=50)
    poi      = models.ForeignKey(
        'content.Poi', on_delete=models.SET_NULL,
        null=True, blank=True, related_name='challenge_stops'
    )

    def __str__(self):
        return f'{self.challenge.title} / Stop {self.order}: {self.name}'

    class Meta:
        ordering = ['challenge', 'order']
        unique_together = ('challenge', 'order')
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations challenges"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run tests to verify they pass**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models"
```

Expected: `OK (7 tests)`

- [ ] **Commit**

```bash
git add app/challenges/models.py app/challenges/migrations/ app/challenges/tests/test_models.py
git commit -m "feat: add RouteChallenge and ChallengeStop models"
```

---

## Task 6: Activity model + JSON schema validation

**Files:**
- Modify: `app/challenges/models.py` — add Activity
- Create: `app/challenges/activity_schemas.py`
- Modify: `app/challenges/tests/test_models.py` — add Activity tests
- Migration: `app/challenges/migrations/`

- [ ] **Create activity_schemas.py**

Create `app/challenges/activity_schemas.py`:

```python
"""
JSON schemas for Activity.content validation.
Field names deliberately mirror future typed subclass fields
so migration later is a rename, not a transform.
"""
from django.core.exceptions import ValidationError

ACTIVITY_TYPES = ['QUIZ', 'LISTEN', 'SPEAK', 'WRITE', 'PHOTO', 'CHECKIN']

REQUIRED_FIELDS = {
    'QUIZ':    ['_type', 'question', 'options'],
    'LISTEN':  ['_type', 'audio_url', 'question', 'options'],
    'SPEAK':   ['_type', 'prompt', 'model_answer'],
    'WRITE':   ['_type', 'prompt', 'model_answer'],
    'PHOTO':   ['_type', 'instruction'],
    'CHECKIN': ['_type', 'instruction'],
}


def validate_activity_content(content):
    """Validate that content JSON matches the declared _type schema."""
    if not isinstance(content, dict):
        raise ValidationError('Activity content must be a JSON object.')

    activity_type = content.get('_type')
    if activity_type not in ACTIVITY_TYPES:
        raise ValidationError(
            f'_type must be one of {ACTIVITY_TYPES}, got {activity_type!r}.'
        )

    required = REQUIRED_FIELDS[activity_type]
    missing = [f for f in required if f not in content]
    if missing:
        raise ValidationError(
            f'{activity_type} content missing required fields: {missing}'
        )

    if activity_type in ('QUIZ', 'LISTEN'):
        options = content.get('options', [])
        if not isinstance(options, list) or len(options) < 2:
            raise ValidationError(
                f'{activity_type} must have at least 2 options.'
            )
        for opt in options:
            if 'text' not in opt or 'is_correct' not in opt:
                raise ValidationError(
                    'Each option must have "text" and "is_correct" fields.'
                )
```

- [ ] **Add Activity tests to test_models.py**

Append to `app/challenges/tests/test_models.py`:

```python
from challenges.models import Activity
from challenges.activity_schemas import validate_activity_content
from django.core.exceptions import ValidationError


class ActivitySchemaTests(TestCase):

    def test_valid_quiz_passes(self):
        content = {
            '_type': 'QUIZ',
            'question': 'Which platform?',
            'options': [
                {'text': 'Gleis 3', 'is_correct': True},
                {'text': 'Gleis 7', 'is_correct': False},
            ],
        }
        # Should not raise
        validate_activity_content(content)

    def test_invalid_type_raises(self):
        with self.assertRaises(ValidationError):
            validate_activity_content({'_type': 'UNKNOWN'})

    def test_missing_required_field_raises(self):
        with self.assertRaises(ValidationError):
            validate_activity_content({'_type': 'QUIZ', 'question': 'What?'})
        # missing 'options'

    def test_quiz_needs_two_options(self):
        with self.assertRaises(ValidationError):
            validate_activity_content({
                '_type': 'QUIZ',
                'question': 'What?',
                'options': [{'text': 'Only one', 'is_correct': True}],
            })

    def test_valid_checkin_passes(self):
        validate_activity_content({'_type': 'CHECKIN', 'instruction': 'Scan the QR code.'})


class ActivityModelTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.challenge = make_challenge(self.org, self.user)
        self.stop = ChallengeStop.objects.create(
            owning_org=self.org,
            challenge=self.challenge,
            order=1,
            name='Hauptbahnhof',
            lat=47.26303,
            lng=11.40048,
        )

    def test_create_activity(self):
        activity = Activity.objects.create(
            owning_org=self.org,
            stop=self.stop,
            order=1,
            activity_type='QUIZ',
            content={
                '_type': 'QUIZ',
                'question': 'Which platform?',
                'options': [
                    {'text': 'Gleis 3', 'is_correct': True},
                    {'text': 'Gleis 7', 'is_correct': False},
                ],
            },
        )
        self.assertEqual(activity.unlock_condition, 'previous_complete')

    def test_activity_content_validated_on_save(self):
        with self.assertRaises(ValidationError):
            Activity(
                owning_org=self.org,
                stop=self.stop,
                order=2,
                activity_type='QUIZ',
                content={'_type': 'QUIZ'},  # missing options
            ).full_clean()
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models.ActivitySchemaTests challenges.tests.test_models.ActivityModelTests"
```

Expected: `ImportError: cannot import name 'Activity'`

- [ ] **Add Activity to models.py**

Append to `app/challenges/models.py`:

```python
from challenges.activity_schemas import validate_activity_content


class Activity(BaseOrgModel):
    MODEL_ORG_LOOKUP = 'owning_org'

    UNLOCK_PREVIOUS = 'previous_complete'
    UNLOCK_ALWAYS   = 'always_open'
    UNLOCK_CHOICES  = [
        (UNLOCK_PREVIOUS, 'Previous complete'),
        (UNLOCK_ALWAYS,   'Always open'),
    ]

    stop             = models.ForeignKey(
        ChallengeStop, on_delete=models.CASCADE, related_name='activities'
    )
    order            = models.PositiveIntegerField()
    activity_type    = models.CharField(max_length=20)
    content          = models.JSONField(validators=[validate_activity_content])
    unlock_condition = models.CharField(
        max_length=20, choices=UNLOCK_CHOICES, default=UNLOCK_PREVIOUS
    )

    def __str__(self):
        return f'{self.stop.name} / Activity {self.order} [{self.activity_type}]'

    class Meta:
        ordering = ['stop', 'order']
        unique_together = ('stop', 'order')
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations challenges"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models"
```

Expected: `OK (12 tests)`

- [ ] **Commit**

```bash
git add app/challenges/models.py app/challenges/activity_schemas.py app/challenges/migrations/ app/challenges/tests/test_models.py
git commit -m "feat: add Activity model with JSON schema validation"
```

---

## Task 7: Enrollment + StudentProgress models

**Files:**
- Modify: `app/challenges/models.py`
- Modify: `app/challenges/tests/test_models.py`
- Migration: `app/challenges/migrations/`

- [ ] **Add tests**

Append to `app/challenges/tests/test_models.py`:

```python
from challenges.models import Enrollment, StudentProgress


def make_student(org, email='student@example.com'):
    return get_user_model().objects.create_user(
        org_domain_name=org.org_domain_name,
        email=email,
        password='pass123',
        is_consumer=True,
    )


def make_activity(org, stop, order=1):
    return Activity.objects.create(
        owning_org=org,
        stop=stop,
        order=order,
        activity_type='CHECKIN',
        content={'_type': 'CHECKIN', 'instruction': 'Scan QR.'},
    )


class EnrollmentModelTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.student = make_student(self.org)
        self.challenge = make_challenge(self.org, self.user)

    def test_create_enrollment(self):
        e = Enrollment.objects.create(
            owning_org=self.org,
            challenge=self.challenge,
            student=self.student,
        )
        self.assertEqual(e.status, 'active')

    def test_enrollment_unique_per_student_challenge(self):
        Enrollment.objects.create(
            owning_org=self.org,
            challenge=self.challenge,
            student=self.student,
        )
        with self.assertRaises(Exception):
            Enrollment.objects.create(
                owning_org=self.org,
                challenge=self.challenge,
                student=self.student,
            )


class StudentProgressModelTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.student = make_student(self.org)
        self.challenge = make_challenge(self.org, self.user)
        self.stop = ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=1, name='Stop 1', lat=47.263, lng=11.400,
        )
        self.activity = make_activity(self.org, self.stop)
        self.enrollment = Enrollment.objects.create(
            owning_org=self.org, challenge=self.challenge, student=self.student
        )

    def test_create_progress(self):
        p = StudentProgress.objects.create(
            owning_org=self.org,
            enrollment=self.enrollment,
            activity=self.activity,
        )
        self.assertEqual(p.status, 'not_started')
        self.assertIsNone(p.score)
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models.EnrollmentModelTests challenges.tests.test_models.StudentProgressModelTests"
```

Expected: `ImportError: cannot import name 'Enrollment'`

- [ ] **Add Enrollment and StudentProgress to models.py**

Append to `app/challenges/models.py`:

```python
class Enrollment(BaseOrgModel):
    MODEL_ORG_LOOKUP = 'owning_org'

    ACTIVE       = 'active'
    COMPLETED    = 'completed'
    DROPPED      = 'dropped'
    STATUS_CHOICES = [
        (ACTIVE,    'Active'),
        (COMPLETED, 'Completed'),
        (DROPPED,   'Dropped'),
    ]

    challenge   = models.ForeignKey(
        RouteChallenge, on_delete=models.CASCADE, related_name='enrollments'
    )
    student     = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='enrollments'
    )
    status      = models.CharField(max_length=20, choices=STATUS_CHOICES, default=ACTIVE)

    def __str__(self):
        return f'{self.student.email} → {self.challenge.title}'

    class Meta:
        unique_together = ('challenge', 'student')


class StudentProgress(BaseOrgModel):
    MODEL_ORG_LOOKUP = 'owning_org'

    NOT_STARTED = 'not_started'
    IN_PROGRESS = 'in_progress'
    COMPLETED   = 'completed'
    SKIPPED     = 'skipped'
    STATUS_CHOICES = [
        (NOT_STARTED, 'Not started'),
        (IN_PROGRESS, 'In progress'),
        (COMPLETED,   'Completed'),
        (SKIPPED,     'Skipped'),
    ]

    enrollment   = models.ForeignKey(
        Enrollment, on_delete=models.CASCADE, related_name='progress'
    )
    activity     = models.ForeignKey(
        Activity, on_delete=models.CASCADE, related_name='progress'
    )
    status       = models.CharField(max_length=20, choices=STATUS_CHOICES, default=NOT_STARTED)
    response     = models.JSONField(null=True, blank=True)
    score        = models.FloatField(null=True, blank=True)
    started_at   = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f'{self.enrollment.student.email} / {self.activity} [{self.status}]'

    class Meta:
        unique_together = ('enrollment', 'activity')
```

- [ ] **Make and run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py makemigrations challenges"
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Run all model tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_models"
```

Expected: `OK (16 tests)`

- [ ] **Commit**

```bash
git add app/challenges/models.py app/challenges/migrations/ app/challenges/tests/test_models.py
git commit -m "feat: add Enrollment and StudentProgress models"
```

---

## Task 8: Challenge CRUD API (teacher)

**Files:**
- Create: `app/challenges/serializers.py`
- Create: `app/challenges/views_challenge.py`
- Modify: `app/challenges/urls.py`
- Create: `app/challenges/tests/test_api_challenge.py`

- [ ] **Create test file**

Create `app/challenges/tests/test_api_challenge.py`:

```python
"""Tests for /api/challenges/ endpoints."""
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge


CHALLENGE_LIST_URL = reverse('challenges:routechallenge-list')


def detail_url(pk):
    return reverse('challenges:routechallenge-detail', args=[pk])


def make_org_and_producer():
    domain = increment_test_url()
    org = OwningOrg.create_org(domain)
    user = get_user_model().objects.create_user(
        org_domain_name=domain,
        email='teacher@example.com',
        password='pass123',
        is_producer=True,
    )
    return org, user


class PublicChallengeAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()

    def test_list_requires_auth(self):
        res = self.client.get(CHALLENGE_LIST_URL)
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)


class PrivateChallengeAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.user = make_org_and_producer()
        self.client.force_authenticate(user=self.user)

    def test_create_challenge(self):
        payload = {'title': 'Innsbruck Route', 'language': 'de', 'level': 'A1'}
        res = self.client.post(CHALLENGE_LIST_URL, payload)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['title'], 'Innsbruck Route')
        self.assertIn('join_code', res.data)

    def test_list_only_own_org_challenges(self):
        RouteChallenge.objects.create(
            owning_org=self.org, title='Mine', language='de', created_by=self.user
        )
        other_org, other_user = make_org_and_producer()
        RouteChallenge.objects.create(
            owning_org=other_org, title='Theirs', language='fr', created_by=other_user
        )
        res = self.client.get(CHALLENGE_LIST_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        titles = [c['title'] for c in res.data]
        self.assertIn('Mine', titles)
        self.assertNotIn('Theirs', titles)

    def test_retrieve_challenge(self):
        c = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de', created_by=self.user
        )
        res = self.client.get(detail_url(c.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['title'], 'Test')

    def test_patch_challenge(self):
        c = RouteChallenge.objects.create(
            owning_org=self.org, title='Old', language='de', created_by=self.user
        )
        res = self.client.patch(detail_url(c.id), {'title': 'New'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        c.refresh_from_db()
        self.assertEqual(c.title, 'New')
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_challenge"
```

Expected: `NoReverseMatch` (router not yet registered)

- [ ] **Create serializers.py**

Create `app/challenges/serializers.py`:

```python
from rest_framework import serializers
from challenges.models import RouteChallenge, ChallengeStop, Activity, Enrollment, StudentProgress


class RouteChallengeSerializer(serializers.ModelSerializer):
    class Meta:
        model = RouteChallenge
        fields = [
            'id', 'title', 'description', 'language', 'level',
            'ux_mode', 'status', 'join_code', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'join_code', 'status', 'created_at', 'updated_at']


class ChallengeStopSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChallengeStop
        fields = ['id', 'order', 'name', 'lat', 'lng', 'radius_m', 'poi', 'created_at']
        read_only_fields = ['id', 'created_at']


class ActivitySerializer(serializers.ModelSerializer):
    class Meta:
        model = Activity
        fields = ['id', 'order', 'activity_type', 'content', 'unlock_condition', 'created_at']
        read_only_fields = ['id', 'created_at']


class EnrollmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Enrollment
        fields = ['id', 'challenge', 'student', 'status', 'enrolled_at']
        read_only_fields = ['id', 'student', 'status', 'enrolled_at']


class StudentProgressSerializer(serializers.ModelSerializer):
    class Meta:
        model = StudentProgress
        fields = [
            'id', 'enrollment', 'activity', 'status',
            'response', 'score', 'started_at', 'completed_at',
        ]
        read_only_fields = ['id', 'score']
```

- [ ] **Create views_challenge.py**

Create `app/challenges/views_challenge.py`:

```python
from rest_framework import viewsets, permissions
from challenges.models import RouteChallenge
from challenges.serializers import RouteChallengeSerializer


class RouteChallengeViewSet(viewsets.ModelViewSet):
    serializer_class = RouteChallengeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return RouteChallenge.objects.filter(owning_org=self.request.user.owning_org)

    def perform_create(self, serializer):
        serializer.save(
            owning_org=self.request.user.owning_org,
            created_by=self.request.user,
        )
```

- [ ] **Register router in urls.py**

Replace `app/challenges/urls.py`:

```python
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from challenges.views_challenge import RouteChallengeViewSet

app_name = 'challenges'

router = DefaultRouter()
router.register(r'', RouteChallengeViewSet, basename='routechallenge')

urlpatterns = [
    path('', include(router.urls)),
]
```

- [ ] **Run tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_challenge"
```

Expected: `OK (5 tests)`

- [ ] **Commit**

```bash
git add app/challenges/serializers.py app/challenges/views_challenge.py app/challenges/urls.py app/challenges/tests/test_api_challenge.py
git commit -m "feat: add RouteChallenge CRUD API endpoints"
```

---

## Task 9: Stop + Activity nested endpoints + Publish action

**Files:**
- Create: `app/challenges/views_stop.py`
- Create: `app/challenges/views_activity.py`
- Modify: `app/challenges/views_challenge.py` — add publish action
- Modify: `app/challenges/urls.py` — register nested routes
- Create: `app/challenges/tests/test_api_stop_activity.py`

- [ ] **Create test file**

Create `app/challenges/tests/test_api_stop_activity.py`:

```python
"""Tests for stop, activity, and publish endpoints."""
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop, Activity


def make_org_and_producer():
    domain = increment_test_url()
    org = OwningOrg.create_org(domain)
    user = get_user_model().objects.create_user(
        org_domain_name=domain, email='teacher@example.com',
        password='pass123', is_producer=True,
    )
    return org, user


def stops_url(challenge_id):
    return reverse('challenges:challengestop-list', args=[challenge_id])


def stop_detail_url(challenge_id, stop_id):
    return reverse('challenges:challengestop-detail', args=[challenge_id, stop_id])


def activities_url(challenge_id, stop_id):
    return reverse('challenges:activity-list', args=[challenge_id, stop_id])


def publish_url(challenge_id):
    return reverse('challenges:routechallenge-publish', args=[challenge_id])


class StopAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.user = make_org_and_producer()
        self.client.force_authenticate(user=self.user)
        self.challenge = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de', created_by=self.user
        )

    def test_create_stop(self):
        payload = {'order': 1, 'name': 'Hauptbahnhof', 'lat': 47.26303, 'lng': 11.40048}
        res = self.client.post(stops_url(self.challenge.id), payload)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['name'], 'Hauptbahnhof')

    def test_list_stops(self):
        ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=1, name='Stop 1', lat=47.263, lng=11.400
        )
        res = self.client.get(stops_url(self.challenge.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)


class ActivityAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.user = make_org_and_producer()
        self.client.force_authenticate(user=self.user)
        self.challenge = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de', created_by=self.user
        )
        self.stop = ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=1, name='Stop 1', lat=47.263, lng=11.400
        )

    def test_create_quiz_activity(self):
        payload = {
            'order': 1,
            'activity_type': 'QUIZ',
            'content': {
                '_type': 'QUIZ',
                'question': 'Which platform?',
                'options': [
                    {'text': 'Gleis 3', 'is_correct': True},
                    {'text': 'Gleis 7', 'is_correct': False},
                ],
            },
            'unlock_condition': 'previous_complete',
        }
        res = self.client.post(activities_url(self.challenge.id, self.stop.id), payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

    def test_invalid_activity_content_rejected(self):
        payload = {
            'order': 1,
            'activity_type': 'QUIZ',
            'content': {'_type': 'QUIZ'},  # missing options
            'unlock_condition': 'previous_complete',
        }
        res = self.client.post(activities_url(self.challenge.id, self.stop.id), payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)


class PublishActionTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.user = make_org_and_producer()
        self.client.force_authenticate(user=self.user)
        self.challenge = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de', created_by=self.user
        )

    def test_publish_sets_status(self):
        res = self.client.post(publish_url(self.challenge.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.challenge.refresh_from_db()
        self.assertEqual(self.challenge.status, 'published')

    def test_cannot_publish_other_orgs_challenge(self):
        other_org, other_user = make_org_and_producer()
        other_challenge = RouteChallenge.objects.create(
            owning_org=other_org, title='Theirs', language='de', created_by=other_user
        )
        res = self.client.post(publish_url(other_challenge.id))
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_stop_activity"
```

Expected: `NoReverseMatch`

- [ ] **Create views_stop.py**

Create `app/challenges/views_stop.py`:

```python
from rest_framework import viewsets, permissions
from challenges.models import ChallengeStop, RouteChallenge
from challenges.serializers import ChallengeStopSerializer


class ChallengeStopViewSet(viewsets.ModelViewSet):
    serializer_class = ChallengeStopSerializer
    permission_classes = [permissions.IsAuthenticated]

    def _get_challenge(self):
        return RouteChallenge.objects.get(
            id=self.kwargs['challenge_pk'],
            owning_org=self.request.user.owning_org,
        )

    def get_queryset(self):
        return ChallengeStop.objects.filter(
            challenge__id=self.kwargs['challenge_pk'],
            owning_org=self.request.user.owning_org,
        )

    def perform_create(self, serializer):
        challenge = self._get_challenge()
        serializer.save(owning_org=self.request.user.owning_org, challenge=challenge)
```

- [ ] **Create views_activity.py**

Create `app/challenges/views_activity.py`:

```python
from rest_framework import viewsets, permissions
from challenges.models import Activity, ChallengeStop
from challenges.serializers import ActivitySerializer


class ActivityViewSet(viewsets.ModelViewSet):
    serializer_class = ActivitySerializer
    permission_classes = [permissions.IsAuthenticated]

    def _get_stop(self):
        return ChallengeStop.objects.get(
            id=self.kwargs['stop_pk'],
            challenge__id=self.kwargs['challenge_pk'],
            owning_org=self.request.user.owning_org,
        )

    def get_queryset(self):
        return Activity.objects.filter(
            stop__id=self.kwargs['stop_pk'],
            stop__challenge__id=self.kwargs['challenge_pk'],
            owning_org=self.request.user.owning_org,
        )

    def perform_create(self, serializer):
        stop = self._get_stop()
        serializer.save(owning_org=self.request.user.owning_org, stop=stop)
```

- [ ] **Add publish action to views_challenge.py**

Add to `app/challenges/views_challenge.py`:

```python
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status

# Add this method inside RouteChallengeViewSet:
    @action(detail=True, methods=['post'], url_path='publish')
    def publish(self, request, pk=None):
        challenge = self.get_object()
        challenge.status = RouteChallenge.PUBLISHED
        challenge.save(update_fields=['status'])
        return Response({'status': challenge.status})
```

- [ ] **Update urls.py with nested routes**

Replace `app/challenges/urls.py`:

```python
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_nested import routers as nested_routers

from challenges.views_challenge import RouteChallengeViewSet
from challenges.views_stop import ChallengeStopViewSet
from challenges.views_activity import ActivityViewSet

app_name = 'challenges'

router = DefaultRouter()
router.register(r'', RouteChallengeViewSet, basename='routechallenge')

stops_router = nested_routers.NestedDefaultRouter(router, r'', lookup='challenge')
stops_router.register(r'stops', ChallengeStopViewSet, basename='challengestop')

activities_router = nested_routers.NestedDefaultRouter(stops_router, r'stops', lookup='stop')
activities_router.register(r'activities', ActivityViewSet, basename='activity')

urlpatterns = [
    path('', include(router.urls)),
    path('', include(stops_router.urls)),
    path('', include(activities_router.urls)),
]
```

> **Note:** This requires `drf-nested-routers`. Check if it's in requirements: `grep nested /requirements.txt`. If not, add `drf-nested-routers` to requirements and rebuild the Docker image.

- [ ] **Check/add drf-nested-routers**

```bash
grep -i nested /home/john/strollopia_git_hub/strollopia-api/requirements.txt
```

If not found:
```bash
echo "drf-nested-routers" >> /home/john/strollopia_git_hub/strollopia-api/requirements.txt
docker compose build
```

- [ ] **Run tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_stop_activity"
```

Expected: `OK (7 tests)`

- [ ] **Commit**

```bash
git add app/challenges/views_stop.py app/challenges/views_activity.py app/challenges/views_challenge.py app/challenges/urls.py app/challenges/tests/test_api_stop_activity.py requirements.txt
git commit -m "feat: add stop, activity, and publish endpoints"
```

---

## Task 10: Enrollment + Progress endpoints

**Files:**
- Create: `app/challenges/views_enrollment.py`
- Create: `app/challenges/views_progress.py`
- Modify: `app/challenges/urls.py`
- Create: `app/challenges/tests/test_api_enrollment.py`

- [ ] **Create test file**

Create `app/challenges/tests/test_api_enrollment.py`:

```python
"""Tests for enrollment and progress endpoints."""
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop, Activity, Enrollment, StudentProgress


def make_org_and_users():
    domain = increment_test_url()
    org = OwningOrg.create_org(domain)
    teacher = get_user_model().objects.create_user(
        org_domain_name=domain, email='teacher@example.com',
        password='pass123', is_producer=True,
    )
    student = get_user_model().objects.create_user(
        org_domain_name=domain, email='student@example.com',
        password='pass123', is_consumer=True,
    )
    return org, teacher, student


ENROLL_URL = reverse('challenges:enrollment-list')
MY_PROGRESS_URL = reverse('challenges:my-progress')


def challenge_progress_url(challenge_id):
    return reverse('challenges:challenge-progress', args=[challenge_id])


class EnrollmentAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.teacher, self.student = make_org_and_users()
        self.challenge = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de',
            status='published', created_by=self.teacher,
        )

    def test_student_can_join_by_code(self):
        self.client.force_authenticate(user=self.student)
        res = self.client.post(ENROLL_URL, {'join_code': self.challenge.join_code})
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Enrollment.objects.filter(
            challenge=self.challenge, student=self.student
        ).exists())

    def test_invalid_code_rejected(self):
        self.client.force_authenticate(user=self.student)
        res = self.client.post(ENROLL_URL, {'join_code': 'BADCODE123'})
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_teacher_can_list_enrollments(self):
        Enrollment.objects.create(
            owning_org=self.org, challenge=self.challenge, student=self.student
        )
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get(ENROLL_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)


class ProgressAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org, self.teacher, self.student = make_org_and_users()
        self.challenge = RouteChallenge.objects.create(
            owning_org=self.org, title='Test', language='de',
            status='published', created_by=self.teacher,
        )
        self.stop = ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=1, name='Stop 1', lat=47.263, lng=11.400,
        )
        self.activity = Activity.objects.create(
            owning_org=self.org, stop=self.stop, order=1,
            activity_type='CHECKIN',
            content={'_type': 'CHECKIN', 'instruction': 'Scan QR.'},
        )
        self.enrollment = Enrollment.objects.create(
            owning_org=self.org, challenge=self.challenge, student=self.student
        )

    def test_student_submit_progress(self):
        self.client.force_authenticate(user=self.student)
        payload = {
            'enrollment': self.enrollment.id,
            'activity': self.activity.id,
            'status': 'completed',
            'response': {'checked_in': True},
        }
        res = self.client.post(reverse('challenges:progress-submit'), payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

    def test_teacher_sees_all_student_progress(self):
        StudentProgress.objects.create(
            owning_org=self.org, enrollment=self.enrollment, activity=self.activity,
            status='completed',
        )
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get(challenge_progress_url(self.challenge.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)

    def test_student_sees_own_progress(self):
        StudentProgress.objects.create(
            owning_org=self.org, enrollment=self.enrollment, activity=self.activity,
            status='in_progress',
        )
        self.client.force_authenticate(user=self.student)
        res = self.client.get(MY_PROGRESS_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
```

- [ ] **Run to verify they fail**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_enrollment"
```

Expected: `NoReverseMatch`

- [ ] **Create views_enrollment.py**

Create `app/challenges/views_enrollment.py`:

```python
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from challenges.models import RouteChallenge, Enrollment
from challenges.serializers import EnrollmentSerializer


class EnrollmentListCreateView(generics.ListCreateAPIView):
    serializer_class = EnrollmentSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Enrollment.objects.filter(
            challenge__owning_org=self.request.user.owning_org
        )

    def create(self, request, *args, **kwargs):
        join_code = request.data.get('join_code')
        try:
            challenge = RouteChallenge.objects.get(
                join_code=join_code,
                owning_org=request.user.owning_org,
                status=RouteChallenge.PUBLISHED,
            )
        except RouteChallenge.DoesNotExist:
            return Response({'join_code': 'Invalid or inactive join code.'}, status=status.HTTP_400_BAD_REQUEST)

        enrollment, created = Enrollment.objects.get_or_create(
            challenge=challenge,
            student=request.user,
            defaults={'owning_org': request.user.owning_org},
        )
        serializer = self.get_serializer(enrollment)
        http_status = status.HTTP_201_CREATED if created else status.HTTP_200_OK
        return Response(serializer.data, status=http_status)
```

- [ ] **Create views_progress.py**

Create `app/challenges/views_progress.py`:

```python
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from challenges.models import StudentProgress, Enrollment, RouteChallenge
from challenges.serializers import StudentProgressSerializer


class ProgressSubmitView(generics.CreateAPIView):
    serializer_class = StudentProgressSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        serializer.save(owning_org=self.request.user.owning_org)


class ChallengeProgressView(APIView):
    """Teacher view: all student progress for a specific challenge."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, challenge_pk):
        challenge = RouteChallenge.objects.get(
            id=challenge_pk, owning_org=request.user.owning_org
        )
        progress = StudentProgress.objects.filter(
            enrollment__challenge=challenge
        )
        serializer = StudentProgressSerializer(progress, many=True)
        return Response(serializer.data)


class MyProgressView(generics.ListAPIView):
    """Student view: own progress across all enrollments."""
    serializer_class = StudentProgressSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return StudentProgress.objects.filter(
            enrollment__student=self.request.user
        )
```

- [ ] **Update urls.py**

Replace `app/challenges/urls.py` (keep existing router and nested routers, add these paths):

```python
from challenges.views_enrollment import EnrollmentListCreateView
from challenges.views_progress import ProgressSubmitView, ChallengeProgressView, MyProgressView

# Add inside urlpatterns after existing includes:
    path('enrollments/', EnrollmentListCreateView.as_view(), name='enrollment-list'),
    path('progress/', ProgressSubmitView.as_view(), name='progress-submit'),
    path('<int:challenge_pk>/progress/', ChallengeProgressView.as_view(), name='challenge-progress'),
    path('me/progress/', MyProgressView.as_view(), name='my-progress'),
```

- [ ] **Run tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges.tests.test_api_enrollment"
```

Expected: `OK (6 tests)`

- [ ] **Run all challenges tests**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test challenges"
```

Expected: `OK (29+ tests)`

- [ ] **Commit**

```bash
git add app/challenges/views_enrollment.py app/challenges/views_progress.py app/challenges/urls.py app/challenges/tests/test_api_enrollment.py
git commit -m "feat: add enrollment join-by-code and progress endpoints"
```

---

## Task 11: Admin registration + Plugin seed data

**Files:**
- Modify: `app/challenges/admin.py`
- Modify: `app/core/admin.py`
- Create: `app/challenges/migrations/0003_seed_learning_plugin.py`

- [ ] **Register challenges models in admin**

Replace `app/challenges/admin.py`:

```python
from django.contrib import admin
from challenges.models import RouteChallenge, ChallengeStop, Activity, Enrollment, StudentProgress


class ChallengeStopInline(admin.TabularInline):
    model = ChallengeStop
    extra = 0
    fields = ['order', 'name', 'lat', 'lng', 'radius_m', 'poi']


@admin.register(RouteChallenge)
class RouteChallengeAdmin(admin.ModelAdmin):
    list_display = ['title', 'owning_org', 'language', 'level', 'status', 'created_by', 'created_at']
    list_filter = ['status', 'language']
    search_fields = ['title', 'owning_org__org_domain_name']
    readonly_fields = ['join_code', 'created_at', 'updated_at']
    inlines = [ChallengeStopInline]


@admin.register(Activity)
class ActivityAdmin(admin.ModelAdmin):
    list_display = ['stop', 'order', 'activity_type', 'unlock_condition']
    list_filter = ['activity_type']


@admin.register(Enrollment)
class EnrollmentAdmin(admin.ModelAdmin):
    list_display = ['student', 'challenge', 'status', 'enrolled_at']
    list_filter = ['status']


@admin.register(StudentProgress)
class StudentProgressAdmin(admin.ModelAdmin):
    list_display = ['enrollment', 'activity', 'status', 'score', 'completed_at']
    list_filter = ['status']
```

- [ ] **Register Plugin + OrgPlugin in core admin**

Add to `app/core/admin.py`:

```python
from core.models import Plugin, OrgPlugin, OrgSiteConfig

@admin.register(Plugin)
class PluginAdmin(admin.ModelAdmin):
    list_display = ['key', 'name', 'is_available', 'version']
    search_fields = ['key', 'name']

@admin.register(OrgPlugin)
class OrgPluginAdmin(admin.ModelAdmin):
    list_display = ['owning_org', 'plugin', 'status', 'activated_at', 'activated_by']
    list_filter = ['status', 'plugin']
    search_fields = ['owning_org__org_domain_name']

@admin.register(OrgSiteConfig)
class OrgSiteConfigAdmin(admin.ModelAdmin):
    list_display = ['owning_org', 'google_analytics_id']
    search_fields = ['owning_org__org_domain_name']
```

- [ ] **Create seed migration for learning Plugin row**

Create `app/challenges/migrations/0003_seed_learning_plugin.py`:

```python
from django.db import migrations


def seed_learning_plugin(apps, schema_editor):
    Plugin = apps.get_model('core', 'Plugin')
    Plugin.objects.get_or_create(
        key='learning',
        defaults={
            'name': 'Place-Based Learning',
            'description': (
                'Teachers build geo-located route challenges. '
                'Students complete language activities at real-world stops.'
            ),
            'is_available': True,
            'quick_start': (
                '1. Create a Route Challenge\n'
                '2. Add stops on the map\n'
                '3. Attach activities to each stop\n'
                '4. Publish and share the join code with your class'
            ),
            'version': '1.0.0',
        }
    )


def unseed_learning_plugin(apps, schema_editor):
    Plugin = apps.get_model('core', 'Plugin')
    Plugin.objects.filter(key='learning').delete()


class Migration(migrations.Migration):

    dependencies = [
        ('challenges', '0002_activity'),  # adjust to your actual last migration name
        ('core', '0001_initial'),         # adjust to your actual core migration with Plugin
    ]

    operations = [
        migrations.RunPython(seed_learning_plugin, unseed_learning_plugin),
    ]
```

> **Note:** Check the actual migration names with `ls app/challenges/migrations/` and `ls app/core/migrations/` and update the `dependencies` list to match your latest migrations.

- [ ] **Run migration**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py migrate"
```

- [ ] **Verify admin loads**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py check"
```

Expected: `System check identified no issues (0 silenced).`

- [ ] **Run full test suite**

```bash
make test
```

Expected: All existing tests pass, no regressions.

- [ ] **Commit**

```bash
git add app/challenges/admin.py app/core/admin.py app/challenges/migrations/
git commit -m "feat: register challenges and plugin models in Django admin; seed learning plugin row"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `is_producer` / `is_consumer` on User | Task 1 |
| `SG` UiType for strollopia-guide | Task 1 |
| `Plugin` model (key, onboarding fields) | Task 2 |
| `OrgPlugin` model (lifecycle, PROTECT FK) | Task 2 |
| `OrgSiteConfig` OneToOne | Task 3 |
| `challenges` app scaffolded | Task 4 |
| `RouteChallenge` + `ChallengeStop` | Task 5 |
| `Activity` + JSON schema validation | Task 6 |
| `Enrollment` + `StudentProgress` | Task 7 |
| Challenge CRUD endpoints | Task 8 |
| Stop + Activity nested endpoints | Task 9 |
| Publish action | Task 9 |
| Enrollment join-by-code | Task 10 |
| Progress submit (student) | Task 10 |
| Teacher progress view | Task 10 |
| Student own-progress view | Task 10 |
| Django admin registration | Task 11 |
| Plugin seed data | Task 11 |

All spec requirements covered. No TBDs or placeholders.
