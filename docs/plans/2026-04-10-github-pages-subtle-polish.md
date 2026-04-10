# GitHub Pages Subtle Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply a subtle premium polish pass to the live GitHub Pages landing page with stronger mobile presentation while preserving the current single refined direction.

**Architecture:** Keep the site as a static `docs/` HTML and CSS landing page. Make the smallest markup changes needed in `docs/index.html` to support better hierarchy and mobile composition, do most of the work in `docs/style.css`, and keep the existing shell regression test aligned with the single-direction live site constraints.

**Tech Stack:** HTML5, CSS3, Bash shell test

---

### Task 1: Reconfirm live-site guardrails before editing

**Files:**
- Read: `docs/index.html`
- Read: `docs/style.css`
- Read: `tests/github-pages-site.sh`
- Read: `docs/plans/2026-04-10-github-pages-subtle-polish-design.md`

**Step 1: Re-read the approved design doc**

Confirm that the work is a subtle refinement, not a redesign.

**Step 2: Re-read the live homepage markup**

Confirm where header, hero, trust strip, feature grids, quickstart steps, and comparison content currently live.

**Step 3: Re-read the stylesheet**

Confirm which current rules are responsible for the sticky header, hero layout, trust strip, cards, and mobile breakpoints.

**Step 4: Re-read the current regression test**

Confirm what live-site constraints are already enforced before adding any new coverage.

**Step 5: Verify there is no accidental site diff yet**

Run: `git diff -- docs/index.html docs/style.css tests/github-pages-site.sh`
Expected: no diff before implementation starts.

---

### Task 2: Add regression coverage for live-site polish constraints

**Files:**
- Modify: `tests/github-pages-site.sh`

**Step 1: Write a failing regression for preserved single-direction structure**

Add a new test function that checks the homepage still contains the refined live-page primitives the polish pass must preserve, for example:

```bash
test_homepage_preserves_refined_live_primitives() (
  local index_path
  index_path="$REPO_ROOT/docs/index.html"

  grep -q 'class="hero-shell"' "$index_path" || fail "homepage missing refined hero shell"
  grep -q 'class="hero-actions"' "$index_path" || fail "homepage missing hero actions"
  grep -q 'class="hero-proof"' "$index_path" || fail "homepage missing hero proof cards"
)
```

Keep the test structural and narrow. Do not assert on decorative copy or brittle whitespace.

**Step 2: Run the test suite to verify the new coverage passes against the current site**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 3: Commit the regression coverage**

```bash
git add tests/github-pages-site.sh
git commit -m "test: extend github pages live-site coverage"
```

---

### Task 3: Refine the homepage markup for cleaner hierarchy and mobile behavior

**Files:**
- Modify: `docs/index.html`
- Test: `tests/github-pages-site.sh`

**Step 1: Write the failing markup-level regression if a new structural hook is needed**

If the planned polish requires a new wrapper or grouping hook, extend `tests/github-pages-site.sh` first with one precise assertion before editing HTML. Example:

```bash
grep -q 'class="hero-copy"' "$index_path" || fail "homepage missing hero copy wrapper"
```

Only add this if the wrapper is truly needed for the CSS plan.

**Step 2: Run the test to verify the new assertion fails**

Run: `bash tests/github-pages-site.sh`
Expected: FAIL with the new missing-wrapper message.

**Step 3: Apply the minimal homepage markup changes**

Make only the smallest structural changes needed to support the approved polish direction. Likely edits:

- group hero copy and actions more deliberately if CSS needs a dedicated wrapper
- tighten trust-strip or hero-proof markup only if current structure blocks better mobile spacing
- preserve all current section anchors and the existing narrative order
- avoid introducing new sections, preview links, or alternate design flows

If a wrapper is added, it should stay simple, for example:

```html
<div class="hero-copy">
  <div class="eyebrow">Persistent Firecracker fleet operations</div>
  <div class="hero-logo">...</div>
  <p class="hero-tagline">...</p>
  <p class="hero-lede">...</p>
  <div class="hero-actions">...</div>
  <div class="hero-install">...</div>
</div>
```

**Step 4: Run the test suite to verify the structure passes**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 5: Commit the markup refinement**

```bash
git add docs/index.html tests/github-pages-site.sh
git commit -m "refactor: tighten github pages hero structure"
```

---

### Task 4: Apply subtle premium CSS refinements to the header, hero, and trust strip

**Files:**
- Modify: `docs/style.css`
- Verify: `docs/index.html`

**Step 1: Adjust spacing and hierarchy tokens first**

Refine the existing design variables rather than replacing the design system. Focus on:

- section spacing
- surface contrast
- border weight and accent restraint
- button emphasis
- headline and supporting text balance

Keep the token changes small, for example:

```css
:root {
  --surface: #151b23;
  --surface-raised: #1a212b;
  --border: rgba(123, 139, 160, 0.2);
  --shadow: 0 24px 60px rgba(0, 0, 0, 0.24);
}
```

**Step 2: Refine the sticky header for narrow screens**

Tune `.site-header`, `.site-header .container`, and `.site-nav` so the mobile state feels intentional. Prefer smaller gaps, better wrapping, and clearer row spacing over a larger structural rewrite.

**Step 3: Refine the hero composition**

Adjust `.hero`, `.hero-shell`, `.hero-layout`, `.hero-logo`, `.hero-tagline`, `.hero-lede`, `.hero-actions`, and `.hero-install` so the hero feels less dense and more balanced.

Target outcomes:

- clearer headline hierarchy
- tighter relationship between copy and CTAs
- calmer install command presentation
- less visual heaviness on smaller screens

**Step 4: Refine the trust strip and top proof surfaces**

Tune `.trust-strip`, `.trust-pill`, `.hero-proof`, and `.proof-card` so the top-of-page proof points scan more comfortably on desktop and stack more cleanly on mobile.

**Step 5: Run the shell regression suite**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 6: Start a local static server for visual verification**

Run: `python3 -m http.server 8031`
Expected: server starts successfully.

**Step 7: Manually verify the live page in a browser**

Visit: `http://localhost:8031/docs/index.html`

Manual checks:

- sticky header remains usable
- hero feels more balanced than before
- trust strip is easy to scan
- no preview or comparison flow is visible

**Step 8: Commit the top-of-page CSS polish**

```bash
git add docs/style.css
git commit -m "style: polish github pages hero and header"
```

---

### Task 5: Improve card density and section pacing across the live page

**Files:**
- Modify: `docs/style.css`
- Verify: `docs/index.html`

**Step 1: Refine shared card and section styles**

Tune the rules for:

- `.feature-card`
- `.benefit`
- `.sandbox-card`
- `.quickstart-step`
- `.faq-item`
- `.callout`

Use spacing, padding, and surface contrast changes rather than new visual effects.

**Step 2: Refine section rhythm**

Adjust `section`, `.section-title`, `.section-subtitle`, `.comparison-intro`, and `.example-intro` so large sections read with more consistent cadence and slightly more premium hierarchy.

**Step 3: Keep credibility sections practical**

Review the comparison table, architecture frame, and terminal blocks. Only make changes that improve readability and viewport fit. Do not turn them into decorative showcase elements.

**Step 4: Run the shell regression suite again**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 5: Commit the section-surface refinements**

```bash
git add docs/style.css
git commit -m "style: refine github pages section surfaces"
```

---

### Task 6: Finish the mobile pass deliberately

**Files:**
- Modify: `docs/style.css`
- Verify: `docs/index.html`
- Test: `tests/github-pages-site.sh`

**Step 1: Tighten the tablet breakpoint deliberately**

Review the existing `@media (max-width: 1040px)` rules and make them more intentional where needed, especially for:

- `.hero-layout`
- `.trust-strip .container`
- `.example-benefits`
- `.sandbox-compare`

**Step 2: Tighten the phone breakpoint deliberately**

Review the existing `@media (max-width: 760px)` rules and refine them for:

- header stacking and nav spacing
- hero shell padding
- hero typography scale
- CTA stacking or wrapping behavior
- card and step density
- terminal and comparison area viewport fit

Prefer clear, targeted overrides such as:

```css
@media (max-width: 760px) {
  .hero-actions {
    flex-direction: column;
    align-items: stretch;
  }

  .btn {
    width: 100%;
  }
}
```

Only use full-width buttons if they actually improve the live result.

**Step 3: Run the shell regression suite**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 4: Re-open the page locally and verify mobile presentation manually**

Run: `python3 -m http.server 8031`
Expected: server starts successfully.

Visit: `http://localhost:8031/docs/index.html`

Manual checks at narrow widths:

- header no longer feels cramped
- hero copy and CTAs feel balanced
- trust strip stacks cleanly
- feature cards and supporting cards do not feel overly dense
- quickstart and terminal blocks remain readable without dominating the screen

**Step 5: Commit the mobile refinements**

```bash
git add docs/style.css
git commit -m "style: improve github pages mobile layout"
```

---

### Task 7: Final verification and review

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/style.css`
- Verify: `tests/github-pages-site.sh`
- Verify: `docs/plans/2026-04-10-github-pages-subtle-polish-design.md`
- Verify: `docs/plans/2026-04-10-github-pages-subtle-polish.md`

**Step 1: Review the final diff**

Run: `git diff -- docs/index.html docs/style.css tests/github-pages-site.sh docs/plans/2026-04-10-github-pages-subtle-polish-design.md docs/plans/2026-04-10-github-pages-subtle-polish.md`
Expected: only the approved design doc, implementation plan, and subtle live-site polish changes appear.

**Step 2: Run the full regression suite one last time**

Run: `bash tests/github-pages-site.sh`
Expected: PASS with `PASS: github pages site checks`

**Step 3: Re-open the final page locally**

Run: `python3 -m http.server 8031`
Expected: server starts successfully.

Visit: `http://localhost:8031/docs/index.html`

Manual checks:

- page still reads as a serious technical product page
- top-of-page hierarchy feels more premium but restrained
- desktop and mobile both feel intentional
- no preview flow or alternate directions are present

**Step 4: Request user review before any integration action**

Share the local preview URL and summarize the refined scope of the changes.

---

### Task 8: Optional commit after user approval

**Files:**
- Stage: `docs/index.html`
- Stage: `docs/style.css`
- Stage: `tests/github-pages-site.sh`
- Stage: `docs/plans/2026-04-10-github-pages-subtle-polish-design.md`
- Stage: `docs/plans/2026-04-10-github-pages-subtle-polish.md`

**Step 1: Ask the user whether they want a final consolidating commit**

Do not create it automatically.

**Step 2: If approved, stage and commit the final result**

```bash
git add docs/index.html docs/style.css tests/github-pages-site.sh docs/plans/2026-04-10-github-pages-subtle-polish-design.md docs/plans/2026-04-10-github-pages-subtle-polish.md
git commit -m "style: subtly polish github pages site"
```

**Step 3: Do not push unless explicitly requested**

The user should review locally first.
