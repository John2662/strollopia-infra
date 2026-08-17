# Place-Based Language Learning Platform — Design Spec

**Date:** 2026-08-06  
**Branch:** feat/port-api-endpoints-to-data-logger  
**Status:** Approved for implementation planning

---

## 1. Overview

A white-label, place-based language learning platform built on top of strollopia-api and a forked frontend (strollopia-base). Language schools get a branded web app where teachers build route challenges pinned to real-world locations and students complete language activities as they walk the route.

**Primary pitch:** same backend, same data, school chooses the student UX.

---

## 2. Goals and Non-Goals

### Goals
- Teacher can build a geo-located route challenge with per-stop language activities
- Students complete challenges on-device as they walk; progress tracked per student
- School admin manages enrollment, sees class-wide progress in a teacher dashboard
- Each school gets fully white-labeled experience: custom domain, logo, colours
- Platform is generic enough to support future domains (tourism, corporate) without model changes

### Non-Goals (v1)
- Native mobile app (PWA only)
- Real-time collaborative editing
- AI-generated activity content
- Payment/billing between schools and platform operator

> **Offline support:** strollopia-base forks data_logger, which already has offline capability. This is inherited, not rebuilt — and is more important here than in most use cases since students walk city routes through patchy coverage.

---

## 3. Architecture

### 3.1 Backend — strollopia-api (extend in place)

New Django app `challenges` sits alongside existing `api`, `ui`, and `core` apps. It shares the existing OwningOrg tenancy model and POI/Map/Route/Trail GIS data. The name is intentionally domain-neutral — the same app serves language schools, tourism operators, and corporate training without implying any one domain.

```
strollopia-api/
  core/          # OwningOrg, BaseOrgModel, OrgSiteConfig, OrgPluginConfig
  api/           # existing POI/Map/Route endpoints (unchanged)
  challenges/    # NEW: route challenges, stops, activities, enrollment, progress
    models.py
    serializers.py
    views.py
    urls.py
    admin.py
    signals.py
```

No API routes, authentication, or tenant isolation for existing apps change. New `challenges/` endpoints sit at `/api/challenges/` with the same DRF token auth.

### 3.2 Frontend — strollopia-guide (fork of data_logger)

Fork `data_logger` into a new repo `strollopia-guide`. The fork gives us a clean development surface without disturbing the live data_logger pilot (ends October 2026). The API identifies this frontend with the key `SG` — added to `UiType` alongside `BL` (Builder), `VW` (Viewer), `ED` (Editor), `DL` (Logger).

`strollopia-guide` is a plugin-aware Next.js app. On startup it reads `OrgPluginConfig.active_plugins` and assembles routes, nav, and role labels from the active plugin manifests.

```
strollopia-guide/
  src/
    core/         # auth, org context, plugin registry, layout
    plugins/
      learning/   # teacher builder, student modes, dashboard
      map-builder/ # (future)
    hooks/        # useAuth, useOrg, usePlugin
    lib/          # api client
```

---

## 4. Plugin Architecture

### 4.1 Plugin Contract

Each plugin exports a manifest that declares what it contributes. The manifest `id` is the primary contract between the frontend plugin and its backend `Plugin` model row — they must match exactly. Core provides the infrastructure; plugins never import from each other.

```typescript
// plugins/learning/index.ts
export default {
  id: 'learning',
  // 'id' is the foreign key to Plugin.key in the database.
  // Core loads this manifest only when OrgPlugin.plugin.key === 'learning'
  // exists with status='active' for the current org.

  routes: [
    { path: '/learn',             component: StudentHome,     role: 'consumer' },
    { path: '/learn/:id',         component: ChallengeView,   role: 'consumer' },
    { path: '/teach',             component: TeacherDash,     role: 'producer' },
    { path: '/teach/builder/:id', component: ChallengeBuilder, role: 'producer' },
    { path: '/join/:code',        component: JoinFlow,        role: 'public' },
  ],

  nav: [
    { label: 'My Challenges', href: '/learn',  role: 'consumer' },
    { label: 'Dashboard',     href: '/teach',  role: 'producer' },
  ],

  roles: {
    producer: { label: 'Teacher',  plural: 'Teachers' },
    consumer: { label: 'Student',  plural: 'Students' },
  },
}
```

### 4.2 Isolation Guarantees

| Namespace | Rule |
|-----------|------|
| Route | Plugin routes live under their own path prefix (`/learn`, `/teach`) |
| Role label | Plugin declares display labels; core uses `is_producer`/`is_consumer` booleans |
| Config | `OrgPlugin.settings` is scoped per plugin row; plugins read only their own row |

### 4.3 Core Responsibilities

- Query `OrgPlugin.objects.filter(org=org, status='active')` at boot to get active plugin keys
- Load the frontend manifest whose `id` matches each active key
- Register routes and nav entries from each loaded manifest
- Inject org branding tokens (logo, colours, domain) into layout
- Handle auth, token refresh, org context — plugins get these via hooks

---

## 5. Data Model

### 5.1 User Model Extension

Two boolean flags added to the existing `User` model. Both default `False`. The existing `is_staff`/`is_superuser` fields are unchanged.

```python
class User(AbstractUser):
    is_producer = models.BooleanField(default=False)   # teacher, guide, trainer
    is_consumer = models.BooleanField(default=False)   # student, visitor, trainee
```

Plugin manifests map these to domain-specific display labels. A user can be both (e.g. a teacher who also takes a peer challenge).

### 5.2 Org Config Models

**Plugin** — system-level registry of available plugins. Managed by superadmin only. Not org-scoped.

```python
class Plugin(models.Model):
    key          = models.CharField(max_length=20, unique=True)
    # Primary contract — must match the frontend manifest's `id` exactly.
    # e.g. 'learning', 'map-builder', 'tourism'

    name         = models.CharField(max_length=100)       # "Place-Based Learning"
    description  = models.TextField()                     # shown in plugin browser
    is_available = models.BooleanField(default=True)
    # False = hidden from all orgs (e.g. sunset or not yet released)

    # Onboarding content — rendered in the admin when an org activates this plugin
    quick_start  = models.TextField(blank=True)           # markdown, step-by-step setup guide
    how_to       = models.TextField(blank=True)           # markdown, detailed usage guide
    demo_url     = models.URLField(blank=True)            # link to a live demo or video
    support_url  = models.URLField(blank=True)            # docs or support page

    version      = models.CharField(max_length=20, blank=True)
    changelog    = models.TextField(blank=True)           # markdown, what's new per version
```

**OrgPlugin** — one row per plugin per org. Replaces the `active_plugins` JSON array entirely.

```python
class OrgPlugin(BaseOrgModel):
    plugin       = models.ForeignKey(Plugin, on_delete=models.PROTECT)
    # PROTECT: a Plugin row cannot be deleted while any org has it

    status       = models.CharField(max_length=20, default='active')
    # active        — plugin running; routes, nav, and data fully accessible
    # suspended     — hidden from all UIs, data fully preserved, re-activatable instantly
    # decommissioned — superadmin-only; requires data export before any removal

    settings     = models.JSONField(default=dict)
    # Plugin-specific org settings, read only by this plugin's own code.
    # e.g. for 'learning':
    # {
    #   "default_ux_mode": "explore",   # linear | explore | dashboard
    #   "enrollment_mode": "both",      # code | self | both
    #   "allow_self_register": false
    # }

    activated_at = models.DateTimeField(auto_now_add=True)
    activated_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='activated_plugins'
    )
    suspended_at = models.DateTimeField(null=True, blank=True)
    suspended_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='suspended_plugins'
    )

    class Meta:
        unique_together = ('owning_org', 'plugin')
```

**Lifecycle rules:**

| Transition | Who can do it | Data effect |
|---|---|---|
| `activate` (new row, `status=active`) | Org admin | None — opens a new data scope |
| `active → suspended` | Org admin, with explicit confirmation | Data preserved; plugin invisible to all users |
| `suspended → active` | Org admin | Data restored immediately; no migration needed |
| `suspended → decommissioned` | Superadmin only | Triggers data export; no deletion until export confirmed |
| Delete `Plugin` row | Impossible while any `OrgPlugin` exists | `PROTECT` FK enforced at database level |

No cascade deletes, ever. Org data outlives plugin activation state.

**OrgSiteConfig** — one-to-one with `OwningOrg`. Covers analytics, SEO, legal, social, and custom head injection. Domain/DNS fields are not here — they live on `OwningOrg.org_domain_name` and related fields to avoid duplication.

```python
class OrgSiteConfig(models.Model):
    # OneToOneField overrides BaseOrgModel's FK — enforced at the database level.
    # Use OrgSiteConfig.objects.get_or_create(owning_org=org) everywhere.
    owning_org = models.OneToOneField(
        OwningOrg, on_delete=models.CASCADE, related_name='site_config'
    )

    # SEO (OrgBranding covers logo/colours/font; this covers site metadata)
    meta_description = models.TextField(blank=True)
    og_image         = models.URLField(blank=True)
    favicon_url      = models.URLField(blank=True)

    # Analytics
    google_analytics_id    = models.CharField(max_length=50, blank=True)
    google_tag_manager_id  = models.CharField(max_length=50, blank=True)
    facebook_pixel_id      = models.CharField(max_length=50, blank=True)

    # Legal
    privacy_policy_url = models.URLField(blank=True)
    cookie_policy_url  = models.URLField(blank=True)
    terms_url          = models.URLField(blank=True)

    # Social
    twitter_handle    = models.CharField(max_length=100, blank=True)
    facebook_page     = models.URLField(blank=True)
    instagram_handle  = models.CharField(max_length=100, blank=True)

    # Escape hatch
    custom_head_html = models.TextField(blank=True)
    # Raw HTML injected into <head> — covers GA, GTM, Hotjar, Intercom, anything
    # the school needs without model changes.
```

### 5.3 Learning App Models

```python
class RouteChallenge(BaseOrgModel):
    title       = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    language    = models.CharField(max_length=10)   # ISO 639-1
    level       = models.CharField(max_length=10)   # A1, B2, etc.
    ux_mode     = models.CharField(max_length=20, null=True, blank=True)
    # overrides OrgPluginConfig default; null = use org default
    status      = models.CharField(max_length=20, default='draft')
    # draft | published | archived
    join_code   = models.CharField(max_length=12, unique=True, blank=True)
    # teacher shares this code; students visit /join/:code to enroll
    created_by  = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)


class ChallengeStop(BaseOrgModel):
    challenge   = models.ForeignKey(RouteChallenge, on_delete=models.CASCADE,
                                    related_name='stops')
    order       = models.PositiveIntegerField()
    name        = models.CharField(max_length=200)
    lat         = models.FloatField()
    lng         = models.FloatField()
    radius_m    = models.IntegerField(default=50)   # unlock radius
    poi         = models.ForeignKey('api.Poi', on_delete=models.SET_NULL,
                                    null=True, blank=True)
    # nullable FK — linking to an existing org POI is optional


class Activity(BaseOrgModel):
    stop          = models.ForeignKey(ChallengeStop, on_delete=models.CASCADE,
                                       related_name='activities')
    order         = models.PositiveIntegerField()
    activity_type = models.CharField(max_length=20)
    # QUIZ | LISTEN | SPEAK | WRITE | PHOTO | CHECKIN
    content       = models.JSONField()
    # typed JSON; schema mirrors future subclass fields (see §5.4)
    unlock_condition = models.CharField(max_length=20, default='previous_complete')
    # previous_complete | always_open


class Enrollment(BaseOrgModel):
    challenge   = models.ForeignKey(RouteChallenge, on_delete=models.CASCADE)
    student     = models.ForeignKey(User, on_delete=models.CASCADE)
    enrolled_at = models.DateTimeField(auto_now_add=True)
    status      = models.CharField(max_length=20, default='active')
    # active | completed | dropped

    class Meta:
        unique_together = ('challenge', 'student')


class StudentProgress(BaseOrgModel):
    enrollment  = models.ForeignKey(Enrollment, on_delete=models.CASCADE,
                                     related_name='progress')
    activity    = models.ForeignKey(Activity, on_delete=models.CASCADE)
    status      = models.CharField(max_length=20, default='not_started')
    # not_started | in_progress | completed | skipped
    response    = models.JSONField(null=True, blank=True)
    score       = models.FloatField(null=True, blank=True)   # 0.0–1.0
    started_at  = models.DateTimeField(null=True)
    completed_at = models.DateTimeField(null=True)
```

### 5.4 Activity JSON Schema (V1)

Field names mirror future typed subclass fields so migration is a single management command with no data transform.

**QUIZ**
```json
{
  "_type": "QUIZ",
  "question": "Wie komme ich zum Marktplatz?",
  "options": [
    { "text": "Bus Linie 2 Richtung Zentrum", "is_correct": true },
    { "text": "S-Bahn nach Salzburg", "is_correct": false }
  ],
  "explanation": "Bus Linie 2 fährt direkt..."
}
```

**LISTEN**
```json
{
  "_type": "LISTEN",
  "audio_url": "https://cdn.example.com/audio/announcement.mp3",
  "transcript": "Achtung, Bus Linie 2 fährt ab Gleis 3...",
  "question": "Welcher Bus fährt zum Marktplatz?",
  "options": [
    { "text": "Bus Linie 2", "is_correct": true },
    { "text": "Straßenbahn 1", "is_correct": false }
  ]
}
```

**SPEAK**
```json
{
  "_type": "SPEAK",
  "prompt": "Ask for a ticket to Vienna.",
  "model_answer": "Einmal nach Wien, bitte.",
  "grading": "manual"
}
```

**WRITE**
```json
{
  "_type": "WRITE",
  "prompt": "Write the opening hours sign in German.",
  "model_answer": "Öffnungszeiten: Mo–Fr 9–18 Uhr",
  "grading": "manual"
}
```

**PHOTO**
```json
{
  "_type": "PHOTO",
  "instruction": "Photograph the departure board and circle your platform.",
  "grading": "manual"
}
```

**CHECKIN**
```json
{
  "_type": "CHECKIN",
  "instruction": "Scan the QR code at the Triumphpforte plaque.",
  "qr_code": "TRI-001"
}
```

---

## 6. Student UX Modes

All three modes read identical backend data. The school sets the default in `OrgPluginConfig.plugin_settings.learning.default_ux_mode`; individual challenges can override via `RouteChallenge.ux_mode`.

### Mode A — Linear Mission
Ordered stop list, one stop expanded at a time. Progress bar at the top. Stops unlock sequentially. Best for classroom field trips with a fixed script.

### Mode B — Explore Map
Full-screen Leaflet map. Students tap numbered markers to open stops. Stops can be in any order unless unlock_condition is set. Best for self-directed explorers.

### Mode C — Dashboard
Split view: active activity card on the left (~55% width), mini-map on the right. Students see task and map simultaneously. Best for more complex stops with multiple activities.

---

## 7. Teacher Interfaces

### 7.1 Challenge Builder (`/teach/builder/:id`)

Three-panel layout:

- **Left panel** — ordered stop list. Drag to reorder. Colour codes: green (complete), blue (selected/editing), grey (empty). Save Draft + Publish controls at the bottom.
- **Centre panel** — Leaflet map. Click to place a new stop. Drag marker to reposition. POI search panel (bottom-left) for optional link to existing org POI.
- **Right panel** — activity editor for the selected stop. 6-type picker (Quiz, Listen, Speak, Write, Photo, Check-in). Inline JSON form per type. Unlock condition toggle per stop.

### 7.2 Teacher Dashboard (`/teach`)

- **Left sidebar** — challenge list; click to select
- **Stats bar** — enrolled count, stops complete %, activities complete %, avg score
- **Centre grid** — student × stop progress matrix; colour-coded by status
- **Right sidebar** — selected student detail (stop-by-stop progress, activity responses)

---

## 8. White-Label Routing

This follows the same pattern already working in `data_logger` — no new infrastructure required.

```
Org owner points org_domain_name at Vercel
  └── Vercel configured to accept that domain → serves strollopia-guide
  └── Frontend reads window.location.hostname → org_domain_name
        ├── User logged in   → auth token carries org context; API resolves silo
        └── User not logged in → frontend passes org_domain_name as API parameter;
                                  API resolves org_domain_name to the right data silo
  └── Frontend fetches OrgBranding (logo, colours) and OrgSiteConfig
      (analytics IDs, custom_head_html) from the API using org context
  └── Layout renders with school identity; custom_head_html injected client-side
```

The mechanism is already proven in production. `strollopia-guide` adopts it unchanged — the only addition is fetching `OrgSiteConfig` fields (analytics tags, custom head HTML) once org context is established.

---

## 9. Enrollment Flows

**Code-based:** Teacher generates a join code → shares with class → students visit `/join/:code`. Student account created or linked automatically.

**Self-register:** School enables `allow_self_register: true` in plugin settings. Students create accounts under the school's custom domain directly.

**Both:** Both flows active simultaneously (recommended for mixed contexts).

---

## 10. API Endpoints (new)

These endpoints belong to the `challenges` Django app — not to the `learning` plugin specifically. The `learning` plugin is the first consumer, but any future plugin that uses the route-challenge data shape (tourism scavenger hunts, corporate training walks) reuses these same endpoints. A future plugin that needs genuinely different data models would add its own Django app and its own URL namespace (e.g. `/api/assessments/`).

All under `/api/challenges/`. Standard DRF + token auth. Org isolation via `BaseOrgModel` queryset filtering.

| Method | Path | Description |
|--------|------|-------------|
| GET/POST | `/api/challenges/` | List/create challenges |
| GET/PUT/PATCH | `/api/challenges/:id/` | Retrieve/update challenge |
| GET/POST | `/api/challenges/:id/stops/` | List/add stops |
| PUT/PATCH | `/api/challenges/:id/stops/:sid/` | Update stop |
| GET/POST | `/api/challenges/:id/stops/:sid/activities/` | List/add activities |
| PUT/PATCH | `/api/challenges/:id/stops/:sid/activities/:aid/` | Update activity |
| POST | `/api/challenges/:id/publish/` | Publish challenge |
| GET/POST | `/api/challenges/enrollments/` | List enrollments / join via code |
| POST | `/api/challenges/progress/` | Submit activity response |
| GET | `/api/challenges/:id/progress/` | Teacher: all student progress for a challenge |
| GET | `/api/challenges/me/progress/` | Student: own progress across all enrollments |

---

## 11. Promotional Mockups

Visual wireframes are in `.superpowers/brainstorm/1683227-1786001121/content/`:

| File | Description |
|------|-------------|
| `builder-innsbruck.html` | Teacher challenge builder — real Innsbruck OSM map, 3-stop route |
| `student-modes-innsbruck.html` | Three student UX modes side-by-side, same Innsbruck route |
| `teacher-dashboard-innsbruck.html` | Teacher progress dashboard, class-wide matrix view |

All use real OpenStreetMap tiles centred on Innsbruck (Train Station → Triumphpforte → Altstadt café). Suitable for pitch decks and school demos.

---

## 12. Implementation Sequence

1. **Backend models + migrations** — `challenges` app: RouteChallenge, ChallengeStop, Activity, Enrollment, StudentProgress
2. **User model flags** — `is_producer`, `is_consumer` fields + migration
3. **Plugin + OrgPlugin + OrgSiteConfig** — new models in `core`; seed `Plugin` rows for `learning` (and any future plugins) as a data migration
4. **DRF serializers + views** — all `/api/learning/` endpoints, with org-scoped querysets
5. **Admin registration** — challenge builder admin, enrollment management
6. **Fork data_logger → strollopia-guide** — set up Next.js app, plugin registry, org branding middleware; add `SG` to `UiType` in strollopia-api
7. **Learning plugin manifest** — routes, nav, role labels
8. **Student UX pages** — three mode implementations reading shared API data
9. **Teacher challenge builder** — three-panel Leaflet editor
10. **Teacher dashboard** — progress matrix, student detail drawer
11. **Enrollment flows** — join-code page, self-register flow
12. **White-label routing** — custom domain middleware + OrgSiteConfig injection

---

## 13. Open Questions (resolved)

| Question | Decision |
|----------|----------|
| Extend API or microservice? | Extend strollopia-api in place — share tenancy, auth, GIS data |
| Fork or extend data_logger? | Fork → strollopia-base, develop independently until October pilot ends |
| Teacher/Student in User model? | No — use `is_producer`/`is_consumer` booleans, plugin declares display labels |
| Typed subclasses or JSON for Activity? | JSON first; builder enforces schema mirroring future fields; migrate via management command |
| Plugin activation as JSON array or model? | Proper `Plugin` + `OrgPlugin` models; `Plugin.key` is the foreign key matching the frontend manifest `id`; deactivation rules enforced in code and at DB level (`PROTECT`) |
| Single UX mode or multiple? | All three built; school picks default via OrgPluginConfig; challenge can override |
| POI link required? | No — `ChallengeStop.poi` is nullable; standalone stops fully supported |
| Enrollment mode? | Both code-based and self-register; school chooses in plugin settings |
