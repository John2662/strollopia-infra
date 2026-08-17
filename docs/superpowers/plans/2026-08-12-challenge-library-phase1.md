# Challenge Library & Clone — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ChallengeCategory`, five new fields on `RouteChallenge`, a transactional clone service, and a two-step Django admin action that clones challenges across orgs.

**Architecture:** `ChallengeCategory` is a global model (derives from `models.Model`, not `BaseOrgModel`) so it sits outside the org silo. Five fields are added to `RouteChallenge` via two sequential migrations. The clone service is a standalone `@transaction.atomic` function in `challenges/services.py` — the admin action is a thin wrapper around it, keeping the service reusable for the Phase 2 REST endpoint. The two-step admin action follows the existing `"apply" in request.POST` pattern used by `DemoRequestAdmin`.

**Tech Stack:** Django 5.x, Django admin, PostgreSQL. No frontend changes.

---

## File Map

| Action | Path |
|---|---|
| Modify | `app/challenges/models.py` |
| Create | `app/challenges/migrations/0005_challengecategory.py` |
| Create | `app/challenges/migrations/0006_routechallenge_library_fields.py` |
| Create | `app/challenges/services.py` |
| Modify | `app/challenges/admin.py` |
| Create | `app/templates/admin/challenges/clone_to_org.html` |
| Modify | `app/challenges/tests/test_models.py` |
| Create | `app/challenges/tests/test_services.py` |
| Create | `app/challenges/tests/test_admin_clone.py` |

All paths are relative to `/home/john/strollopia_git_hub/strollopia-api/`.

---

## Task 1: ChallengeCategory model

**Files:**
- Modify: `app/challenges/models.py` (insert before `RouteChallenge`)
- Create: `app/challenges/migrations/0005_challengecategory.py`
- Modify: `app/challenges/tests/test_models.py`

- [ ] **Step 1: Write failing tests for ChallengeCategory**

Add to the bottom of `app/challenges/tests/test_models.py`:

```python
from challenges.models import ChallengeCategory


class ChallengeCategoryTests(TestCase):

    def test_create_category(self):
        cat = ChallengeCategory.objects.create(
            name='Language Learning',
            slug='language-learning',
            default_icon='🗣️',
        )
        self.assertEqual(str(cat), 'Language Learning')
        self.assertEqual(cat.default_icon, '🗣️')

    def test_description_and_icon_optional(self):
        cat = ChallengeCategory.objects.create(name='History', slug='history')
        self.assertEqual(cat.description, '')
        self.assertEqual(cat.default_icon, '')

    def test_ordering_by_name(self):
        ChallengeCategory.objects.create(name='Zebra', slug='zebra')
        ChallengeCategory.objects.create(name='Aardvark', slug='aardvark')
        names = list(ChallengeCategory.objects.values_list('name', flat=True))
        self.assertEqual(names[0], 'Aardvark')
```

- [ ] **Step 2: Run — expect ImportError (model doesn't exist yet)**

```bash
cd /home/john/strollopia_git_hub/strollopia-api/app
python manage.py test challenges.tests.test_models.ChallengeCategoryTests --verbosity=2 2>&1 | tail -20
```

Expected: `ImportError: cannot import name 'ChallengeCategory'`

- [ ] **Step 3: Add ChallengeCategory to models.py**

Insert this block in `app/challenges/models.py` **before** the `RouteChallenge` class (after the imports):

```python
class ChallengeCategory(models.Model):
    name         = models.CharField(max_length=100, unique=True)
    slug         = models.SlugField(unique=True)
    description  = models.TextField(blank=True)
    default_icon = models.CharField(max_length=20, blank=True)

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'challenge categories'

    def __str__(self):
        return self.name
```

- [ ] **Step 4: Create migration 0005**

Create `app/challenges/migrations/0005_challengecategory.py`:

```python
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('challenges', '0004_seed_learning_plugin'),
    ]

    operations = [
        migrations.CreateModel(
            name='ChallengeCategory',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=100, unique=True)),
                ('slug', models.SlugField(unique=True)),
                ('description', models.TextField(blank=True)),
                ('default_icon', models.CharField(blank=True, max_length=20)),
            ],
            options={
                'verbose_name_plural': 'challenge categories',
                'ordering': ['name'],
            },
        ),
    ]
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
python manage.py test challenges.tests.test_models.ChallengeCategoryTests --verbosity=2 2>&1 | tail -20
```

Expected: `Ran 3 tests in ...s OK`

- [ ] **Step 6: Commit**

```bash
git add app/challenges/models.py app/challenges/migrations/0005_challengecategory.py app/challenges/tests/test_models.py
git commit -m "feat: add ChallengeCategory model and migration 0005"
```

---

## Task 2: RouteChallenge new fields

**Files:**
- Modify: `app/challenges/models.py` (add 5 fields to RouteChallenge)
- Create: `app/challenges/migrations/0006_routechallenge_library_fields.py`
- Modify: `app/challenges/tests/test_models.py`

- [ ] **Step 1: Write failing tests**

Add to `RouteChallengeTests` in `app/challenges/tests/test_models.py`:

```python
    def test_new_fields_have_correct_defaults(self):
        c = make_challenge(self.org, self.user)
        self.assertFalse(c.is_template)
        self.assertIsNone(c.category)
        self.assertEqual(c.author_name, '')
        self.assertEqual(c.content_language, 'en')
        self.assertEqual(c.challenge_icon, '')

    def test_set_library_fields(self):
        cat = ChallengeCategory.objects.create(name='Lang', slug='lang')
        c = make_challenge(
            self.org, self.user,
            is_template=True,
            category=cat,
            author_name='María García',
            content_language='fr',
            challenge_icon='🇫🇷',
        )
        self.assertTrue(c.is_template)
        self.assertEqual(c.category, cat)
        self.assertEqual(c.author_name, 'María García')
        self.assertEqual(c.content_language, 'fr')
        self.assertEqual(c.challenge_icon, '🇫🇷')
```

- [ ] **Step 2: Run — expect failure (fields don't exist)**

```bash
python manage.py test challenges.tests.test_models.RouteChallengeTests.test_new_fields_have_correct_defaults --verbosity=2 2>&1 | tail -15
```

Expected: `AttributeError: 'RouteChallenge' object has no attribute 'is_template'`

- [ ] **Step 3: Add five fields to RouteChallenge in models.py**

After the `created_by` field in `RouteChallenge`, add:

```python
    is_template      = models.BooleanField(default=False)
    category         = models.ForeignKey(
        'ChallengeCategory',
        null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name='challenges',
    )
    author_name      = models.CharField(max_length=200, blank=True)
    content_language = models.CharField(max_length=10, default='en')
    challenge_icon   = models.CharField(max_length=20, blank=True)
```

- [ ] **Step 4: Create migration 0006**

Create `app/challenges/migrations/0006_routechallenge_library_fields.py`:

```python
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('challenges', '0005_challengecategory'),
    ]

    operations = [
        migrations.AddField(
            model_name='routechallenge',
            name='is_template',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='routechallenge',
            name='category',
            field=models.ForeignKey(
                blank=True, null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='challenges',
                to='challenges.challengecategory',
            ),
        ),
        migrations.AddField(
            model_name='routechallenge',
            name='author_name',
            field=models.CharField(blank=True, max_length=200),
        ),
        migrations.AddField(
            model_name='routechallenge',
            name='content_language',
            field=models.CharField(default='en', max_length=10),
        ),
        migrations.AddField(
            model_name='routechallenge',
            name='challenge_icon',
            field=models.CharField(blank=True, max_length=20),
        ),
    ]
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
python manage.py test challenges.tests.test_models.RouteChallengeTests --verbosity=2 2>&1 | tail -15
```

Expected: `Ran 7 tests in ...s OK`

- [ ] **Step 6: Verify migrations are consistent**

```bash
python manage.py migrate --run-syncdb 2>&1 | tail -10
python manage.py migrate 2>&1 | tail -10
```

Expected: `No migrations to apply.`

- [ ] **Step 7: Commit**

```bash
git add app/challenges/models.py app/challenges/migrations/0006_routechallenge_library_fields.py app/challenges/tests/test_models.py
git commit -m "feat: add is_template, category, author_name, content_language, challenge_icon to RouteChallenge"
```

---

## Task 3: Clone service

**Files:**
- Create: `app/challenges/services.py`
- Create: `app/challenges/tests/test_services.py`

- [ ] **Step 1: Write failing tests**

Create `app/challenges/tests/test_services.py`:

```python
"""Tests for challenges/services.py — clone_challenge()."""
from unittest.mock import patch

from django.test import TestCase
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop, Activity, ChallengeCategory
from challenges.services import clone_challenge


def make_org():
    return OwningOrg.create_org(increment_test_url())


def make_user(org, email='teacher@example.com'):
    return get_user_model().objects.create_user(
        org_domain_name=org.org_domain_name,
        email=email,
        password='pass123',
        is_producer=True,
    )


def make_stop(org, challenge, order=1, name='Hauptbahnhof'):
    return ChallengeStop.objects.create(
        owning_org=org, challenge=challenge,
        order=order, name=name, lat=47.263, lng=11.400,
    )


def make_activity(org, stop, order=1):
    return Activity.objects.create(
        owning_org=org, stop=stop, order=order,
        activity_type='CHECKIN',
        content={'_type': 'CHECKIN', 'instruction': 'Scan QR.'},
    )


class CloneChallengeTests(TestCase):

    def setUp(self):
        self.src_org = make_org()
        self.dst_org = make_org()
        self.src_user = make_user(self.src_org)
        self.dst_user = make_user(self.dst_org, 'dst@example.com')
        self.cat = ChallengeCategory.objects.create(
            name='Language Learning', slug='lang', default_icon='🗣️'
        )
        self.source = RouteChallenge.objects.create(
            owning_org=self.src_org,
            created_by=self.src_user,
            title='Innsbruck Nouns',
            language='de',
            level='A1',
            is_template=True,
            category=self.cat,
            author_name='Original Author',
            content_language='en',
            challenge_icon='🇩🇪',
        )
        stop = make_stop(self.src_org, self.source)
        make_activity(self.src_org, stop)

    def test_clone_belongs_to_target_org(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.owning_org, self.dst_org)
        self.assertEqual(clone.created_by, self.dst_user)

    def test_clone_title_prefixed(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.title, 'Copy of Innsbruck Nouns')

    def test_clone_is_draft_not_template(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.status, RouteChallenge.DRAFT)
        self.assertFalse(clone.is_template)

    def test_clone_has_unique_join_code(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertNotEqual(clone.join_code, self.source.join_code)
        self.assertTrue(len(clone.join_code) > 0)

    def test_clone_copies_metadata_fields(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.category, self.cat)
        self.assertEqual(clone.author_name, 'Original Author')
        self.assertEqual(clone.content_language, 'en')
        self.assertEqual(clone.challenge_icon, '🇩🇪')
        self.assertEqual(clone.language, 'de')
        self.assertEqual(clone.level, 'A1')

    def test_clone_copies_stops(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.stops.count(), 1)
        cloned_stop = clone.stops.first()
        self.assertEqual(cloned_stop.name, 'Hauptbahnhof')
        self.assertEqual(cloned_stop.owning_org, self.dst_org)

    def test_clone_nulls_poi_on_stops(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        for stop in clone.stops.all():
            self.assertIsNone(stop.poi)

    def test_clone_copies_activities(self):
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        cloned_stop = clone.stops.first()
        self.assertEqual(cloned_stop.activities.count(), 1)
        act = cloned_stop.activities.first()
        self.assertEqual(act.activity_type, 'CHECKIN')
        self.assertEqual(act.owning_org, self.dst_org)

    def test_source_is_unchanged_after_clone(self):
        clone_challenge(self.source, self.dst_org, self.dst_user)
        self.source.refresh_from_db()
        self.assertTrue(self.source.is_template)
        self.assertEqual(self.source.stops.count(), 1)

    def test_clone_multiple_stops_and_activities(self):
        stop2 = make_stop(self.src_org, self.source, order=2, name='Triumphal Arch')
        make_activity(self.src_org, stop2, order=1)
        make_activity(self.src_org, stop2, order=2)
        clone = clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(clone.stops.count(), 2)
        arch_stop = clone.stops.get(name='Triumphal Arch')
        self.assertEqual(arch_stop.activities.count(), 2)

    def test_failed_stop_save_rolls_back_entire_clone(self):
        with patch.object(ChallengeStop, 'save', side_effect=Exception('db fail')):
            with self.assertRaises(Exception, msg='db fail'):
                clone_challenge(self.source, self.dst_org, self.dst_user)
        self.assertEqual(RouteChallenge.objects.filter(owning_org=self.dst_org).count(), 0)
```

- [ ] **Step 2: Run — expect ImportError**

```bash
python manage.py test challenges.tests.test_services --verbosity=2 2>&1 | tail -10
```

Expected: `ImportError: cannot import name 'clone_challenge' from 'challenges.services'`

- [ ] **Step 3: Create challenges/services.py**

Create `app/challenges/services.py`:

```python
from django.db import transaction

from .models import RouteChallenge, ChallengeStop, Activity


@transaction.atomic
def clone_challenge(source: RouteChallenge, target_org, cloned_by) -> RouteChallenge:
    """
    Deep-copies source into target_org.
    poi is nulled on each stop — cross-org POI copy is out of scope.
    Clone starts as DRAFT with is_template=False.
    join_code is auto-generated by RouteChallenge.save().
    """
    new_challenge = RouteChallenge(
        owning_org=target_org,
        created_by=cloned_by,
        title=f'Copy of {source.title}',
        description=source.description,
        language=source.language,
        level=source.level,
        ux_mode=source.ux_mode,
        category=source.category,
        author_name=source.author_name,
        content_language=source.content_language,
        challenge_icon=source.challenge_icon,
        status=RouteChallenge.DRAFT,
        is_template=False,
    )
    new_challenge.save()

    for stop in source.stops.order_by('order'):
        new_stop = ChallengeStop(
            owning_org=target_org,
            challenge=new_challenge,
            order=stop.order,
            name=stop.name,
            lat=stop.lat,
            lng=stop.lng,
            radius_m=stop.radius_m,
            poi=None,
        )
        new_stop.save()

        for activity in stop.activities.order_by('order'):
            Activity(
                owning_org=target_org,
                stop=new_stop,
                order=activity.order,
                activity_type=activity.activity_type,
                content=activity.content,
                unlock_condition=activity.unlock_condition,
            ).save()

    return new_challenge
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
python manage.py test challenges.tests.test_services --verbosity=2 2>&1 | tail -15
```

Expected: `Ran 11 tests in ...s OK`

- [ ] **Step 5: Commit**

```bash
git add app/challenges/services.py app/challenges/tests/test_services.py
git commit -m "feat: clone_challenge service with full deep-copy and atomic rollback"
```

---

## Task 4: Admin — ChallengeCategory + updated RouteChallengeAdmin

**Files:**
- Modify: `app/challenges/admin.py`

- [ ] **Step 1: Replace admin.py with updated version**

Rewrite `app/challenges/admin.py` in full:

```python
from django import forms
from django.contrib import admin, messages
from django.contrib.admin import ACTION_CHECKBOX_NAME
from django.template.response import TemplateResponse

from core.models import OwningOrg
from challenges.models import (
    RouteChallenge, ChallengeStop, Activity,
    Enrollment, StudentProgress, ChallengeCategory,
)
from challenges.services import clone_challenge


class ChallengeStopInline(admin.TabularInline):
    model = ChallengeStop
    extra = 0
    fields = ['order', 'name', 'lat', 'lng', 'radius_m', 'poi']


class CloneToOrgForm(forms.Form):
    target_org = forms.ModelChoiceField(
        queryset=OwningOrg.objects.all().order_by('org_domain_name'),
        label='Target organisation',
        help_text='Challenges will be cloned into this org as DRAFTs.',
    )


@admin.register(ChallengeCategory)
class ChallengeCategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'default_icon', 'description']
    prepopulated_fields = {'slug': ('name',)}
    search_fields = ['name']


@admin.register(RouteChallenge)
class RouteChallengeAdmin(admin.ModelAdmin):
    list_display = [
        'title', 'owning_org', 'language', 'level', 'status',
        'is_template', 'category', 'challenge_icon', 'content_language',
        'created_by', 'created_at',
    ]
    list_filter = ['status', 'is_template', 'category', 'language', 'content_language']
    search_fields = ['title', 'owning_org__org_domain_name']
    readonly_fields = ['join_code', 'created_at', 'updated_at']
    inlines = [ChallengeStopInline]
    actions = ['clone_to_org']

    def clone_to_org(self, request, queryset):
        if 'apply' in request.POST:
            form = CloneToOrgForm(request.POST)
            if form.is_valid():
                target_org = form.cleaned_data['target_org']
                cloned = 0
                for source in queryset:
                    try:
                        clone_challenge(source, target_org, request.user)
                        cloned += 1
                    except Exception as e:
                        self.message_user(
                            request,
                            f'Failed to clone "{source.title}": {e}',
                            messages.ERROR,
                        )
                if cloned:
                    self.message_user(
                        request,
                        f'Cloned {cloned} challenge(s) into {target_org.org_domain_name}.',
                        messages.SUCCESS,
                    )
                return None
        else:
            form = CloneToOrgForm()

        return TemplateResponse(
            request,
            'admin/challenges/clone_to_org.html',
            {
                'title': 'Clone challenges to org',
                'challenges': queryset,
                'form': form,
                'action_checkbox_name': ACTION_CHECKBOX_NAME,
                'selected_ids': request.POST.getlist(ACTION_CHECKBOX_NAME),
                'opts': self.model._meta,
            },
        )

    clone_to_org.short_description = 'Clone selected challenges to another org'


@admin.register(Activity)
class ActivityAdmin(admin.ModelAdmin):
    list_display = ['stop', 'order', 'activity_type', 'unlock_condition']
    list_filter = ['activity_type']


@admin.register(Enrollment)
class EnrollmentAdmin(admin.ModelAdmin):
    list_display = ['student', 'challenge', 'status', 'created_at']
    list_filter = ['status']


@admin.register(StudentProgress)
class StudentProgressAdmin(admin.ModelAdmin):
    list_display = ['enrollment', 'activity', 'status', 'score', 'completed_at']
    list_filter = ['status']
```

- [ ] **Step 2: Verify admin loads without errors**

```bash
python manage.py check --deploy 2>&1 | grep -E "ERROR|challenges" | head -20
python manage.py check 2>&1 | tail -5
```

Expected: `System check identified no issues (0 silenced).`

- [ ] **Step 3: Commit**

```bash
git add app/challenges/admin.py
git commit -m "feat: ChallengeCategoryAdmin + clone_to_org action on RouteChallengeAdmin"
```

---

## Task 5: Clone action template + admin tests

**Files:**
- Create: `app/templates/admin/challenges/clone_to_org.html`
- Create: `app/challenges/tests/test_admin_clone.py`

- [ ] **Step 1: Write failing admin tests**

Create `app/challenges/tests/test_admin_clone.py`:

```python
"""Tests for the clone_to_org admin action."""
from django.test import TestCase
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeCategory, ChallengeStop, Activity

CHANGELIST_URL = '/admin/challenges/routechallenge/'


def make_org():
    return OwningOrg.create_org(increment_test_url())


def make_superuser(org):
    return get_user_model().objects.create_superuser(
        org_domain_name=org.org_domain_name,
        email='admin@example.com',
        password='admin123',
    )


def make_challenge(org, user, **kwargs):
    defaults = dict(
        owning_org=org, title='Test Challenge',
        language='de', level='A1', created_by=user,
    )
    defaults.update(kwargs)
    return RouteChallenge.objects.create(**defaults)


class CloneAdminActionTests(TestCase):

    def setUp(self):
        self.src_org = make_org()
        self.dst_org = make_org()
        self.admin_user = make_superuser(self.src_org)
        self.client.force_login(self.admin_user)
        self.cat = ChallengeCategory.objects.create(
            name='Language', slug='language', default_icon='🗣️'
        )
        self.challenge = make_challenge(
            self.src_org, self.admin_user,
            is_template=True, category=self.cat, challenge_icon='🇩🇪',
        )

    def test_action_returns_intermediate_page(self):
        res = self.client.post(CHANGELIST_URL, {
            'action': 'clone_to_org',
            '_selected_action': [str(self.challenge.pk)],
        })
        self.assertEqual(res.status_code, 200)
        self.assertContains(res, self.challenge.title)
        self.assertContains(res, 'Target organisation')
        self.assertContains(res, 'clone_to_org')

    def test_intermediate_page_lists_selected_challenges(self):
        res = self.client.post(CHANGELIST_URL, {
            'action': 'clone_to_org',
            '_selected_action': [str(self.challenge.pk)],
        })
        self.assertContains(res, 'Test Challenge')

    def test_apply_clones_into_target_org(self):
        res = self.client.post(CHANGELIST_URL, {
            'action': 'clone_to_org',
            '_selected_action': [str(self.challenge.pk)],
            'apply': '1',
            'target_org': str(self.dst_org.pk),
        })
        self.assertEqual(res.status_code, 302)
        clone = RouteChallenge.objects.filter(owning_org=self.dst_org).first()
        self.assertIsNotNone(clone)
        self.assertEqual(clone.title, f'Copy of {self.challenge.title}')
        self.assertFalse(clone.is_template)
        self.assertEqual(clone.status, RouteChallenge.DRAFT)

    def test_apply_with_invalid_org_shows_form_errors(self):
        res = self.client.post(CHANGELIST_URL, {
            'action': 'clone_to_org',
            '_selected_action': [str(self.challenge.pk)],
            'apply': '1',
            'target_org': '999999',  # non-existent org pk
        })
        self.assertEqual(res.status_code, 200)
        self.assertContains(res, 'select a valid choice')

    def test_unauthenticated_user_cannot_access_admin(self):
        self.client.logout()
        res = self.client.post(CHANGELIST_URL, {
            'action': 'clone_to_org',
            '_selected_action': [str(self.challenge.pk)],
        })
        self.assertNotEqual(res.status_code, 200)
```

- [ ] **Step 2: Run — expect template not found or 200 but no template**

```bash
python manage.py test challenges.tests.test_admin_clone --verbosity=2 2>&1 | tail -20
```

Expected: `TemplateDoesNotExist: admin/challenges/clone_to_org.html`

- [ ] **Step 3: Create the template directory and file**

```bash
mkdir -p /home/john/strollopia_git_hub/strollopia-api/app/templates/admin/challenges
```

Create `app/templates/admin/challenges/clone_to_org.html`:

```html
{% extends "admin/base_site.html" %}

{% block content %}
<h1>{{ title }}</h1>

<p>The following {{ challenges|length }} challenge{{ challenges|length|pluralize }} will be cloned:</p>

<ul>
  {% for c in challenges %}
    <li>
      <strong>{{ c.title }}</strong>
      ({{ c.owning_org }})
      — {{ c.stops.count }} stop{{ c.stops.count|pluralize }}
      {% if c.challenge_icon %} {{ c.challenge_icon }}{% endif %}
    </li>
  {% endfor %}
</ul>

<p>Each challenge will be cloned as a <strong>DRAFT</strong> with <code>is_template=False</code>.
   The POI link on each stop will be cleared.</p>

<form method="post">
  {% csrf_token %}
  <input type="hidden" name="action" value="clone_to_org">
  <input type="hidden" name="apply" value="1">
  {% for id in selected_ids %}
    <input type="hidden" name="{{ action_checkbox_name }}" value="{{ id }}">
  {% endfor %}

  <fieldset class="module aligned">
    {{ form.as_p }}
  </fieldset>

  <div class="submit-row">
    <input type="submit" value="Clone challenges" class="default">
    <a href=".." class="button cancel-link">Cancel</a>
  </div>
</form>
{% endblock %}
```

- [ ] **Step 4: Run all tests — expect PASS**

```bash
python manage.py test challenges.tests.test_admin_clone --verbosity=2 2>&1 | tail -15
```

Expected: `Ran 5 tests in ...s OK`

- [ ] **Step 5: Run the full challenge test suite to confirm no regressions**

```bash
python manage.py test challenges --verbosity=2 2>&1 | tail -20
```

Expected: All tests pass. No failures.

- [ ] **Step 6: Commit**

```bash
git add app/templates/admin/challenges/clone_to_org.html app/challenges/tests/test_admin_clone.py
git commit -m "feat: clone_to_org two-step admin action with template and tests"
```

---

## Task 6: Final verification + push

- [ ] **Step 1: Run full test suite**

```bash
python manage.py test --verbosity=1 2>&1 | tail -10
```

Expected: `OK` with no failures.

- [ ] **Step 2: Confirm migrations are clean**

```bash
python manage.py showmigrations challenges 2>&1
```

Expected:
```
challenges
 [X] 0001_initial
 [X] 0002_activity
 [X] 0003_enrollment_studentprogress_and_more
 [X] 0004_seed_learning_plugin
 [X] 0005_challengecategory
 [X] 0006_routechallenge_library_fields
```

- [ ] **Step 3: Push**

```bash
git push
```
