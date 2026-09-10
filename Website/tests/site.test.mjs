import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const websiteRoot = resolve(import.meta.dirname, "..");
const indexPath = resolve(websiteRoot, "index.html");
const stylesPath = resolve(websiteRoot, "styles.css");
const scriptPath = resolve(websiteRoot, "script.js");

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
  assert.match(html, /1,050/);
  assert.match(html, /504/);
  assert.match(html, />Ask</);
  assert.match(html, />Manual</);
  assert.match(html, />Maps</);
  assert.match(html, />Tools</);
});

test("the page avoids rejected brands and unsupported claims", () => {
  const html = readRequired(indexPath);
  const visibleCopy = html.replace(/<[^>]+>/g, " ");

  assert.doesNotMatch(visibleCopy, /Aurora|Aurora Labs|Aurora LLC/i);
  assert.doesNotMatch(visibleCopy, /download now|available now|customers love|trusted by/i);
  assert.doesNotMatch(visibleCopy, /Built by Kenny Guo/i);
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
});

test("the stylesheet preserves focus, reduced motion, and narrow-screen layouts", () => {
  const css = readRequired(stylesPath);

  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /@media[^\{]*max-width/);
  assert.match(css, /overflow-wrap/);
});

test("the navigation script is local and progressively enhances the page", () => {
  const html = readRequired(indexPath);
  const script = readRequired(scriptPath);

  assert.match(html, /<script\s+src="script\.js"\s+defer><\/script>/);
  assert.match(script, /aria-expanded/);
  assert.match(script, /matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
});
