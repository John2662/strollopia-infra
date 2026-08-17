# Challenge Library Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose published template challenges via three new API actions and build a teacher-facing library page that lets teachers browse, preview, and clone templates into their own org in one click.

**Architecture:** Three new `@action` methods on the existing `RouteChallengeViewSet` (no router change). Two new serializers in `serializers.py`. Frontend gets three new API constants, three new fetch functions, one new page at `/teach/library/`, and a link from the existing teacher dashboard.

**Tech Stack:** Django REST Framework (backend), Next.js App Router `'use client'` (frontend), Tailwind CSS.

---

## File map

| File | Change |
|---|---|
| `strollopia-api/app/challenges/serializers.py` | Add `ChallengeTemplateListSerializer`, `TemplateStopSerializer`, `ChallengeTemplateDetailSerializer` |
| `strollopia-api/app/challenges/views_challenge.py` | Add `_template_queryset`, `templates`, `template_detail`, `clone` actions |
| `strollopia-api/app/challenges/tests/test_api_templates.py` | **New** — API tests for all three actions |
| `strollopia-pwa/utils/api.js` | Add three endpoint constants |
| `strollopia-pwa/utils/challengesApi.js` | Add `listTemplates`, `getTemplateDetail`, `cloneTemplate` |
| `strollopia-pwa/app/teach/library/page.js` | **New** — library page |
| `strollopia-pwa/app/teach/page.js` | Add "Browse library" link |

---

## Task 1: Backend serializers

**Files:**
- Modify: `strollopia-api/app/challenges/serializers.py`
- Test: `strollopia-api/app/challenges/tests/test_serializers.py` (new)

- [ ] **Step 1: Write the failing tests**

Create `strollopia-api/app/challenges/tests/test_serializers.py`:

```python
"""Tests for template library serializers."""
from django.test import TestCase
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop, Activity, ChallengeCategory
from challenges.serializers import (
    ChallengeTemplateListSerializer,
    ChallengeTemplateDetailSerializer,
)


def make_org():
    return OwningOrg.create_org(increment_test_url())


def make_user(org):
    return get_user_model().objects.create_user(
        org_domain_name=org.org_domain_name,
        email='t@example.com',
        password='pass',
        is_producer=True,
    )


def make_template(org, user, category=None):
    return RouteChallenge.objects.create(
        owning_org=org,
        created_by=user,
        title='Paris Walk',
        language='fr',
        level='A2',
        is_template=True,
        status=RouteChallenge.PUBLISHED,
        author_name='Strollopia Language Team',
        content_language='en',
        challenge_icon='🇫🇷',
        category=category,
    )


class ChallengeTemplateListSerializerTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.cat = ChallengeCategory.objects.create(name='Language Learning', slug='language-learning')
        self.challenge = make_template(self.org, self.user, category=self.cat)

    def test_contains_expected_fields(self):
        from django.db.models import Count
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateListSerializer(qs.first()).data
        expected = {
            'id', 'title', 'description', 'language', 'level',
            'challenge_icon', 'content_language', 'author_name',
            'category_slug', 'category_name', 'stop_count', 'activity_count',
        }
        self.assertEqual(set(data.keys()), expected)

    def test_category_slug_and_name(self):
        from django.db.models import Count
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateListSerializer(qs.first()).data
        self.assertEqual(data['category_slug'], 'language-learning')
        self.assertEqual(data['category_name'], 'Language Learning')

    def test_stop_and_activity_counts(self):
        from django.db.models import Count
        stop = ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=0, name='Eiffel Tower', lat=48.858, lng=2.294,
        )
        Activity.objects.create(
            owning_org=self.org, stop=stop, order=0,
            activity_type='QUIZ', content={'question': 'Q?', 'options': []},
        )
        Activity.objects.create(
            owning_org=self.org, stop=stop, order=1,
            activity_type='WRITE', content={'prompt': 'Write.'},
        )
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateListSerializer(qs.first()).data
        self.assertEqual(data['stop_count'], 1)
        self.assertEqual(data['activity_count'], 2)


class ChallengeTemplateDetailSerializerTests(TestCase):

    def setUp(self):
        self.org = make_org()
        self.user = make_user(self.org)
        self.challenge = make_template(self.org, self.user)
        self.stop = ChallengeStop.objects.create(
            owning_org=self.org, challenge=self.challenge,
            order=0, name='Louvre', lat=48.860, lng=2.337,
        )
        Activity.objects.create(
            owning_org=self.org, stop=self.stop, order=0,
            activity_type='QUIZ', content={'question': 'Q?', 'options': []},
        )
        Activity.objects.create(
            owning_org=self.org, stop=self.stop, order=1,
            activity_type='WRITE', content={'prompt': 'Write.'},
        )

    def test_includes_stops_field(self):
        from django.db.models import Count
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).prefetch_related('stops__activities').annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateDetailSerializer(qs.first()).data
        self.assertIn('stops', data)
        self.assertEqual(len(data['stops']), 1)

    def test_stop_has_activity_types(self):
        from django.db.models import Count
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).prefetch_related('stops__activities').annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateDetailSerializer(qs.first()).data
        stop_data = data['stops'][0]
        self.assertEqual(stop_data['activity_types'], ['QUIZ', 'WRITE'])

    def test_activity_content_not_exposed(self):
        from django.db.models import Count
        qs = RouteChallenge.objects.filter(pk=self.challenge.pk).prefetch_related('stops__activities').annotate(
            stop_count=Count('stops', distinct=True),
            activity_count=Count('stops__activities', distinct=True),
        )
        data = ChallengeTemplateDetailSerializer(qs.first()).data
        stop_data = data['stops'][0]
        self.assertNotIn('content', stop_data)
```

- [ ] **Step 2: Run tests to confirm they fail**

```
cd strollopia-api
docker compose run --rm -e DB_HOST=db -e DB_NAME=devdb -e DB_USER=devuser -e DB_PASS=changeme app python manage.py test challenges.tests.test_serializers --keepdb
```

Expected: `ImportError` — `ChallengeTemplateListSerializer` not yet defined.

- [ ] **Step 3: Add serializers to `app/challenges/serializers.py`**

Append after the existing `StudentProgressSerializer`:

```python
class ChallengeTemplateListSerializer(serializers.ModelSerializer):
    stop_count     = serializers.IntegerField(read_only=True)
    activity_count = serializers.IntegerField(read_only=True)
    category_slug  = serializers.SlugRelatedField(
        source='category', slug_field='slug', read_only=True
    )
    category_name  = serializers.SlugRelatedField(
        source='category', slug_field='name', read_only=True
    )

    class Meta:
        model  = RouteChallenge
        fields = [
            'id', 'title', 'description', 'language', 'level',
            'challenge_icon', 'content_language', 'author_name',
            'category_slug', 'category_name',
            'stop_count', 'activity_count',
        ]


class TemplateStopSerializer(serializers.ModelSerializer):
    activity_types = serializers.SerializerMethodField()

    def get_activity_types(self, stop):
        return list(stop.activities.values_list('activity_type', flat=True).order_by('order'))

    class Meta:
        model  = ChallengeStop
        fields = ['id', 'order', 'name', 'lat', 'lng', 'activity_types']


class ChallengeTemplateDetailSerializer(ChallengeTemplateListSerializer):
    stops = TemplateStopSerializer(many=True, read_only=True)

    class Meta(ChallengeTemplateListSerializer.Meta):
        fields = ChallengeTemplateListSerializer.Meta.fields + ['stops']
```

Also add the missing model imports at the top of the file:

```python
from challenges.models import RouteChallenge, ChallengeStop, Activity, Enrollment, StudentProgress
```

(`ChallengeStop` is already imported — confirm this before adding.)

- [ ] **Step 4: Run tests to confirm they pass**

```
docker compose run --rm -e DB_HOST=db -e DB_NAME=devdb -e DB_USER=devuser -e DB_PASS=changeme app python manage.py test challenges.tests.test_serializers --keepdb
```

Expected: 6 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/challenges/serializers.py app/challenges/tests/test_serializers.py
git commit -m "feat: add template library serializers"
```

---

## Task 2: ViewSet actions + API tests

**Files:**
- Modify: `strollopia-api/app/challenges/views_challenge.py`
- Create: `strollopia-api/app/challenges/tests/test_api_templates.py`

- [ ] **Step 1: Write the failing tests**

Create `strollopia-api/app/challenges/tests/test_api_templates.py`:

```python
"""Tests for /api/challenges/templates/, template-detail, and clone actions."""
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model

from core.models import OwningOrg
from core.tests.test_url_resolution import increment_test_url
from challenges.models import RouteChallenge, ChallengeStop, Activity, ChallengeCategory


TEMPLATES_URL = reverse('challenges:routechallenge-templates')


def template_detail_url(pk):
    return reverse('challenges:routechallenge-template-detail', args=[pk])


def clone_url(pk):
    return reverse('challenges:routechallenge-clone', args=[pk])


def make_org():
    return OwningOrg.create_org(increment_test_url())


def make_user(org):
    return get_user_model().objects.create_user(
        org_domain_name=org.org_domain_name,
        email='teacher@example.com',
        password='pass123',
        is_producer=True,
    )


def make_default_org():
    from core.models import DEFAULT_ORG_DOMAIN_NAME
    try:
        return OwningOrg.objects.get(org_domain_name=DEFAULT_ORG_DOMAIN_NAME)
    except OwningOrg.DoesNotExist:
        return OwningOrg.create_org(DEFAULT_ORG_DOMAIN_NAME)


def make_template(default_org, default_user, category=None, **kwargs):
    defaults = dict(
        owning_org=default_org,
        created_by=default_user,
        title='Innsbruck Walk',
        language='de',
        level='A2',
        is_template=True,
        status=RouteChallenge.PUBLISHED,
        author_name='Strollopia Language Team',
        content_language='en',
        challenge_icon='🇦🇹',
    )
    defaults.update(kwargs)
    if category is not None:
        defaults['category'] = category
    return RouteChallenge.objects.create(**defaults)


class TemplateListTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.default_org = make_default_org()
        self.default_user = make_user(self.default_org)
        self.teacher_org = make_org()
        self.teacher = make_user(self.teacher_org)
        self.client.force_authenticate(user=self.teacher)
        self.cat = ChallengeCategory.objects.create(name='Language Learning', slug='language-learning')

    def test_requires_auth(self):
        self.client.force_authenticate(user=None)
        res = self.client.get(TEMPLATES_URL)
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_returns_published_templates_only(self):
        make_template(self.default_org, self.default_user, category=self.cat)
        # Draft template — must NOT appear
        make_template(
            self.default_org, self.default_user, category=self.cat,
            status=RouteChallenge.DRAFT, title='Hidden Draft',
        )
        res = self.client.get(TEMPLATES_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        self.assertEqual(res.data[0]['title'], 'Innsbruck Walk')

    def test_does_not_return_non_template_challenges(self):
        RouteChallenge.objects.create(
            owning_org=self.default_org, created_by=self.default_user,
            title='Regular Challenge', language='de', status=RouteChallenge.PUBLISHED,
            is_template=False,
        )
        res = self.client.get(TEMPLATES_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 0)

    def test_filter_by_category(self):
        other_cat = ChallengeCategory.objects.create(name='STEM', slug='stem')
        make_template(self.default_org, self.default_user, category=self.cat)
        make_template(self.default_org, self.default_user, category=other_cat, title='STEM Walk')
        res = self.client.get(TEMPLATES_URL, {'category': 'stem'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        self.assertEqual(res.data[0]['title'], 'STEM Walk')

    def test_filter_by_content_language(self):
        make_template(self.default_org, self.default_user, category=self.cat, content_language='en')
        make_template(self.default_org, self.default_user, category=self.cat, title='FR Walk', content_language='fr')
        res = self.client.get(TEMPLATES_URL, {'content_language': 'fr'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        self.assertEqual(res.data[0]['title'], 'FR Walk')

    def test_filter_by_language(self):
        make_template(self.default_org, self.default_user, category=self.cat, language='de')
        make_template(self.default_org, self.default_user, category=self.cat, title='FR Template', language='fr')
        res = self.client.get(TEMPLATES_URL, {'language': 'fr'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        self.assertEqual(res.data[0]['title'], 'FR Template')

    def test_response_includes_stop_and_activity_counts(self):
        template = make_template(self.default_org, self.default_user, category=self.cat)
        stop = ChallengeStop.objects.create(
            owning_org=self.default_org, challenge=template,
            order=0, name='Goldenes Dachl', lat=47.268, lng=11.394,
        )
        Activity.objects.create(
            owning_org=self.default_org, stop=stop, order=0,
            activity_type='QUIZ', content={'question': 'Q?', 'options': []},
        )
        res = self.client.get(TEMPLATES_URL)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data[0]['stop_count'], 1)
        self.assertEqual(res.data[0]['activity_count'], 1)


class TemplateDetailTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.default_org = make_default_org()
        self.default_user = make_user(self.default_org)
        self.teacher_org = make_org()
        self.teacher = make_user(self.teacher_org)
        self.client.force_authenticate(user=self.teacher)
        self.template = make_template(self.default_org, self.default_user)
        self.stop = ChallengeStop.objects.create(
            owning_org=self.default_org, challenge=self.template,
            order=0, name='Goldenes Dachl', lat=47.268, lng=11.394,
        )
        Activity.objects.create(
            owning_org=self.default_org, stop=self.stop, order=0,
            activity_type='QUIZ', content={'question': 'Q?', 'options': []},
        )
        Activity.objects.create(
            owning_org=self.default_org, stop=self.stop, order=1,
            activity_type='WRITE', content={'prompt': 'Write.'},
        )

    def test_returns_stops_with_activity_types(self):
        res = self.client.get(template_detail_url(self.template.pk))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('stops', res.data)
        self.assertEqual(len(res.data['stops']), 1)
        self.assertEqual(res.data['stops'][0]['activity_types'], ['QUIZ', 'WRITE'])

    def test_activity_content_not_in_response(self):
        res = self.client.get(template_detail_url(self.template.pk))
        stop_data = res.data['stops'][0]
        self.assertNotIn('content', stop_data)

    def test_404_for_non_template_challenge(self):
        regular = RouteChallenge.objects.create(
            owning_org=self.default_org, created_by=self.default_user,
            title='Regular', language='de', is_template=False, status=RouteChallenge.PUBLISHED,
        )
        res = self.client.get(template_detail_url(regular.pk))
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_requires_auth(self):
        self.client.force_authenticate(user=None)
        res = self.client.get(template_detail_url(self.template.pk))
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)


class CloneTemplateTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.default_org = make_default_org()
        self.default_user = make_user(self.default_org)
        self.teacher_org = make_org()
        self.teacher = make_user(self.teacher_org)
        self.client.force_authenticate(user=self.teacher)
        self.template = make_template(self.default_org, self.default_user)

    def test_clone_returns_201_with_new_challenge(self):
        res = self.client.post(clone_url(self.template.pk))
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertTrue(res.data['title'].startswith('Copy of'))

    def test_clone_places_challenge_in_teacher_org(self):
        res = self.client.post(clone_url(self.template.pk))
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        new_id = res.data['id']
        cloned = RouteChallenge.objects.get(pk=new_id)
        self.assertEqual(cloned.owning_org, self.teacher_org)

    def test_clone_result_is_draft_not_template(self):
        res = self.client.post(clone_url(self.template.pk))
        new_id = res.data['id']
        cloned = RouteChallenge.objects.get(pk=new_id)
        self.assertEqual(cloned.status, RouteChallenge.DRAFT)
        self.assertFalse(cloned.is_template)

    def test_cannot_clone_non_template(self):
        regular = RouteChallenge.objects.create(
            owning_org=self.default_org, created_by=self.default_user,
            title='Regular', language='de', is_template=False, status=RouteChallenge.PUBLISHED,
        )
        res = self.client.post(clone_url(regular.pk))
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_requires_auth(self):
        self.client.force_authenticate(user=None)
        res = self.client.post(clone_url(self.template.pk))
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)
```

- [ ] **Step 2: Run tests to confirm they fail**

```
docker compose run --rm -e DB_HOST=db -e DB_NAME=devdb -e DB_USER=devuser -e DB_PASS=changeme app python manage.py test challenges.tests.test_api_templates --keepdb
```

Expected: `NoReverseMatch` — actions not yet registered.

- [ ] **Step 3: Add three actions to `RouteChallengeViewSet`**

Replace the entire content of `app/challenges/views_challenge.py`:

```python
from django.db.models import Count
from django.shortcuts import get_object_or_404
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response

from core.models import DEFAULT_ORG_DOMAIN_NAME
from challenges.models import RouteChallenge
from challenges.serializers import (
    RouteChallengeSerializer,
    ChallengeTemplateListSerializer,
    ChallengeTemplateDetailSerializer,
)
from challenges.services import clone_challenge


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

    @action(detail=True, methods=['post'], url_path='publish')
    def publish(self, request, pk=None):
        challenge = self.get_object()
        challenge.status = RouteChallenge.PUBLISHED
        challenge.save(update_fields=['status'])
        return Response({'status': challenge.status})

    def _template_queryset(self):
        return (
            RouteChallenge.objects
            .filter(
                owning_org__org_domain_name=DEFAULT_ORG_DOMAIN_NAME,
                is_template=True,
                status=RouteChallenge.PUBLISHED,
            )
            .select_related('category')
            .annotate(
                stop_count=Count('stops', distinct=True),
                activity_count=Count('stops__activities', distinct=True),
            )
            .order_by('category__name', 'title')
        )

    @action(detail=False, methods=['get'], url_path='templates')
    def templates(self, request):
        qs = self._template_queryset()
        category = request.query_params.get('category')
        content_language = request.query_params.get('content_language')
        language = request.query_params.get('language')
        if category:
            qs = qs.filter(category__slug=category)
        if content_language:
            qs = qs.filter(content_language=content_language)
        if language:
            qs = qs.filter(language=language)
        serializer = ChallengeTemplateListSerializer(qs, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'], url_path='template-detail')
    def template_detail(self, request, pk=None):
        qs = self._template_queryset().prefetch_related('stops__activities')
        template = get_object_or_404(qs, pk=pk)
        serializer = ChallengeTemplateDetailSerializer(template)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], url_path='clone')
    def clone(self, request, pk=None):
        source = get_object_or_404(
            RouteChallenge,
            pk=pk,
            owning_org__org_domain_name=DEFAULT_ORG_DOMAIN_NAME,
            is_template=True,
            status=RouteChallenge.PUBLISHED,
        )
        new_challenge = clone_challenge(source, request.user.owning_org, request.user)
        return Response(
            RouteChallengeSerializer(new_challenge).data,
            status=status.HTTP_201_CREATED,
        )
```

- [ ] **Step 4: Run all challenge tests**

```
docker compose run --rm -e DB_HOST=db -e DB_NAME=devdb -e DB_USER=devuser -e DB_PASS=changeme app python manage.py test challenges --keepdb
```

Expected: All tests pass (existing + new).

- [ ] **Step 5: Commit**

```bash
git add app/challenges/views_challenge.py app/challenges/tests/test_api_templates.py
git commit -m "feat: add template list, detail, and clone API actions"
```

---

## Task 3: Frontend API layer

**Files:**
- Modify: `strollopia-pwa/utils/api.js`
- Modify: `strollopia-pwa/utils/challengesApi.js`

No test step — these are thin wrappers; the integration is tested by the library page loading correctly.

- [ ] **Step 1: Add endpoint constants to `utils/api.js`**

Find the `// Challenges` section (line 72). After `CHALLENGE_PROGRESS` (the last challenge constant), add:

```js
  CHALLENGE_TEMPLATES:       `${API_BASE_URL}/api/challenges/templates/`,
  CHALLENGE_TEMPLATE_DETAIL: (id) => `${API_BASE_URL}/api/challenges/${id}/template-detail/`,
  CHALLENGE_CLONE:           (id) => `${API_BASE_URL}/api/challenges/${id}/clone/`,
```

- [ ] **Step 2: Add fetch functions to `utils/challengesApi.js`**

Append after the last export in the file:

```js
// ── Template Library ──────────────────────────────────────────
export const listTemplates = (token, params = {}) => {
  const qs = new URLSearchParams(params).toString();
  const url = qs
    ? `${API_ENDPOINTS.CHALLENGE_TEMPLATES}?${qs}`
    : API_ENDPOINTS.CHALLENGE_TEMPLATES;
  return apiFetch(url, { headers: authHeaders(token) });
};

export const getTemplateDetail = (token, id) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_TEMPLATE_DETAIL(id), { headers: authHeaders(token) });

export const cloneTemplate = (token, id) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_CLONE(id), {
    method: 'POST',
    headers: authHeaders(token),
  });
```

- [ ] **Step 3: Commit**

```bash
git add utils/api.js utils/challengesApi.js
git commit -m "feat: add template library API constants and fetch functions"
```

---

## Task 4: Library page + dashboard link

**Files:**
- Create: `strollopia-pwa/app/teach/library/page.js`
- Modify: `strollopia-pwa/app/teach/page.js`

- [ ] **Step 1: Create `strollopia-pwa/app/teach/library/page.js`**

```js
'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '../../../lib/auth';
import { listTemplates, getTemplateDetail, cloneTemplate } from '../../../utils/challengesApi';

const LEVEL_BADGE = {
  A1: 'bg-green-100 text-green-700',
  A2: 'bg-green-100 text-green-700',
  B1: 'bg-blue-100 text-blue-700',
  B2: 'bg-blue-100 text-blue-700',
  C1: 'bg-purple-100 text-purple-700',
  C2: 'bg-purple-100 text-purple-700',
};

export default function LibraryPage() {
  const { authToken } = useAuth();
  const router = useRouter();

  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [categoryFilter, setCategoryFilter] = useState('');
  const [langFilter, setLangFilter] = useState('');

  const [preview, setPreview] = useState(null);       // template id being previewed
  const [previewData, setPreviewData] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState(null);

  const [cloning, setCloning] = useState(false);
  const [cloneError, setCloneError] = useState(null);

  useEffect(() => {
    if (!authToken) return;
    setLoading(true);
    const params = {};
    if (categoryFilter) params.category = categoryFilter;
    if (langFilter) params.content_language = langFilter;
    listTemplates(authToken, params)
      .then(setTemplates)
      .catch(() => setError('Failed to load library.'))
      .finally(() => setLoading(false));
  }, [authToken, categoryFilter, langFilter]);

  // Derive unique categories from loaded templates
  const categories = [...new Set(
    templates.filter((t) => t.category_slug).map((t) => ({ slug: t.category_slug, name: t.category_name }))
      .map(JSON.stringify)
  )].map(JSON.parse);

  function openPreview(template) {
    if (preview === template.id) {
      setPreview(null);
      setPreviewData(null);
      return;
    }
    setPreview(template.id);
    setPreviewData(null);
    setPreviewError(null);
    setPreviewLoading(true);
    getTemplateDetail(authToken, template.id)
      .then(setPreviewData)
      .catch(() => setPreviewError('Failed to load preview.'))
      .finally(() => setPreviewLoading(false));
  }

  async function handleClone(templateId) {
    setCloning(true);
    setCloneError(null);
    try {
      const newChallenge = await cloneTemplate(authToken, templateId);
      router.push(`/teach/builder/${newChallenge.id}`);
    } catch {
      setCloneError('Could not clone challenge. Please try again.');
      setCloning(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Challenge Library</h1>
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-6">
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="border border-gray-300 rounded-lg px-3 py-1.5 text-sm"
        >
          <option value="">All categories</option>
          {categories.map((c) => (
            <option key={c.slug} value={c.slug}>{c.name}</option>
          ))}
        </select>
        <select
          value={langFilter}
          onChange={(e) => setLangFilter(e.target.value)}
          className="border border-gray-300 rounded-lg px-3 py-1.5 text-sm"
        >
          <option value="">Any instruction language</option>
          <option value="en">English</option>
          <option value="fr">French</option>
          <option value="de">German</option>
          <option value="es">Spanish</option>
        </select>
      </div>

      {cloneError && (
        <p className="mb-4 text-sm text-red-600 bg-red-50 rounded-lg px-4 py-2">{cloneError}</p>
      )}

      {error && (
        <p className="text-sm text-red-600 bg-red-50 rounded-lg px-4 py-2">{error}</p>
      )}

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-20 bg-gray-100 rounded-xl animate-pulse" />
          ))}
        </div>
      ) : (
        <div className="space-y-3">
          {templates.map((t) => (
            <div key={t.id} className="border border-gray-200 rounded-xl overflow-hidden">
              <button
                className="w-full flex items-center justify-between p-4 hover:bg-gray-50 transition text-left"
                onClick={() => openPreview(t)}
              >
                <div className="flex items-center gap-3">
                  {t.challenge_icon && (
                    <span className="text-2xl">{t.challenge_icon}</span>
                  )}
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium">{t.title}</p>
                      {t.level && (
                        <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${LEVEL_BADGE[t.level] || 'bg-gray-100 text-gray-600'}`}>
                          {t.level}
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-gray-500 mt-0.5">
                      by {t.author_name}
                      {t.category_name ? ` · ${t.category_name}` : ''}
                      {' · '}{t.stop_count} stop{t.stop_count !== 1 ? 's' : ''}
                      {' · '}{t.activity_count} activit{t.activity_count !== 1 ? 'ies' : 'y'}
                    </p>
                  </div>
                </div>
                <span className="text-gray-400 text-sm">{preview === t.id ? '▲' : '▼'}</span>
              </button>

              {preview === t.id && (
                <div className="border-t border-gray-100 p-4 bg-gray-50">
                  {previewLoading && (
                    <p className="text-sm text-gray-400">Loading preview…</p>
                  )}
                  {previewError && (
                    <p className="text-sm text-red-600">{previewError}</p>
                  )}
                  {previewData && (
                    <>
                      {previewData.description && (
                        <p className="text-sm text-gray-600 mb-3">{previewData.description}</p>
                      )}
                      <ol className="space-y-1 mb-4">
                        {previewData.stops.map((stop) => (
                          <li key={stop.id} className="text-sm">
                            <span className="font-medium">{stop.order + 1}. {stop.name}</span>
                            <span className="ml-2 text-gray-400">
                              {stop.activity_types.map((type) => (
                                <span
                                  key={type}
                                  className="inline-block bg-white border border-gray-200 text-xs px-1.5 py-0.5 rounded mr-1"
                                >
                                  {type}
                                </span>
                              ))}
                            </span>
                          </li>
                        ))}
                      </ol>
                      <button
                        onClick={() => handleClone(t.id)}
                        disabled={cloning}
                        className="px-4 py-2 bg-orange-600 text-white text-sm rounded-lg hover:bg-orange-700 disabled:opacity-50 transition"
                      >
                        {cloning ? 'Cloning…' : 'Use this challenge'}
                      </button>
                    </>
                  )}
                </div>
              )}
            </div>
          ))}
          {!loading && templates.length === 0 && !error && (
            <p className="text-gray-400 text-center py-12">No templates found.</p>
          )}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Add "Browse library" link to teacher dashboard (`app/teach/page.js`)**

In `app/teach/page.js`, find the header `<div className="flex items-center justify-between mb-6">` block. Add a `Link` to the library alongside the "New challenge" button:

```js
import Link from 'next/link';
```

(Already imported — confirm before adding.)

Replace the header section so it reads:

```js
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">My Challenges</h1>
        <div className="flex items-center gap-3">
          <Link
            href="/teach/library"
            className="px-4 py-2 border border-gray-300 text-sm text-gray-700 rounded-lg hover:bg-gray-50 transition"
          >
            Browse library
          </Link>
          <button
            onClick={handleCreate}
            disabled={creating}
            className="flex items-center gap-2 px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 disabled:opacity-50 text-sm transition"
          >
            <Plus className="w-4 h-4" />
            {creating ? 'Creating…' : 'New challenge'}
          </button>
        </div>
      </div>
```

- [ ] **Step 3: Commit**

```bash
git add app/teach/library/page.js app/teach/page.js
git commit -m "feat: add challenge library page and dashboard link"
```

---

## Self-review

**Spec coverage:**
- `GET /api/challenges/templates/` with filters — ✅ Task 2
- `GET /api/challenges/<id>/template-detail/` — ✅ Task 2
- `POST /api/challenges/<id>/clone/` — ✅ Task 2
- `ChallengeTemplateListSerializer` with annotated counts — ✅ Task 1
- `ChallengeTemplateDetailSerializer` with stops + activity types, no content — ✅ Task 1
- `CHALLENGE_TEMPLATES`, `CHALLENGE_TEMPLATE_DETAIL`, `CHALLENGE_CLONE` in `api.js` — ✅ Task 3
- `listTemplates`, `getTemplateDetail`, `cloneTemplate` in `challengesApi.js` — ✅ Task 3
- Library page: filter bar, cards, preview panel with stop list + activity type badges — ✅ Task 4
- "Use this challenge" button → clone → redirect to builder — ✅ Task 4
- Library linked from teacher dashboard — ✅ Task 4
- Loading and error states on list and clone action — ✅ Task 4

**Placeholder scan:** None found.

**Type consistency:** `ChallengeTemplateDetailSerializer` extends `ChallengeTemplateListSerializer.Meta` — ✅. `TemplateStopSerializer` used only inside `ChallengeTemplateDetailSerializer` — ✅. `cloneTemplate` returns `RouteChallengeSerializer` data with `id` field — router push uses `newChallenge.id` — ✅.
