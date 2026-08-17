# strollopia-pwa Vercel Setup

**Repo:** https://github.com/John2662/strollopia-pwa  
**Branches:** `main` (production), `dev` (preview/staging)

---

## Step 0: Connect Vercel to your GitHub account

**Start in Vercel — it redirects you to GitHub to authorize.**

1. Go to https://vercel.com and sign in (or create an account)
2. Click **Add New… → Project**
3. On the "Import Git Repository" screen, if no repos are listed click **"Add GitHub Account"** or **"Configure GitHub App"**
4. You are redirected to **GitHub** — choose **Only select repositories**, add `John2662/strollopia-pwa`, click **Install**
5. GitHub redirects you back to Vercel — `strollopia-pwa` now appears in the import list

> If Vercel already has GitHub access from a previous project (repos are already listed), you may still need to grant access to the new repo: on GitHub go to **Settings → Applications → Vercel → Repository access** and add `strollopia-pwa`.

---

## Step 1: Import the repo into Vercel

1. In Vercel, click **Add New… → Project**
2. Under "Import Git Repository", find `John2662/strollopia-pwa` and click **Import**
3. Framework preset: confirm it shows **Next.js** (auto-detected)
4. Root directory: leave as `.` (the repo root IS the Next.js app)
5. Do NOT deploy yet — set environment variables first (Step 2)

---

## Step 2: Set environment variables

On the import screen, expand **Environment Variables** before clicking Deploy, or go to the project → **Settings → Environment Variables** afterwards.

Add the same variable name twice with different values per environment:

| Name | Value | Environment |
|------|-------|-------------|
| `NEXT_PUBLIC_API_URL` | `https://prod.strollopia.com` | Production |
| `NEXT_PUBLIC_API_URL` | `https://dev.strollopia.com` | Preview |

> **Do NOT include `/api`** — `utils/api.js` already appends `/api/...` to every endpoint.  
> The `NEXT_PUBLIC_` prefix is required for Next.js to expose the value to the browser bundle.

Now click **Deploy**. Vercel builds and deploys `main` as Production.

---

## Step 3: How branches map to deployments

Vercel auto-deploys on every push — no extra config needed for the `dev` branch:

| Branch | Deployment type | URL |
|--------|----------------|-----|
| `main` | Production | `strollopia-pwa.vercel.app` (or your custom domain) |
| `dev` | Preview | `strollopia-pwa-git-dev-john2662.vercel.app` (auto-generated) |
| Any other branch | Preview | auto-generated URL |

Every push to either branch triggers a build automatically.

---

## Step 4: Assign a production domain

1. Project → **Settings → Domains**
2. Click **Add**, enter `guide.strollopia.com` (or whatever you want)
3. Vercel shows a CNAME record to add — go to your DNS provider and add:
   - Type: `CNAME`
   - Name: `guide`
   - Value: `cname.vercel-dns.com`
4. Vercel auto-detects the DNS change (usually < 5 min)

---

## Step 5: Give `dev` a stable preview domain (optional but recommended)

By default the `dev` preview URL changes each deployment. To pin it to a stable URL:

1. Project → **Settings → Domains**
2. Click **Add**, enter `dev-guide.strollopia.com`
3. After adding, click **Edit** on that domain entry
4. Set **Git Branch** to `dev`
5. Add the CNAME in your DNS provider:
   - Type: `CNAME`
   - Name: `dev-guide`
   - Value: `cname.vercel-dns.com`

Now the stable URLs are:

```
main → guide.strollopia.com
dev  → dev-guide.strollopia.com
```

---

## Step 6: Day-to-day workflow

```bash
cd strollopia_git_hub/strollopia-pwa
git checkout dev          # always develop on dev
# ... make changes ...
git add <files>
git commit -m "feat: ..."
git push                  # triggers Vercel preview build on dev-guide.strollopia.com
```

To ship to production, open a PR from `dev` → `main` on GitHub and merge it. Vercel auto-deploys `main` to `guide.strollopia.com`.

---

## Troubleshooting

- **Build fails on Vercel but works locally:** check that `NEXT_PUBLIC_API_URL` is set for the correct environment in Vercel Settings → Environment Variables, then redeploy.
- **DNS not resolving:** CNAME changes can take up to 24h, but Vercel's panel shows a green checkmark once it detects the record.
- **Wrong API URL in prod:** confirm the Production environment variable points to `https://prod.strollopia.com`, not the dev API.
