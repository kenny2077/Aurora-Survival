---
name: Aurora Survival
description: Pragmatic offline field software presented with physical proof and editorial restraint.
colors:
  canvas: "#e8ece7"
  paper: "#fafbf8"
  ink: "#14221d"
  muted: "#637069"
  line: "#cad2cb"
  line-strong: "#aab6ad"
  spruce: "#173f35"
  teal: "#087b76"
  signal: "#a6300f"
  white: "#f7fbf8"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Display, Helvetica Neue, sans-serif"
    fontSize: "clamp(3.2rem, 7.1vw, 5.6rem)"
    fontWeight: 700
    lineHeight: 0.92
    letterSpacing: "-0.04em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Display, Helvetica Neue, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1.1
rounded:
  square: "0"
  icon: "10px"
  device: "42px"
spacing:
  xs: "10px"
  sm: "18px"
  md: "28px"
  lg: "48px"
  section: "clamp(68px, 9vw, 104px)"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "12px 17px"
    height: "46px"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "12px 17px"
    height: "46px"
---

# Design System: Aurora Survival

## Overview

**Creative North Star: "The Field Manual"**

Aurora feels like dependable equipment laid out on a clean work surface: direct, legible, and built to be trusted. Its maturity comes from measured spacing, blunt typography, thin rules, real product evidence, and a single controlled atmospheric moment rather than decorative technology imagery.

The system is pragmatic SaaS presentation grounded in an outdoor product. It avoids glossy AI tropes, fake interfaces, glowing ornaments, pill-heavy layouts, and motion without function.

**Key Characteristics:**

- Narrow ruled canvas with generous breathing room.
- Physical-device proof as the primary product material.
- Deep spruce and warm paper, with aurora color reserved for the real identity asset.
- Square, decisive controls and compact monospaced utility copy.

## Colors

Warm paper and quiet green-gray neutrals establish calm; spruce carries privacy and field reliability, while signal rust is reserved for focus visibility.

### Primary

- **Deep Spruce:** Used for privacy surfaces, selections, and confident hover states.

### Secondary

- **Field Teal:** A restrained supporting accent. The production icon remains the richest teal/indigo moment.

### Neutral

- **Warm Canvas:** The outer page ground.
- **Clean Paper:** The centered content surface.
- **Graphite Ink:** Primary text and action fill.
- **Weathered Gray:** Supporting copy.
- **Fine Rule / Strong Rule:** Structural dividers and list boundaries.

**The Aurora Reserve Rule.** Saturated aurora color belongs mainly to the production mark and real product imagery; it is not a generic decoration.

## Typography

**Display Font:** System sans with SF Pro Display and Helvetica Neue fallbacks  
**Body Font:** System sans  
**Label/Mono Font:** System monospace with SFMono and Menlo fallbacks

**Character:** Large sans headings are compressed, sturdy, and plainspoken. Monospaced labels provide technical precision without turning body copy into a terminal theme.

### Hierarchy

- **Display:** Heavy, tightly tracked, near-solid line spacing; reserved for the hero.
- **Headline:** Large and compact; used for section arguments.
- **Title:** Strong one-line labels for tools and FAQ questions.
- **Body:** Regular-weight, relaxed line spacing, and limited measure for easy reading.
- **Label:** Small, bold monospace for navigation, actions, captions, and measured facts.

**The Plain Language Rule.** Typography supplies authority; copy stays concrete and never performs futurism.

## Layout

The site occupies a centered 1120px canvas with fine vertical rules. Sections use generous vertical rhythm and grid relationships rather than card stacks. The hero centers its argument; product and privacy sections use deliberate split compositions. At 800px, navigation becomes a controlled menu and all primary splits stack. At 520px, proof metrics become a single column and feature rows simplify.

## Elevation & Depth

The system is flat by default. Borders, tonal fields, and overlapping scale create structure. The physical iPhone capture alone receives a substantial shadow because it represents a real object above the dark stage; the sticky header uses a restrained translucent blur for continuity while scrolling.

**The Physical Depth Rule.** Shadow belongs to the device proof, not to generic content containers.

## Shapes

Controls, sections, lists, and content frames use square edges. The rounded app icon and iPhone silhouette are factual product shapes and remain the exceptions. Thin one-pixel rules organize the page without soft card chrome.

## Components

### Buttons

- **Shape:** Rectangular with square corners and a one-pixel graphite border.
- **Primary:** Graphite fill with warm-white text; spruce on hover.
- **Secondary:** Transparent paper fill with graphite text.
- **Hover / Focus:** A two-pixel lift on hover, reset on active, and a three-pixel rust focus outline with four-pixel offset.

### Cards / Containers

- **Corner Style:** Square for content surfaces; the physical device keeps its native rounded silhouette.
- **Background:** Paper for reading, spruce or near-black green for product and privacy proof.
- **Shadow Strategy:** No generic card shadows.
- **Border:** Thin neutral rules or translucent white rules on dark surfaces.

### Navigation

The sticky header pairs the production icon and name with compact monospaced links. Desktop links use an underline response; mobile links become full-width ruled rows, with the App Store status retained as the strongest action.

### Product Stage

A dark, square-edged split field pairs compact factual copy with one tall real-device capture. Atmospheric color is subtle and subordinate to the screenshot.

## Do's and Don'ts

### Do:

- **Do** use real app captures whenever describing product behavior.
- **Do** keep claims traceable to product documentation or repository evidence.
- **Do** use whitespace, rules, and scale to create hierarchy.
- **Do** retain visible focus and reduced-motion behavior.

### Don't:

- **Don't** add glowing orbs, particle fields, fake dashboards, or decorative chat bubbles.
- **Don't** turn sections into interchangeable rounded cards or oversized pills.
- **Don't** introduce web fonts or third-party runtime assets without a specific need.
- **Don't** publish founder identity in page copy; use the Aurora contact link.
