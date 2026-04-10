# Design: GitHub Pages subtle polish and mobile refinement

**Date:** 2026-04-10
**Status:** Approved

## Problem

The live GitHub Pages site has already been corrected back to a single refined direction,
but it still has room for a final polish pass. The user wants the page to feel a bit more
premium while preserving the current technical-product tone and avoiding another broad
visual experiment.

The page also needs a more deliberate mobile presentation. It is already responsive, but
some areas can still feel dense, compressed, or visually heavy on smaller screens.

## Decision

Keep the current refined landing page structure and apply a subtle, single-direction polish
pass. Do not redesign the site, add preview flows, or introduce additional public design
variants.

The selected tone is **slightly premium**: more finished and composed than the current
state, but still restrained, technical, and credibility-first.

## Design

### Positioning

The page should continue to read as a serious infrastructure product page. This pass is not
about adding more content or more visual drama. It is about making the existing design feel
more deliberate through better hierarchy, spacing, typography, and mobile composition.

The visual result should feel calmer, cleaner, and more confident.

### Scope

This pass should focus on refinement of the existing live page:

- improve hierarchy and pacing without changing the overall structure
- make the hero feel better balanced on desktop and mobile
- make the sticky header feel cleaner on narrow screens
- improve scanability of the trust strip and card-based sections
- reduce visual heaviness where surfaces, borders, or spacing feel crowded

This pass should not:

- add a public preview page
- introduce multiple design directions into the live site
- perform a major content rewrite
- add flashy effects or marketing-style treatments

### Selected direction

The approved direction is a **slightly premium refinement** of the current refined design.

Core traits:

- restrained but clearer typographic hierarchy
- more intentional section spacing
- cleaner CTA grouping and emphasis
- subtle surface and border tuning for a more finished feel
- stronger mobile layout discipline

### Information architecture

Keep the current section order and content model intact. This work is a polish pass, not an
information architecture rewrite.

Expected section flow remains:

1. sticky header
2. hero
3. trust strip
4. features and product sections
5. credibility and architecture sections
6. quick start and supporting sections
7. footer

Small structural adjustments are acceptable only if they improve scan order or mobile
presentation without changing the overall narrative.

### Header and navigation

Keep the sticky header, but make it feel more intentional at smaller widths.

Goals:

- reduce cramped spacing in narrow layouts
- ensure link wrapping or stacking feels designed rather than accidental
- preserve fast access to major sections
- maintain the current low-JavaScript static-site approach

If a mobile-specific layout treatment is needed, it should remain minimal and static-site
friendly.

### Hero

The hero is the highest-value target for subtle polish.

Goals:

- improve the balance between headline, supporting copy, and action area
- refine CTA grouping so the primary action feels clear without overpowering the page
- reduce any oversized or dense presentation on mobile
- keep the tone practical and technical rather than promotional

The hero should feel slightly more premium through composition, not through decorative
effects.

### Trust strip and section surfaces

The trust strip and section cards should become easier to scan, especially on phones.

Goals:

- improve spacing rhythm between trust items
- make card density more comfortable on smaller screens
- tune borders, surface contrast, and internal padding so sections feel composed rather than
  boxed-in
- preserve the current refined dark technical tone

### Mobile refinement

Mobile presentation is a first-class requirement for this pass.

Key mobile outcomes:

- cleaner vertical rhythm between sections
- no cramped header or CTA area
- feature and supporting cards stack cleanly
- text blocks keep readable line length and spacing
- comparison-style content and command/code surfaces do not dominate the viewport

The mobile experience should feel intentionally designed, not merely reduced from desktop.

### Visual system

Preserve the current refined design language and improve its finish rather than changing its
identity.

Planned areas of refinement:

- heading and body scale relationships
- section spacing tokens
- surface contrast and border weight
- button emphasis and grouping
- small-radius, shadow, or highlight tuning only where it improves clarity

Any premium cues should remain subtle and functional.

### Technical constraints

- keep the site static: HTML and CSS only unless minimal JavaScript is clearly necessary
- preserve GitHub Pages compatibility
- keep changes limited to the live single-direction site
- avoid reintroducing preview-specific public artifacts
- preserve and extend responsive behavior rather than replacing it wholesale

### Files expected to change

| File | Change |
|------|--------|
| `docs/index.html` | Small structural and content-grouping refinements where needed for header, hero, and mobile behavior |
| `docs/style.css` | Subtle hierarchy, spacing, surface, CTA, and responsive refinements |
| `tests/github-pages-site.sh` | Extend regression coverage only if needed for live-site constraints |

### Risks

- The polish pass could drift into another redesign rather than a refinement.
- Mobile fixes could overcorrect and weaken the desktop presentation.
- Additional visual treatment could reduce the credibility-first tone.

### Mitigations

- Keep the current structure and content mostly intact.
- Treat mobile improvements as layout and spacing refinements first.
- Prefer the smallest CSS and markup changes that materially improve composition.
- Preserve the single refined live direction and keep tests aligned with that constraint.
