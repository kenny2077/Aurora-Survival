# Aurora Forge Lab Company Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy a dependency-free company website for Aurora Forge Lab at `https://auroraforgelab.com` while leaving the existing Aurora Survival site unchanged.

**Architecture:** Create a separate private repository containing a static `site/` directory served directly by Cloudflare Pages. Semantic HTML owns all content, CSS owns the visual and reduced-motion systems, and one small JavaScript file progressively enhances mobile navigation, section reveals, and pointer effects. Node built-in tests validate the public contract before GitHub Actions deploys the exact `site/` directory.

**Tech Stack:** HTML5, CSS, vanilla JavaScript, Node.js built-in test runner, GitHub Actions, Cloudflare Pages

**Spec:** `Docs/superpowers/specs/2026-09-12-aurora-forge-lab-company-site-design.md`

## Global Constraints

- Create the private repository `kenny2077/aurora-forge-lab` and keep it private.
- Use semantic HTML, CSS, minimal vanilla JavaScript, and no package dependencies.
- Use Aurora Forge Lab as the public brand and Aurora Labs LLC as the legal operator.
- Name Kenny Guo as founder and Product Manager.
- Use `hello@auroraforgelab.com` as the only public contact address.
- Feature exactly Aurora Survival and Aurora Digest; do not add products, testimonials, customers, metrics, funding claims, or certifications.
- Describe Aurora Survival as coming to the App Store.
- Describe Aurora Digest as active, open-source, and self-hosted.
- Add no forms, analytics, cookies, external fonts, embedded widgets, or runtime asset hotlinks.
- Keep all content visible without JavaScript and static under `prefers-reduced-motion: reduce`.
- Do not change the existing Aurora Survival repository or deployment.

---

### Task 1: Create the private repository and test-first static shell

**Files:**
- Create repository: `kenny2077/aurora-forge-lab`
- Create: `site/index.html`
- Create: `site/privacy/index.html`
- Create: `site/support/index.html`
- Create: `tests/site.test.mjs`
- Create: `docs/design.md`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Produces: a private Git repository whose deployable root is `site/`.
- Produces: `tests/site.test.mjs`, the single contract-test entry point used locally and in CI.
- Produces: `docs/design.md`, a copy of the approved design that travels with the new repository.
- Consumes: the approved design specification from the Aurora Survival repository.

- [ ] **Step 1: Create and clone the private repository**

Run from `/Users/kenny/Desktop`:

```bash
rtk gh repo create kenny2077/aurora-forge-lab --private --description "Company website for Aurora Forge Lab" --clone
cd /Users/kenny/Desktop/aurora-forge-lab
```

Expected: GitHub reports a private repository and `rtk gh repo view kenny2077/aurora-forge-lab --json visibility` returns `{"visibility":"PRIVATE"}`.

- [ ] **Step 2: Write the first failing contract tests**

Create `tests/site.test.mjs` with Node built-ins. It must define `readRequired(relativePath)` from the repository root and include these first contracts:

```js
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const root = resolve(import.meta.dirname, "..");

function readRequired(relativePath) {
  const path = resolve(root, relativePath);
  assert.ok(existsSync(path), `required file is missing: ${relativePath}`);
  return readFileSync(path, "utf8");
}

test("the homepage identifies the company and its legal operator", () => {
  const html = readRequired("site/index.html");
  assert.match(html, /<title>Aurora Forge Lab — Practical AI tools<\/title>/);
  assert.match(html, /<h1[^>]*>Practical AI tools built for real use\.<\/h1>/);
  assert.match(html, /Aurora Forge Lab is operated by Aurora Labs LLC\./);
});

test("privacy and support pages are public", () => {
  assert.match(readRequired("site/privacy/index.html"), /<h1[^>]*>Privacy<\/h1>/);
  assert.match(readRequired("site/support/index.html"), /<h1[^>]*>Support<\/h1>/);
});
```

- [ ] **Step 3: Run the tests and verify the missing-site failure**

Run:

```bash
node --test tests/site.test.mjs
```

Expected: FAIL because `site/index.html` does not exist.

- [ ] **Step 4: Add the minimal semantic pages**

Create each page with `<!doctype html>`, language, charset, viewport, title, one skip link, header, navigation, main landmark, one `h1`, and footer. Use relative links that work from both nested pages. The homepage contains the approved hero and legal disclosure. Privacy and Support initially contain their approved headings and a link back to `/`.

- [ ] **Step 5: Document local use and repository boundaries**

Create `README.md` with:

```markdown
# Aurora Forge Lab

Static company website for Aurora Forge Lab.

## Test

`node --test tests/site.test.mjs`

## Preview

`python3 -m http.server 4173 --directory site`

The deployable artifact is the dependency-free `site/` directory.
```

Create `.gitignore` containing `.DS_Store` and `.playwright-cli/`. Copy the approved design specification into `docs/design.md` without changing its requirements.

- [ ] **Step 6: Run the initial tests and commit**

Run:

```bash
node --test tests/site.test.mjs
rtk git diff --check
```

Expected: PASS with zero whitespace errors.

Commit:

```bash
rtk git add README.md .gitignore docs/design.md site tests
rtk git commit -m "feat: add Aurora Forge Lab site shell"
```

---

### Task 2: Build the complete company content and public metadata

**Files:**
- Modify: `site/index.html`
- Modify: `site/privacy/index.html`
- Modify: `site/support/index.html`
- Create: `site/assets/aurora-mark.svg`
- Create: `site/assets/aurora-survival.webp`
- Create: `site/assets/aurora-digest.webp`
- Create: `site/assets/social-preview.webp`
- Create: `site/robots.txt`
- Create: `site/sitemap.xml`
- Create: `site/_headers`
- Modify: `tests/site.test.mjs`

**Interfaces:**
- Consumes: the semantic page shell and `readRequired(relativePath)` from Task 1.
- Produces: exact public copy, local imagery, legal pages, metadata, crawler files, and response-header rules.
- Produces: section IDs `products`, `principles`, `founder`, and `contact` for navigation and motion hooks.

- [ ] **Step 1: Add failing identity, product, link, and metadata contracts**

Extend `tests/site.test.mjs` with assertions for:

```js
test("the homepage presents exactly the two verified Aurora products", () => {
  const html = readRequired("site/index.html");
  assert.equal((html.match(/class="product-entry/g) ?? []).length, 2);
  assert.match(html, /Aurora Survival[\s\S]*Coming to the App Store/);
  assert.match(html, /Aurora Digest[\s\S]*active[\s\S]*open-source[\s\S]*self-hosted/i);
});

test("all public destinations are exact and external links are safe", () => {
  const html = readRequired("site/index.html");
  for (const url of [
    "https://survival.auroraforgelab.com",
    "https://github.com/kenny2077/aurora-survival",
    "https://kenny2077.github.io/Aurora/",
    "https://github.com/kenny2077/Aurora",
    "https://github.com/kenny2077",
  ]) {
    const escaped = url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    assert.match(html, new RegExp(`href="${escaped}"[^>]*target="_blank"[^>]*rel="noopener noreferrer"`));
  }
  assert.match(html, /href="mailto:hello@auroraforgelab\.com"/);
});

test("the homepage publishes canonical and social metadata", () => {
  const html = readRequired("site/index.html");
  assert.match(html, /rel="canonical" href="https:\/\/auroraforgelab\.com\/"/);
  assert.match(html, /property="og:url" content="https:\/\/auroraforgelab\.com\/"/);
  assert.match(html, /property="og:image" content="https:\/\/auroraforgelab\.com\/assets\/social-preview\.webp"/);
});
```

Also assert the Founder section contains `Kenny Guo` and `Product Manager`, and that visible copy excludes `customers`, `trusted by`, `funded`, `certified`, and `available now`.

- [ ] **Step 2: Run the targeted contracts and verify failure**

Run:

```bash
node --test --test-name-pattern="verified Aurora products|public destinations|canonical" tests/site.test.mjs
```

Expected: FAIL because the product entries and metadata do not yet exist.

- [ ] **Step 3: Implement the homepage information architecture**

Build these sections in order:

1. Header with Aurora Forge Lab mark and anchors to Products, Principles, Founder, and Contact.
2. Hero with the exact `h1` “Practical AI tools built for real use.” and a contact action.
3. Principles with exactly the three approved product values.
4. Products with exactly two `<article class="product-entry">` elements and factual local imagery.
5. Founder with Kenny Guo, Product Manager, and the founder GitHub link.
6. Contact with `mailto:hello@auroraforgelab.com` and no form.
7. Footer with Privacy, Support, GitHub, and the exact legal disclosure.

Every off-site link that opens a new tab uses `target="_blank" rel="noopener noreferrer"`.

- [ ] **Step 4: Add factual local assets**

Copy or derive the Aurora family mark and product imagery from the two public repositories. Do not hotlink. Optimize raster assets to WebP, preserve useful detail, and declare intrinsic `width`, `height`, and descriptive `alt` attributes in HTML.

Keep these budgets:

- `aurora-mark.svg`: under 25 KB.
- Each product image: under 500 KB.
- `social-preview.webp`: 1200×630 and under 500 KB.

- [ ] **Step 5: Complete privacy and support pages**

Privacy must state that the company website uses no analytics, advertising trackers, cookies, accounts, or form collection, and that linked products have separate behavior and documentation. Support must expose `hello@auroraforgelab.com` plus direct Survival and Digest links. Both pages use their own canonical URL and the shared header/footer.

- [ ] **Step 6: Add crawler and header files**

Create `site/robots.txt`:

```text
User-agent: *
Allow: /
Sitemap: https://auroraforgelab.com/sitemap.xml
```

Create `site/sitemap.xml` containing the exact homepage, `/privacy/`, and `/support/` URLs.

Create `site/_headers`:

```text
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  X-Frame-Options: DENY
  Content-Security-Policy: default-src 'self'; img-src 'self'; script-src 'self'; style-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'

/assets/*
  Cache-Control: public, max-age=31536000, immutable
```

- [ ] **Step 7: Add local-asset and static-file tests**

Parse every local `src` and `href` from all three HTML files, resolve it below `site/`, and assert the file exists and is non-empty. Assert every `<img>` contains non-empty `alt`, numeric `width`, and numeric `height`. Assert `robots.txt`, `sitemap.xml`, and `_headers` contain the exact production hostname and required policies.

- [ ] **Step 8: Run the complete content suite and commit**

Run:

```bash
node --test tests/site.test.mjs
rtk git diff --check
```

Expected: all tests PASS.

Commit:

```bash
rtk git add site tests/site.test.mjs
rtk git commit -m "feat: add company content and public metadata"
```

---

### Task 3: Implement the visual system, navigation, and restrained motion

**Files:**
- Create: `site/styles.css`
- Create: `site/script.js`
- Modify: `site/index.html`
- Modify: `site/privacy/index.html`
- Modify: `site/support/index.html`
- Modify: `tests/site.test.mjs`
- Create: `DESIGN.md`

**Interfaces:**
- Consumes: section IDs and content structure from Task 2.
- Produces: `.nav-toggle`, `#nav-links`, `[data-reveal]`, `.cursor-field`, and `[data-depth]` enhancement hooks.
- Produces: a no-dependency JavaScript module that does not alter content when required browser APIs are missing.

- [ ] **Step 1: Add failing layout, progressive-enhancement, and motion contracts**

Add tests that require:

```js
test("the interface is responsive and honors reduced motion", () => {
  const css = readRequired("site/styles.css");
  assert.match(css, /:focus-visible/);
  assert.match(css, /@media[^\{]*max-width:\s*800px/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /prefers-reduced-motion:[\s\S]*animation:\s*none/);
  assert.match(css, /overflow-wrap/);
});

test("JavaScript only progressively enhances navigation and motion", () => {
  const script = readRequired("site/script.js");
  assert.match(script, /matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(script, /IntersectionObserver/);
  assert.match(script, /requestAnimationFrame/);
  assert.doesNotMatch(script, /innerHTML|document\.write|preventDefault\(\).*wheel/s);
});
```

- [ ] **Step 2: Run the motion contracts and verify failure**

Run:

```bash
node --test --test-name-pattern="responsive|progressively enhances" tests/site.test.mjs
```

Expected: FAIL because `styles.css` and `script.js` do not exist.

- [ ] **Step 3: Implement the company visual system**

Create `site/styles.css` using custom properties for deep navy, cyan, teal, amber, warm paper, ink, muted text, and rules. Use system sans and system monospace only. Implement:

- A sticky, translucent company header.
- A full-height dark hero with slow CSS aurora ribbons and technical texture.
- Off-white reading sections with clear tonal transition bands.
- A two-entry product portfolio whose Survival entry has stronger scale without hiding Digest.
- Square actions, thin rules, and visible 3px focus outlines.
- Desktop layouts capped at readable measures.
- Mobile stacking at 800px and tighter adjustments at 520px.
- No horizontal overflow at 320px.

- [ ] **Step 4: Implement minimal progressive enhancement**

Create `site/script.js` that:

- Toggles `aria-expanded` and an `.is-open` class for mobile navigation.
- Adds a `.motion-ready` class only after initializing reveal behavior.
- Uses one `IntersectionObserver` to reveal `[data-reveal]` elements.
- Uses one `requestAnimationFrame` loop to ease CSS custom properties for the hero pointer field and `[data-depth]` product imagery on fine pointers.
- Skips observers, transforms, and continuous animation when reduced motion is requested.
- Leaves all content visible when JavaScript is absent.

- [ ] **Step 5: Record the design system**

Create `DESIGN.md` describing the company-level Aurora system: colors, typography, layout, motion, focus behavior, product hierarchy, legal surfaces, and rules preventing generic AI visuals or fabricated UI.

- [ ] **Step 6: Run all automated tests and commit**

Run:

```bash
node --test tests/site.test.mjs
rtk git diff --check
```

Expected: all tests PASS.

Commit:

```bash
rtk git add site tests/site.test.mjs DESIGN.md
rtk git commit -m "feat: add Aurora Forge Lab visual system"
```

---

### Task 4: Browser verification and defect correction

**Files:**
- Modify only when a verified defect requires it: `site/index.html`, `site/privacy/index.html`, `site/support/index.html`, `site/styles.css`, `site/script.js`, `tests/site.test.mjs`

**Interfaces:**
- Consumes: the complete static site from Tasks 1–3.
- Produces: verified desktop, mobile, keyboard, no-JavaScript, and reduced-motion behavior.

- [ ] **Step 1: Start the static preview**

Run:

```bash
python3 -m http.server 4173 --directory site
```

Expected: `http://127.0.0.1:4173/` returns the company homepage.

- [ ] **Step 2: Inspect desktop and mobile in one bounded pass**

Use the Playwright CLI to inspect:

- 1440×900 desktop.
- 390×844 mobile.
- 320×700 narrow mobile.

At every width verify zero horizontal overflow, correct product hierarchy, readable legal copy, local images loaded at their intrinsic ratio, and visible footer links. Capture one homepage screenshot per width and one nested-page mobile screenshot.

- [ ] **Step 3: Verify interaction and accessibility states**

Verify:

- Tab focus reaches every header, product, founder, contact, privacy, and support link.
- Focus outlines are visible.
- Mobile navigation opens, closes, and reports the correct `aria-expanded` value.
- Anchor links land below the sticky header.
- With JavaScript disabled, content and navigation remain visible.
- With reduced motion enabled, aurora, reveals, and depth remain static.
- Privacy and Support return 200 and link back to the homepage.

- [ ] **Step 4: Fix verified defects in one surgical batch**

For each defect, add or tighten a contract test when the behavior can be expressed statically, then edit only the owning HTML, CSS, or JavaScript. Do not redesign adjacent sections during this pass.

- [ ] **Step 5: Confirm once and run the final local gate**

Repeat the failing viewport or state once. Then run:

```bash
node --test tests/site.test.mjs
rtk git diff --check
rtk git status --short
```

Expected: tests PASS, no whitespace errors, and only intentional site files are modified.

- [ ] **Step 6: Commit verified corrections**

If files changed:

```bash
rtk git add site tests/site.test.mjs
rtk git commit -m "fix: finish responsive company site"
```

If no files changed, do not create an empty commit.

---

### Task 5: Add Cloudflare deployment and publish the company domain

**Files:**
- Create: `.github/workflows/pages-deployment.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: the fully verified `site/` directory and passing `tests/site.test.mjs` suite.
- Produces: GitHub Actions deployment to the Cloudflare Pages project `aurora-forge-lab`.
- Requires repository secrets: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` with the same least-privilege Pages deployment access already used for Aurora Survival.

- [ ] **Step 1: Add a failing deployment-workflow contract**

Add a test that reads `.github/workflows/pages-deployment.yml` and asserts:

```js
assert.match(workflow, /node --test tests\/site\.test\.mjs/);
assert.match(workflow, /projectName:\s*aurora-forge-lab/);
assert.match(workflow, /directory:\s*site/);
assert.match(workflow, /CLOUDFLARE_API_TOKEN/);
assert.match(workflow, /CLOUDFLARE_ACCOUNT_ID/);
```

- [ ] **Step 2: Run the workflow contract and verify failure**

Run:

```bash
node --test --test-name-pattern="deployment" tests/site.test.mjs
```

Expected: FAIL because the workflow does not exist.

- [ ] **Step 3: Create the tested Pages workflow**

Create `.github/workflows/pages-deployment.yml` with `push` on `main` and `workflow_dispatch`. Give it read-only contents permission. Pin `actions/checkout` and `cloudflare/wrangler-action` to reviewed commit SHAs. Its steps must:

1. Check out the repository.
2. Run `node --test tests/site.test.mjs`.
3. Run Wrangler Pages deploy for `site/` with project name `aurora-forge-lab` and branch `main`.

- [ ] **Step 4: Configure the private repository secrets**

Reuse the existing Cloudflare account ID and least-privilege Pages deployment token without printing either value. Store them as GitHub Actions secrets named exactly `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. Confirm only the secret names with:

```bash
rtk gh secret list --repo kenny2077/aurora-forge-lab
```

Expected: both names appear; secret values never appear in output or files.

- [ ] **Step 5: Run the final pre-push gate and commit**

Run:

```bash
node --test tests/site.test.mjs
rtk git diff --check
```

Expected: all tests PASS.

Commit:

```bash
rtk git add .github/workflows/pages-deployment.yml README.md tests/site.test.mjs
rtk git commit -m "ci: deploy company site to Cloudflare Pages"
```

- [ ] **Step 6: Push and verify the first deployment**

Run:

```bash
rtk git push -u origin main
rtk gh run watch --repo kenny2077/aurora-forge-lab --exit-status
```

Expected: the deployment workflow succeeds and creates `https://aurora-forge-lab.pages.dev`.

- [ ] **Step 7: Attach the apex and www hostnames**

In Cloudflare Pages → `aurora-forge-lab` → Custom domains:

1. Add `auroraforgelab.com` and wait for `Active` with SSL enabled.
2. Add `www.auroraforgelab.com` and wait for `Active` with SSL enabled.
3. Create a host-specific redirect rule from `www.auroraforgelab.com/*` to `https://auroraforgelab.com/${1}` with status 301 and query-string preservation.

Do not edit or remove Zoho MX, SPF, DKIM, or verification records.

- [ ] **Step 8: Redirect only the production pages.dev hostname**

Create an account-level Bulk Redirect entry from `https://aurora-forge-lab.pages.dev/` to `https://auroraforgelab.com/` with subpath and query-string preservation. Enable the list with a Bulk Redirect Rule. Do not match `*.aurora-forge-lab.pages.dev`; preview deployment hostnames must remain available.

- [ ] **Step 9: Verify the public release**

Run read-only checks:

```bash
rtk proxy curl -fsSI https://auroraforgelab.com/
rtk proxy curl -fsSI https://www.auroraforgelab.com/
rtk proxy curl -fsSI https://aurora-forge-lab.pages.dev/
rtk proxy curl -fsSI https://survival.auroraforgelab.com/
rtk proxy curl -fsSL https://auroraforgelab.com/ | rtk grep "Practical AI tools built for real use"
```

Expected:

- Apex returns 200 with the configured security headers.
- `www` returns a permanent redirect to the same apex path.
- The production `pages.dev` hostname redirects to the apex.
- Survival still returns 200 and retains the Aurora Survival title.
- The company homepage contains the approved hero.

- [ ] **Step 10: Record deployment details**

Update `README.md` with the public apex URL, Pages project name, deploy workflow path, and the statement that Survival is an independent product deployment. Commit and push:

```bash
rtk git add README.md
rtk git commit -m "docs: record company site deployment"
rtk git push origin main
```

Watch the final workflow and repeat the public read-only checks before reporting completion.
