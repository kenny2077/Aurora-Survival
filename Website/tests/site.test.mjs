import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const websiteRoot = resolve(import.meta.dirname, "..");
const indexPath = resolve(websiteRoot, "index.html");
const stylesPath = resolve(websiteRoot, "styles.css");
const scriptPath = resolve(websiteRoot, "script.js");
const designSpecPath = resolve(websiteRoot, "..", "Docs", "superpowers", "specs", "2026-09-10-aurora-kinetic-field-refresh-design.md");
const designSystemPath = resolve(websiteRoot, "..", "DESIGN.md");
const deploymentWorkflowPath = resolve(websiteRoot, "..", ".github", "workflows", "pages-deployment.yml");

function readRequired(path) {
  assert.ok(existsSync(path), `required file is missing: ${path}`);
  return readFileSync(path, "utf8");
}

test("the public page exposes the approved semantic journey", () => {
  const html = readRequired(indexPath);

  for (const landmark of ["<header", "<nav", "<main", "<footer"]) {
    assert.ok(html.includes(landmark), `missing ${landmark} landmark`);
  }

  assert.match(html, /href="#main-content"[^>]*>Skip to content</);
  assert.match(html, /class="nav-toggle"[^>]*aria-label="Toggle navigation menu"/);
  assert.match(html, /<h1[^>]*>\s*Survival knowledge that stays with you\./);
  assert.match(html, /Coming to the App Store/);
  assert.match(html, /mailto:guokenny7@gmail\.com/);
  assert.match(html, /founder-led/i);
  assert.match(html, /class="button button-primary"[^>]*href="mailto:guokenny7@gmail\.com/);
  assert.match(html, /class="availability-label">Coming to the App Store<\/span>/);
  assert.match(html, /How is Aurora’s content verified\?/);
  assert.match(html, /source metadata[^<]*signed before activation[^<]*physical iPhone 13/i);
  assert.match(html, /1,050/);
  assert.match(html, /504/);
});

test("the product overview is removed and the species visual uses crisp pixel wildlife art", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.doesNotMatch(html, /href="#product"/);
  assert.doesNotMatch(html, /class="product-section"|class="feature-list"/);
  assert.doesNotMatch(css, /\.product-section|\.feature-list/);
  assert.doesNotMatch(html, /class="species-mark"/);
  assert.match(html, /<svg class="species-pixel-art"[^>]*shape-rendering="crispEdges"/);
  assert.match(html, /class="pixel-animal"/);
});

test("founder contact methods stay hidden inside one accessible disclosure", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);
  const contact = html.match(/<details class="contact-menu">([\s\S]*?)<\/details>/)?.[1] ?? "";

  assert.match(contact, /<summary>Contact Aurora <span class="contact-toggle" aria-hidden="true"><\/span><\/summary>/);
  assert.match(contact, /href="mailto:guokenny7@gmail\.com\?subject=Aurora%20Survival"[^>]*>Email/);
  assert.match(
    contact,
    /href="https:\/\/github\.com\/kenny2077"[^>]*target="_blank"[^>]*rel="noopener noreferrer"[^>]*>GitHub/,
  );
  assert.doesNotMatch(html, /View the founder’s GitHub|class="contact-email"|class="story-actions"/);
  assert.match(css, /\.contact-menu\s*\{/);
  assert.match(css, /\.contact-options\s*\{/);
  assert.match(css, /\.contact-toggle::before/);
  assert.match(css, /\.contact-toggle::after/);
});

test("the kinetic field journey exposes safe open-source and founder links", () => {
  const html = readRequired(indexPath);

  assert.match(html, /class="hero-signal"/);
  assert.match(html, /id="open-source"/);
  assert.match(html, /class="species-section[^"]*"/);
  assert.match(
    html,
    /href="https:\/\/github\.com\/kenny2077\/aurora-species-BioCLIP"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.match(
    html,
    /href="https:\/\/github\.com\/kenny2077"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.ok((html.match(/data-reveal/g) ?? []).length >= 6, "expected reveal hooks across the page");
  assert.match(html, /aria-label="Aurora Survival on GitHub"/);
});

test("Aurora Survival remains primary while the header and footer identify the product family", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.match(html, /class="brand-family">An Aurora product<\/span>/);
  assert.match(html, /class="footer-family"/);
  assert.match(html, /Also from Aurora:/);
  assert.match(html, /Aurora Digest/);
  assert.match(html, /A self-hosted daily learning radar for AI builders\./);
  assert.match(
    html,
    /href="https:\/\/kenny2077\.github\.io\/Aurora\/"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.match(
    html,
    /href="https:\/\/github\.com\/kenny2077\/Aurora"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.doesNotMatch(html, /<a[^>]*href="#(?:digest|products)"/);
  assert.match(css, /\.footer-family\s*\{/);
  assert.match(css, /@media\s*\(max-width:\s*800px\)[\s\S]*\.site-footer\s*\{[^}]*grid-template-columns:\s*1fr/s);
});

test("the page avoids rejected brands and unsupported claims", () => {
  const html = readRequired(indexPath);
  const visibleCopy = html.replace(/<[^>]+>/g, " ");

  assert.doesNotMatch(visibleCopy, /Aurora|Aurora Labs|Aurora LLC/i);
  assert.doesNotMatch(visibleCopy, /download now|available now|customers love|trusted by/i);
  assert.doesNotMatch(visibleCopy, /Built by Kenny Guo/i);
  assert.doesNotMatch(visibleCopy, /No account required/i);
  assert.doesNotMatch(visibleCopy, /Lite model targets iPhone 13-class/i);
});

test("all local page assets resolve and images carry intrinsic dimensions and alt text", () => {
  const html = readRequired(indexPath);
  const localReferences = [...html.matchAll(/(?:src|href)="(?!#|mailto:|https?:)([^"?]+)(?:\?[^\"]*)?"/g)]
    .map((match) => match[1]);

  assert.ok(localReferences.length >= 3, "expected local CSS, JavaScript, and image assets");
  for (const reference of localReferences) {
    const path = resolve(websiteRoot, reference.replace(/^\//, ""));
    assert.ok(existsSync(path), `broken local reference: ${reference}`);
    assert.ok(statSync(path).size > 0, `empty local asset: ${reference}`);
  }

  const images = [...html.matchAll(/<img\b[^>]*>/g)].map((match) => match[0]);
  assert.ok(images.length >= 2, "expected the brand icon and a real iPhone app capture");
  for (const image of images) {
    assert.match(image, /alt="[^"]+"/, `image needs meaningful alt text: ${image}`);
    assert.match(image, /width="\d+"/, `image needs intrinsic width: ${image}`);
    assert.match(image, /height="\d+"/, `image needs intrinsic height: ${image}`);
  }

  assert.ok(statSync(resolve(websiteRoot, "assets", "aurora-icon.webp")).size < 250_000, "brand icon should be web-sized");
});

test("the page omits the redundant privacy, closing availability, and header status areas", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.doesNotMatch(html, /href="#privacy"/);
  assert.doesNotMatch(html, /class="privacy-section"/);
  assert.doesNotMatch(html, /class="availability-section"/);
  assert.doesNotMatch(html, /class="nav-status"/);
  assert.doesNotMatch(css, /\.privacy-section|\.privacy-copy|\.privacy-art|\.availability-section|\.nav-status/);
});

test("the stylesheet preserves focus, reduced motion, and narrow-screen layouts", () => {
  const css = readRequired(stylesPath);

  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /@media[^\{]*max-width/);
  assert.match(css, /overflow-wrap/);
  assert.match(css, /img\s*\{[^}]*height:\s*auto/s);
  assert.match(css, /section\[id\]\s*\{[^}]*scroll-margin-top:\s*76px/s);
  assert.doesNotMatch(css, /0\.6[69]rem/);
  assert.match(css, /\.contact-options\s+small\s*\{[^}]*0\.72rem/s);
  assert.match(css, /@media\s*\(max-width:\s*340px\)/);
  assert.match(css, /@keyframes\s+aurora-drift/);
  assert.match(css, /@keyframes\s+signal-pulse/);
  assert.match(css, /@keyframes\s+scan-pass/);
  assert.match(css, /\.species-section\s*\{/);
  assert.match(css, /\.motion-ready\s+\[data-reveal\]/);
  assert.match(css, /@media\s*\(hover:\s*hover\)\s*and\s*\(pointer:\s*fine\)/);
  assert.match(css, /prefers-reduced-motion:\s*reduce[\s\S]*\.aurora-ribbon[\s\S]*animation:\s*none/);
  assert.doesNotMatch(css, /\.hero-signal\s*>\s*span\s*\{[^}]*animation:/s);
  assert.doesNotMatch(css, /box-shadow:\s*0\s+0\s+\d+px\s+rgba\(21,\s*217,\s*197/s);
  assert.doesNotMatch(css, /\.hero-signal\s*\{[^}]*text-transform:\s*uppercase/s);
  assert.doesNotMatch(css, /\.species-caption\s*\{[^}]*text-transform:\s*uppercase/s);
});

test("the navigation script is local and progressively enhances the page", () => {
  const html = readRequired(indexPath);
  const script = readRequired(scriptPath);

  assert.match(html, /<script\s+src="script\.js"\s+defer><\/script>/);
  assert.match(script, /aria-expanded/);
  assert.match(script, /matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(script, /event\.key === "Escape"/);
  assert.match(script, /navToggle\?\.focus\(\)/);
  assert.match(script, /function\s+setupRevealMotion\(\)/);
  assert.match(script, /IntersectionObserver/);
  assert.match(script, /document\.documentElement\.classList\.add\("motion-ready"\)/);
  assert.match(script, /function\s+setupDeviceDepth\(\)/);
  assert.match(script, /\(hover: hover\) and \(pointer: fine\)/);
  assert.match(script, /--tilt-x/);
  assert.match(script, /--tilt-y/);
});

test("the design record preserves the approved direction contract", () => {
  const spec = readRequired(designSpecPath);
  const system = readRequired(designSystemPath);

  for (const heading of ["Chosen Direction: Kinetic Field Signal", "Page Structure", "Motion and Interaction", "GitHub Link Contract", "Acceptance Criteria"]) {
    assert.match(spec, new RegExp(`## ${heading}`), `missing ${heading} direction section`);
  }
  assert.match(spec, /aurora-species-BioCLIP/);
  assert.match(spec, /prefers-reduced-motion: reduce/);
  assert.match(spec, /Do not publish the refresh until/);
  assert.match(system, /^---\nname: Aurora Survival/m);
  assert.match(system, /Creative North Star: "Kinetic Field Signal"/);
  assert.match(system, /Motion is progressive enhancement/);
  assert.match(system, /aurora-drift/);
  assert.match(system, /scan-pass/);
  assert.match(system, /Aurora product family/);
});

test("main pushes deploy the tested Website directory to the existing Cloudflare project", () => {
  const workflow = readRequired(deploymentWorkflowPath);

  assert.match(workflow, /push:\s*\n\s+branches:\s*\[main\]/);
  assert.match(workflow, /paths:\s*\n\s+- "Website\/\*\*"/);
  assert.match(workflow, /timeout-minutes:\s*10/);
  assert.match(workflow, /node --test Website\/tests\/site\.test\.mjs/);
  assert.match(workflow, /python3 tools\/validate\.py/);
  assert.match(workflow, /cloudflare\/wrangler-action@v3/);
  assert.match(workflow, /apiToken:\s*\$\{\{ secrets\.CLOUDFLARE_API_TOKEN \}\}/);
  assert.match(workflow, /accountId:\s*\$\{\{ secrets\.CLOUDFLARE_ACCOUNT_ID \}\}/);
  assert.match(workflow, /command:\s*pages deploy Website --project-name=aurora-survival/);
});

test("the landing experience uses full-screen chapters without section overlap", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.match(html, /class="cursor-field" aria-hidden="true"/);
  assert.match(css, /\.site-header,\s*\nmain,\s*\n\.site-footer\s*\{[^}]*width:\s*100%/s);
  assert.match(css, /\.hero\s*\{[^}]*min-height:\s*calc\(100svh - 74px\)/s);
  assert.match(css, /\.product-stage\s*\{[^}]*min-height:\s*calc\(100svh - 74px\)[^}]*margin:\s*0/s);
  assert.doesNotMatch(css, /\.product-stage\s*\{[^}]*margin:\s*-\d/s);
  assert.match(css, /\.product-stage::after\s*\{[^}]*linear-gradient/s);
  assert.match(css, /\.device-capture\s*\{\s*\n\s*width:\s*min\(100%,\s*320px\);\s*\n\s*margin/s);
});

test("the hero pointer field is bounded and respects motion preferences", () => {
  const css = readRequired(stylesPath);
  const script = readRequired(scriptPath);

  assert.match(css, /\.cursor-field\s*\{[^}]*--pointer-x[^}]*--pointer-y/s);
  assert.doesNotMatch(css, /cursor:\s*none/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.cursor-field[\s\S]*display:\s*none/);
  assert.match(script, /function\s+setupHeroPointerField\(\)/);
  assert.match(script, /\(hover: hover\) and \(pointer: fine\)/);
  assert.match(script, /requestAnimationFrame/);
  assert.match(script, /--pointer-x/);
  assert.match(script, /--pointer-y/);
});
