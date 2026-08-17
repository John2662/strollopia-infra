# strollopia-pwa Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build strollopia-pwa — a forked Next.js PWA with a teacher challenge builder, student Linear Mission mode, and teacher dashboard, backed by the `/api/challenges/` endpoints from Plan 1.

**Architecture:** Fork data_logger for the proven auth/config/ThemeInjector/offline/IndexedDB stack. Add a PluginProvider that reads `is_producer`/`is_consumer` from the user profile to gate teacher vs student routes. The learning plugin manifest wires these flags to nav and role labels. Student Explore Map and Dashboard modes (Modes B and C) are deferred to Plan 3.

**Tech Stack:** Next.js 14, React 18, Tailwind CSS, Leaflet 1.9, @dnd-kit/sortable, Vitest, IndexedDB, Service Worker (PWA)

**Spec:** `docs/superpowers/specs/2026-08-06-place-based-learning-design.md`

**Note:** This is Plan 2 of 3. Plan 1 (backend) is complete. Plan 3 will add student Explore Map and Dashboard modes.

---

## Prerequisites

- GitHub repo `git@github.com:John2662/strollopia-pwa.git` is already cloned at `strollopia_git_hub/strollopia-pwa/`. No further repo setup needed.
- `strollopia-api` dev server running at `http://localhost:8000` (or your API URL set as `NEXT_PUBLIC_API_URL`).
- Docker up for running backend tests (Task 1).

---

## Test runner

**Backend tests (Task 1 only — run from `strollopia-api/`):**
```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test user.tests.test_user_api --keepdb"
```

**Frontend tests (all other tasks — run from `strollopia-pwa/`):**
```bash
npm test
# or watch mode:
npm run test:watch
```

---

## File structure

**New files in `strollopia-pwa/` (relative to repo root):**

| File | Purpose |
|------|---------|
| `app/layout.js` | Root layout (adapted from data_logger) |
| `app/providers.js` | Auth + Config + Plugin providers |
| `app/globals.css` | Base Tailwind + CSS vars |
| `app/page.js` | Home: role-based redirect |
| `app/join/[code]/page.js` | Enrollment join-code flow |
| `app/learn/page.js` | Student home: enrolled challenge list |
| `app/learn/[id]/page.js` | Challenge view: mode router → LinearMissionView |
| `app/teach/page.js` | Teacher dashboard |
| `app/teach/builder/[id]/page.js` | 3-panel challenge builder |
| `lib/auth.js` | Adapted from data_logger; adds `isProducer`/`isConsumer` |
| `lib/config.js` | Copied from data_logger |
| `lib/plugin.js` | NEW: PluginProvider + usePlugin hook |
| `utils/api.js` | Adapted from data_logger; adds challenges endpoints |
| `utils/challengesApi.js` | NEW: typed wrappers for /api/challenges/ |
| `utils/api.test.js` | Vitest: challenges API client unit tests |
| `components/AppShell.js` | Simplified from data_logger |
| `components/ThemeInjector.js` | Copied from data_logger |
| `components/LoginModal.js` | Copied from data_logger |
| `components/learn/ChallengeCard.js` | Challenge list item |
| `components/learn/LinearMissionView.js` | Mode A: ordered stop list |
| `components/learn/ActivityCard.js` | Renders QUIZ, CHECKIN, WRITE, etc. |
| `components/teach/StopSidebar.js` | Left panel: dnd-kit sortable stop list |
| `components/teach/BuilderMap.js` | Centre panel: Leaflet map, click to place stops |
| `components/teach/ActivityEditor.js` | Right panel: activity type picker + JSON form |
| `components/teach/ProgressMatrix.js` | Teacher dashboard: student × stop grid |
| `plugins/learning/index.js` | Plugin manifest: routes, nav, role labels |
| `CLAUDE.md` | Project guidelines |

---

## Task 1: Expose is_producer / is_consumer in user profile API

*Working directory: `strollopia-api/`*

**Files:**
- Modify: `app/user/serializers.py:33-41` — add two fields to `UserSerializer`
- Modify: `app/user/tests/test_user_api.py` — add assertions to existing profile test

- [ ] **Add test assertions for the new profile fields**

Find the existing test that calls `GET /api/user/profile/` in `app/user/tests/test_user_api.py`. Locate the test `test_retrieve_user_success` (or equivalent) and add:

```python
def test_profile_returns_producer_consumer_flags(self):
    """Profile endpoint must return is_producer and is_consumer."""
    from core.tests.test_url_resolution import increment_test_url
    from core.models import OwningOrg
    domain = increment_test_url()
    OwningOrg.create_org(domain)
    user = get_user_model().objects.create_user(
        org_domain_name=domain,
        email='flagtest@example.com',
        password='pass123',
        is_producer=True,
    )
    self.client.force_authenticate(user=user)
    res = self.client.get('/api/user/profile/')
    self.assertEqual(res.status_code, 200)
    self.assertIn('is_producer', res.data)
    self.assertIn('is_consumer', res.data)
    self.assertTrue(res.data['is_producer'])
    self.assertFalse(res.data['is_consumer'])
```

- [ ] **Run the test to verify it fails**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test user.tests.test_user_api.UserApiTests.test_profile_returns_producer_consumer_flags --keepdb"
```

Expected: `AssertionError: 'is_producer' not found in {'email': ..., 'can_edit_org_data': ...}`

- [ ] **Add the fields to UserSerializer**

In `app/user/serializers.py`, update the `fields` list in `UserSerializer.Meta`:

```python
class Meta:
    model = get_user_model()
    fields = [
        'email',
        'password',
        'name',
        'created_at',
        'owning_org',
        'can_edit_org_data',
        'has_org_admin_access',
        'is_producer',
        'is_consumer',
    ]
    extra_kwargs = {
        'password': {'write_only': True, 'min_length': MIN_LEN_PASSWORD},
        'created_at': {'read_only': True},
        'owning_org': {'read_only': True},
        'org_domain_name': {'read_only': True},
        'can_edit_org_data': {'read_only': True},
        'is_producer': {'read_only': True},
        'is_consumer': {'read_only': True},
    }
```

- [ ] **Run test to verify it passes**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test user.tests.test_user_api.UserApiTests.test_profile_returns_producer_consumer_flags --keepdb"
```

Expected: `OK (1 test)`

- [ ] **Run full user test suite to check for regressions**

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py test user --keepdb"
```

Expected: all existing tests still pass.

- [ ] **Commit (in strollopia-api/)**

```bash
git add app/user/serializers.py app/user/tests/test_user_api.py
git commit -m "feat: expose is_producer and is_consumer in user profile endpoint"
```

---

## Task 2: Fork data_logger → strollopia-pwa

*Working directory: `strollopia_git_hub/` (parent of data_logger and strollopia-pwa)*

**Files:** Populates the existing `strollopia-pwa/` clone (`git@github.com:John2662/strollopia-pwa.git`) with data_logger as the fork base.

- [ ] **Copy data_logger into the existing cloned repo**

```bash
# strollopia-pwa/ is already cloned with origin configured — copy data_logger content into it
cp -r data_logger/. strollopia-pwa/
cd strollopia-pwa
rm -rf node_modules
```

- [ ] **Remove data_logger-specific app pages**

These pages belong to the data logger product, not the guide:

```bash
rm -rf app/builder app/editor app/viewer app/route-mapper app/route-planner app/translate app/admin app/\[slug\]
```

- [ ] **Update package.json**

Replace `"name": "field-data-pwa"` with `"name": "strollopia-pwa"`.

The full `package.json` (keep all existing dependencies — Leaflet, dnd-kit, Tailwind are all needed):

```json
{
  "name": "strollopia-pwa",
  "version": "0.1.0",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@dnd-kit/core": "^6.3.1",
    "@dnd-kit/modifiers": "^9.0.0",
    "@dnd-kit/sortable": "^10.0.0",
    "@dnd-kit/utilities": "^3.2.2",
    "leaflet": "^1.9.4",
    "leaflet-geosearch": "^4.4.0",
    "leaflet.markercluster": "^1.5.3",
    "lucide-react": "^0.263.1",
    "next": "^14.2.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0"
  },
  "devDependencies": {
    "autoprefixer": "^10.0.0",
    "postcss": "^8.0.0",
    "tailwindcss": "^3.0.0",
    "vitest": "^1.0.0"
  }
}
```

- [ ] **Write CLAUDE.md**

```bash
cat > CLAUDE.md << 'EOF'
# Project Guidelines

## Git Commits
- Never include "Co-Authored-By: Claude" or any Claude co-author line in commit messages.

## Responses
- No end-of-turn summaries or recaps. Don't summarise what was just done.
EOF
```

- [ ] **Create .env.local for dev**

```bash
cat > .env.local << 'EOF'
NEXT_PUBLIC_API_URL=https://dev.strollopia.com
EOF
```

- [ ] **Install deps and verify dev server starts**

```bash
npm install
npm run dev
```

Visit `http://localhost:3001`. Expected: no JS errors, page loads (even if blank — the stripped data_logger shell).

- [ ] **Initial commit and push**

```bash
git add -A
git commit -m "init: fork data_logger as strollopia-pwa base"
git branch -M main
git push -u origin main
```

---

## Task 3: Core lib files — auth + config + plugin registry

**Files:**
- Modify: `lib/auth.js` — add `isProducer` / `isConsumer` state
- Create: `lib/plugin.js` — PluginProvider + usePlugin hook
- Create: `plugins/learning/index.js` — plugin manifest

- [ ] **Update lib/auth.js to expose isProducer and isConsumer**

Open `lib/auth.js`. Find the state declarations near the top (after `const [isOrgAdmin, setIsOrgAdmin] = useState(false);`) and add:

```javascript
const [isProducer, setIsProducer] = useState(false);
const [isConsumer, setIsConsumer] = useState(false);
```

Find where the profile response is parsed (look for `setCanEditOrgData` or `setIsOrgAdmin`) and add after those lines:

```javascript
setIsProducer(data.is_producer ?? false);
setIsConsumer(data.is_consumer ?? false);
```

Find the `AuthContext.Provider value={...}` and add to the value object:

```javascript
isProducer,
isConsumer,
```

Find the `useAuth()` hook consumer pattern (search for the exported destructuring list or the context value). The auth context value should now include `isProducer` and `isConsumer` alongside the existing fields.

- [ ] **Create plugins/learning/index.js**

```bash
mkdir -p plugins/learning
```

```javascript
// plugins/learning/index.js
const learningPlugin = {
  id: 'learning',
  // 'id' must match Plugin.key in the database exactly.

  nav: [
    { label: 'My Challenges', href: '/learn',  role: 'consumer' },
    { label: 'Dashboard',     href: '/teach',  role: 'producer' },
  ],

  roles: {
    producer: { label: 'Teacher',  plural: 'Teachers' },
    consumer: { label: 'Student',  plural: 'Students' },
  },
};

export default learningPlugin;
```

- [ ] **Create lib/plugin.js**

```javascript
'use client';

import { createContext, useContext, useMemo } from 'react';
import { useAuth } from './auth';
import learningPlugin from '../plugins/learning/index';

const PluginContext = createContext(null);

// All available plugin manifests. Add new plugin imports here.
const REGISTRY = [learningPlugin];

export function PluginProvider({ children }) {
  const { isProducer, isConsumer, isAuthenticated } = useAuth();

  // For v1: the learning plugin is always active.
  // A future version will fetch OrgPlugin.status from /api/core/org-plugins/
  // and filter REGISTRY by active keys.
  const activePlugins = useMemo(() => {
    if (!isAuthenticated) return [];
    return REGISTRY;
  }, [isAuthenticated]);

  const nav = useMemo(() => {
    const items = [];
    for (const plugin of activePlugins) {
      for (const entry of plugin.nav) {
        if (entry.role === 'producer' && isProducer) items.push(entry);
        if (entry.role === 'consumer' && isConsumer) items.push(entry);
      }
    }
    return items;
  }, [activePlugins, isProducer, isConsumer]);

  const roleLabel = useMemo(() => {
    if (!activePlugins.length) return { producer: 'Teacher', consumer: 'Student' };
    return activePlugins[0].roles;
  }, [activePlugins]);

  return (
    <PluginContext.Provider value={{ activePlugins, nav, roleLabel, isProducer, isConsumer }}>
      {children}
    </PluginContext.Provider>
  );
}

export function usePlugin() {
  const ctx = useContext(PluginContext);
  if (!ctx) throw new Error('usePlugin must be used inside PluginProvider');
  return ctx;
}
```

- [ ] **Update app/providers.js to include PluginProvider**

Find the return in `providers.js`. Add `PluginProvider` wrapping `children`, inside `AuthProvider` (because PluginProvider reads from auth):

```javascript
import { PluginProvider } from '../lib/plugin';

// Inside the return JSX, wrap children with PluginProvider
// (inside AuthProvider, after TranslationProvider or wherever children is rendered)
<AuthProvider>
  <ConfigProvider orgDomainName={orgDomainName}>
    <PluginProvider>
      <ThemeInjector />
      <TranslationProvider orgDomainName={orgDomainName}>
        {children}
        {!isEmbed && (
          <DevPanel currentOrg={orgDomainName} onOrgChange={handleOrgChange} />
        )}
      </TranslationProvider>
    </PluginProvider>
  </ConfigProvider>
</AuthProvider>
```

- [ ] **Verify dev server still loads**

```bash
npm run dev
```

Expected: no import errors, page loads.

- [ ] **Commit**

```bash
git add lib/auth.js lib/plugin.js plugins/ app/providers.js
git commit -m "feat: add PluginProvider and learning plugin manifest"
```

---

## Task 4: Challenges API client

**Files:**
- Modify: `utils/api.js` — add CHALLENGES_* endpoints
- Create: `utils/challengesApi.js` — typed fetch wrappers
- Create: `utils/api.test.js` — Vitest tests

- [ ] **Add challenge endpoints to utils/api.js**

Find the `API_ENDPOINTS` object. Add after the last existing entry:

```javascript
// Challenges
CHALLENGES:           `${API_BASE_URL}/api/challenges/`,
CHALLENGE_DETAIL:     (id) => `${API_BASE_URL}/api/challenges/${id}/`,
CHALLENGE_PUBLISH:    (id) => `${API_BASE_URL}/api/challenges/${id}/publish/`,
CHALLENGE_STOPS:      (id) => `${API_BASE_URL}/api/challenges/${id}/stops/`,
CHALLENGE_STOP:       (id, sid) => `${API_BASE_URL}/api/challenges/${id}/stops/${sid}/`,
CHALLENGE_ACTIVITIES: (id, sid) => `${API_BASE_URL}/api/challenges/${id}/stops/${sid}/activities/`,
CHALLENGE_ACTIVITY:   (id, sid, aid) => `${API_BASE_URL}/api/challenges/${id}/stops/${sid}/activities/${aid}/`,
CHALLENGE_ENROLL:     `${API_BASE_URL}/api/challenges/enrollments/`,
CHALLENGE_PROGRESS_SUBMIT: `${API_BASE_URL}/api/challenges/progress/`,
CHALLENGE_PROGRESS:   (id) => `${API_BASE_URL}/api/challenges/${id}/progress/`,
MY_PROGRESS:          `${API_BASE_URL}/api/challenges/me/progress/`,
```

- [ ] **Create utils/challengesApi.js**

```javascript
import { API_ENDPOINTS } from './api';
import { fetchWithTimeout } from '../lib/fetchWithTimeout';

function authHeaders(token) {
  return {
    'Content-Type': 'application/json',
    Authorization: `Token ${token}`,
  };
}

async function apiFetch(url, options) {
  const res = await fetchWithTimeout(url, options, 10000);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API ${res.status}: ${body}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

// ── Challenges ────────────────────────────────────────────────
export const listChallenges = (token) =>
  apiFetch(API_ENDPOINTS.CHALLENGES, { headers: authHeaders(token) });

export const getChallenge = (token, id) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_DETAIL(id), { headers: authHeaders(token) });

export const createChallenge = (token, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGES, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const patchChallenge = (token, id, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_DETAIL(id), {
    method: 'PATCH',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const publishChallenge = (token, id) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_PUBLISH(id), {
    method: 'POST',
    headers: authHeaders(token),
  });

// ── Stops ─────────────────────────────────────────────────────
export const listStops = (token, challengeId) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_STOPS(challengeId), { headers: authHeaders(token) });

export const createStop = (token, challengeId, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_STOPS(challengeId), {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const patchStop = (token, challengeId, stopId, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_STOP(challengeId, stopId), {
    method: 'PATCH',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const deleteStop = (token, challengeId, stopId) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_STOP(challengeId, stopId), {
    method: 'DELETE',
    headers: authHeaders(token),
  });

// ── Activities ────────────────────────────────────────────────
export const listActivities = (token, challengeId, stopId) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_ACTIVITIES(challengeId, stopId), {
    headers: authHeaders(token),
  });

export const createActivity = (token, challengeId, stopId, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_ACTIVITIES(challengeId, stopId), {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const patchActivity = (token, challengeId, stopId, activityId, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_ACTIVITY(challengeId, stopId, activityId), {
    method: 'PATCH',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

// ── Enrollment ────────────────────────────────────────────────
export const joinByCode = (token, joinCode) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_ENROLL, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ join_code: joinCode }),
  });

export const listEnrollments = (token) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_ENROLL, { headers: authHeaders(token) });

// ── Progress ──────────────────────────────────────────────────
export const submitProgress = (token, payload) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_PROGRESS_SUBMIT, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify(payload),
  });

export const getMyProgress = (token) =>
  apiFetch(API_ENDPOINTS.MY_PROGRESS, { headers: authHeaders(token) });

export const getChallengeProgress = (token, challengeId) =>
  apiFetch(API_ENDPOINTS.CHALLENGE_PROGRESS(challengeId), {
    headers: authHeaders(token),
  });
```

- [ ] **Create utils/api.test.js**

```javascript
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock fetchWithTimeout before importing the module under test
vi.mock('../lib/fetchWithTimeout', () => ({
  fetchWithTimeout: vi.fn(),
}));

import { fetchWithTimeout } from '../lib/fetchWithTimeout';
import {
  listChallenges,
  createChallenge,
  publishChallenge,
  joinByCode,
} from './challengesApi';

function mockResponse(status, body) {
  return {
    ok: status < 400,
    status,
    json: () => Promise.resolve(body),
    text: () => Promise.resolve(JSON.stringify(body)),
  };
}

describe('challengesApi', () => {
  const TOKEN = 'test-token-123';

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('listChallenges sends auth header and returns data', async () => {
    const data = [{ id: 1, title: 'Test' }];
    fetchWithTimeout.mockResolvedValue(mockResponse(200, data));

    const result = await listChallenges(TOKEN);

    expect(result).toEqual(data);
    const [url, opts] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/challenges/');
    expect(opts.headers.Authorization).toBe(`Token ${TOKEN}`);
  });

  it('createChallenge posts JSON body', async () => {
    const payload = { title: 'New', language: 'de' };
    fetchWithTimeout.mockResolvedValue(mockResponse(201, { id: 2, ...payload }));

    const result = await createChallenge(TOKEN, payload);

    expect(result.title).toBe('New');
    const [, opts] = fetchWithTimeout.mock.calls[0];
    expect(opts.method).toBe('POST');
    expect(JSON.parse(opts.body)).toEqual(payload);
  });

  it('publishChallenge posts to /publish/ endpoint', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse(200, { status: 'published' }));

    const result = await publishChallenge(TOKEN, 42);

    expect(result.status).toBe('published');
    const [url] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/challenges/42/publish/');
  });

  it('joinByCode sends join_code in body', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse(201, { id: 1 }));

    await joinByCode(TOKEN, 'ABC123');

    const [, opts] = fetchWithTimeout.mock.calls[0];
    expect(JSON.parse(opts.body)).toEqual({ join_code: 'ABC123' });
  });

  it('throws on non-ok response', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse(400, { detail: 'Bad request' }));

    await expect(createChallenge(TOKEN, {})).rejects.toThrow('API 400');
  });
});
```

- [ ] **Run tests to verify they pass**

```bash
npm test
```

Expected: `5 tests passed`

- [ ] **Commit**

```bash
git add utils/api.js utils/challengesApi.js utils/api.test.js
git commit -m "feat: add challenges API client with unit tests"
```

---

## Task 5: Home page and AppShell

**Files:**
- Modify: `app/page.js` — role-based redirect
- Modify: `components/AppShell.js` — simplified shell with plugin-aware nav

- [ ] **Rewrite app/page.js**

```javascript
'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '../lib/auth';
import { usePlugin } from '../lib/plugin';

export default function Home() {
  const router = useRouter();
  const { isAuthenticated } = useAuth();
  const { isProducer, isConsumer } = usePlugin();

  useEffect(() => {
    if (!isAuthenticated) return;
    if (isProducer) router.replace('/teach');
    else if (isConsumer) router.replace('/learn');
  }, [isAuthenticated, isProducer, isConsumer, router]);

  if (!isAuthenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center p-8 text-center">
        <div>
          <h1 className="text-2xl font-bold">Strollopia Guide</h1>
          <p className="mt-2 text-gray-600">Please log in to continue.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center">
      <p className="text-gray-500">Redirecting…</p>
    </div>
  );
}
```

- [ ] **Rewrite components/AppShell.js**

```javascript
'use client';

import Link from 'next/link';
import { usePlugin } from '../lib/plugin';
import LoginModal from './LoginModal';

export default function AppShell({ children }) {
  const { nav } = usePlugin();

  return (
    <>
      {nav.length > 0 && (
        <nav className="fixed top-0 inset-x-0 z-50 bg-white border-b border-gray-200 px-4 h-12 flex items-center gap-6">
          {nav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="text-sm font-medium text-gray-700 hover:text-orange-600 transition-colors"
            >
              {item.label}
            </Link>
          ))}
        </nav>
      )}
      <main className={nav.length > 0 ? 'pt-12' : ''}>
        {children}
      </main>
      <LoginModal />
    </>
  );
}
```

- [ ] **Verify dev server — home page redirects correctly**

Log in as a producer user and verify redirect to `/teach`. Log in as a consumer and verify redirect to `/learn`. Not-logged-in state shows the login message.

- [ ] **Commit**

```bash
git add app/page.js components/AppShell.js
git commit -m "feat: home page role redirect + plugin-aware nav"
```

---

## Task 6: Teacher challenge builder

**Files:**
- Create: `app/teach/builder/[id]/page.js` — 3-panel layout
- Create: `components/teach/StopSidebar.js` — dnd-kit sortable stop list
- Create: `components/teach/BuilderMap.js` — Leaflet map, click-to-place stops
- Create: `components/teach/ActivityEditor.js` — activity type picker + JSON form

- [ ] **Create components/teach/StopSidebar.js**

```javascript
'use client';

import { DndContext, closestCenter, PointerSensor, useSensor, useSensors } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy, useSortable, arrayMove } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { GripVertical, Plus, Trash2 } from 'lucide-react';

function SortableStop({ stop, isSelected, onSelect, onDelete }) {
  const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id: stop.id });
  const style = { transform: CSS.Transform.toString(transform), transition };

  const statusColor = stop.activities?.length > 0
    ? 'bg-green-100 border-green-300'
    : isSelected
    ? 'bg-blue-100 border-blue-300'
    : 'bg-gray-50 border-gray-200';

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`flex items-center gap-2 p-3 mb-2 rounded-lg border cursor-pointer ${statusColor}`}
      onClick={() => onSelect(stop)}
    >
      <button {...attributes} {...listeners} className="text-gray-400 hover:text-gray-600 cursor-grab">
        <GripVertical className="w-4 h-4" />
      </button>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{stop.name || `Stop ${stop.order}`}</p>
        <p className="text-xs text-gray-500">{stop.activities?.length ?? 0} activities</p>
      </div>
      <button
        onClick={(e) => { e.stopPropagation(); onDelete(stop.id); }}
        className="text-gray-400 hover:text-red-500"
      >
        <Trash2 className="w-4 h-4" />
      </button>
    </div>
  );
}

export default function StopSidebar({ stops, selectedStop, onSelect, onReorder, onDelete, onAdd }) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  function handleDragEnd(event) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIndex = stops.findIndex((s) => s.id === active.id);
    const newIndex = stops.findIndex((s) => s.id === over.id);
    onReorder(arrayMove(stops, oldIndex, newIndex));
  }

  return (
    <div className="flex flex-col h-full">
      <div className="p-4 border-b border-gray-200">
        <h2 className="font-semibold text-gray-800">Stops</h2>
      </div>
      <div className="flex-1 overflow-y-auto p-3">
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={stops.map((s) => s.id)} strategy={verticalListSortingStrategy}>
            {stops.map((stop) => (
              <SortableStop
                key={stop.id}
                stop={stop}
                isSelected={selectedStop?.id === stop.id}
                onSelect={onSelect}
                onDelete={onDelete}
              />
            ))}
          </SortableContext>
        </DndContext>
        {stops.length === 0 && (
          <p className="text-sm text-gray-400 text-center mt-8">Click the map to place your first stop.</p>
        )}
      </div>
      <div className="p-3 border-t border-gray-200">
        <button
          onClick={onAdd}
          className="w-full flex items-center justify-center gap-2 py-2 text-sm text-orange-600 border border-orange-200 rounded-lg hover:bg-orange-50"
        >
          <Plus className="w-4 h-4" />
          Add stop manually
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Create components/teach/BuilderMap.js**

```javascript
'use client';

import { useEffect, useRef } from 'react';

const INNSBRUCK = [47.2692, 11.4041];
const ZOOM = 14;

export default function BuilderMap({ stops, selectedStop, onMapClick, onMarkerDrag }) {
  const mapRef = useRef(null);
  const leafletRef = useRef(null);
  const markersRef = useRef({});

  useEffect(() => {
    if (typeof window === 'undefined' || leafletRef.current) return;

    import('leaflet').then((L) => {
      delete L.Icon.Default.prototype._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
        iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
        shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      });

      const map = L.map(mapRef.current).setView(INNSBRUCK, ZOOM);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
      }).addTo(map);

      map.on('click', (e) => onMapClick(e.latlng.lat, e.latlng.lng));
      leafletRef.current = { map, L };
    });

    return () => {
      if (leafletRef.current?.map) {
        leafletRef.current.map.remove();
        leafletRef.current = null;
      }
    };
  }, []);

  // Sync markers with stops
  useEffect(() => {
    if (!leafletRef.current) return;
    const { map, L } = leafletRef.current;

    // Remove stale markers
    const stopIds = new Set(stops.map((s) => s.id));
    for (const [id, marker] of Object.entries(markersRef.current)) {
      if (!stopIds.has(Number(id))) {
        map.removeLayer(marker);
        delete markersRef.current[id];
      }
    }

    // Add/update markers
    for (const stop of stops) {
      if (markersRef.current[stop.id]) {
        markersRef.current[stop.id].setLatLng([stop.lat, stop.lng]);
      } else {
        const marker = L.marker([stop.lat, stop.lng], { draggable: true })
          .addTo(map)
          .bindPopup(stop.name || `Stop ${stop.order}`);
        marker.on('dragend', (e) => {
          const { lat, lng } = e.target.getLatLng();
          onMarkerDrag(stop.id, lat, lng);
        });
        markersRef.current[stop.id] = marker;
      }
    }
  }, [stops, onMarkerDrag]);

  // Highlight selected stop
  useEffect(() => {
    if (!selectedStop || !markersRef.current[selectedStop.id]) return;
    markersRef.current[selectedStop.id].openPopup();
  }, [selectedStop]);

  return (
    <>
      <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
      <div ref={mapRef} className="w-full h-full" />
    </>
  );
}
```

- [ ] **Create components/teach/ActivityEditor.js**

```javascript
'use client';

import { useState } from 'react';

const ACTIVITY_TYPES = [
  { type: 'QUIZ',    label: 'Quiz',      icon: '🔤' },
  { type: 'LISTEN',  label: 'Listen',    icon: '🎧' },
  { type: 'SPEAK',   label: 'Speak',     icon: '🗣️' },
  { type: 'WRITE',   label: 'Write',     icon: '✏️' },
  { type: 'PHOTO',   label: 'Photo',     icon: '📷' },
  { type: 'CHECKIN', label: 'Check-in',  icon: '✅' },
];

function QuizForm({ content, onChange }) {
  const options = content.options || [
    { text: '', is_correct: true },
    { text: '', is_correct: false },
  ];
  return (
    <div className="space-y-3">
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">Question</label>
        <input
          className="w-full border rounded px-3 py-2 text-sm"
          value={content.question || ''}
          onChange={(e) => onChange({ ...content, question: e.target.value })}
          placeholder="Wie komme ich zum Marktplatz?"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">Options</label>
        {options.map((opt, i) => (
          <div key={i} className="flex items-center gap-2 mb-2">
            <input
              type="radio"
              checked={opt.is_correct}
              onChange={() =>
                onChange({
                  ...content,
                  options: options.map((o, j) => ({ ...o, is_correct: j === i })),
                })
              }
            />
            <input
              className="flex-1 border rounded px-2 py-1 text-sm"
              value={opt.text}
              placeholder={`Option ${i + 1}`}
              onChange={(e) => {
                const updated = [...options];
                updated[i] = { ...updated[i], text: e.target.value };
                onChange({ ...content, options: updated });
              }}
            />
          </div>
        ))}
        <button
          className="text-xs text-orange-600 hover:underline"
          onClick={() =>
            onChange({
              ...content,
              options: [...options, { text: '', is_correct: false }],
            })
          }
        >
          + Add option
        </button>
      </div>
    </div>
  );
}

function SimplePromptForm({ content, onChange, promptLabel, answerLabel }) {
  return (
    <div className="space-y-3">
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">{promptLabel}</label>
        <textarea
          className="w-full border rounded px-3 py-2 text-sm"
          rows={3}
          value={content.prompt || ''}
          onChange={(e) => onChange({ ...content, prompt: e.target.value })}
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">{answerLabel}</label>
        <textarea
          className="w-full border rounded px-3 py-2 text-sm"
          rows={2}
          value={content.model_answer || ''}
          onChange={(e) => onChange({ ...content, model_answer: e.target.value })}
        />
      </div>
    </div>
  );
}

function InstructionForm({ content, onChange, placeholder }) {
  return (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">Instruction</label>
      <textarea
        className="w-full border rounded px-3 py-2 text-sm"
        rows={3}
        value={content.instruction || ''}
        placeholder={placeholder}
        onChange={(e) => onChange({ ...content, instruction: e.target.value })}
      />
    </div>
  );
}

function ListenForm({ content, onChange }) {
  return (
    <div className="space-y-3">
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">Audio URL</label>
        <input
          className="w-full border rounded px-3 py-2 text-sm"
          value={content.audio_url || ''}
          placeholder="https://cdn.example.com/audio/clip.mp3"
          onChange={(e) => onChange({ ...content, audio_url: e.target.value })}
        />
      </div>
      <QuizForm content={content} onChange={onChange} />
    </div>
  );
}

const FORMS = {
  QUIZ:    (c, onChange) => <QuizForm content={c} onChange={onChange} />,
  LISTEN:  (c, onChange) => <ListenForm content={c} onChange={onChange} />,
  SPEAK:   (c, onChange) => <SimplePromptForm content={c} onChange={onChange} promptLabel="Prompt" answerLabel="Model answer" />,
  WRITE:   (c, onChange) => <SimplePromptForm content={c} onChange={onChange} promptLabel="Prompt" answerLabel="Model answer" />,
  PHOTO:   (c, onChange) => <InstructionForm content={c} onChange={onChange} placeholder="Photograph the departure board…" />,
  CHECKIN: (c, onChange) => <InstructionForm content={c} onChange={onChange} placeholder="Scan the QR code at the plaque." />,
};

export default function ActivityEditor({ stop, activities, onSave }) {
  const [activityType, setActivityType] = useState('QUIZ');
  const [content, setContent] = useState({});
  const [saving, setSaving] = useState(false);

  if (!stop) {
    return (
      <div className="flex items-center justify-center h-full text-gray-400 text-sm">
        Select a stop to add activities.
      </div>
    );
  }

  async function handleSave() {
    setSaving(true);
    try {
      await onSave(stop.id, activityType, { _type: activityType, ...content });
      setContent({});
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex flex-col h-full">
      <div className="p-4 border-b">
        <h2 className="font-semibold text-gray-800">{stop.name || `Stop ${stop.order}`}</h2>
        <p className="text-xs text-gray-500 mt-0.5">
          {activities.length} {activities.length === 1 ? 'activity' : 'activities'}
        </p>
      </div>

      {/* Existing activities */}
      {activities.length > 0 && (
        <div className="p-3 border-b">
          {activities.map((a) => (
            <div key={a.id} className="flex items-center gap-2 py-1 text-sm text-gray-700">
              <span>{ACTIVITY_TYPES.find((t) => t.type === a.activity_type)?.icon}</span>
              <span>{ACTIVITY_TYPES.find((t) => t.type === a.activity_type)?.label}</span>
              <span className="text-gray-400">#{a.order}</span>
            </div>
          ))}
        </div>
      )}

      {/* Add new activity */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-2">Activity type</label>
          <div className="grid grid-cols-3 gap-2">
            {ACTIVITY_TYPES.map(({ type, label, icon }) => (
              <button
                key={type}
                onClick={() => { setActivityType(type); setContent({}); }}
                className={`flex flex-col items-center p-2 rounded-lg border text-xs transition ${
                  activityType === type
                    ? 'border-orange-500 bg-orange-50 text-orange-700'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <span className="text-lg">{icon}</span>
                <span>{label}</span>
              </button>
            ))}
          </div>
        </div>

        {FORMS[activityType]?.(content, setContent)}
      </div>

      <div className="p-3 border-t">
        <button
          onClick={handleSave}
          disabled={saving}
          className="w-full py-2 bg-orange-600 text-white text-sm rounded-lg hover:bg-red-700 disabled:opacity-50"
        >
          {saving ? 'Saving…' : 'Add activity'}
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Create app/teach/builder/[id]/page.js**

```javascript
'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import { useAuth } from '../../../../lib/auth';
import {
  getChallenge, listStops, listActivities,
  createStop, patchStop, deleteStop, patchChallenge,
  publishChallenge, createActivity,
} from '../../../../utils/challengesApi';
import StopSidebar from '../../../../components/teach/StopSidebar';
import ActivityEditor from '../../../../components/teach/ActivityEditor';

// Leaflet must be client-only (no SSR)
const BuilderMap = dynamic(() => import('../../../../components/teach/BuilderMap'), { ssr: false });

export default function ChallengeBuilderPage({ params }) {
  const { id } = params;
  const router = useRouter();
  const { authToken } = useAuth();
  const [challenge, setChallenge] = useState(null);
  const [stops, setStops] = useState([]);
  const [activities, setActivities] = useState({}); // { [stopId]: Activity[] }
  const [selectedStop, setSelectedStop] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!authToken) return;
    getChallenge(authToken, id).then(setChallenge);
    listStops(authToken, id).then((data) => {
      setStops(data);
      // Load activities for each stop
      data.forEach((stop) => {
        listActivities(authToken, id, stop.id).then((acts) =>
          setActivities((prev) => ({ ...prev, [stop.id]: acts }))
        );
      });
    });
  }, [authToken, id]);

  const handleMapClick = useCallback(async (lat, lng) => {
    const order = stops.length + 1;
    const newStop = await createStop(authToken, id, {
      order,
      name: `Stop ${order}`,
      lat,
      lng,
    });
    setStops((prev) => [...prev, newStop]);
    setSelectedStop(newStop);
    setActivities((prev) => ({ ...prev, [newStop.id]: [] }));
  }, [authToken, id, stops.length]);

  const handleMarkerDrag = useCallback(async (stopId, lat, lng) => {
    await patchStop(authToken, id, stopId, { lat, lng });
    setStops((prev) => prev.map((s) => s.id === stopId ? { ...s, lat, lng } : s));
  }, [authToken, id]);

  const handleReorder = useCallback(async (reordered) => {
    setStops(reordered);
    // Patch each stop's order
    reordered.forEach((stop, idx) => {
      if (stop.order !== idx + 1) {
        patchStop(authToken, id, stop.id, { order: idx + 1 });
      }
    });
  }, [authToken, id]);

  const handleDelete = useCallback(async (stopId) => {
    await deleteStop(authToken, id, stopId);
    setStops((prev) => prev.filter((s) => s.id !== stopId));
    if (selectedStop?.id === stopId) setSelectedStop(null);
  }, [authToken, id, selectedStop]);

  const handleAddActivity = useCallback(async (stopId, activityType, content) => {
    const order = (activities[stopId]?.length ?? 0) + 1;
    const newActivity = await createActivity(authToken, id, stopId, {
      order,
      activity_type: activityType,
      content,
    });
    setActivities((prev) => ({
      ...prev,
      [stopId]: [...(prev[stopId] || []), newActivity],
    }));
  }, [authToken, id, activities]);

  const handlePublish = async () => {
    setSaving(true);
    try {
      const updated = await publishChallenge(authToken, id);
      setChallenge((prev) => ({ ...prev, status: updated.status }));
    } finally {
      setSaving(false);
    }
  };

  if (!challenge) return <div className="flex items-center justify-center h-screen">Loading…</div>;

  return (
    <div className="flex h-screen">
      {/* Left: stop sidebar */}
      <div className="w-64 border-r border-gray-200 flex flex-col flex-shrink-0">
        <StopSidebar
          stops={stops}
          selectedStop={selectedStop}
          onSelect={setSelectedStop}
          onReorder={handleReorder}
          onDelete={handleDelete}
          onAdd={() => handleMapClick(47.2692, 11.4041)}
        />
        <div className="p-3 border-t space-y-2">
          {challenge.status === 'draft' && (
            <button
              onClick={handlePublish}
              disabled={saving || stops.length === 0}
              className="w-full py-2 bg-green-600 text-white text-sm rounded-lg hover:bg-green-700 disabled:opacity-40"
            >
              {saving ? 'Publishing…' : 'Publish'}
            </button>
          )}
          {challenge.status === 'published' && (
            <div className="text-center text-xs text-green-600 font-medium">
              Published · Join code: {challenge.join_code}
            </div>
          )}
        </div>
      </div>

      {/* Centre: map */}
      <div className="flex-1 relative">
        <BuilderMap
          stops={stops}
          selectedStop={selectedStop}
          onMapClick={handleMapClick}
          onMarkerDrag={handleMarkerDrag}
        />
      </div>

      {/* Right: activity editor */}
      <div className="w-72 border-l border-gray-200 flex flex-col flex-shrink-0">
        <ActivityEditor
          stop={selectedStop}
          activities={selectedStop ? (activities[selectedStop.id] || []) : []}
          onSave={handleAddActivity}
        />
      </div>
    </div>
  );
}
```

- [ ] **Create app/teach/page.js (teacher dashboard stub — expanded in Task 8)**

```javascript
'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { Plus } from 'lucide-react';
import { useAuth } from '../../lib/auth';
import { listChallenges, createChallenge } from '../../utils/challengesApi';

export default function TeacherDashboard() {
  const { authToken } = useAuth();
  const [challenges, setChallenges] = useState([]);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (!authToken) return;
    listChallenges(authToken).then(setChallenges);
  }, [authToken]);

  async function handleCreate() {
    setCreating(true);
    try {
      const challenge = await createChallenge(authToken, {
        title: 'New Challenge',
        language: 'en',
      });
      setChallenges((prev) => [challenge, ...prev]);
    } finally {
      setCreating(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">My Challenges</h1>
        <button
          onClick={handleCreate}
          disabled={creating}
          className="flex items-center gap-2 px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50 text-sm"
        >
          <Plus className="w-4 h-4" />
          {creating ? 'Creating…' : 'New challenge'}
        </button>
      </div>

      <div className="space-y-3">
        {challenges.map((c) => (
          <div key={c.id} className="flex items-center justify-between p-4 border border-gray-200 rounded-xl">
            <div>
              <p className="font-medium">{c.title}</p>
              <p className="text-sm text-gray-500">{c.language.toUpperCase()} · {c.level || 'No level'} · {c.status}</p>
              {c.status === 'published' && (
                <p className="text-xs text-green-600 mt-0.5">Join code: {c.join_code}</p>
              )}
            </div>
            <Link
              href={`/teach/builder/${c.id}`}
              className="text-sm text-orange-600 hover:underline"
            >
              Edit →
            </Link>
          </div>
        ))}
        {challenges.length === 0 && (
          <p className="text-gray-400 text-center py-12">No challenges yet. Create your first one.</p>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Verify builder works end-to-end**

1. Start the dev server: `npm run dev`
2. Log in as a producer user.
3. Navigate to `/teach` → should see challenge list.
4. Click "New challenge" → new challenge created, appears in list.
5. Click "Edit →" → should go to `/teach/builder/:id`
6. Map renders centered on Innsbruck.
7. Click map → stop appears in sidebar and as a marker.
8. Drag marker → position updates.
9. Select stop → ActivityEditor shows.
10. Pick "Quiz", fill question + 2 options, click "Add activity" → activity saved.
11. Click "Publish" → status updates, join code shown.

- [ ] **Commit**

```bash
git add app/teach/ components/teach/
git commit -m "feat: teacher challenge builder — 3-panel layout with Leaflet + dnd-kit"
```

---

## Task 7: Student home + Linear Mission mode

**Files:**
- Create: `app/learn/page.js` — student challenge list
- Create: `app/learn/[id]/page.js` — challenge view (mode router)
- Create: `components/learn/ChallengeCard.js`
- Create: `components/learn/LinearMissionView.js`
- Create: `components/learn/ActivityCard.js`

- [ ] **Create components/learn/ChallengeCard.js**

```javascript
import Link from 'next/link';
import { MapPin, ChevronRight } from 'lucide-react';

export default function ChallengeCard({ challenge }) {
  return (
    <Link
      href={`/learn/${challenge.id}`}
      className="flex items-center gap-4 p-4 border border-gray-200 rounded-xl hover:border-orange-300 hover:shadow-sm transition"
    >
      <div className="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center flex-shrink-0">
        <MapPin className="w-5 h-5 text-orange-600" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-medium truncate">{challenge.title}</p>
        <p className="text-sm text-gray-500">
          {challenge.language.toUpperCase()} · {challenge.level || '—'} · {challenge.stops_count ?? '?'} stops
        </p>
      </div>
      <ChevronRight className="w-5 h-5 text-gray-400 flex-shrink-0" />
    </Link>
  );
}
```

- [ ] **Create components/learn/ActivityCard.js**

```javascript
'use client';

import { useState } from 'react';
import { CheckCircle } from 'lucide-react';

function QuizActivity({ content, onSubmit, disabled }) {
  const [selected, setSelected] = useState(null);
  const [submitted, setSubmitted] = useState(false);

  function handleSubmit() {
    if (selected === null) return;
    setSubmitted(true);
    const correct = content.options[selected]?.is_correct ?? false;
    onSubmit({ selected_index: selected, is_correct: correct }, correct ? 1.0 : 0.0);
  }

  return (
    <div className="space-y-3">
      <p className="font-medium text-gray-800">{content.question}</p>
      <div className="space-y-2">
        {(content.options || []).map((opt, i) => {
          let optClass = 'border-gray-200 bg-white';
          if (submitted) {
            optClass = opt.is_correct
              ? 'border-green-500 bg-green-50'
              : selected === i
              ? 'border-red-400 bg-red-50'
              : 'border-gray-200 bg-white opacity-50';
          } else if (selected === i) {
            optClass = 'border-orange-500 bg-orange-50';
          }
          return (
            <button
              key={i}
              disabled={submitted || disabled}
              onClick={() => setSelected(i)}
              className={`w-full text-left px-4 py-3 rounded-lg border text-sm transition ${optClass}`}
            >
              {opt.text}
            </button>
          );
        })}
      </div>
      {!submitted && (
        <button
          disabled={selected === null || disabled}
          onClick={handleSubmit}
          className="w-full py-2 bg-orange-600 text-white rounded-lg text-sm hover:bg-red-700 disabled:opacity-40"
        >
          Submit
        </button>
      )}
      {submitted && content.explanation && (
        <p className="text-sm text-gray-600 bg-gray-50 rounded-lg p-3">{content.explanation}</p>
      )}
    </div>
  );
}

function CheckinActivity({ content, onSubmit, disabled }) {
  const [done, setDone] = useState(false);
  function handleCheckin() {
    setDone(true);
    onSubmit({ checked_in: true }, 1.0);
  }
  return (
    <div className="space-y-3">
      <p className="text-gray-700">{content.instruction}</p>
      <button
        disabled={done || disabled}
        onClick={handleCheckin}
        className="w-full py-2 bg-orange-600 text-white rounded-lg text-sm hover:bg-red-700 disabled:opacity-40 flex items-center justify-center gap-2"
      >
        {done ? <><CheckCircle className="w-4 h-4" /> Checked in</> : 'Check in here'}
      </button>
    </div>
  );
}

function ManualActivity({ content, activityType, onSubmit, disabled }) {
  const [response, setResponse] = useState('');
  const [submitted, setSubmitted] = useState(false);
  function handleSubmit() {
    setSubmitted(true);
    onSubmit({ response_text: response }, null);
  }
  return (
    <div className="space-y-3">
      <p className="font-medium text-gray-800">{content.prompt || content.instruction}</p>
      {content.model_answer && (
        <p className="text-xs text-gray-500 italic">Model: {content.model_answer}</p>
      )}
      {!submitted ? (
        <>
          <textarea
            className="w-full border rounded-lg px-3 py-2 text-sm"
            rows={3}
            value={response}
            onChange={(e) => setResponse(e.target.value)}
            placeholder="Your response…"
            disabled={disabled}
          />
          <button
            disabled={!response.trim() || disabled}
            onClick={handleSubmit}
            className="w-full py-2 bg-orange-600 text-white rounded-lg text-sm hover:bg-red-700 disabled:opacity-40"
          >
            Submit
          </button>
        </>
      ) : (
        <p className="text-sm text-green-600">Response recorded — your teacher will review it.</p>
      )}
    </div>
  );
}

export default function ActivityCard({ activity, onSubmit, disabled = false }) {
  const { content, activity_type: type } = activity;

  const body = (() => {
    if (type === 'QUIZ') return <QuizActivity content={content} onSubmit={onSubmit} disabled={disabled} />;
    if (type === 'CHECKIN') return <CheckinActivity content={content} onSubmit={onSubmit} disabled={disabled} />;
    return <ManualActivity content={content} activityType={type} onSubmit={onSubmit} disabled={disabled} />;
  })();

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5 shadow-sm">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-xs font-medium text-orange-600 uppercase tracking-wider">{type}</span>
      </div>
      {body}
    </div>
  );
}
```

- [ ] **Create components/learn/LinearMissionView.js**

```javascript
'use client';

import { useState } from 'react';
import { CheckCircle, Lock, MapPin } from 'lucide-react';
import ActivityCard from './ActivityCard';

export default function LinearMissionView({ challenge, stops, activities, progress, onSubmit }) {
  const [expandedStop, setExpandedStop] = useState(stops[0]?.id ?? null);

  function isStopUnlocked(stopIndex) {
    if (stopIndex === 0) return true;
    const prevStop = stops[stopIndex - 1];
    const prevActivities = activities[prevStop?.id] || [];
    if (prevActivities.length === 0) return true;
    return prevActivities.every((a) =>
      progress[a.id]?.status === 'completed' || progress[a.id]?.status === 'skipped'
    );
  }

  function stopStatus(stop) {
    const acts = activities[stop.id] || [];
    if (acts.length === 0) return 'empty';
    const completed = acts.filter((a) => progress[a.id]?.status === 'completed').length;
    if (completed === acts.length) return 'done';
    if (completed > 0) return 'partial';
    return 'pending';
  }

  const statusIcon = {
    done:    <CheckCircle className="w-5 h-5 text-green-500" />,
    partial: <div className="w-5 h-5 rounded-full border-2 border-orange-400 bg-orange-100" />,
    pending: <div className="w-5 h-5 rounded-full border-2 border-gray-300" />,
    empty:   <MapPin className="w-5 h-5 text-gray-400" />,
  };

  return (
    <div className="max-w-lg mx-auto p-4 space-y-3 pb-20">
      {/* Progress bar */}
      <div className="mb-4">
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>{challenge.title}</span>
          <span>
            {stops.filter((s, i) => stopStatus(s) === 'done').length} / {stops.length} stops
          </span>
        </div>
        <div className="h-2 bg-gray-200 rounded-full">
          <div
            className="h-2 bg-orange-500 rounded-full transition-all"
            style={{
              width: `${stops.length ? (stops.filter((s) => stopStatus(s) === 'done').length / stops.length) * 100 : 0}%`,
            }}
          />
        </div>
      </div>

      {stops.map((stop, i) => {
        const unlocked = isStopUnlocked(i);
        const status = stopStatus(stop);
        const isOpen = expandedStop === stop.id && unlocked;

        return (
          <div key={stop.id} className={`rounded-xl border overflow-hidden transition ${unlocked ? 'border-gray-200' : 'border-gray-100 opacity-60'}`}>
            <button
              className="w-full flex items-center gap-3 p-4 text-left"
              onClick={() => unlocked && setExpandedStop(isOpen ? null : stop.id)}
              disabled={!unlocked}
            >
              {unlocked ? statusIcon[status] : <Lock className="w-5 h-5 text-gray-400" />}
              <div className="flex-1">
                <p className="font-medium text-sm">{stop.name}</p>
                <p className="text-xs text-gray-500">{(activities[stop.id] || []).length} activities</p>
              </div>
            </button>

            {isOpen && (
              <div className="px-4 pb-4 space-y-3 border-t border-gray-100 pt-3">
                {(activities[stop.id] || []).map((activity) => (
                  <ActivityCard
                    key={activity.id}
                    activity={activity}
                    disabled={progress[activity.id]?.status === 'completed'}
                    onSubmit={(response, score) => onSubmit(activity, response, score)}
                  />
                ))}
                {(activities[stop.id] || []).length === 0 && (
                  <p className="text-sm text-gray-400">No activities at this stop yet.</p>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
```

- [ ] **Create app/learn/page.js**

```javascript
'use client';

import { useState, useEffect } from 'react';
import { useAuth } from '../../lib/auth';
import { listEnrollments } from '../../utils/challengesApi';
import ChallengeCard from '../../components/learn/ChallengeCard';

export default function StudentHome() {
  const { authToken } = useAuth();
  const [enrollments, setEnrollments] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authToken) return;
    listEnrollments(authToken)
      .then(setEnrollments)
      .finally(() => setLoading(false));
  }, [authToken]);

  if (loading) return <div className="flex items-center justify-center h-64 text-gray-400">Loading…</div>;

  return (
    <div className="p-6 max-w-lg mx-auto">
      <h1 className="text-2xl font-bold mb-6">My Challenges</h1>
      <div className="space-y-3">
        {enrollments.map((enrollment) => (
          <ChallengeCard key={enrollment.id} challenge={enrollment.challenge} />
        ))}
        {enrollments.length === 0 && (
          <div className="text-center py-12">
            <p className="text-gray-400">No challenges yet.</p>
            <p className="text-sm text-gray-400 mt-1">Ask your teacher for a join code.</p>
          </div>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Create app/learn/[id]/page.js**

```javascript
'use client';

import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../../../lib/auth';
import {
  getChallenge, listStops, listActivities,
  getMyProgress, submitProgress,
} from '../../../utils/challengesApi';
import LinearMissionView from '../../../components/learn/LinearMissionView';

export default function ChallengeViewPage({ params }) {
  const { id } = params;
  const { authToken } = useAuth();
  const [challenge, setChallenge] = useState(null);
  const [stops, setStops] = useState([]);
  const [activities, setActivities] = useState({});     // { [stopId]: Activity[] }
  const [progress, setProgress] = useState({});         // { [activityId]: StudentProgress }
  const [enrollmentId, setEnrollmentId] = useState(null);

  useEffect(() => {
    if (!authToken) return;
    async function load() {
      const [ch, myProgress] = await Promise.all([
        getChallenge(authToken, id),
        getMyProgress(authToken),
      ]);
      setChallenge(ch);

      const enrollment = myProgress.find
        ? myProgress.find((p) => p.enrollment?.challenge === Number(id))
        : null;
      if (enrollment) setEnrollmentId(enrollment.enrollment);

      const progressMap = {};
      (Array.isArray(myProgress) ? myProgress : []).forEach((p) => {
        progressMap[p.activity] = p;
      });
      setProgress(progressMap);

      const stopsData = await listStops(authToken, id);
      setStops(stopsData);

      const acts = {};
      await Promise.all(
        stopsData.map(async (stop) => {
          acts[stop.id] = await listActivities(authToken, id, stop.id);
        })
      );
      setActivities(acts);
    }
    load();
  }, [authToken, id]);

  const handleSubmit = useCallback(async (activity, response, score) => {
    if (!enrollmentId) return;
    const result = await submitProgress(authToken, {
      enrollment: enrollmentId,
      activity: activity.id,
      status: 'completed',
      response,
      score,
    });
    setProgress((prev) => ({ ...prev, [activity.id]: result }));
  }, [authToken, enrollmentId]);

  if (!challenge) return <div className="flex items-center justify-center h-64 text-gray-400">Loading…</div>;

  return (
    <LinearMissionView
      challenge={challenge}
      stops={stops}
      activities={activities}
      progress={progress}
      onSubmit={handleSubmit}
    />
  );
}
```

- [ ] **Verify student flow works end-to-end**

1. Log in as a consumer user who has an enrollment (use the join flow, Task 8, or create via admin).
2. Navigate to `/learn` → should see enrolled challenges.
3. Click a challenge → LinearMissionView renders stops.
4. First stop is unlocked; complete its activities.
5. Second stop unlocks after first is done.

- [ ] **Commit**

```bash
git add app/learn/ components/learn/
git commit -m "feat: student home and Linear Mission mode (Mode A)"
```

---

## Task 8: Join-code enrollment flow

**Files:**
- Create: `app/join/[code]/page.js`

- [ ] **Create app/join/[code]/page.js**

```javascript
'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '../../../lib/auth';
import { joinByCode } from '../../../utils/challengesApi';
import { MapPin } from 'lucide-react';

export default function JoinPage({ params }) {
  const { code } = params;
  const router = useRouter();
  const { authToken, isAuthenticated, promptLogin } = useAuth();
  const [status, setStatus] = useState('idle'); // idle | joining | done | error
  const [error, setError] = useState('');

  useEffect(() => {
    if (!isAuthenticated) {
      promptLogin();
      return;
    }
    if (status !== 'idle') return;
    setStatus('joining');
    joinByCode(authToken, code)
      .then(() => {
        setStatus('done');
        setTimeout(() => router.replace('/learn'), 1500);
      })
      .catch((err) => {
        setStatus('error');
        setError(err.message.includes('400')
          ? 'Invalid or expired join code. Check with your teacher.'
          : err.message);
      });
  }, [isAuthenticated, authToken, code, status, promptLogin, router]);

  return (
    <div className="flex min-h-screen items-center justify-center p-8">
      <div className="max-w-sm w-full text-center space-y-4">
        <div className="w-16 h-16 bg-orange-100 rounded-full flex items-center justify-center mx-auto">
          <MapPin className="w-8 h-8 text-orange-600" />
        </div>

        {status === 'idle' && <p className="text-gray-500">Preparing to join…</p>}

        {status === 'joining' && (
          <>
            <h1 className="text-xl font-bold">Joining challenge…</h1>
            <p className="text-gray-500">Code: {code}</p>
          </>
        )}

        {status === 'done' && (
          <>
            <h1 className="text-xl font-bold text-green-600">Enrolled!</h1>
            <p className="text-gray-500">Taking you to your challenges…</p>
          </>
        )}

        {status === 'error' && (
          <>
            <h1 className="text-xl font-bold text-red-600">Couldn't join</h1>
            <p className="text-sm text-gray-600">{error}</p>
            <button
              onClick={() => router.replace('/learn')}
              className="mt-4 px-6 py-2 bg-orange-600 text-white rounded-lg text-sm hover:bg-red-700"
            >
              Go to my challenges
            </button>
          </>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Verify join flow**

1. Teacher publishes a challenge and copies the join code.
2. Log in as a consumer.
3. Navigate to `/join/THE-JOIN-CODE`.
4. Page shows "Joining…" then "Enrolled!" then redirects to `/learn`.
5. Challenge appears in student's list.

- [ ] **Commit**

```bash
git add app/join/
git commit -m "feat: join-code enrollment flow"
```

---

## Task 9: OrgSiteConfig head injection

**Files:**
- Modify: `utils/api.js` — add ORG_SITE_CONFIG endpoint
- Create: `components/SiteConfigInjector.js`
- Modify: `app/providers.js` — mount SiteConfigInjector

A new API endpoint is needed in strollopia-api. Add it first.

- [ ] **Add OrgSiteConfig endpoint to strollopia-api**

*Working directory: `strollopia-api/`*

Create `app/core/views_site_config.py`:

```python
from rest_framework import generics, permissions
from rest_framework.response import Response

from core.models import OrgSiteConfig


class OrgSiteConfigView(generics.RetrieveAPIView):
    permission_classes = [permissions.IsAuthenticated]

    def retrieve(self, request, *args, **kwargs):
        config, _ = OrgSiteConfig.objects.get_or_create(owning_org=request.user.owning_org)
        return Response({
            'meta_description': config.meta_description,
            'og_image': config.og_image,
            'favicon_url': config.favicon_url,
            'google_analytics_id': config.google_analytics_id,
            'google_tag_manager_id': config.google_tag_manager_id,
            'facebook_pixel_id': config.facebook_pixel_id,
            'twitter_handle': config.twitter_handle,
            'custom_head_html': config.custom_head_html,
        })
```

Add to `app/core/urls.py` (find the urlpatterns list and append):

```python
from core.views_site_config import OrgSiteConfigView

# In urlpatterns:
path('site-config/', OrgSiteConfigView.as_view(), name='site-config'),
```

Verify:

```bash
docker compose run --rm app sh -c "python manage.py wait_for_db && python manage.py check"
```

Expected: `System check identified no issues (0 silenced).`

Commit in strollopia-api:

```bash
git add app/core/views_site_config.py app/core/urls.py
git commit -m "feat: expose OrgSiteConfig via GET /api/core/site-config/"
```

- [ ] **Add endpoint to frontend API client**

*Working directory: `strollopia-pwa/`*

In `utils/api.js`, inside `API_ENDPOINTS`:

```javascript
ORG_SITE_CONFIG: `${API_BASE_URL}/api/core/site-config/`,
```

- [ ] **Create components/SiteConfigInjector.js**

```javascript
'use client';

import { useEffect } from 'react';
import { useAuth } from '../lib/auth';
import { API_ENDPOINTS } from '../utils/api';
import { fetchWithTimeout } from '../lib/fetchWithTimeout';

export default function SiteConfigInjector() {
  const { isAuthenticated, authToken } = useAuth();

  useEffect(() => {
    if (!isAuthenticated || !authToken) return;

    fetchWithTimeout(
      API_ENDPOINTS.ORG_SITE_CONFIG,
      { headers: { Authorization: `Token ${authToken}` } },
      5000
    )
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => {
        if (!data?.custom_head_html) return;
        const existing = document.querySelector('[data-site-config-html]');
        if (existing) existing.remove();
        const div = document.createElement('div');
        div.setAttribute('data-site-config-html', 'true');
        div.innerHTML = data.custom_head_html;
        // Move script/link/meta children into <head>
        Array.from(div.childNodes).forEach((node) => {
          document.head.appendChild(node.cloneNode(true));
        });
      })
      .catch(() => {});
  }, [isAuthenticated, authToken]);

  return null;
}
```

- [ ] **Mount SiteConfigInjector in providers.js**

In `app/providers.js`, import and add inside the return JSX (alongside ThemeInjector):

```javascript
import SiteConfigInjector from '../components/SiteConfigInjector';

// Inside JSX:
<SiteConfigInjector />
```

- [ ] **Commit**

```bash
git add utils/api.js components/SiteConfigInjector.js app/providers.js
git commit -m "feat: OrgSiteConfig custom_head_html injection"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Teacher builds geo-located route challenge | Task 6 (builder map, stop placement) |
| Per-stop language activities | Task 6 (ActivityEditor: QUIZ, LISTEN, SPEAK, WRITE, PHOTO, CHECKIN) |
| Students complete challenges on-device | Task 7 (LinearMissionView) |
| Progress tracked per student | Task 7 (submitProgress on each activity) |
| Class-wide progress — teacher dashboard | Task 6 (stub `/teach/page.js`; full matrix is Plan 3) |
| White-label: custom domain, logo, colours | Inherited from data_logger (ThemeInjector, config.js) |
| Analytics + custom head injection | Task 9 (SiteConfigInjector) |
| Join-code enrollment | Task 8 |
| `is_producer`/`is_consumer` flags surfaced | Task 1 (profile serializer) + Task 3 (PluginProvider) |
| `SG` UiType in strollopia-api | Done in Plan 1 |
| Student Explore Map mode (Mode B) | Deferred to Plan 3 |
| Student Dashboard mode (Mode C) | Deferred to Plan 3 |
| Teacher progress matrix | Deferred to Plan 3 (stub exists in Task 6) |
| Self-register enrollment | Deferred to Plan 3 |

**Deferred to Plan 3:**
- Student Mode B (Explore Map) — full Leaflet map with numbered markers
- Student Mode C (Dashboard) — split-panel view
- Teacher progress matrix (`ProgressMatrix.js` component)
- Self-register enrollment flow
- LISTEN activity audio playback in student UI
