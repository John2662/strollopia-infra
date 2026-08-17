# Translation Editor and Translator Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give translators a dedicated `/translate` route with a card-per-string editor, and give admins a redesigned `/admin/translations` with the same card editor plus a language/translator management tab.

**Architecture:** A new `GET trans_editor/` backend endpoint returns each language with embedded page IDs and string pairs (English + translation) for the authenticated user's assigned languages (all languages for admins). The frontend shares a `TranslationStringCard` component across both the translator route and the admin translations tab. Language management uses the active `managed_language/<pk>/` PATCH with `new_translators`/`delete_translators` payloads.

**Tech Stack:** Django REST Framework (backend), Next.js App Router + React (frontend), vitest

---

## Background

### Backend: active endpoints
| URL | Method | Who | Notes |
|-----|--------|-----|-------|
| `trans_editor/` | PATCH | Translators | Saves strings; needs `page_id` (int), `langauge_id` (int, typo in backend), `translation_data` dict |
| `trans_editor/` | GET | **New** | Returns languages + embedded translations for the authenticated user |
| `managed_language/` | GET | Admins | Lists org's managed languages |
| `managed_language/<pk>/` | PATCH | Admins | Add/remove translators via `new_translators`/`delete_translators` |
| `managed_language/` | POST | Admins | Add a new language |

`trans_manage/` is **commented out** in urls.py — do not use it.

### Translator PATCH payload (existing)
```json
{
  "page_id": 8,
  "langauge_id": 5,
  "translation_data": { "title": "Explorez les cartes" }
}
```
Note the typo `langauge_id` — this matches the backend field name exactly.

### New GET response shape
```json
[
  {
    "id": 5,
    "language": "fr",
    "language_name": "French",
    "flag_emoji": "🇫🇷",
    "pages": [
      {
        "page_id": 8,
        "page_name": "viewer",
        "strings": {
          "title": ["Explore Maps", "Explorez les cartes"],
          "subtitle": ["Walking tours", "Visites à pied"]
        }
      }
    ]
  }
]
```

---

## File Map

| File | Repo | Action |
|------|------|--------|
| `app/ui_support/view_trans_man.py` | strollopia-api | Add `GET` to `TranslationEditorView` |
| `utils/api.js` | data_logger | Add `fetchTranslatorLanguagesAPI`, `updateLanguageTranslatorsAPI`, `addManagedLanguageAPI` |
| `components/TranslationStringCard.js` | data_logger | New — card with English + editable translation, auto-save |
| `app/translate/page.js` | data_logger | New — translator-facing route |
| `app/admin/translations/page.js` | data_logger | Redesign with two tabs: editor + manage |

---

## Task 1: Backend — add GET to TranslationEditorView

**Files:**
- Modify: `strollopia-api/app/ui_support/view_trans_man.py`

The `TranslationEditorView` already inherits `OrganizationRequiredMixin` (so `self.org` and `self.request.user` are available). No `org_domain_name` query param needed.

### Step 1: Understand existing structure

Read `strollopia-api/app/ui_support/view_trans_man.py` lines 442–560 to see `TranslationEditorView` class, its imports, and how `OrgManagedLanguage`, `UiTranslation`, and `UiPage` are used in the PATCH method.

### Step 2: Add the GET method

Inside `TranslationEditorView`, add this GET method **before** the existing PATCH method:

```python
def get(self, request):
    """
    Returns the languages the authenticated user is assigned to translate,
    with all string pairs (English + translation) embedded by page.
    Org admins receive all managed languages for the org.
    """
    from .models import OrgManagedLanguage, UiTranslation

    if request.user.has_org_edit_access:
        managed_languages = OrgManagedLanguage.objects.filter(owning_org=self.org)
    else:
        managed_languages = OrgManagedLanguage.objects.filter(
            owning_org=self.org,
            allowed_translators=request.user
        )

    result = []
    for lang in managed_languages:
        pages_data = []
        ui_translations = UiTranslation.objects.filter(org_managed_language=lang)
        for ui_trans in ui_translations:
            ui_page = ui_trans.ui_page
            strings = {}
            for key, english in ui_page.text_string_lookup.items():
                translated = ui_trans.text_string_lookup.get(key, '')
                strings[key] = [english, translated]
            pages_data.append({
                'page_id': ui_page.id,
                'page_name': ui_page.page_name,
                'strings': strings,
            })
        result.append({
            'id': lang.id,
            'language': lang.language_name,
            'language_name': lang.display_name or lang.language_name,
            'flag_emoji': lang.flag_emoji or '',
            'pages': pages_data,
        })

    return Response(status=status.HTTP_200_OK, data=result)
```

### Step 3: Verify the import paths

Check that `OrgManagedLanguage`, `UiTranslation`, and `UiPage` are already imported at the top of `view_trans_man.py`. If not, add the missing imports from `.models`.

### Step 4: Manual test with curl (or note for human verification)

```bash
# From a shell with the dev server running:
curl -H "Authorization: Token <translator_token>" \
  "http://localhost:8000/api/ui_support/trans_editor/?org_domain_name=<org>"
```

Expected: 200 with a JSON array of language objects, each with `pages` containing `page_id`, `page_name`, and `strings`.

Expected for a non-translator: `[]` (empty array, not 403 — they just have no assigned languages).

### Step 5: Commit

```bash
git -C /home/john/strollopia_git_hub/strollopia-api add app/ui_support/view_trans_man.py
git -C /home/john/strollopia_git_hub/strollopia-api commit -m "feat: add GET to TranslationEditorView returning assigned languages with embedded strings"
```

---

## Task 2: Add API functions to `utils/api.js`

**Files:**
- Modify: `/home/john/strollopia_git_hub/data_logger/utils/api.js`
- Modify: `/home/john/strollopia_git_hub/data_logger/tests/utils/api.test.js`

`TRANS_EDITOR` and `MANAGED_LANGUAGES` are already in `API_ENDPOINTS`. No new constants needed.

### Step 1: Write failing tests

Add to `tests/utils/api.test.js`:

```js
describe('fetchTranslatorLanguagesAPI', () => {
  it('GETs trans_editor with auth header and no org_domain_name param', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse([{ id: 5, language: 'fr' }]));
    const result = await fetchTranslatorLanguagesAPI('mytoken');
    const [url, opts] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/ui_support/trans_editor/');
    expect(url).not.toContain('org_domain_name');
    expect(opts.headers.Authorization).toBe('Token mytoken');
    expect(result).toEqual([{ id: 5, language: 'fr' }]);
  });

  it('throws on non-ok response', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse({}, { ok: false, status: 403 }));
    await expect(fetchTranslatorLanguagesAPI('tok')).rejects.toThrow();
  });
});

describe('updateLanguageTranslatorsAPI', () => {
  it('PATCHes managed_language/<pk>/ with new_translators and delete_translators', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse({}));
    await updateLanguageTranslatorsAPI('mytoken', 5, {
      newTranslators: [{ email: 'a@b.com', password: 'pass' }],
      deleteTranslators: [],
    });
    const [url, opts] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/ui_support/managed_language/5/');
    expect(opts.method).toBe('PATCH');
    const body = JSON.parse(opts.body);
    expect(body.new_translators).toEqual([{ email: 'a@b.com', password: 'pass' }]);
    expect(body.delete_translators).toEqual([]);
  });
});

describe('addManagedLanguageAPI', () => {
  it('POSTs to managed_language with language code and ui_type DL', async () => {
    fetchWithTimeout.mockResolvedValue(mockResponse({}));
    await addManagedLanguageAPI('mytoken', 'fr');
    const [url, opts] = fetchWithTimeout.mock.calls[0];
    expect(url).toContain('/api/ui_support/managed_language/');
    expect(opts.method).toBe('POST');
    const body = JSON.parse(opts.body);
    expect(body.language).toBe('fr');
    expect(body.ui_type).toBe('DL');
  });
});
```

Also add `fetchTranslatorLanguagesAPI`, `updateLanguageTranslatorsAPI`, `addManagedLanguageAPI` to the named imports at the top of the test file.

### Step 2: Run to confirm they fail

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/utils/api.test.js 2>&1 | tail -20
```

Expected: FAIL — functions not found.

### Step 3: Add the three functions to `utils/api.js`

After the existing `fetchOrgPolicyAPI` function, add:

```js
// Fetch languages the authenticated user is assigned to translate (no org_domain_name — derived server-side)
export const fetchTranslatorLanguagesAPI = async (authToken) => {
  const response = await fetchWithTimeout(API_ENDPOINTS.TRANS_EDITOR, {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Token ${authToken}`,
    },
  });
  if (!response.ok) throw new Error('Failed to fetch translator languages');
  return response.json();
};

// Add or remove translators on an existing managed language by PK
export const updateLanguageTranslatorsAPI = async (authToken, langPk, { newTranslators = [], deleteTranslators = [] }) => {
  const response = await fetchWithTimeout(`${API_ENDPOINTS.MANAGED_LANGUAGES}${langPk}/`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Token ${authToken}`,
    },
    body: JSON.stringify({
      new_translators: newTranslators,
      delete_translators: deleteTranslators,
    }),
  });
  if (!response.ok) throw new Error('Failed to update language translators');
  return response.json();
};

// Add a new language to the org's managed languages
export const addManagedLanguageAPI = async (authToken, languageCode) => {
  const response = await fetchWithTimeout(API_ENDPOINTS.MANAGED_LANGUAGES, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Token ${authToken}`,
    },
    body: JSON.stringify({ language: languageCode, ui_type: 'DL' }),
  });
  if (!response.ok) throw new Error('Failed to add language');
  return response.json();
};
```

### Step 4: Run to confirm tests pass

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test -- tests/utils/api.test.js 2>&1 | tail -20
```

Expected: all tests pass.

### Step 5: Run full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

### Step 6: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add utils/api.js tests/utils/api.test.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: add fetchTranslatorLanguagesAPI, updateLanguageTranslatorsAPI, addManagedLanguageAPI"
```

---

## Task 3: Create `TranslationStringCard` component

**Files:**
- Create: `/home/john/strollopia_git_hub/data_logger/components/TranslationStringCard.js`

This is a pure UI component — no API calls. The parent manages saving.

### Step 1: Create the component

```js
'use client';

import { useState, useRef } from 'react';

export default function TranslationStringCard({ pageName, stringKey, english, translation, onSave }) {
  const [value, setValue] = useState(translation ?? '');
  const [status, setStatus] = useState(null); // null | 'saving' | 'saved' | 'error'
  const lastSavedRef = useRef(translation ?? '');

  const handleBlur = async () => {
    if (value === lastSavedRef.current) return;
    setStatus('saving');
    try {
      await onSave(stringKey, value);
      lastSavedRef.current = value;
      setStatus('saved');
      setTimeout(() => setStatus(null), 2000);
    } catch {
      setStatus('error');
    }
  };

  const isUntranslated = !translation || translation === english;

  return (
    <div className={`bg-white rounded-xl border p-4 space-y-2 ${isUntranslated ? 'border-amber-200' : 'border-gray-100'}`}>
      <div className="flex items-center justify-between">
        <span className="text-xs text-gray-400 font-mono">
          {pageName} / {stringKey}
        </span>
        {status === 'saving' && (
          <span className="text-xs text-blue-500">Saving…</span>
        )}
        {status === 'saved' && (
          <span className="text-xs text-green-600">✓ Saved</span>
        )}
        {status === 'error' && (
          <span className="text-xs text-red-500">Save failed</span>
        )}
      </div>

      <p className="text-sm text-gray-500 bg-gray-50 rounded-lg px-3 py-2 select-none">
        {english}
      </p>

      <textarea
        value={value}
        onChange={(e) => { setValue(e.target.value); setStatus(null); }}
        onBlur={handleBlur}
        rows={value.split('\n').length + 1}
        placeholder="Enter translation…"
        className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400 resize-none"
      />
    </div>
  );
}
```

### Step 2: Run the full suite to confirm no breakage

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

### Step 3: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add components/TranslationStringCard.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: add TranslationStringCard component with auto-save on blur"
```

---

## Task 4: Create `/translate` page for translators

**Files:**
- Create: `/home/john/strollopia_git_hub/data_logger/app/translate/page.js`

### Step 1: Create the page

```js
'use client';

import { useState, useEffect, useMemo } from 'react';
import Link from 'next/link';
import { useAuth } from '../../lib/auth';
import { useConfig } from '../../lib/config';
import { fetchTranslatorLanguagesAPI, updateTranslationAPI } from '../../utils/api';
import { getOrgDomainFromURL } from '../../lib/utils';
import TranslationStringCard from '../../components/TranslationStringCard';

export default function TranslatePage() {
  const { authToken, isAuthenticated } = useAuth();
  const { orgDomainName } = useConfig();

  const [languages, setLanguages] = useState([]);
  const [selectedLang, setSelectedLang] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [untranslatedOnly, setUntranslatedOnly] = useState(false);
  const [selectedPage, setSelectedPage] = useState('');

  useEffect(() => {
    if (!authToken) return;
    setLoading(true);
    fetchTranslatorLanguagesAPI(authToken)
      .then((data) => {
        setLanguages(Array.isArray(data) ? data : []);
        if (Array.isArray(data) && data.length > 0) setSelectedLang(data[0]);
      })
      .catch((err) => setError(err.message || 'Failed to load languages'))
      .finally(() => setLoading(false));
  }, [authToken]);

  // All pages for the selected language
  const pages = selectedLang?.pages ?? [];

  // Page options for filter dropdown
  const pageOptions = pages.map((p) => ({ id: p.page_id, name: p.page_name }));

  // Flat list of all string entries across pages (filtered)
  const allEntries = useMemo(() => {
    const filtered = selectedPage
      ? pages.filter((p) => String(p.page_id) === selectedPage)
      : pages;

    return filtered.flatMap((page) =>
      Object.entries(page.strings).map(([key, [english, translation]]) => ({
        pageId: page.page_id,
        pageName: page.page_name,
        key,
        english,
        translation,
      }))
    );
  }, [selectedLang, selectedPage]);

  const visibleEntries = useMemo(() => {
    let entries = allEntries;
    if (untranslatedOnly) {
      entries = entries.filter((e) => !e.translation || e.translation === e.english);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      entries = entries.filter(
        (e) => e.english.toLowerCase().includes(q) || e.key.toLowerCase().includes(q)
      );
    }
    return entries;
  }, [allEntries, search, untranslatedOnly]);

  const handleSave = async (pageId, langId, key, value) => {
    const orgDomain = orgDomainName || getOrgDomainFromURL();
    await updateTranslationAPI(authToken, orgDomain, {
      page_id: pageId,
      langauge_id: langId,
      translation_data: { [key]: value },
    });
  };

  if (!isAuthenticated) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <p className="text-white text-lg">Please log in to access translations.</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <div className="animate-spin rounded-full h-10 w-10 border-4 border-t-transparent" style={{ borderColor: 'var(--theme-primary)', borderTopColor: 'transparent' }} />
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <div className="bg-white rounded-2xl shadow-2xl p-8 text-center max-w-sm space-y-4">
          <p className="text-red-600 font-medium">{error}</p>
          <Link href="/" className="inline-block px-6 py-3 text-white font-semibold rounded-xl" style={{ backgroundColor: 'var(--theme-primary)' }}>Home</Link>
        </div>
      </div>
    );
  }

  if (languages.length === 0) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <div className="bg-white rounded-2xl shadow-2xl p-8 text-center max-w-sm space-y-4">
          <p className="text-gray-700 font-medium">You have no languages assigned.</p>
          <p className="text-gray-500 text-sm">Contact your administrator to be assigned as a translator.</p>
          <Link href="/" className="inline-block px-6 py-3 text-white font-semibold rounded-xl" style={{ backgroundColor: 'var(--theme-primary)' }}>Home</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen theme-gradient-bg p-6">
      <div className="max-w-2xl mx-auto space-y-6">
        <h1 className="text-3xl font-bold text-white text-center">Translate</h1>

        <div className="bg-white rounded-2xl shadow-2xl p-6 space-y-4">

          {/* Language tabs */}
          <div className="flex gap-1 overflow-x-auto pb-1">
            {languages.map((lang) => (
              <button
                key={lang.id}
                onClick={() => { setSelectedLang(lang); setSelectedPage(''); setSearch(''); }}
                className={`px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition ${
                  selectedLang?.id === lang.id ? 'text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
                style={selectedLang?.id === lang.id ? { backgroundColor: 'var(--theme-primary)' } : undefined}
              >
                {lang.flag_emoji} {lang.language_name}
              </button>
            ))}
          </div>

          {/* Filters */}
          <div className="flex flex-wrap gap-3 items-center">
            <input
              type="search"
              placeholder="Search strings…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="flex-1 min-w-[160px] px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
            />
            {pageOptions.length > 1 && (
              <select
                value={selectedPage}
                onChange={(e) => setSelectedPage(e.target.value)}
                className="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
              >
                <option value="">All sections</option>
                {pageOptions.map((p) => (
                  <option key={p.id} value={String(p.id)}>{p.name}</option>
                ))}
              </select>
            )}
            <label className="flex items-center gap-2 text-sm text-gray-600 cursor-pointer">
              <input
                type="checkbox"
                checked={untranslatedOnly}
                onChange={(e) => setUntranslatedOnly(e.target.checked)}
                className="rounded"
              />
              Untranslated only
            </label>
          </div>

          {/* Stats */}
          <p className="text-xs text-gray-400">
            {visibleEntries.length} of {allEntries.length} strings
            {untranslatedOnly ? ' — untranslated' : ''}
          </p>

          {/* Cards */}
          <div className="space-y-3">
            {visibleEntries.length === 0 && (
              <p className="text-center text-gray-400 py-8">
                {untranslatedOnly ? 'All strings translated!' : 'No strings match your search.'}
              </p>
            )}
            {visibleEntries.map((entry) => (
              <TranslationStringCard
                key={`${entry.pageId}::${entry.key}`}
                pageName={entry.pageName}
                stringKey={entry.key}
                english={entry.english}
                translation={entry.translation}
                onSave={(key, value) => handleSave(entry.pageId, selectedLang.id, key, value)}
              />
            ))}
          </div>
        </div>

        <div className="text-center">
          <Link href="/" className="inline-block px-6 py-3 bg-white/20 hover:bg-white/30 text-white font-semibold rounded-xl transition">
            Home
          </Link>
        </div>
      </div>
    </div>
  );
}
```

### Step 2: Run full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

### Step 3: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/translate/page.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: add /translate route for translator-role users"
```

---

## Task 5: Redesign `/admin/translations` with two tabs

**Files:**
- Modify: `/home/john/strollopia_git_hub/data_logger/app/admin/translations/page.js`

Replace the existing table-based UI with two tabs: **Edit Translations** (card layout, all languages) and **Manage Languages** (add translators, add new languages).

### Step 1: Read the current file

Read the full current content of `app/admin/translations/page.js` before editing.

### Step 2: Replace with the new implementation

```js
'use client';

import { useState, useEffect, useMemo } from 'react';
import Link from 'next/link';
import { useAuth } from '../../../lib/auth';
import { useConfig } from '../../../lib/config';
import {
  fetchTranslatorLanguagesAPI,
  updateTranslationAPI,
  updateLanguageTranslatorsAPI,
  addManagedLanguageAPI,
  fetchSupportedLanguagesAPI,
} from '../../../utils/api';
import { getOrgDomainFromURL } from '../../../lib/utils';
import TranslationStringCard from '../../../components/TranslationStringCard';

export default function TranslationsPage() {
  const { authToken, canEditOrgData } = useAuth();
  const { orgDomainName } = useConfig();
  const [activeTab, setActiveTab] = useState('edit');

  // --- Edit Translations state ---
  const [languages, setLanguages] = useState([]);
  const [selectedLang, setSelectedLang] = useState(null);
  const [loadingLangs, setLoadingLangs] = useState(true);
  const [langsError, setLangsError] = useState(null);
  const [search, setSearch] = useState('');
  const [untranslatedOnly, setUntranslatedOnly] = useState(false);
  const [selectedPage, setSelectedPage] = useState('');

  // --- Manage Languages state ---
  const [supportedLanguages, setSupportedLanguages] = useState([]);
  const [newLangCode, setNewLangCode] = useState('');
  const [addingLang, setAddingLang] = useState(false);
  const [manageFeedback, setManageFeedback] = useState(null);

  // Translator management per language
  const [translatorInputs, setTranslatorInputs] = useState({}); // langId -> email input
  const [translatorPassInputs, setTranslatorPassInputs] = useState({}); // langId -> password input

  const showManageFeedback = (msg, isError = false) => {
    setManageFeedback({ msg, isError });
    setTimeout(() => setManageFeedback(null), 3500);
  };

  // Load languages (admin uses fetchTranslatorLanguagesAPI which returns all for admins)
  useEffect(() => {
    if (!authToken || !canEditOrgData) { setLoadingLangs(false); return; }
    setLoadingLangs(true);
    fetchTranslatorLanguagesAPI(authToken)
      .then((data) => {
        setLanguages(Array.isArray(data) ? data : []);
        if (Array.isArray(data) && data.length > 0) setSelectedLang(data[0]);
      })
      .catch((err) => setLangsError(err.message || 'Failed to load languages'))
      .finally(() => setLoadingLangs(false));
  }, [authToken, canEditOrgData]);

  // Load supported languages for the "Add Language" dropdown
  useEffect(() => {
    if (!authToken || !canEditOrgData) return;
    fetchSupportedLanguagesAPI()
      .then((data) => setSupportedLanguages(Array.isArray(data) ? data : data?.results ?? []))
      .catch(() => {});
  }, [authToken, canEditOrgData]);

  // --- Edit tab helpers ---
  const pages = selectedLang?.pages ?? [];
  const pageOptions = pages.map((p) => ({ id: p.page_id, name: p.page_name }));

  const allEntries = useMemo(() => {
    const filteredPages = selectedPage
      ? pages.filter((p) => String(p.page_id) === selectedPage)
      : pages;
    return filteredPages.flatMap((page) =>
      Object.entries(page.strings).map(([key, [english, translation]]) => ({
        pageId: page.page_id,
        pageName: page.page_name,
        key,
        english,
        translation,
      }))
    );
  }, [selectedLang, selectedPage]);

  const visibleEntries = useMemo(() => {
    let entries = allEntries;
    if (untranslatedOnly) {
      entries = entries.filter((e) => !e.translation || e.translation === e.english);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      entries = entries.filter(
        (e) => e.english.toLowerCase().includes(q) || e.key.toLowerCase().includes(q)
      );
    }
    return entries;
  }, [allEntries, search, untranslatedOnly]);

  const handleSave = async (pageId, langId, key, value) => {
    const orgDomain = orgDomainName || getOrgDomainFromURL();
    await updateTranslationAPI(authToken, orgDomain, {
      page_id: pageId,
      langauge_id: langId,
      translation_data: { [key]: value },
    });
  };

  // --- Manage tab helpers ---
  const handleAddTranslator = async (lang) => {
    const email = (translatorInputs[lang.id] || '').trim();
    const password = (translatorPassInputs[lang.id] || '').trim();
    if (!email || !password) {
      showManageFeedback('Email and temporary password are required', true);
      return;
    }
    try {
      await updateLanguageTranslatorsAPI(authToken, lang.id, {
        newTranslators: [{ email, password }],
        deleteTranslators: [],
      });
      setTranslatorInputs((prev) => ({ ...prev, [lang.id]: '' }));
      setTranslatorPassInputs((prev) => ({ ...prev, [lang.id]: '' }));
      showManageFeedback(`Added ${email} as translator for ${lang.language_name}`);
      // Refresh language list to show updated translators
      const data = await fetchTranslatorLanguagesAPI(authToken);
      setLanguages(Array.isArray(data) ? data : []);
    } catch (err) {
      showManageFeedback(err.message || 'Failed to add translator', true);
    }
  };

  const handleAddLanguage = async () => {
    if (!newLangCode) return;
    setAddingLang(true);
    try {
      await addManagedLanguageAPI(authToken, newLangCode);
      setNewLangCode('');
      showManageFeedback('Language added successfully');
      const data = await fetchTranslatorLanguagesAPI(authToken);
      setLanguages(Array.isArray(data) ? data : []);
      if (Array.isArray(data) && data.length > 0 && !selectedLang) setSelectedLang(data[0]);
    } catch (err) {
      showManageFeedback(err.message || 'Failed to add language', true);
    } finally {
      setAddingLang(false);
    }
  };

  if (!authToken) {
    return (
      <div className="min-h-screen theme-gradient-bg flex items-center justify-center">
        <p className="text-white text-lg">Loading…</p>
      </div>
    );
  }

  if (!canEditOrgData) {
    return (
      <div className="min-h-screen theme-gradient-bg p-6 flex items-center justify-center">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-2xl p-8 text-center space-y-6">
          <div className="text-5xl">&#128274;</div>
          <h1 className="text-2xl font-bold text-gray-800">Access Denied</h1>
          <p className="text-gray-600">You do not have permission to manage translations.</p>
          <Link href="/admin" className="inline-block px-6 py-3 text-white font-semibold rounded-xl transition" style={{ backgroundColor: 'var(--theme-primary)' }}>Back</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen theme-gradient-bg p-6">
      <div className="max-w-3xl mx-auto space-y-6">
        <h1 className="text-3xl font-bold text-white text-center">Translations</h1>

        {/* Tabs */}
        <div className="flex gap-1 bg-white/10 rounded-xl p-1">
          {[
            { key: 'edit', label: 'Edit Translations' },
            { key: 'manage', label: 'Manage Languages' },
          ].map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`flex-1 py-2 rounded-lg text-sm font-semibold transition ${
                activeTab === tab.key ? 'bg-white text-gray-800 shadow' : 'text-white/80 hover:text-white'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* ── Edit Translations Tab ── */}
        {activeTab === 'edit' && (
          <div className="bg-white rounded-2xl shadow-2xl p-6 space-y-4">
            {loadingLangs && (
              <div className="flex justify-center py-12">
                <div className="animate-spin rounded-full h-10 w-10 border-4 border-t-transparent" style={{ borderColor: 'var(--theme-primary)', borderTopColor: 'transparent' }} />
              </div>
            )}
            {langsError && <p className="text-red-600 text-center">{langsError}</p>}
            {!loadingLangs && !langsError && languages.length === 0 && (
              <p className="text-center text-gray-500 py-8">No languages set up yet. Add one in the Manage Languages tab.</p>
            )}
            {!loadingLangs && languages.length > 0 && (
              <>
                {/* Language tabs */}
                <div className="flex gap-1 overflow-x-auto pb-1">
                  {languages.map((lang) => (
                    <button
                      key={lang.id}
                      onClick={() => { setSelectedLang(lang); setSelectedPage(''); setSearch(''); }}
                      className={`px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition ${
                        selectedLang?.id === lang.id ? 'text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                      }`}
                      style={selectedLang?.id === lang.id ? { backgroundColor: 'var(--theme-primary)' } : undefined}
                    >
                      {lang.flag_emoji} {lang.language_name}
                    </button>
                  ))}
                </div>

                {/* Filters */}
                <div className="flex flex-wrap gap-3 items-center">
                  <input
                    type="search"
                    placeholder="Search strings…"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    className="flex-1 min-w-[160px] px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
                  />
                  {pageOptions.length > 1 && (
                    <select
                      value={selectedPage}
                      onChange={(e) => setSelectedPage(e.target.value)}
                      className="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
                    >
                      <option value="">All sections</option>
                      {pageOptions.map((p) => (
                        <option key={p.id} value={String(p.id)}>{p.name}</option>
                      ))}
                    </select>
                  )}
                  <label className="flex items-center gap-2 text-sm text-gray-600 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={untranslatedOnly}
                      onChange={(e) => setUntranslatedOnly(e.target.checked)}
                      className="rounded"
                    />
                    Untranslated only
                  </label>
                </div>

                <p className="text-xs text-gray-400">{visibleEntries.length} of {allEntries.length} strings</p>

                {/* Cards */}
                <div className="space-y-3">
                  {visibleEntries.length === 0 && (
                    <p className="text-center text-gray-400 py-8">
                      {untranslatedOnly ? 'All strings translated!' : 'No strings match your search.'}
                    </p>
                  )}
                  {visibleEntries.map((entry) => (
                    <TranslationStringCard
                      key={`${entry.pageId}::${entry.key}`}
                      pageName={entry.pageName}
                      stringKey={entry.key}
                      english={entry.english}
                      translation={entry.translation}
                      onSave={(key, value) => handleSave(entry.pageId, selectedLang.id, key, value)}
                    />
                  ))}
                </div>
              </>
            )}
          </div>
        )}

        {/* ── Manage Languages Tab ── */}
        {activeTab === 'manage' && (
          <div className="space-y-4">
            {manageFeedback && (
              <div className={`text-center py-2 px-4 rounded-xl font-medium text-sm ${
                manageFeedback.isError ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'
              }`}>
                {manageFeedback.msg}
              </div>
            )}

            {/* Add Language */}
            <div className="bg-white rounded-2xl shadow-2xl p-6 space-y-3">
              <h2 className="text-lg font-bold text-gray-800">Add Language</h2>
              <div className="flex gap-2">
                <select
                  value={newLangCode}
                  onChange={(e) => setNewLangCode(e.target.value)}
                  className="flex-1 px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
                >
                  <option value="">Select a language…</option>
                  {supportedLanguages.map((lang) => (
                    <option key={lang.id ?? lang.language_code} value={lang.language_code ?? lang.id}>
                      {lang.language_name ?? lang.name}
                    </option>
                  ))}
                </select>
                <button
                  onClick={handleAddLanguage}
                  disabled={!newLangCode || addingLang}
                  className="px-4 py-2 text-white text-sm font-semibold rounded-lg disabled:opacity-50 transition"
                  style={{ backgroundColor: 'var(--theme-primary)' }}
                >
                  {addingLang ? 'Adding…' : 'Add'}
                </button>
              </div>
            </div>

            {/* Language list with translator management */}
            {languages.map((lang) => (
              <div key={lang.id} className="bg-white rounded-2xl shadow-2xl p-6 space-y-4">
                <h2 className="text-lg font-bold text-gray-800">
                  {lang.flag_emoji} {lang.language_name}
                </h2>

                <div className="space-y-2">
                  <p className="text-sm font-medium text-gray-600">Add Translator</p>
                  <div className="flex gap-2 flex-wrap">
                    <input
                      type="email"
                      placeholder="translator@email.com"
                      value={translatorInputs[lang.id] || ''}
                      onChange={(e) => setTranslatorInputs((p) => ({ ...p, [lang.id]: e.target.value }))}
                      className="flex-1 min-w-[180px] px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
                    />
                    <input
                      type="password"
                      placeholder="Temporary password"
                      value={translatorPassInputs[lang.id] || ''}
                      onChange={(e) => setTranslatorPassInputs((p) => ({ ...p, [lang.id]: e.target.value }))}
                      className="flex-1 min-w-[160px] px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
                    />
                    <button
                      onClick={() => handleAddTranslator(lang)}
                      className="px-4 py-2 text-white text-sm font-semibold rounded-lg transition"
                      style={{ backgroundColor: 'var(--theme-primary)' }}
                    >
                      Add
                    </button>
                  </div>
                  <p className="text-xs text-gray-400">A temporary password is required to create the translator account if they don't already exist.</p>
                </div>
              </div>
            ))}
          </div>
        )}

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

### Step 3: Check that `fetchSupportedLanguagesAPI` exists

Run:
```bash
grep -n "fetchSupportedLanguagesAPI" /home/john/strollopia_git_hub/data_logger/utils/api.js
```

If it does not exist, add it to `utils/api.js`:
```js
export const fetchSupportedLanguagesAPI = async () => {
  const response = await fetchWithTimeout(API_ENDPOINTS.SUPPORTED_LANGUAGES, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!response.ok) throw new Error('Failed to fetch supported languages');
  return response.json();
};
```

### Step 4: Run full suite

```bash
cd /home/john/strollopia_git_hub/data_logger && npm test 2>&1 | tail -10
```

### Step 5: Commit

```bash
git -C /home/john/strollopia_git_hub/data_logger add app/admin/translations/page.js utils/api.js
git -C /home/john/strollopia_git_hub/data_logger commit -m "feat: redesign admin translations with card editor and language management tabs"
```
