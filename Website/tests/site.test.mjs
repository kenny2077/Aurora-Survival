import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const websiteRoot = resolve(import.meta.dirname, "..");
const indexPath = resolve(websiteRoot, "index.html");
const stylesPath = resolve(websiteRoot, "styles.css");
const scriptPath = resolve(websiteRoot, "script.js");
const designSpecPath = resolve(websiteRoot, "..", "Docs", "superpowers", "specs", "2026-09-10-aurora-marketing-site-design.md");
const designSystemPath = resolve(websiteRoot, "..", "DESIGN.md");

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
  assert.match(html, /class="nav-status"[^>]*>Coming to the App Store<\/span>/);
  assert.match(html, /class="button button-primary"[^>]*href="mailto:guokenny7@gmail\.com/);
  assert.match(html, /class="availability-label">Coming to the App Store<\/span>/);
  assert.match(html, />guokenny7@gmail\.com<\/a>/);
  assert.match(html, /How is Aurora’s content verified\?/);
  assert.match(html, /source metadata[^<]*signed before activation[^<]*physical iPhone 13/i);
  assert.match(html, /1,050/);
  assert.match(html, /504/);
  assert.match(html, />Ask</);
  assert.match(html, />Manual</);
  assert.match(html, />Maps</);
  assert.match(html, />Tools</);
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

test("the privacy panel uses a dedicated high-resolution aurora photograph", () => {
  const html = readRequired(indexPath);
  const privacyFigure = html.match(/<figure class="privacy-art"[^>]*>([\s\S]*?)<\/figure>/)?.[1] ?? "";

  assert.match(privacyFigure, /src="assets\/aurora-field-v2\.webp"/);
  assert.match(privacyFigure, /width="1122"/);
  assert.match(privacyFigure, /height="1402"/);
  assert.ok(
    statSync(resolve(websiteRoot, "assets", "aurora-field-v2.webp")).size > 100_000,
    "the full-size privacy photograph should retain useful detail after web optimization",
  );
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
  assert.match(css, /\.contact-email\s*\{[^}]*0\.8125rem/s);
  assert.match(css, /@media\s*\(max-width:\s*340px\)/);
});

test("the navigation script is local and progressively enhances the page", () => {
  const html = readRequired(indexPath);
  const script = readRequired(scriptPath);

  assert.match(html, /<script\s+src="script\.js"\s+defer><\/script>/);
  assert.match(script, /aria-expanded/);
  assert.match(script, /matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(script, /event\.key === "Escape"/);
  assert.match(script, /navToggle\?\.focus\(\)/);
});

test("the design record preserves the approved direction contract", () => {
  const spec = readRequired(designSpecPath);
  const system = readRequired(designSystemPath);

  for (const block of ["THESIS", "OWN-WORLD", "STORY", "FIRST VIEWPORT", "FORM", "FINISH"]) {
    assert.match(spec, new RegExp(`\\*\\*${block}:\\*\\*`), `missing ${block} direction block`);
  }
  assert.match(spec, /approve-mature-saas/);
  assert.match(system, /^---\nname: Aurora Survival/m);
  assert.match(system, /Creative North Star: "The Field Manual"/);
});
