# Challenge Library — Phase 2 Design

**Goal:** Let teachers browse a curated library of template challenges (all owned by the default org) and clone any one into their own org with a single action.

**Architecture:** Two new ViewSet actions on the existing `RouteChallengeViewSet` (no new router registration needed). Templates live exclusively in `admin.strollopia.com` — no cross-org permission complexity. A new library page in `strollopia-pwa/app/teach/` fetches the template list and triggers the clone action. Phase 2 requires zero model or migration changes — all models, the clone service, and the admin tooling were delivered in Phase 1.

**Tech Stack:** Django REST Framework (backend), Next.js App Router with `'use client'` (frontend).

---

## Backend

### New: `ChallengeTemplateListSerializer`

Returns the data needed for a library card. Added to `app/challenges/serializers.py`:

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
```

`stop_count` and `activity_count` are annotated onto the queryset — not computed per-object — so the list endpoint is a single query with two `COUNT` subqueries.

### New: `ChallengeTemplateDetailSerializer`

Returns stops with activity type summaries for the preview panel. Added to `app/challenges/serializers.py`:

```python
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

`activity.content` is intentionally excluded — the template content stays in the default org until a teacher clones it.

### Two new ViewSet actions (`app/challenges/views_challenge.py`)

```python
from django.db.models import Count
from core.models import DEFAULT_ORG_DOMAIN_NAME
from challenges.serializers import (
    RouteChallengeSerializer,
    ChallengeTemplateListSerializer,
    ChallengeTemplateDetailSerializer,
)
from challenges.services import clone_challenge


class RouteChallengeViewSet(viewsets.ModelViewSet):
    # ... existing code unchanged ...

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

All three actions use `permission_classes = [permissions.IsAuthenticated]` (inherited from the viewset). No additional permission class is needed — any authenticated teacher can read and clone templates.

### URL changes (`app/challenges/urls.py`)

No changes needed. `DefaultRouter` auto-registers `templates`, `template-detail`, and `clone` as extra actions on the existing `RouteChallengeViewSet`.

### Query params summary

| Param | Filter |
|---|---|
| `category` | `category__slug` |
| `content_language` | challenge instructions language (e.g. `en`) |
| `language` | target/teaching language (e.g. `nl`, `de`) |

---

## Frontend

### New API constants (`strollopia-pwa/utils/api.js`)

```js
CHALLENGE_TEMPLATES:        `${API_BASE_URL}/api/challenges/templates/`,
CHALLENGE_TEMPLATE_DETAIL:  (id) => `${API_BASE_URL}/api/challenges/${id}/template-detail/`,
CHALLENGE_CLONE:            (id) => `${API_BASE_URL}/api/challenges/${id}/clone/`,
```

### New API functions (`strollopia-pwa/utils/challengesApi.js`)

```js
export const listTemplates = (token, params = {}) => {
  const qs = new URLSearchParams(params).toString();
  const url = qs ? `${API_ENDPOINTS.CHALLENGE_TEMPLATES}?${qs}` : API_ENDPOINTS.CHALLENGE_TEMPLATES;
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

### New page (`strollopia-pwa/app/teach/library/page.js`)

Library page UI behaviour:
- Loads all templates on mount
- Filter bar: category dropdown (populated from the template list), content_language dropdown
- Each card shows: `challenge_icon`, title, `author_name`, level, stop_count, activity_count, category
- Clicking a card opens a **preview panel** (slide-over or expandable section) showing the stop list with activity type badges — fetched from `template-detail` on demand
- "Use this challenge" button in the preview panel → calls `cloneTemplate` → on success, redirects to `/teach/challenges/<new_id>/` (the existing challenge editor)
- Loading and error states on both the list and the clone action

The library page is linked from the existing teacher dashboard (`/teach/`) alongside the "Create new challenge" button.

---

## Data setup (admin, no code)

Before Phase 2 goes live:

1. Create `ChallengeCategory` rows in Django admin: Language Learning (🗣️), Nature & Ecology (🌿), Urban History (🏛️), STEM (🔬), Art & Architecture (🎨)
2. Use the Phase 1 `clone_to_org` admin action to clone the 12 seeded challenges into `admin.strollopia.com`
3. Set `is_template=True`, assign categories, set `challenge_icon`, `content_language='en'`, `author_name='Strollopia Language Team'` on each
4. Publish each template

---

## Out of Scope (this phase)

- Teacher self-submit ("publish my challenge to the library") — that flow requires the payment/attribution reference (`source_challenge` FK) and admin review workflow; deferred
- Pagination on the template list — library will be small enough that a single page is fine initially
- Search by free text — filtering by category and language covers the primary discovery need
- Favourites / saved templates
