---
name: Aurora Survival
description: Kinetic offline field software grounded in physical proof and editorial restraint.
colors:
  canvas: "#dfe5df"
  paper: "#f7f9f5"
  ink: "#10201a"
  muted: "#5b6962"
  line: "#c5cec6"
  line-strong: "#9eaaa1"
  spruce: "#143f35"
  teal: "#087b76"
  signal: "#a6300f"
  white: "#f5fbf7"
  night: "#061311"
  aurora-cyan: "#15d9c5"
  aurora-blue: "#3478f6"
  aurora-violet: "#7546ff"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Display, Helvetica Neue, sans-serif"
    fontSize: "clamp(3.35rem, 7.5vw, 5.8rem)"
    fontWeight: 780
    lineHeight: 0.91
    letterSpacing: "-0.04em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Display, Helvetica Neue, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1.4
rounded:
  square: "0"
  icon: "10px"
  device: "42px"
spacing:
  xs: "10px"
  sm: "18px"
  md: "28px"
  lg: "54px"
  section: "clamp(82px, 10vw, 124px)"
motion:
  easing: "cubic-bezier(0.22, 1, 0.36, 1)"
  revealDuration: "700ms"
  auroraDuration: "18s"
  scanDuration: "7.5s"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.square}"
    padding: "13px 19px"
    height: "48px"
  hero-button:
    backgroundColor: "{colors.aurora-cyan}"
    textColor: "{colors.night}"
    rounded: "{rounded.square}"
    padding: "13px 19px"
    height: "48px"
---

# Design System: Aurora Survival

## Overview

**Creative North Star: "Kinetic Field Signal"**

Aurora feels like dependable field equipment activated under a moving night sky. The field-manual foundation remains direct, legible, and evidence-led; controlled aurora light supplies motion, depth, and a memorable sense of readiness.

The system is a mature SaaS presentation grounded in an outdoor product. It uses real product evidence, strong section pacing, and restrained atmospheric effects without generic AI particles, fake dashboards, decorative chat bubbles, or invented claims.

**Key Characteristics:**

- A cinematic dark first viewport with slow teal, blue, and violet light.
- Physical-device proof as the primary product material.
- Warm paper reading sections separated by decisive dark product moments.
- Square controls, thin rules, compact measurement labels, and generous space.
- One coordinated motion language that becomes completely static when requested.

## Colors

Warm paper and green-gray neutrals keep reading calm. Night and spruce surfaces carry product proof, privacy, and open-source material. Signal rust remains reserved for visible focus.

**The Aurora Field Rule.** Saturated teal, blue, and violet may move across dark atmospheric surfaces. Reading surfaces remain restrained, and saturated color never replaces product evidence.

## Typography

System sans is used for display and body copy to keep the static site fast and native to Apple-device audiences. System monospace is limited to measured facts, device metadata, status signals, and technical captions.

- **Display:** Heavy, tightly tracked, balanced, and capped below 6rem.
- **Headline:** Compact section arguments with more space above than below.
- **Body:** Relaxed 1.65 line height and limited measure.
- **Measurement:** Small monospace only where the content behaves like data.

Typography supplies authority; copy stays concrete and never performs futurism.

## Layout and Rhythm

The site occupies a centered 1180px canvas. The dark hero establishes the world, the real-device stage overlaps its lower edge, and quieter paper sections alternate with dense product moments. Product, species, and privacy sections use asymmetric splits rather than interchangeable cards. At 800px the navigation becomes a controlled menu and every split stacks. At 520px imagery and scanner geometry contract while actions remain readable.

## Motion

Motion is progressive enhancement: the complete page remains visible without JavaScript and becomes static under reduced-motion preferences.

- `aurora-drift` moves two low-opacity light fields over 18–24 seconds.
- `signal-pulse` gives the privacy/offline status a slow breathing cadence.
- `scan-pass` supplies a seven-second measurement sweep in the species section.
- Section reveals use a short rise, blur resolution, and exponential ease-out once per element.
- Fine-pointer devices may tilt the physical iPhone capture by no more than five degrees; touch and reduced-motion contexts receive no tilt.

No motion may scroll-jack, flash, delay content access, or imitate a loading state.

## Depth and Shapes

Content frames and controls remain square. The app icon and iPhone silhouette keep their factual rounded shapes. Shadows carry visible vertical offset and soft blur, and are reserved for the device and large dark product fields rather than generic cards.

## Components

### Navigation

The sticky header pairs the production icon and name with plain product anchors, the founder GitHub profile, and a truthful App Store status. Desktop links respond with color and a fine underline; mobile links become full-width ruled rows.

### Hero

The hero combines the product promise, real availability state, and a subtle field signal over slow aurora light. The headline and action remain visually dominant at every viewport.

### Product Stage

A dark split surface pairs physical-build facts with the native-resolution iPhone capture. Grid and light treatments support the real screen instead of replacing it.

### Species Section

The scanner motif uses verified offline-species count, measurement rules, and one slow scan line. It links directly to the public BioCLIP repository and never pretends to be a live product interface.

### Privacy Art

The high-resolution aurora photograph is displayed at its natural aspect and may receive only subtle hover scale on fine pointers. It must never be stretched, softened, or replaced by a low-resolution crop.

## Do and Don't

### Do

- Use real app captures whenever describing product behavior.
- Keep claims traceable to product documentation or repository evidence.
- Use light, motion, spacing, and scale to lead attention.
- Preserve keyboard focus, mobile readability, no-JavaScript content, and reduced motion.
- Keep the BioCLIP and founder GitHub links descriptive and safe.

### Don't

- Don't add particles, glowing orbs, fake dashboards, testimonials, customer logos, or decorative chat bubbles.
- Don't turn sections into interchangeable rounded cards or oversized pills.
- Don't introduce web fonts, trackers, or third-party runtime assets.
- Don't publish the founder's name in page copy; use contact and profile links.
- Don't imply the App Store release is currently available.
