import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const websiteRoot = resolve(import.meta.dirname, "..");
const indexPath = resolve(websiteRoot, "index.html");
const stylesPath = resolve(websiteRoot, "styles.css");
const scriptPath = resolve(websiteRoot, "script.js");
const designSystemPath = resolve(websiteRoot, "..", "DESIGN.md");
const manualSourcePath = resolve(websiteRoot, "..", "Resources", "Knowledge", "survival_knowledge_source.json");
const deploymentWorkflowPath = resolve(websiteRoot, "..", ".github", "workflows", "pages-deployment.yml");

function readRequired(path) {
  assert.ok(existsSync(path), `required file is missing: ${path}`);
  return readFileSync(path, "utf8");
}

const text = (html) => html.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();

test("the public page exposes the approved semantic journey", () => {
  const html = readRequired(indexPath);

  for (const landmark of ["<header", "<nav", "<main", "<footer"]) {
    assert.ok(html.includes(landmark), `missing ${landmark} landmark`);
  }

  assert.match(html, /href="#main-content"[^>]*>Skip to content</);
  assert.match(html, /id="main-content"/);
  assert.match(html, /class="nav-toggle"[^>]*aria-label="Toggle navigation menu"/);
  assert.match(html, /<h1[^>]*>\s*Survival knowledge that stays with you\./);
  assert.match(html, /Coming to the App Store/);
  assert.match(html, /mailto:guokenny7@gmail\.com/);
  assert.match(html, /founder-led/i);
  assert.match(html, /class="button button-primary"[^>]*href="mailto:guokenny7@gmail\.com/);
  assert.match(html, /class="availability-label">Coming to the App Store<\/span>/);
  assert.match(html, /How is Aurora’s content verified\?/);
  assert.match(html, /source metadata[^<]*signed before activation[^<]*physical iPhone 13/i);
  assert.match(html, /iPhone and iPad/);
  assert.match(html, /educational aid/i);
});

test("the field kit names the four verified capabilities without inventing metrics", () => {
  const html = readRequired(indexPath);
  const visible = text(html);

  assert.match(html, /id="field-kit"/);
  assert.equal((html.match(/<article class="tool[^"]*"/g) ?? []).length, 4, "expected four tool cards");
  assert.match(visible, /An on-device language model\./);
  assert.match(visible, /A reviewed field manual\./);
  assert.match(visible, /Signed offline maps\./);
  assert.match(visible, /Core ML/);
  assert.match(visible, /Ed25519/);
  assert.match(visible, /Photos are never sent off the phone/);
  assert.match(visible, /likely matches, not certainty/);
  assert.match(visible, /only in explicit Preparation mode/);
});

test("the standalone product metrics strip is removed", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.doesNotMatch(html, /class="proof-band"/);
  assert.doesNotMatch(html, /Indexed manual passages|Offline species|Primary areas|Cloud queries in ordinary use/);
  assert.doesNotMatch(css, /\.proof-band/);
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

test("the hero demo quotes the reviewed manual verbatim and works without JavaScript", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);
  const manual = JSON.parse(readRequired(manualSourcePath));
  const ask = html.match(/<aside class="ask"[\s\S]*?<\/aside>/)?.[0] ?? "";
  const answers = [...ask.matchAll(/<article class="ask-answer" data-answer="([^"]+)">([\s\S]*?)<\/article>/g)];

  assert.ok(ask, "the hero needs the Ask the field manual card");
  assert.equal((ask.match(/<input type="radio" name="ask"/g) ?? []).length, answers.length);
  assert.equal((ask.match(/ checked>/g) ?? []).length, 1, "exactly one question starts selected");
  assert.ok(answers.length >= 3, "expected several real manual answers");

  for (const [, key, body] of answers) {
    assert.match(ask, new RegExp(`<input type="radio" name="ask" value="${key}"`));
    const title = text(body.match(/<p class="ask-path">([\s\S]*?)<\/p>/)[1]).split(" / ").pop();
    const lesson = manual.lessons.find((entry) => entry.title === title);
    assert.ok(lesson, `"${title}" must be a real manual lesson`);
    assert.equal(lesson.reviewStatus, "primary-source-verified", `${title} must be reviewed`);
    const steps = [...body.matchAll(/<li>([\s\S]*?)<\/li>/g)].map((m) => text(m[1]));
    assert.deepEqual(steps, lesson.actions, `${title} steps must match the manual exactly`);
    assert.equal(text(body.match(/<p class="ask-warn">([\s\S]*?)<\/p>/)[1]), lesson.warnings[0]);
    const organizations = new Set(lesson.sourceIDs.map((id) => manual.sources.find((s) => s.id === id).organization));
    for (const organization of organizations) assert.ok(body.includes(organization), `${title} must cite ${organization}`);
  }

  assert.match(ask, /educational aid, not a replacement for emergency services/i);
  // Answers are only hidden where :has() can reveal the chosen one again.
  assert.match(css, /@supports selector\(:has\(\*\)\)\s*\{\s*\.ask-answer\s*\{\s*visibility:\s*hidden/);
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

test("the field journey exposes safe open-source and founder links", () => {
  const html = readRequired(indexPath);

  assert.match(html, /class="hero-signal"/);
  assert.match(html, /id="open-source"/);
  assert.match(html, /class="[^"]*\bspecies-section\b[^"]*"/);
  assert.match(
    html,
    /href="https:\/\/github\.com\/kenny2077\/aurora-species-BioCLIP"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.match(
    html,
    /href="https:\/\/github\.com\/kenny2077"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.match(html, /aria-label="Aurora Survival on GitHub"/);
  for (const anchor of html.matchAll(/href="#([^"]+)"/g)) {
    assert.match(html, new RegExp(`id="${anchor[1]}"`), `in-page link #${anchor[1]} needs a target`);
  }
});

test("Aurora Survival remains primary while the footer links quietly to Aurora Digest and Aurora Forge Lab", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);

  assert.match(html, /class="brand-family">An Aurora product<\/span>/);
  assert.match(
    html,
    /class="footer-project"[^>]*href="https:\/\/github\.com\/kenny2077\/Aurora"[^>]*target="_blank"[^>]*rel="noopener noreferrer"/,
  );
  assert.match(
    html,
    /src="assets\/aurora-digest-icon\.svg"[^>]*width="24"[^>]*height="24"[^>]*alt="Aurora Digest icon"/,
  );
  assert.match(html, /<span>Aurora Digest<\/span>/);
  assert.match(html, /<footer[\s\S]*href="https:\/\/auroraforgelab\.com\/"[^>]*>An Aurora Forge Lab product<\/a>[\s\S]*<\/footer>/);
  assert.doesNotMatch(html, /kenny2077\.github\.io\/Aurora|Also from Aurora:|A self-hosted daily learning radar|>Source/);
  assert.doesNotMatch(html, /<a[^>]*href="#(?:digest|products)"/);
  assert.match(css, /\.footer-project\s*\{/);
  assert.match(css, /@media\s*\(max-width:\s*800px\)[\s\S]*\.footer-inner\s*\{[^}]*grid-template-columns:\s*1fr/s);
});

test("the page avoids rejected brands and unsupported claims", () => {
  const html = readRequired(indexPath);
  const visibleCopy = html.replace(/<[^>]+>/g, " ");

  assert.doesNotMatch(visibleCopy, /Aurora Labs|Aurora LLC/i);
  assert.doesNotMatch(visibleCopy, /download now|available now|customers love|trusted by/i);
  assert.doesNotMatch(visibleCopy, /Built by Kenny Guo/i);
  assert.doesNotMatch(visibleCopy, /No account required/i);
  assert.doesNotMatch(visibleCopy, /Lite model targets iPhone 13-class/i);
  assert.doesNotMatch(visibleCopy, /\b\d+(?:\.\d+)?x\b|testimonial|5 stars|★/i);
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
  assert.match(html, /src="assets\/iphone-ask-home\.webp"/);

  assert.ok(statSync(resolve(websiteRoot, "assets", "aurora-icon.webp")).size < 250_000, "brand icon should be web-sized");
});

test("fonts and scripts are self-hosted with no third-party runtime requests", () => {
  const html = readRequired(indexPath);
  const css = readRequired(stylesPath);
  const script = readRequired(scriptPath);

  assert.doesNotMatch(html, /<script[^>]+src="https?:/);
  assert.doesNotMatch(html, /<link[^>]+href="https?:/);
  assert.doesNotMatch(css, /url\(["']?https?:|@import/);
  assert.doesNotMatch(script, /fetch\(|import\(|https?:\/\//);
  assert.match(css, /@font-face\s*\{[^}]*url\("assets\/fonts\/archivo-latin-var\.woff2"\)[^}]*font-display:\s*swap/s);
  assert.ok(statSync(resolve(websiteRoot, "assets", "fonts", "archivo-latin-var.woff2")).size < 150_000);
  assert.match(readRequired(resolve(websiteRoot, "assets", "fonts", "OFL.txt")), /SIL OPEN FONT LICENSE/);
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

test("the stylesheet preserves focus, reduced motion, touch, and narrow-screen layouts", () => {
  const css = readRequired(stylesPath);

  assert.match(css, /:focus-visible\s*\{[^}]*outline:\s*3px solid/);
  assert.match(css, /\.skip-link:focus\s*\{/);
  assert.match(css, /@media[^\{]*max-width/);
  assert.match(css, /overflow-wrap/);
  assert.match(css, /overflow-x:\s*clip/);
  assert.match(css, /img\s*\{[^}]*height:\s*auto/s);
  assert.match(css, /section\[id\]\s*\{[^}]*scroll-margin-top:\s*76px/s);
  assert.doesNotMatch(css, /0\.6[69]rem/);
  assert.match(css, /\.contact-options\s+small\s*\{[^}]*0\.72rem/s);
  assert.match(css, /@media\s*\(hover:\s*hover\)\s*and\s*\(pointer:\s*fine\)/);
  assert.match(css, /@media\s*\(hover:\s*none\)\s*\{\s*\.wordmark-hint\s*\{\s*display:\s*none/);
  assert.doesNotMatch(css, /cursor:\s*none/);

  const reduced = css.match(/@media \(prefers-reduced-motion: reduce\) \{([\s\S]*)\}\s*$/)?.[1] ?? "";
  assert.match(reduced, /animation:\s*none\s*!important/);
  assert.match(reduced, /transition:\s*none\s*!important/);
  assert.match(reduced, /\.statement\s*\{\s*height:\s*auto/);
  assert.match(reduced, /\.statement \.pin\s*\{\s*position:\s*relative/);
  assert.match(reduced, /\.tool\s*\{\s*position:\s*relative/);

  assert.doesNotMatch(css, /\.hero-signal\s*>\s*span\s*\{[^}]*animation:/s);
  assert.doesNotMatch(css, /box-shadow:\s*0\s+0\s+\d+px\s+rgba\(21,\s*217,\s*197/s);
  assert.doesNotMatch(css, /\.hero-signal\s*\{[^}]*text-transform:\s*uppercase/s);
  assert.doesNotMatch(css, /\.species-caption\s*\{[^}]*text-transform:\s*uppercase/s);
});

test("the script progressively enhances navigation and motion", () => {
  const html = readRequired(indexPath);
  const script = readRequired(scriptPath);

  assert.match(html, /<script\s+src="script\.js"\s+defer><\/script>/);
  assert.match(script, /aria-expanded/);
  assert.match(script, /matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(script, /event\.key === "Escape"/);
  assert.match(script, /navToggle\?\.focus\(\)/);
  assert.match(script, /function\s+setupDeviceDepth\(\)/);
  assert.match(script, /\(hover: hover\) and \(pointer: fine\)/);
  assert.match(script, /--tilt-x/);
  assert.match(script, /--tilt-y/);
  // One rAF loop; offscreen fields pause; pointer heat only on fine pointers without reduced motion.
  assert.equal((script.match(/function loop\(\)/g) ?? []).length, 1);
  assert.match(script, /IntersectionObserver/);
  assert.match(script, /if \(finePointer\.matches && !RM\)/);
  assert.match(script, /if \(!hot && !this\.dirty\) return;/);
});

test("the signature pixel field is decorative and reused across the page", () => {
  const html = readRequired(indexPath);

  const canvases = [...html.matchAll(/<canvas\b[^>]*>/g)].map((m) => m[0]);
  assert.ok(canvases.length >= 7, "hero, four numerals, maps and wordmark");
  for (const canvas of canvases) {
    assert.match(canvas, /class="field /);
    assert.ok(/aria-hidden="true"/.test(canvas) || canvas.includes("wordmark-field"), `decorative canvas must be hidden: ${canvas}`);
  }
  assert.match(html, /<div class="wordmark" aria-hidden="true">/);
  assert.match(html, /<canvas class="field hero-field" aria-hidden="true">/);
});

test("the design record preserves the approved direction contract", () => {
  const system = readRequired(designSystemPath);

  assert.match(system, /^---\nname: Aurora Survival/m);
  assert.match(system, /Creative North Star: "Kinetic Field Signal"/);
  assert.match(system, /Motion is progressive enhancement/);
  assert.match(system, /Headlamp Pixel Field/);
  assert.match(system, /Archivo/);
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
  const css = readRequired(stylesPath);

  assert.match(css, /\.hero\s*\{[^}]*min-height:\s*100svh/s);
  assert.match(css, /\.product-stage\s*\{[^}]*margin:\s*0/s);
  assert.doesNotMatch(css, /\.product-stage\s*\{[^}]*margin:\s*-\d/s);
  assert.match(css, /\.product-stage::after\s*\{[^}]*linear-gradient/s);
  assert.match(css, /\.device-capture\s*\{[^}]*width:\s*min\(100%,\s*320px/s);
  assert.match(css, /\.statement \.pin\s*\{[^}]*position:\s*sticky/s);
  assert.match(css, /\.site-footer\s*\{[^}]*position:\s*sticky/s);
});
