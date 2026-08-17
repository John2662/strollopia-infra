# Org-Policy Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch `/api/org/org-policy/` once on app load and use it to (1) show the canonical `display_name` in the splash/viewer, (2) seed the Leaflet map center from `default_location` when no POIs exist, and (3) gate the Appender tile with `anon_policy.allows_poi_append`.

**Architecture:** A new `OrgPolicyProvider` in `lib/orgPolicy.js` fetches the public endpoint on mount (same pattern as `ConfigProvider`). It is added to `app/providers.js` alongside the existing providers. Consumer pages import `useOrgPolicy()` to read the three fields they need.

**Tech Stack:** Next.js 14 App Router, React context, vitest

---

## Background

The org-policy endpoint is public (no auth header needed):

```
GET /api/org/org-policy/?org_domain_name=<domain>
```

Response shape relevant to this plan:

```json
{
  "display_name": "Kentville Murals",
  "tag_line": "Explore art in the valley",
  "default_location": [-64.495, 45.077],
  "anon_policy": {
    "allows_anon": true,
    "allows_poi_append": true,
    "allows_map_creation": false,
    "anon_post_targets": [12, 14]
  }
}
```

`default_location` is `[lng, lat]` (GeoJSON order). Leaflet needs `[lat, lng]`.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `utils/api.js` | Modify | Add `ORG_POLICY` endpoint constant + `fetchOrgPolicyAPI()` |
| `lib/orgPolicy.js` | Create | `OrgPolicyProvider` context + `useOrgPolicy()` hook |
| `app/providers.js` | Modify | Add `OrgPolicyProvider` to provider tree |
| `app/page.js` | Modify | Use `displayName` in hero title fallback chain |
| `app/viewer/page.js` | Modify | Use `displayName` as fallback map name |
| `app/viewer/maps/page.js` | Modify | Use `defaultLocation` as Leaflet center when no POIs + no `centerGeom` |
| `app/builder/page.js` | Modify | Gate Appender tile with `allowsPOIAppend` |
| `tests/utils/api.test.js` | Modify | Add test for `fetchOrgPolicyAPI` |
| `tests/lib/orgPolicy.test.js` | Create | Tests for `OrgPolicyProvider` and `useOrgPolicy` |

---

## Task 1: Add `fetchOrgPolicyAPI` to `utils/api.js`

**Files:**
- Modify: `utils/api.js` (around line 70, in `API_ENDPOINTS`, and after line 362)
- Modify: `tests/utils/api.test.js`

### Step 1: Write the failing test

Open `tests/utils/api.test.js`. The imports block already imports from `utils/api`. Add `fetchOrgPolicyAPI` to the named imports, and add this test suite at the bottom of the file:

```js
describe('fetchOrgPolicyAPI', () => {
  it('fetches org policy by org_domain_name with no auth header', async () => {
    const policy = {
      display_name: 'Test Org',
      tag_line: 'tagline',
      default_location: [-64.5, 45.1],
      anon_policy: { allows_poi_append: true, anon_post_targets: [] },
    };
    fetchWithTimeout.mockResolvedValue(mockResponse(policy));

    const result = await fetchOrgPolicyAPI('testorg');

    const [url, opts] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/org/org-policy/');
    expect(url).toContain('org_domain_name=testorg');
    expect(opts.headers?.Authorization).toBeUndefined();
    expect(result).toEqual(policy);
  });

  it('throws on non-ok response', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse({}, { ok: false, status: 500 }));
    await expect(fetchOrgPolicyAPI('testorg')).rejects.toThrow();
  });
});
```

### Step 2: Run the test to verify it fails

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/utils/api.test.js 2>&1 | tail -20
```

Expected: FAIL — `fetchOrgPolicyAPI is not a function` or import error.

### Step 3: Add `ORG_POLICY` to `API_ENDPOINTS` in `utils/api.js`

In `API_ENDPOINTS` (lines 30–70), after the `ROUTE_EXPORT` line and before the closing `};`, add:

```js
  ORG_POLICY: `${API_BASE_URL}/api/org/org-policy/`,
```

### Step 4: Add `fetchOrgPolicyAPI` function to `utils/api.js`

After the `fetchConfigAPI` function (after line 362), add:

```js
// Fetch org-level policy (public endpoint — no auth required)
export const fetchOrgPolicyAPI = async (orgDomainName) => {
  try {
    const response = await fetchWithTimeout(
      `${API_ENDPOINTS.ORG_POLICY}?org_domain_name=${encodeURIComponent(orgDomainName)}`,
      { method: 'GET', headers: { 'Content-Type': 'application/json' } }
    );
    if (!response.ok) throw new Error('Failed to fetch org policy');
    return response.json();
  } catch (error) {
    console.error('Org policy fetch error:', error);
    throw error;
  }
};
```

### Step 5: Run the test again to verify it passes

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/utils/api.test.js 2>&1 | tail -20
```

Expected: all tests in that file pass.

### Step 6: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add utils/api.js tests/utils/api.test.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: add fetchOrgPolicyAPI to api.js"
```

---

## Task 2: Create `lib/orgPolicy.js` context provider

**Files:**
- Create: `lib/orgPolicy.js`
- Create: `tests/lib/orgPolicy.test.js`

### Step 1: Write the failing tests

Create `tests/lib/orgPolicy.test.js`:

```js
import { describe, it, expect, vi, beforeEach, beforeAll } from 'vitest';
import React from 'react';
import { createRoot } from 'react-dom/client';
import { act } from 'react-dom/test-utils';

beforeAll(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
});

vi.mock('../../utils/api', () => ({
  fetchOrgPolicyAPI: vi.fn(),
}));

import { fetchOrgPolicyAPI } from '../../utils/api';
import { OrgPolicyProvider, useOrgPolicy } from '../../lib/orgPolicy';

const MOCK_POLICY = {
  display_name: 'Test Org',
  tag_line: 'A tagline',
  default_location: [-64.5, 45.1],
  anon_policy: {
    allows_anon: true,
    allows_poi_append: false,
    allows_map_creation: false,
    anon_post_targets: [3, 7],
  },
};

function renderWithPolicy(orgDomainName, TestComponent) {
  const container = document.createElement('div');
  document.body.appendChild(container);
  let root;
  act(() => {
    root = createRoot(container);
    root.render(
      React.createElement(OrgPolicyProvider, { orgDomainName },
        React.createElement(TestComponent)
      )
    );
  });
  return {
    container,
    cleanup() {
      act(() => root.unmount());
      container.remove();
    },
  };
}

describe('OrgPolicyProvider', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('fetches org policy on mount when orgDomainName is provided', async () => {
    fetchOrgPolicyAPI.mockResolvedValue(MOCK_POLICY);
    let captured = null;
    function Capture() {
      captured = useOrgPolicy();
      return null;
    }
    const { cleanup } = renderWithPolicy('testorg', Capture);
    await act(async () => {});
    expect(fetchOrgPolicyAPI).toHaveBeenCalledWith('testorg');
    cleanup();
  });

  it('exposes displayName, tagLine, defaultLocation from fetched policy', async () => {
    fetchOrgPolicyAPI.mockResolvedValue(MOCK_POLICY);
    let captured = null;
    function Capture() {
      captured = useOrgPolicy();
      return null;
    }
    const { cleanup } = renderWithPolicy('testorg', Capture);
    await act(async () => {});
    expect(captured.displayName).toBe('Test Org');
    expect(captured.tagLine).toBe('A tagline');
    expect(captured.defaultLocation).toEqual([-64.5, 45.1]);
    cleanup();
  });

  it('exposes allowsPOIAppend and anonPostTargets from anon_policy', async () => {
    fetchOrgPolicyAPI.mockResolvedValue(MOCK_POLICY);
    let captured = null;
    function Capture() {
      captured = useOrgPolicy();
      return null;
    }
    const { cleanup } = renderWithPolicy('testorg', Capture);
    await act(async () => {});
    expect(captured.allowsPOIAppend).toBe(false);
    expect(captured.anonPostTargets).toEqual([3, 7]);
    cleanup();
  });

  it('defaults allowsPOIAppend to true before fetch completes', () => {
    fetchOrgPolicyAPI.mockReturnValue(new Promise(() => {})); // never resolves
    let captured = null;
    function Capture() {
      captured = useOrgPolicy();
      return null;
    }
    const { cleanup } = renderWithPolicy('testorg', Capture);
    expect(captured.allowsPOIAppend).toBe(true);
    cleanup();
  });

  it('does not fetch when orgDomainName is empty', () => {
    let captured = null;
    function Capture() {
      captured = useOrgPolicy();
      return null;
    }
    const { cleanup } = renderWithPolicy('', Capture);
    expect(fetchOrgPolicyAPI).not.toHaveBeenCalled();
    cleanup();
  });
});
```

### Step 2: Run test to verify it fails

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/lib/orgPolicy.test.js 2>&1 | tail -20
```

Expected: FAIL — `Cannot find module '../../lib/orgPolicy'`.

### Step 3: Create `lib/orgPolicy.js`

```js
'use client';

import { createContext, useContext, useState, useEffect } from 'react';
import { fetchOrgPolicyAPI } from '../utils/api';

const OrgPolicyContext = createContext({
  displayName: '',
  tagLine: '',
  defaultLocation: null,
  allowsPOIAppend: true,
  anonPostTargets: [],
});

export function OrgPolicyProvider({ children, orgDomainName }) {
  const [displayName, setDisplayName] = useState('');
  const [tagLine, setTagLine] = useState('');
  const [defaultLocation, setDefaultLocation] = useState(null);
  const [allowsPOIAppend, setAllowsPOIAppend] = useState(true);
  const [anonPostTargets, setAnonPostTargets] = useState([]);

  useEffect(() => {
    if (!orgDomainName) return;

    fetchOrgPolicyAPI(orgDomainName)
      .then((data) => {
        if (data.display_name) setDisplayName(data.display_name);
        if (data.tag_line) setTagLine(data.tag_line);
        if (data.default_location) setDefaultLocation(data.default_location);
        const anon = data.anon_policy ?? {};
        setAllowsPOIAppend(anon.allows_poi_append !== false);
        setAnonPostTargets(anon.anon_post_targets ?? []);
      })
      .catch(() => {
        // Fail silently — defaults are safe
      });
  }, [orgDomainName]);

  return (
    <OrgPolicyContext.Provider value={{ displayName, tagLine, defaultLocation, allowsPOIAppend, anonPostTargets }}>
      {children}
    </OrgPolicyContext.Provider>
  );
}

export function useOrgPolicy() {
  return useContext(OrgPolicyContext);
}
```

### Step 4: Run the tests to verify they pass

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/lib/orgPolicy.test.js 2>&1 | tail -20
```

Expected: all 5 tests pass.

### Step 5: Run the full suite to confirm no regressions

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

Expected: all tests pass (now 16 files).

### Step 6: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add lib/orgPolicy.js tests/lib/orgPolicy.test.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: add OrgPolicyProvider context"
```

---

## Task 3: Wire `OrgPolicyProvider` into `app/providers.js`

**Files:**
- Modify: `app/providers.js`

### Step 1: Add the import

At the top of `app/providers.js`, add the import after the existing lib imports:

```js
import { OrgPolicyProvider } from '../lib/orgPolicy';
```

### Step 2: Add the provider to the tree

`OrgPolicyProvider` needs `orgDomainName`. It should sit inside `ConfigProvider` (same level as `TranslationProvider`) so it benefits from the same org resolution, but it's independent of config data.

Change the return JSX from:

```jsx
  return (
    <EmbedProvider isEmbed={isEmbed}>
      <AuthProvider>
        <ConfigProvider orgDomainName={orgDomainName}>
          <ThemeInjector />
          <TranslationProvider orgDomainName={orgDomainName}>
            {children}
            {!isEmbed && (
              <DevPanel
                currentOrg={orgDomainName}
                onOrgChange={handleOrgChange}
              />
            )}
          </TranslationProvider>
        </ConfigProvider>
      </AuthProvider>
    </EmbedProvider>
  );
```

to:

```jsx
  return (
    <EmbedProvider isEmbed={isEmbed}>
      <AuthProvider>
        <ConfigProvider orgDomainName={orgDomainName}>
          <OrgPolicyProvider orgDomainName={orgDomainName}>
            <ThemeInjector />
            <TranslationProvider orgDomainName={orgDomainName}>
              {children}
              {!isEmbed && (
                <DevPanel
                  currentOrg={orgDomainName}
                  onOrgChange={handleOrgChange}
                />
              )}
            </TranslationProvider>
          </OrgPolicyProvider>
        </ConfigProvider>
      </AuthProvider>
    </EmbedProvider>
  );
```

### Step 3: Run the full suite to confirm no regressions

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

Expected: all tests still pass.

### Step 4: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/providers.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: wire OrgPolicyProvider into app providers"
```

---

## Task 4: Use `displayName` in splash and viewer

**Files:**
- Modify: `app/page.js` (around line 95 and line 103)
- Modify: `app/viewer/page.js` (around line 29 and line 81)

### Step 1: Update `app/page.js`

At the top of the file, add the import after the existing `useConfig` import:

```js
import { useOrgPolicy } from '../lib/orgPolicy';
```

Inside the `Home` component, add after the existing `useConfig()` destructure call (currently around line 11):

```js
  const { displayName } = useOrgPolicy();
```

`orgName` is already assigned on line 95:

```js
const orgName = getConfigValue(config, 'identity.org_name', '');
```

Change the `heroTitle` line from:

```js
const heroTitle = ts('heroTitle') || orgName || t(translations, 'viewer', 'title', 'Explore Maps');
```

to:

```js
const heroTitle = ts('heroTitle') || displayName || orgName || t(translations, 'viewer', 'title', 'Explore Maps');
```

### Step 2: Update `app/viewer/page.js`

Add the import after the existing `useConfig` import (around line 8):

```js
import { useOrgPolicy } from '../../lib/orgPolicy';
```

Inside `ViewerPageContent`, add after the existing `useConfig()` line:

```js
  const { displayName } = useOrgPolicy();
```

The existing `orgName` is used in the fallback maps list when the list API fails (around line 81):

```js
const fallbackMaps = [{ pk: defaultTargetMapPk, name: orgName || 'Map', is_org_map: true }];
```

Change to:

```js
const fallbackMaps = [{ pk: defaultTargetMapPk, name: displayName || orgName || 'Map', is_org_map: true }];
```

### Step 3: Run the full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

Expected: all tests pass.

### Step 4: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/page.js app/viewer/page.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: use org-policy display_name in splash and viewer"
```

---

## Task 5: Use `defaultLocation` as map center fallback in `app/viewer/maps/page.js`

**Files:**
- Modify: `app/viewer/maps/page.js` (the `initMap` function, around lines 288–340)

### Step 1: Add import

At the top of `app/viewer/maps/page.js`, after the existing `useConfig` import:

```js
import { useOrgPolicy } from '../../../lib/orgPolicy';
```

### Step 2: Destructure `defaultLocation` from the hook

Inside `CombinedMapView` (after the existing `useConfig()` line, around line 22):

```js
  const { defaultLocation } = useOrgPolicy();
```

### Step 3: Update the `initMap` function center calculation

The current center logic (lines 310–323) is:

```js
      let center = [0, 0];
      let zoom = 13;

      if (allPois.length > 0) {
        const lats = allPois.map(p => p.latitude);
        const lngs = allPois.map(p => p.longitude);
        center = [
          (Math.min(...lats) + Math.max(...lats)) / 2,
          (Math.min(...lngs) + Math.max(...lngs)) / 2,
        ];
      } else if (centerGeom) {
        center = [centerGeom.coordinates[1], centerGeom.coordinates[0]];
      }
```

Change to:

```js
      let center = [0, 0];
      let zoom = 13;

      if (allPois.length > 0) {
        const lats = allPois.map(p => p.latitude);
        const lngs = allPois.map(p => p.longitude);
        center = [
          (Math.min(...lats) + Math.max(...lats)) / 2,
          (Math.min(...lngs) + Math.max(...lngs)) / 2,
        ];
      } else if (centerGeom) {
        center = [centerGeom.coordinates[1], centerGeom.coordinates[0]];
      } else if (defaultLocation) {
        // default_location is [lng, lat] (GeoJSON); Leaflet needs [lat, lng]
        center = [defaultLocation[1], defaultLocation[0]];
      }
```

### Step 4: Run the full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

Expected: all tests pass.

### Step 5: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/viewer/maps/page.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: use org-policy default_location as map center fallback"
```

---

## Task 6: Gate Appender tile with `allowsPOIAppend` in `app/builder/page.js`

**Files:**
- Modify: `app/builder/page.js`

### Step 1: Add import

At the top of `app/builder/page.js`, after the existing imports:

```js
import { useOrgPolicy } from '../../lib/orgPolicy';
```

### Step 2: Destructure `allowsPOIAppend`

Inside `BuilderHubPage`, after the existing `useConfig()` line:

```js
  const { allowsPOIAppend } = useOrgPolicy();
```

### Step 3: Gate the Appender tile

The Appender tile is currently always rendered (no condition). Change from:

```jsx
          {/* Appender */}
          <Link href="/builder/append" className="block">
            <div className="bg-white rounded-2xl shadow-2xl p-6 border-2 border-gray-100 hover:border-gray-300 transition-all active:scale-[0.98]">
              <div className="flex items-center gap-4">
                <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-blue-500 to-indigo-600 flex items-center justify-center flex-shrink-0">
                  <svg className="w-7 h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                </div>
                <div>
                  <h2 className="text-lg font-bold text-gray-800">Appender</h2>
                  <p className="text-sm text-gray-500">Add points to an existing map</p>
                </div>
              </div>
            </div>
          </Link>
```

to:

```jsx
          {/* Appender — only shown when org allows anonymous POI submissions */}
          {allowsPOIAppend && (
            <Link href="/builder/append" className="block">
              <div className="bg-white rounded-2xl shadow-2xl p-6 border-2 border-gray-100 hover:border-gray-300 transition-all active:scale-[0.98]">
                <div className="flex items-center gap-4">
                  <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-blue-500 to-indigo-600 flex items-center justify-center flex-shrink-0">
                    <svg className="w-7 h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                    </svg>
                  </div>
                  <div>
                    <h2 className="text-lg font-bold text-gray-800">Appender</h2>
                    <p className="text-sm text-gray-500">Add points to an existing map</p>
                  </div>
                </div>
              </div>
            </Link>
          )}
```

### Step 4: Run the full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

Expected: all tests pass.

### Step 5: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/builder/page.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: gate builder Appender tile with org-policy allows_poi_append"
```
