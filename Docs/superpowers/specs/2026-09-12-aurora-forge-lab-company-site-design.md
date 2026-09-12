# Aurora Forge Lab Company Site Design

## Goal

Create a company-level website for Aurora Forge Lab at `https://auroraforgelab.com`. The site presents Aurora Forge Lab as the parent studio behind Aurora Survival and Aurora Digest without changing either product website.

Aurora Forge Lab is the public brand. Aurora Labs LLC is the legal operator. Kenny Guo is the founder and Product Manager.

## Scope

This phase includes only the new company website, its private GitHub repository, automated tests, Cloudflare Pages deployment, and root-domain configuration.

It does not change the Aurora Survival repository or website, Zoho Mail, R2 storage, package catalogs, product binaries, or startup applications.

## Repository and Architecture

- Create a private GitHub repository named `kenny2077/aurora-forge-lab`.
- Build a dependency-free static site using semantic HTML, CSS, and minimal vanilla JavaScript.
- Keep the complete content visible without JavaScript.
- Add Node built-in contract tests; do not add a package dependency solely for testing.
- Deploy the tested static directory through GitHub Actions to a new Cloudflare Pages project named `aurora-forge-lab`.
- Serve the production site at `https://auroraforgelab.com`.
- Redirect `www.auroraforgelab.com` to the apex domain.
- Redirect the production `pages.dev` hostname to the apex domain while leaving Cloudflare deployment previews usable.

## Information Architecture

### Header

Use the Aurora mark with the company name, Aurora Forge Lab. Navigation links point to Products, Principles, Founder, and Contact. The mobile navigation is keyboard accessible and works without hiding content when JavaScript is unavailable.

### Hero

Lead with the line “Practical AI tools built for real use.” Supporting copy describes a small product studio building private, dependable, user-controlled software. The copy must not imply customers, funding, traction, certifications, or product availability beyond verified facts.

### Principles

Explain the shared product values in concise language:

- Practical utility over spectacle.
- Local or self-hosted operation where appropriate.
- Visible sources and understandable behavior.

These are product principles, not unverifiable performance claims.

### Products

Feature exactly two products.

**Aurora Survival** is the flagship product. Describe it as private, source-backed survival guidance for iPhone and iPad that is coming to the App Store. Link to `https://survival.auroraforgelab.com` and its public GitHub repository at `https://github.com/kenny2077/aurora-survival`.

**Aurora Digest** is an active, open-source, self-hosted daily learning radar for AI builders, researchers, and students. Link to `https://kenny2077.github.io/Aurora/` and its repository at `https://github.com/kenny2077/Aurora`.

Use factual product imagery and existing Aurora assets. Do not invent dashboards, testimonials, user counts, customer logos, or product metrics.

### Founder

Name Kenny Guo as founder and Product Manager. Link to `https://github.com/kenny2077`. Do not publish private biography details or use the AWS profile as a public endorsement.

### Contact

Use `mailto:hello@auroraforgelab.com` as the public company contact. The site contains no contact form.

### Legal Pages and Footer

Provide public `/privacy/` and `/support/` pages. The privacy page states that the company site uses no analytics, advertising trackers, cookies, accounts, or form collection. It must distinguish the company website policy from separate product behavior and link to product-specific information where appropriate.

The support page provides the company contact address and direct links to the two product destinations.

The footer includes the exact disclosure: “Aurora Forge Lab is operated by Aurora Labs LLC.”

## Visual Direction

The company site inherits the strongest parts of Aurora Survival's visual language without copying its field-manual composition.

- Deep navy is the primary atmospheric surface.
- Cyan and teal aurora light identify the Aurora family.
- Amber is a restrained signal color for small highlights and focus states.
- Warm off-white supports longer reading sections.
- System fonts keep the site fast and avoid external font requests.
- Square controls, fine rules, and crisp product imagery keep the presentation pragmatic.

The Aurora mark becomes the studio-level identity. Product marks remain attached to their individual products.

## Motion and Transitions

Use one restrained motion system:

- A slow cursor-responsive light field in the hero on fine pointers only.
- Soft section reveals as content enters the viewport.
- Small depth response on product imagery.
- Tonal transition bands between navy and off-white sections.
- Clear hover and keyboard-focus feedback.

Motion must not replace the system cursor, hijack scrolling, delay access to content, imitate loading, or create continuous high-frequency movement. Touch devices skip pointer effects. `prefers-reduced-motion: reduce` disables decorative animation, depth, and reveal transforms.

## Metadata and Static Assets

Include:

- Canonical URLs for the homepage, privacy page, and support page.
- Open Graph and basic social-preview metadata.
- Local favicon and social-preview image.
- `robots.txt` and `sitemap.xml` using the apex domain.
- A static `_headers` file with appropriate security and caching headers.
- Intrinsic image dimensions and useful alternative text.

The site uses no external fonts, analytics, cookies, embedded third-party widgets, or runtime asset hotlinks.

## Testing

Node contract tests verify:

- Semantic landmarks and heading hierarchy.
- Exact company identity, founder, legal disclosure, product status, contact address, and URLs.
- Safe external-link attributes.
- Canonical and social metadata.
- Privacy and support page presence and content.
- Local asset resolution and intrinsic image dimensions.
- Sitemap, robots, and security-header configuration.
- JavaScript progressive enhancement and reduced-motion CSS.

Browser verification covers desktop and narrow mobile layouts, navigation, overflow, keyboard focus, no-JavaScript visibility, transition behavior, and reduced-motion rendering.

## Release Verification

Before release:

1. Run all company-site contract tests and whitespace checks.
2. Verify the production deployment completes through GitHub Actions.
3. Confirm `https://auroraforgelab.com` serves the new company site with a valid TLS certificate.
4. Confirm `https://www.auroraforgelab.com` redirects to the apex domain.
5. Confirm the production `pages.dev` hostname redirects to the apex domain.
6. Confirm both product links and `mailto:hello@auroraforgelab.com` are correct.
7. Confirm `https://survival.auroraforgelab.com` remains unchanged and available.

## Constraints

- The repository remains private.
- The implementation stays dependency-free.
- Aurora Survival remains the flagship but does not dominate the company identity.
- Only verified product and company facts appear in public copy.
- The company site does not submit any startup, credit, or partner application.
