# Port API Endpoints to data_logger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up 5 strollopia-api endpoints in data_logger — individual subcategory CRUD, layout read/write, and POI slug resolution — so data_logger reaches parity with map_builder and wysiwyg_editor for these features.

**Architecture:** All HTTP functions follow the existing pattern in `utils/api.js`: add URL constants to `API_ENDPOINTS`, add exported `async` functions using `fetchWithTimeout`. Subcategory changes refactor `handleSave` in the categories admin page to call individual endpoints instead of burying subcategory ops inside the bulk payload. Layouts get a new admin page at `/admin/layout`. The POI slug resolver is a new dynamic route at `/poi/[slug]` that resolves a short slug to a `poi_id` and redirects to the viewer.

**Tech Stack:** Next.js App Router, React hooks, `fetchWithTimeout` wrapper (`lib/fetchWithTimeout.js`), auth via `useAuth()` (IndexedDB-backed token), org domain via `useConfig()`.

---

## Feature 1: Subcategory Individual CRUD

### Task 1: Add subcategory API functions to utils/api.js

**Files:**
- Modify: `data_logger/utils/api.js`

- [ ] **Step 1: Add SUBCATEGORIES constants to API_ENDPOINTS**

In `data_logger/utils/api.js`, inside the `API_ENDPOINTS` object after the `CATEGORIES_BULK` line (~line 37), add:

```js
  SUBCATEGORIES:       `${API_BASE_URL}/api/org/subcategories/`,
  SUBCATEGORY_DETAIL:  (pk) => `${API_BASE_URL}/api/org/subcategories/${pk}/`,
```

- [ ] **Step 2: Add createSubcategoryAPI after bulkUpdateCategoriesAPI**

```js
export const createSubcategoryAPI = async (authToken, name, owningCategoryId) => {
  try {
    const response = await fetchWithTimeout(API_ENDPOINTS.SUBCATEGORIES, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${authToken}`,
      },
      body: JSON.stringify({ name, owning_category: owningCategoryId }),
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.detail || 'Failed to create subcategory');
    }
    return response.json();
  } catch (error) {
    console.error('Create subcategory error:', error);
    throw error;
  }
};
```

- [ ] **Step 3: Add updateSubcategoryAPI**

```js
export const updateSubcategoryAPI = async (authToken, pk, name, owningCategoryId) => {
  try {
    const response = await fetchWithTimeout(API_ENDPOINTS.SUBCATEGORY_DETAIL(pk), {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${authToken}`,
      },
      body: JSON.stringify({ name, owning_category: owningCategoryId }),
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.detail || 'Failed to update subcategory');
    }
    return response.json();
  } catch (error) {
    console.error('Update subcategory error:', error);
    throw error;
  }
};
```

- [ ] **Step 4: Add deleteSubcategoryAPI**

```js
export const deleteSubcategoryAPI = async (authToken, pk) => {
  try {
    const response = await fetchWithTimeout(API_ENDPOINTS.SUBCATEGORY_DETAIL(pk), {
      method: 'DELETE',
      headers: { 'Authorization': `Token ${authToken}` },
    });
    if (!response.ok && response.status !== 204) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.detail || 'Failed to delete subcategory');
    }
  } catch (error) {
    console.error('Delete subcategory error:', error);
    throw error;
  }
};
```

- [ ] **Step 5: Commit**

```bash
git add data_logger/utils/api.js
git commit -m "feat(data_logger): add individual subcategory CRUD API functions"
```

---

### Task 2: Refactor categories page to use individual subcategory endpoints

**Files:**
- Modify: `data_logger/app/admin/categories/page.js`

**Context:** The current `handleSave` builds one bulk payload and sends everything — category creates/renames/deletes and subcategory creates/renames/deletes — to `bulkUpdateCategoriesAPI`. After this task, subcategory operations use individual endpoints. Category-level operations (create/rename/delete a whole category) still use bulk, because new categories and their first subcategories must be created atomically.

- [ ] **Step 1: Update the import line (line 6)**

Change:
```js
import { fetchCategoriesAPI, bulkUpdateCategoriesAPI } from '../../../utils/api';
```
To:
```js
import {
  fetchCategoriesAPI,
  bulkUpdateCategoriesAPI,
  createSubcategoryAPI,
  updateSubcategoryAPI,
  deleteSubcategoryAPI,
} from '../../../utils/api';
```

- [ ] **Step 2: Replace the handleSave function (currently lines 210–232)**

Replace the entire `handleSave` function with:

```js
  const handleSave = async () => {
    setSaveError(null);
    setSaving(true);

    try {
      // Build lookup of original subcategory data for rename detection
      const originalSubById = {};
      for (const cat of categories) {
        for (const sub of cat.sub_categories || []) {
          originalSubById[sub.id] = { name: sub.name, owningCategoryId: cat.id };
        }
      }

      // 1. Delete subcategories individually (these are always existing subs — new
      //    unsaved subs are removed from editCategories immediately without entering this set)
      for (const subId of deletedSubCategoryIds) {
        await deleteSubcategoryAPI(authToken, subId);
      }

      // 2. Bulk-handle category-level changes: new categories (with any initial subs),
      //    renamed categories, and deleted categories
      const originalCatMap = {};
      for (const cat of categories) originalCatMap[cat.id] = cat;

      const categoryPayload = [];
      for (const id of deletedCategoryIds) {
        categoryPayload.push({ id, name: '__delete__' });
      }
      for (const editCat of editCategories) {
        if (editCat.id && deletedCategoryIds.has(editCat.id)) continue;
        const origCat = editCat.id ? originalCatMap[editCat.id] : null;

        if (!editCat.id && editCat.name.trim()) {
          // New category — bundle its new subcategories in the same bulk call
          const entry = { name: editCat.name.trim() };
          const newSubs = editCat.sub_categories
            .filter((s) => !s.id && s.name.trim())
            .map((s) => ({ name: s.name.trim() }));
          if (newSubs.length > 0) entry.sub_categories = newSubs;
          categoryPayload.push(entry);
        } else if (editCat.id && origCat && editCat.name.trim() !== origCat.name) {
          categoryPayload.push({ id: editCat.id, name: editCat.name.trim() });
        }
      }
      if (categoryPayload.length > 0) {
        await bulkUpdateCategoriesAPI(authToken, categoryPayload);
      }

      // 3. Individual subcategory renames and new subs under existing categories
      for (const editCat of editCategories) {
        if (!editCat.id || deletedCategoryIds.has(editCat.id)) continue;
        for (const sub of editCat.sub_categories) {
          if (sub.id && deletedSubCategoryIds.has(sub.id)) continue;
          if (!sub.id && sub.name.trim()) {
            await createSubcategoryAPI(authToken, sub.name.trim(), editCat.id);
          } else if (sub.id) {
            const orig = originalSubById[sub.id];
            if (orig && sub.name.trim() !== orig.name) {
              await updateSubcategoryAPI(authToken, sub.id, sub.name.trim(), editCat.id);
            }
          }
        }
      }

      await loadCategories();
      setEditMode(false);
      setEditCategories([]);
      setDeletedCategoryIds(new Set());
      setDeletedSubCategoryIds(new Set());
    } catch (err) {
      setSaveError(err.message || 'Failed to save changes');
    } finally {
      setSaving(false);
    }
  };
```

- [ ] **Step 3: Manual verification**

Start the dev server (`npm run dev` in `data_logger/`). Navigate to `/admin/categories` and enter Edit mode. Test each case:

1. **Rename a subcategory** → Save → Confirm new name persists on reload (PUT to `/api/org/subcategories/<pk>/` called)
2. **Delete an existing subcategory** → Save → Confirm it is gone (DELETE to `/api/org/subcategories/<pk>/` called)
3. **Add a new subcategory to an existing category** → Save → Confirm it appears (POST to `/api/org/subcategories/` called)
4. **Add a brand new category with a subcategory** → Save → Confirm both appear (bulk POST called)
5. **Rename a category** → Save → Confirm new name persists (bulk PUT called)

Check the browser Network tab to confirm the correct endpoints are being called for each case.

- [ ] **Step 4: Commit**

```bash
git add data_logger/app/admin/categories/page.js
git commit -m "feat(data_logger): use individual subcategory endpoints in categories admin page"
```

---

## Feature 2: Layout Read/Write

### Task 3: Add layout API functions to utils/api.js

**Files:**
- Modify: `data_logger/utils/api.js`

- [ ] **Step 1: Add LAYOUTS constants to API_ENDPOINTS**

After `SUBCATEGORY_DETAIL` in the `API_ENDPOINTS` object, add:

```js
  LAYOUTS:       `${API_BASE_URL}/api/org/layouts/`,
  LAYOUT_DETAIL: (pk) => `${API_BASE_URL}/api/org/layouts/${pk}/`,
```

- [ ] **Step 2: Add fetchDefaultLayoutAPI**

```js
export const fetchDefaultLayoutAPI = async (authToken, orgDomainName) => {
  try {
    const url = `${API_ENDPOINTS.LAYOUTS}?default=true&org_domain_name=${encodeURIComponent(orgDomainName)}`;
    const response = await fetchWithTimeout(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${authToken}`,
      },
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.detail || 'Failed to fetch layout');
    }
    const data = await response.json();
    // DRF returns a list for list endpoints
    return Array.isArray(data) ? data[0] : (data?.results?.[0] ?? data);
  } catch (error) {
    console.error('Fetch layout error:', error);
    throw error;
  }
};
```

- [ ] **Step 3: Add updateLayoutDesignAPI**

```js
export const updateLayoutDesignAPI = async (authToken, pk, frontendDesignCode) => {
  try {
    const response = await fetchWithTimeout(API_ENDPOINTS.LAYOUT_DETAIL(pk), {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${authToken}`,
      },
      body: JSON.stringify({ frontend_design_code: frontendDesignCode }),
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.detail || 'Failed to update layout');
    }
    return response.json();
  } catch (error) {
    console.error('Update layout error:', error);
    throw error;
  }
};
```

- [ ] **Step 4: Commit**

```bash
git add data_logger/utils/api.js
git commit -m "feat(data_logger): add layout read/write API functions"
```

---

### Task 4: Create admin layout page and add nav tile

**Files:**
- Create: `data_logger/app/admin/layout/page.js`
- Modify: `data_logger/app/admin/page.js`

**Context:** `admin/page.js` renders a `tiles` array of `{ title, href, icon, description }` objects. Each tile becomes a nav card. Add a new tile to that array, then create the layout page following the exact same structure as `admin/theme/page.js` (same auth guards, same loading/error/feedback pattern, same Tailwind classes).

- [ ] **Step 1: Add nav tile to admin/page.js**

In `data_logger/app/admin/page.js`, add to the `tiles` array (after the `'Theme'` tile):

```js
  {
    title: 'Card Layout',
    href: '/admin/layout',
    icon: '🃏',
    description: 'Edit the POI card HTML template',
  },
```

- [ ] **Step 2: Create data_logger/app/admin/layout/page.js**

```js
'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { useAuth } from '../../../lib/auth';
import { useConfig } from '../../../lib/config';
import { fetchDefaultLayoutAPI, updateLayoutDesignAPI } from '../../../utils/api';

export default function LayoutPage() {
  const { authToken, canEditOrgData } = useAuth();
  const { orgDomainName } = useConfig();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);
  const [feedback, setFeedback] = useState(null);
  const [layoutPk, setLayoutPk] = useState(null);
  const [layoutName, setLayoutName] = useState('');
  const [frontendDesignCode, setFrontendDesignCode] = useState('');

  const showFeedback = (message, isError = false) => {
    setFeedback({ message, isError });
    setTimeout(() => setFeedback(null), 3000);
  };

  const loadLayout = async () => {
    if (!authToken || !orgDomainName) return;
    setLoading(true);
    setError(null);
    try {
      const layout = await fetchDefaultLayoutAPI(authToken, orgDomainName);
      if (!layout) throw new Error('No default layout found for this org');
      setLayoutPk(layout.pk ?? layout.id);
      setLayoutName(layout.name || '');
      setFrontendDesignCode(layout.frontend_design_code || '');
    } catch (err) {
      setError(err.message || 'Failed to load layout');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!authToken || !canEditOrgData) {
      setLoading(false);
      return;
    }
    loadLayout();
  }, [authToken, canEditOrgData, orgDomainName]);

  const handleSave = async (e) => {
    e.preventDefault();
    if (!layoutPk) {
      showFeedback('Layout not loaded — please refresh', true);
      return;
    }
    setSaving(true);
    try {
      await updateLayoutDesignAPI(authToken, layoutPk, frontendDesignCode);
      showFeedback('Layout saved successfully');
    } catch (err) {
      showFeedback(err.message || 'Failed to save layout', true);
    } finally {
      setSaving(false);
    }
  };

  if (!authToken) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <p className="text-white text-lg">Loading...</p>
      </div>
    );
  }

  if (!canEditOrgData) {
    return (
      <div className="min-h-screen theme-gradient-bg p-6 flex items-center justify-center">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-2xl p-8 text-center space-y-6">
          <div className="text-5xl">🔒</div>
          <h1 className="text-2xl font-bold text-gray-800">Access Denied</h1>
          <p className="text-gray-600">You do not have permission to manage layouts.</p>
          <Link href="/admin" className="inline-block px-6 py-3 text-white font-semibold rounded-xl transition" style={{ backgroundColor: 'var(--theme-primary)' }}>
            Back
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen theme-gradient-bg p-6 flex items-center justify-center">
      <div className="w-full max-w-3xl space-y-6">
        <h1 className="text-3xl font-bold text-white text-center">Card Layout Design</h1>

        {feedback && (
          <div className={`text-center py-2 px-4 rounded-xl font-medium text-sm ${feedback.isError ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'}`}>
            {feedback.message}
          </div>
        )}

        <div className="bg-white rounded-2xl shadow-2xl p-6 space-y-4">
          {loading && (
            <div className="flex justify-center py-12">
              <div className="animate-spin rounded-full h-10 w-10 border-4 border-t-transparent" style={{ borderColor: 'var(--theme-primary)', borderTopColor: 'transparent' }} />
            </div>
          )}

          {error && (
            <div className="text-center py-8 space-y-4">
              <p className="text-red-600 font-medium">{error}</p>
              <button onClick={loadLayout} className="px-6 py-2 text-white font-semibold rounded-xl transition" style={{ backgroundColor: 'var(--theme-primary)' }}>
                Retry
              </button>
            </div>
          )}

          {!loading && !error && (
            <form onSubmit={handleSave} className="space-y-4">
              <p className="text-sm text-gray-500">
                Layout: <span className="font-medium text-gray-700">{layoutName}</span>
              </p>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Frontend Design Code
                  <span className="ml-2 font-normal text-gray-400">(HTML with {'{{field_key}}'} tokens)</span>
                </label>
                <textarea
                  value={frontendDesignCode}
                  onChange={(e) => setFrontendDesignCode(e.target.value)}
                  rows={20}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="<div>{{my_field}}</div>"
                />
              </div>
              <button
                type="submit"
                disabled={saving}
                className="w-full py-3 text-white font-semibold rounded-xl transition flex items-center justify-center gap-2"
                style={{ backgroundColor: 'var(--theme-primary)' }}
              >
                {saving && <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" />}
                {saving ? 'Saving...' : 'Save Layout'}
              </button>
            </form>
          )}
        </div>

        <div className="text-center">
          <Link href="/admin" className="inline-block px-6 py-3 bg-white/20 hover:bg-white/30 text-white font-semibold rounded-xl transition">
            Back
          </Link>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Manual verification**

Start the dev server. Navigate to `/admin` and confirm the "Card Layout" tile appears. Click it and confirm:
1. The page loads the org's default layout name and `frontend_design_code` in the textarea.
2. Editing the textarea and clicking Save calls PATCH and shows the green toast.
3. Refreshing the page re-loads the saved content from the API.

- [ ] **Step 4: Commit**

```bash
git add data_logger/app/admin/layout/page.js data_logger/app/admin/page.js
git commit -m "feat(data_logger): add card layout admin page"
```

---

## Feature 3: POI Slug Redirect

**Background:** Physical plaques at the 17 Kentville murals have QR codes pointing to URLs on the old Locomotive CMS + Wagtail stack, e.g. `https://kentvillemurals.ca/annapolis-valley`. When the org is migrated to strollopia, `kentvillemurals.ca` will be pointed at data_logger as a custom Vercel domain. The slugs encoded in those QR codes must resolve to the correct POI in the new viewer. Since these QR codes are on physical plaques that cannot be changed, this redirect is permanent, load-bearing infrastructure.

**Known slugs from QR codes (all 17 murals):**
`daughter-of-our-community`, `new-wave`, `artistic-visionary`, `annapolis-valley`, `bryan-gibson`, `community-crossing`, `dar`, `duck-marsh`, `family-resurgence`, `little-thunder-stone-canoe`, `lost-dominion`, `northern-pitcher-plant`, `memory-lane`, `microecosystems`, `sassy-pants`, `no-place-like-kentville`, `miyoshi-kondo`

**Route:** The QR codes encode `https://kentvillemurals.ca/<slug>` — the slug is at the **root of the domain** with no path prefix. The route must be `app/[slug]/page.js` (root-level dynamic segment). Next.js App Router gives priority to all specific static routes (`/viewer`, `/admin`, `/builder`, etc.) over dynamic `[slug]`, so existing pages are not affected.

**org_domain_name:** Since data_logger is deployed at `kentvillemurals.ca`, `useConfig()` will already return `kentvillemurals.ca` as the `orgDomainName`. No hardcoding needed.

---

### Task 5: Add POI slug resolver API function to utils/api.js

**Files:**
- Modify: `data_logger/utils/api.js`

**Context:** The strollopia-api endpoint `/api/org/poi-redirects/<slug>/?org_domain_name=<domain>` returns `{ poi_id: <int> }` on success, `{ error: 'Poi not found' }` with 404 on failure. No auth token required (public endpoint).

- [ ] **Step 1: Add POI_REDIRECTS constant to API_ENDPOINTS**

```js
  POI_REDIRECTS: (slug) => `${API_BASE_URL}/api/org/poi-redirects/${encodeURIComponent(slug)}/`,
```

- [ ] **Step 2: Add resolvePoiSlugAPI**

```js
export const resolvePoiSlugAPI = async (slug, orgDomainName) => {
  try {
    const url = `${API_ENDPOINTS.POI_REDIRECTS(slug)}?org_domain_name=${encodeURIComponent(orgDomainName)}`;
    const response = await fetchWithTimeout(url, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.error || data.detail || 'POI not found');
    }
    return response.json();
  } catch (error) {
    console.error('Resolve POI slug error:', error);
    throw error;
  }
};
```

- [ ] **Step 3: Commit**

```bash
git add data_logger/utils/api.js
git commit -m "feat(data_logger): add POI slug resolver API function"
```

---

### Task 6: Create root-level slug redirect page

**Files:**
- Create: `data_logger/app/[slug]/page.js`

**Context:** A visitor scans a plaque QR code → lands on `https://kentvillemurals.ca/annapolis-valley` → data_logger receives the request → `app/[slug]/page.js` fires → calls the API with the slug and org domain → redirects to `/viewer/?poi=<poi_id>`. The page is public (no login). `orgDomainName` from `useConfig()` may be briefly null on first render; the `useEffect` dependency on it ensures the API call waits until it resolves.

- [ ] **Step 1: Create the directory and page file**

```bash
mkdir -p data_logger/app/\[slug\]
```

Create `data_logger/app/[slug]/page.js`:

```js
'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useConfig } from '../../lib/config';
import { resolvePoiSlugAPI } from '../../utils/api';

export default function SlugRedirectPage() {
  const { slug } = useParams();
  const router = useRouter();
  const { orgDomainName } = useConfig();
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!slug || !orgDomainName) return;

    resolvePoiSlugAPI(slug, orgDomainName)
      .then((data) => {
        const poiId = data.poi_id;
        if (!poiId) throw new Error('Unexpected response from server');
        router.replace(`/viewer/?poi=${poiId}`);
      })
      .catch((err) => {
        setError(err.message || 'This link is invalid or has expired.');
      });
  }, [slug, orgDomainName, router]);

  if (error) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center p-6">
        <div className="bg-white rounded-2xl shadow-2xl p-8 text-center max-w-sm space-y-4">
          <div className="text-5xl">❌</div>
          <h1 className="text-xl font-bold text-gray-800">Mural Not Found</h1>
          <p className="text-gray-600 text-sm">
            This QR code link could not be resolved. The mural may have moved or been removed.
          </p>
          <a
            href="/"
            className="inline-block px-6 py-3 text-white font-semibold rounded-xl transition"
            style={{ backgroundColor: 'var(--theme-primary)' }}
          >
            View All Murals
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
      <div
        className="animate-spin rounded-full h-10 w-10 border-4 border-t-transparent"
        style={{ borderColor: 'var(--theme-primary)', borderTopColor: 'transparent' }}
      />
    </div>
  );
}
```

- [ ] **Step 2: Manual verification**

Using the dev server pointed at the kentvillemurals.ca org (or a local org with a POI that has a `slug` field set):

1. Navigate to `/<slug>` (e.g. `/annapolis-valley`) — confirm the spinner shows then the browser redirects to `/viewer/?poi=<expected_poi_id>`.
2. Navigate to `/nonexistent-slug` — confirm the "Mural Not Found" error card renders.
3. Navigate to `/viewer` and `/admin` — confirm these still load their correct pages (not caught by `[slug]`).

- [ ] **Step 3: Commit**

```bash
git add data_logger/app/\[slug\]/
git commit -m "feat(data_logger): add root-level QR code slug redirect page for kentvillemurals.ca"
```

---

### Task 7: Handle ?poi= in the viewer to auto-open the POI

**Files:**
- Modify: `data_logger/app/viewer/page.js`

**Context:** After Task 6, the redirect lands on `/viewer/?poi=<poi_id>`. The viewer page currently reads `?map=` but not `?poi=`. Without this task, the visitor lands on a generic map with no POI opened — a broken experience for someone who scanned a plaque. This task reads the `?poi=` param on load and passes it through to the map so the correct mural detail opens automatically.

- [ ] **Step 1: Add useSearchParams import**

In `data_logger/app/viewer/page.js`, add `useSearchParams` to the existing next/navigation import:

```js
import { useRouter, useSearchParams } from 'next/navigation';
```

- [ ] **Step 2: Read the ?poi= param and store it in state**

Near the top of the component (after existing `useRouter` / `useParams` calls), add:

```js
const searchParams = useSearchParams();
const initialPoiId = searchParams.get('poi') ? Number(searchParams.get('poi')) : null;
```

- [ ] **Step 3: Pass initialPoiId to the map component**

Find where the viewer renders its map component (the component that accepts POI selection / opens POI detail panels). Pass `initialPoiId` as a prop — the exact prop name depends on how the map component currently accepts a "selected POI" — read that component to confirm the prop name before editing.

- [ ] **Step 4: In the map component, open the POI detail on mount if initialPoiId is set**

In the map/viewer component that receives `initialPoiId`, add a `useEffect` that fires once on mount:

```js
useEffect(() => {
  if (!initialPoiId) return;
  // trigger whatever the existing "open POI detail" action is
  openPoiDetail(initialPoiId);
}, [initialPoiId]);
```

Replace `openPoiDetail` with the actual function or state setter used in that component.

- [ ] **Step 5: Manual verification**

1. Navigate to `/viewer/?poi=<valid_poi_id>` — confirm the viewer loads and the matching POI detail panel opens automatically.
2. Navigate to `/viewer/` without `?poi=` — confirm the viewer loads normally with no POI pre-selected.
3. Full flow: navigate to `/<slug>` → confirm redirect → confirm POI detail opens in viewer.

- [ ] **Step 6: Commit**

```bash
git add data_logger/app/viewer/page.js
git commit -m "feat(data_logger): auto-open POI detail when viewer receives ?poi= param"
```
