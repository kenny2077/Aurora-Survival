---
name: Aurora Survival
description: Kinetic offline field software grounded in physical proof and editorial restraint.
colors:
  spruce: "#143f35"
  flare: "#ff7a4d"
  lamp: "#ffd9a3"
  white: "#f5fbf7"
  mist: "#c3d4cc"
  faint: "#8aa298"
  night: "#061311"
  night-2: "#0b1f1b"
  deep: "#030a09"
  aurora-cyan: "#15d9c5"
  aurora-blue: "#3478f6"
  aurora-violet: "#7546ff"
typography:
  display:
    fontFamily: "Archivo (self-hosted variable woff2, OFL), Arial Narrow, sans-serif"
    fontSize: "clamp(3.2rem, min(8.2vw, 12.5vh), 7.6rem)"
    fontWeight: 800
    fontStretch: "78%"
    lineHeight: 0.93
    letterSpacing: "-0.015em"
  headline:
    fontFamily: "Archivo (self-hosted variable woff2, OFL), Arial Narrow, sans-serif"
    fontSize: "clamp(2.6rem, 6.6vw, 6.4rem)"
    fontWeight: 800
    fontStretch: "78%"
    lineHeight: 0.93
    letterSpacing: "-0.015em"
  statement:
    fontFamily: "Archivo (self-hosted variable woff2, OFL), Arial Narrow, sans-serif"
    fontSize: "clamp(2.15rem, min(5vw, 7.6vh), 5.4rem)"
    fontWeight: 750
    fontStretch: "80%"
    lineHeight: 1.02
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Helvetica Neue, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.78rem"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  square: "0"
  icon: "9px"
  device: "42px"
spacing:
  xs: "6px"
  sm: "14px"
  md: "28px"
  lg: "56px"
  section: "clamp(96px, 14vh, 160px)"
  gutter: "max(clamp(20px, 5vw, 72px), calc((100% - 1240px) / 2))"
components:
  button-primary:
    backgroundColor: "{colors.aurora-cyan}"
    textColor: "{colors.night}"
    rounded: "{rounded.square}"
    padding: "13px 20px"
    height: "48px"
  ask-card:
    backgroundColor: "rgba(6, 19, 17, 0.74)"
    textColor: "{colors.white}"
    rounded: "{rounded.square}"
    padding: "18px 20px"
  tool-card:
    backgroundColor: "{colors.night-2}"
    textColor: "{colors.white}"
    rounded: "{rounded.square}"
    padding: "clamp(28px, 3.4vw, 48px)"
---

# Design System: Aurora Survival

## Overview

**Creative North Star: "Kinetic Field Signal"**

Aurora feels like dependable field equipment switched on under a night sky. The field-manual foundation stays direct, legible, and evidence-led; a pixel aurora and a headlamp beam supply motion, depth, and a memorable sense of readiness.

The page proves the product instead of describing it. The hero carries a working sample of the reviewed manual, the stage shows the real iPhone build, and every claim traces to repository evidence. There are no generic AI particles, fake dashboards, decorative chat bubbles, or invented claims.

Aurora Survival remains the flagship within the Aurora product family. A quiet header label establishes the relationship, while the footer introduces Aurora Newsletter and the Aurora Forge Lab studio without competing with Survival's primary story.

**Key Characteristics:**

- One signature motif, the Headlamp Pixel Field, reused at every scale.
- A four-beat scroll story with exactly one motion idea per beat.
- A live, offline proof of the manual above the fold.
- Huge condensed display type against calm system body text.
- Square controls, thin rules, viewfinder corner ticks, and generous space.
- Motion that is scrubbed by scroll or driven by the pointer, and fully static on request.

## The Headlamp Pixel Field

A low-resolution buffer is upscaled with nearest-neighbour sampling and 1px seams, so light reads as pixels. A fine pointer acts as a headlamp: cells it passes warm to Lamp and cool back within a second. Hidden contour cells answer in Aurora Cyan, a quiet nod to offline maps.

It appears four times: the hero sky (dithered aurora curtains, far ridge, pine line), the 5x7 numerals on the field-kit cards, the topographic panel on the Maps card, and the AURORA wordmark revealed under the footer. The crisp pixel wildlife silhouette on the Species card belongs to the same family.

Fields are decorative (`aria-hidden`), redraw only while dirty or warm, pause offscreen, and cap device pixel ratio at 2. Touch has no hover, so a tap lights the field where it lands. Nothing reacts under reduced motion.

## Colors

One continuous night palette carries every chapter, from the hero through the field kit to the footer, so scrolling never flashes to a light surface. Green-gray text steps keep reading calm.

### Primary

- **Deep Spruce:** Numeral pixels and dark product ground.

### Secondary

- **Aurora Cyan:** Primary actions, kickers, and lit statement words on night.
- **Aurora Blue and Violet:** Supporting light inside pixel fields and the Ask flow only.

### Light and signal

- **Lamp:** The headlamp warmth in pixel fields and the availability marker.
- **Flare:** Focus outlines and warnings on night surfaces.

### Neutral

- **Night and Deep:** Cinematic surfaces and the footer beneath the page.
- **Night 2:** The raised surface of the field-kit cards.
- **White, Mist, and Faint:** Text steps on night.
- **Dark lines:** Translucent rules, dividers, and disclosure structure.

**The Aurora Field Rule.** Saturated teal, blue, and violet move only inside generated light on dark surfaces. Reading surfaces remain restrained, and saturated color never replaces product evidence.

## Typography

Archivo, a variable OFL face, is self-hosted from `Website/assets/fonts` and used only for display, headline, statement, and card titles at weight 750–800 and 78–80% width. System sans carries body copy so reading stays native to Apple devices. System monospace is limited to measured facts, device metadata, source citations, status signals, and kickers.

### Hierarchy

- **Display:** Condensed, heavy, balanced, sized by both viewport width and height so the hero fits short screens.
- **Headline:** Compact section arguments that end with a period.
- **Statement:** One paragraph that lights word by word.
- **Body:** Relaxed 1.65 line height with every measure capped in `ch`.
- **Label:** Small monospace only where the content behaves like data.

**The Plain Language Rule.** Let scale and weight supply authority; copy stays concrete and never performs futurism.

## Layout

The site uses full-width chapters aligned to a 1240px measure through one gutter token, framed by four fixed viewfinder corners. The scroll story is: hero (100svh, sky and Ask card) → pinned statement (220vh, words light with scroll) → real-device stage → night field kit (four sticky cards that stack and recede) → founder and FAQ → footer revealed from beneath the page. Sections never overlap with negative margins.

The hero anchors copy bottom-left with the Ask card on the right; at 1100px the card flows beneath the copy. At 800px the navigation becomes a controlled menu and splits stack. At 760px the tool cards stop stacking and become a plain list. At 520px actions go full width. Nothing scrolls horizontally at 390px.

Motion is progressive enhancement: the complete page, including every manual answer, remains readable without JavaScript, and becomes static under reduced-motion preferences. One load moment exists: the aurora ignites over 1.4 seconds. Everything else is scrubbed by scroll from a single request-animation-frame loop that only works when scroll changes or a field is warm: aurora drift, hero parallax and fade, statement lighting, device rise, card stacking, the species scan line, and the footer reveal. On fine pointers, the headlamp warms pixel fields, a soft light follows the pointer over Ask questions and tool cards, and the physical device tilts below five degrees. Touch gets tap-to-light instead of hover; reduced-motion preferences disable pointer response entirely. No motion may replace the system cursor, scroll-jack, flash, delay content access, or imitate a loading state.

## Elevation & Depth

Depth comes from tonal layering, the stacked cards receding (scale to 0.95, brightness to 0.9), the page lifting off the footer, and the physical device shadow. There are no glows on buttons or cards.

**The Physical Evidence Rule.** Depth supports real product evidence; it never turns ordinary content into floating UI chrome.

## Shapes

Content frames and controls remain square. Thin rules and inset 1px lines establish structure, and viewfinder corner ticks mark the frame and the Ask card. The app icon and iPhone silhouette alone retain their factual rounded shapes, with the device using its native 42px silhouette radius.

## Components

### Navigation

The fixed header pairs the production icon and name with a small “An Aurora Forge Lab product” family label, numbered section anchors, and a GitHub link to the Aurora Survival repository. It turns to night glass after the first scroll. On narrow screens a labelled Menu toggle opens full-width ruled rows and closes with Escape.

### Hero and Ask the field manual

The hero combines the product promise, the real availability state (“Coming to the App Store”), and a field signal over the pixel sky. The Ask card offers four questions as a native radio group; each answer is the exact steps, warning, and primary-source organizations of a reviewed lesson from `Resources/Knowledge/survival_knowledge_source.json`, enforced by the site tests. CSS `:has()` shows the chosen answer and replays a short stagger; without `:has()` or JavaScript, every answer stays visible. The card states that it is an educational aid.

### Statement

One sentence-level argument about why Aurora exists, lit word by word as the reader scrolls; the payoff phrase lights in Aurora Cyan. Under reduced motion it is unpinned and fully lit.

### Product Stage

A dark split surface pairs physical-build facts with the native-resolution iPhone capture, which rises into place with scroll and tilts slightly under a fine pointer.

### Field Kit

Four sticky cards for Ask, Manual, Maps, and Species ID, each with a pixel numeral, one declarative title, one paragraph, fact chips, an honest limitation note, and a dark visual: the Ask flow, the manual chapter index, the topographic pixel field, and the pixel wildlife scanner. The Species card links to the public BioCLIP repository and never pretends to be a live interface.

### Founder Contact

The founder section has one “Contact Aurora” disclosure. Email and GitHub remain hidden until requested, then appear as two clear, keyboard-accessible choices without JavaScript.

### Product Family Footer

The footer sits beneath the page and is revealed as the page lifts away. It quietly links to Aurora Newsletter with its local icon and name, to Aurora Forge Lab as “An Aurora Forge Lab product”, and ends with the warmable AURORA pixel wordmark. It stacks without overflow on narrow screens.

## Do's and Don'ts

### Do

- Use real app captures and real manual passages whenever describing product behavior.
- Keep claims traceable to product documentation or repository evidence.
- Reuse the Headlamp Pixel Field rather than adding new decorative motifs.
- Preserve keyboard focus, mobile readability, no-JavaScript content, and reduced motion.
- Keep the BioCLIP, founder GitHub, Aurora Newsletter, and Aurora Forge Lab links descriptive and safe.

### Don't

- Don't add particles, glowing orbs, fake dashboards, testimonials, customer logos, metrics strips, or decorative chat bubbles.
- Don't turn sections into interchangeable rounded cards or oversized pills.
- Don't load fonts, scripts, trackers, or any other asset from a third party at runtime.
- Don't add fade-in-on-scroll to every block or idle looping animation.
- Don't publish the founder's name in page copy; use contact and profile links.
- Don't imply the App Store release is currently available.
