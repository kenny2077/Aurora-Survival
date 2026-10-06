// Aurora Survival: progressive enhancement only. Every word on the page is in the HTML.
const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");
const RM = reduceMotion.matches;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/* ---------- Navigation ---------- */
function closeNavigation() {
  navToggle?.setAttribute("aria-expanded", "false");
  navLinks?.classList.remove("is-open");
}

navToggle?.addEventListener("click", () => {
  const isOpen = navToggle.getAttribute("aria-expanded") === "true";
  navToggle.setAttribute("aria-expanded", String(!isOpen));
  navLinks?.classList.toggle("is-open", !isOpen);
});

navLinks?.addEventListener("click", (event) => {
  if (event.target.closest("a")) closeNavigation();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && navToggle?.getAttribute("aria-expanded") === "true") {
    closeNavigation();
    navToggle?.focus();
  }
});

window.addEventListener("resize", () => {
  if (window.innerWidth > 800) closeNavigation();
});

/* ---------- Pixel field: the signature motif ----------
   A low-res buffer upscaled with nearest-neighbour and 1px seams. A fine pointer
   acts as a headlamp: cells it passes light up, then cool back to the base image.
   Idle fields cost nothing: they redraw only while dirty or warm. */
const LAMP = [[255, 170, 92], [255, 228, 176]];
const CONTOUR = [[21, 217, 197], [190, 255, 246]];
const AURORA = [[21, 217, 197], [117, 70, 255]];
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((n) => n / 16);
const hash = (x, y) => {
  const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - Math.floor(s);
};

class PixelField {
  constructor(canvas, { cell, paint, heat = LAMP, alt = AURORA, seam = "rgba(3,10,9,.4)", radius = 3, decay = 0.9, strength = 1 }) {
    this.c = canvas;
    this.ctx = canvas.getContext("2d");
    this.low = document.createElement("canvas");
    this.lctx = this.low.getContext("2d");
    Object.assign(this, { cellFor: cell, paint, heatColors: heat, altColors: alt, seam, radius, decay, strength });
    this.visible = true;
    this.last = null;
    new ResizeObserver(() => this.resize()).observe(canvas);
    new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      this.dirty = true;
    }).observe(canvas);
  }

  resize() {
    const w = this.c.clientWidth;
    const h = this.c.clientHeight;
    if (!w || !h) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.cell = typeof this.cellFor === "function" ? this.cellFor(w, h) : this.cellFor;
    this.cols = Math.ceil(w / this.cell);
    this.rows = Math.ceil(h / this.cell);
    this.scale = this.cell * dpr;
    this.c.width = Math.round(w * dpr);
    this.c.height = Math.round(h * dpr);
    this.low.width = this.cols;
    this.low.height = this.rows;
    this.img = this.lctx.createImageData(this.cols, this.rows);
    const n = this.cols * this.rows;
    this.base = new Float32Array(n * 3);
    this.react = new Float32Array(n);
    this.alt = new Uint8Array(n);
    this.heat = new Float32Array(n);
    this.repaint();
  }

  repaint() {
    if (!this.base) return;
    this.react.fill(1);
    this.alt.fill(0);
    this.paint(this);
    this.dirty = true;
  }

  stamp(cx, cy) {
    const r = this.radius;
    for (let y = Math.max(0, Math.floor(cy - r)); y <= Math.min(this.rows - 1, Math.ceil(cy + r)); y++) {
      for (let x = Math.max(0, Math.floor(cx - r)); x <= Math.min(this.cols - 1, Math.ceil(cx + r)); x++) {
        const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r;
        if (d >= 1) continue;
        const i = y * this.cols + x;
        this.heat[i] = Math.max(this.heat[i], 1 - d * d * 0.9);
      }
    }
  }

  warm(clientX, clientY) {
    if (!this.visible || !this.base) return;
    const rect = this.c.getBoundingClientRect();
    const x = (clientX - rect.left) / this.cell;
    const y = (clientY - rect.top) / this.cell;
    if (x < -4 || y < -4 || x > this.cols + 4 || y > this.rows + 4) {
      this.last = null;
      return;
    }
    const p = this.last || [x, y];
    const steps = Math.max(1, Math.ceil(Math.hypot(x - p[0], y - p[1]) / 1.2));
    for (let s = 1; s <= steps; s++) this.stamp(p[0] + ((x - p[0]) * s) / steps, p[1] + ((y - p[1]) * s) / steps);
    this.last = [x, y];
  }

  frame() {
    if (!this.visible || !this.img) return;
    const H = this.heat;
    let hot = false;
    for (let i = 0; i < H.length; i++) {
      if (H[i] > 0) {
        H[i] = H[i] < 0.08 ? 0 : H[i] * this.decay;
        hot = true;
      }
    }
    if (!hot && !this.dirty) return;
    const d = this.img.data;
    const B = this.base;
    for (let i = 0; i < H.length; i++) {
      let r = B[i * 3];
      let g = B[i * 3 + 1];
      let b = B[i * 3 + 2];
      const h = H[i] * this.react[i];
      if (h > 0.3) {
        const q = Math.ceil(h * 4) / 4; // four light levels keep it pixelated
        const [a, z] = this.alt[i] ? this.altColors : this.heatColors;
        const k = (0.35 + q * 0.55) * this.strength;
        r += (a[0] + (z[0] - a[0]) * q - r) * k;
        g += (a[1] + (z[1] - a[1]) * q - g) * k;
        b += (a[2] + (z[2] - a[2]) * q - b) * k;
      }
      d[i * 4] = r;
      d[i * 4 + 1] = g;
      d[i * 4 + 2] = b;
      d[i * 4 + 3] = 255;
    }
    this.lctx.putImageData(this.img, 0, 0);
    const ctx = this.ctx;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(this.low, 0, 0, this.cols * this.scale, this.rows * this.scale);
    ctx.fillStyle = this.seam;
    for (let x = 1; x <= this.cols; x++) ctx.fillRect(Math.round(x * this.scale) - 1, 0, 1, this.c.height);
    for (let y = 1; y <= this.rows; y++) ctx.fillRect(0, Math.round(y * this.scale) - 1, this.c.width, 1);
    this.dirty = false;
  }
}

/* Hero sky: dithered aurora over a far ridge and a pine line. Hidden contour lines
   in the terrain only appear under the lamp, a nod to the offline maps. */
let skyPhase = 0;
let skyGlow = RM ? 1 : 0;
function paintSky(f) {
  const { cols, rows, base, react, alt } = f;
  for (let y = 0; y < rows; y++) {
    const v = y / rows;
    for (let x = 0; x < cols; x++) {
      const u = x / cols;
      const i = y * cols + x;
      let r = 3 + 8 * v;
      let g = 10 + 22 * v;
      let b = 9 + 20 * v;
      const ridge = 0.56 + 0.07 * Math.sin(u * 3.1 + 0.6) + 0.04 * Math.sin(u * 7.7 + 1.3) + 0.018 * Math.sin(u * 19);
      const group = Math.floor(x / 5);
      const profile = [0.3, 0.65, 1, 0.65, 0.3][x % 5];
      const trees = 0.74 + 0.025 * Math.sin(u * 4.2 + 2) - hash(group, 7) * 0.075 * profile;
      if (v > trees) {
        r = 2; g = 9; b = 8;
        const e = (v - trees) * 9 + Math.sin(u * 8 + v * 5) * 0.6;
        if ((e * 3) % 1 < 0.2) { alt[i] = 1; g += 6; b += 5; }
      } else if (v > ridge) {
        const fog = clamp(1 - (v - ridge) * 6, 0, 1);
        r = 5 + 6 * fog; g = 20 + 16 * fog; b = 18 + 16 * fog;
        const e = (v - ridge) * 7 + Math.sin(u * 11 + 1) * 0.35;
        if ((e * 4) % 1 < 0.16) { alt[i] = 1; g += 5; b += 5; }
        react[i] = 0.9;
      } else {
        react[i] = 0.45;
        let I = 0;
        let tc = 0;
        for (const [lift, gain, off] of [[0, 1, 0], [0.13, 0.5, 2.1]]) {
          const edge = 0.34 - lift + 0.09 * Math.sin(u * 2.7 + skyPhase + off) + 0.045 * Math.sin(u * 6.1 - skyPhase * 1.4 + 1 + off) + 0.015 * Math.sin(u * 17 + skyPhase * 2);
          const dist = edge - v;
          const fall = dist < 0 ? Math.exp(-((dist / 0.018) ** 2)) : Math.exp(-dist / 0.19);
          const rays = 0.62 + 0.38 * Math.sin(u * 41 + Math.sin(u * 13 + off) * 3 + skyPhase * 2) * (0.55 + 0.45 * Math.sin(u * 97 + off));
          const sway = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(u * 3.3 + skyPhase * 0.8 + off)) ** 1.4;
          const k = fall * (0.3 + 0.7 * rays * sway) * gain * 1.15;
          if (k > I) { I = k; tc = clamp(dist / 0.32, 0, 1); }
        }
        I = clamp(I * skyGlow, 0, 1);
        const q = Math.floor(I * 5 + BAYER[(y & 3) * 4 + (x & 3)]) / 5;
        const t = tc;
        const cr = t < 0.5 ? 21 + (52 - 21) * t * 2 : 52 + (117 - 52) * (t - 0.5) * 2;
        const cg = t < 0.5 ? 217 + (120 - 217) * t * 2 : 120 + (70 - 120) * (t - 0.5) * 2;
        const cb = t < 0.5 ? 197 + (246 - 197) * t * 2 : 246 + (255 - 246) * (t - 0.5) * 2;
        r += cr * q * 0.85; g += cg * q * 0.85; b += cb * q * 0.85;
        const star = hash(x, y);
        if (star > 0.993 && v < ridge - 0.08) {
          const s = (star - 0.993) * 9000 * (1 - q);
          r += s; g += s; b += s;
        }
      }
      base[i * 3] = r;
      base[i * 3 + 1] = g;
      base[i * 3 + 2] = b;
    }
  }
}

/* Topographic pixels for the Maps card: a cell is a contour where the level changes. */
function paintTopo(f) {
  const { cols, rows, base, alt } = f;
  const level = (x, y) => {
    const u = x / cols;
    const v = y / rows;
    const e = Math.sin(u * 3 + 1) * Math.cos(v * 2.6 - 0.4) + 0.35 * Math.sin(u * 5.5 - v * 4) + 0.2 * Math.cos(u * 2 + v * 5);
    return Math.floor((e + 2) * 2.6);
  };
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const i = y * cols + x;
      const l = level(x, y);
      const edge = l !== level(x + 1, y) || l !== level(x, y + 1);
      let r = 6, g = 19, b = 17;
      if (edge) {
        const index = l % 3 === 0;
        r = index ? 21 : 12; g = index ? 160 : 84; b = index ? 146 : 78;
        alt[i] = 1;
      }
      base[i * 3] = r;
      base[i * 3 + 1] = g;
      base[i * 3 + 2] = b;
    }
  }
}

/* 5x7 glyphs reused for card numerals and the footer wordmark. */
const GLYPHS = {
  0: "01110100011001110101110011000101110",
  1: "00100011000010000100001000010001110",
  2: "01110100010000100010001000100011111",
  3: "11110000010000101110000010000111110",
  4: "00010001100101010010111110001000010",
  A: "01110100011000111111100011000110001",
  U: "10001100011000110001100011000101110",
  R: "11110100011000111110101001001010001",
  O: "01110100011000110001100011000101110",
};
function glyphPainter(text, bg, from, to) {
  return (f) => {
    const { cols, rows, base, react } = f;
    for (let i = 0; i < cols * rows; i++) {
      base[i * 3] = bg[0];
      base[i * 3 + 1] = bg[1];
      base[i * 3 + 2] = bg[2];
      react[i] = 0;
    }
    const width = text.length * 6 - 1;
    [...text].forEach((ch, n) => {
      const bits = GLYPHS[ch];
      for (let gy = 0; gy < 7; gy++) {
        for (let gx = 0; gx < 5; gx++) {
          if (bits[gy * 5 + gx] !== "1") continue;
          const x = n * 6 + gx;
          if (x >= cols || gy >= rows) continue;
          const t = (x / width) * 0.6 + (gy / 6) * 0.4;
          const i = gy * cols + x;
          base[i * 3] = from[0] + (to[0] - from[0]) * t;
          base[i * 3 + 1] = from[1] + (to[1] - from[1]) * t;
          base[i * 3 + 2] = from[2] + (to[2] - from[2]) * t;
          react[i] = 1;
        }
      }
    });
  };
}
const glyphCell = (len) => (w, h) => Math.max(4, Math.floor(Math.min(h / 7, w / (len * 6 - 1))));

const fields = [];
const heroField = document.querySelector(".hero-field");
let sky = null;
if (heroField) {
  sky = new PixelField(heroField, { cell: (w) => (w < 700 ? 9 : w < 1200 ? 11 : 13), paint: paintSky, alt: CONTOUR, strength: 0.8 });
  fields.push(sky);
}
const topo = document.querySelector(".topo-field");
if (topo) fields.push(new PixelField(topo, { cell: 10, paint: paintTopo, alt: CONTOUR }));
document.querySelectorAll(".numeral").forEach((canvas) => {
  const text = canvas.dataset.glyph;
  fields.push(new PixelField(canvas, {
    cell: glyphCell(text.length),
    paint: glyphPainter(text, [237, 241, 236], [20, 63, 53], [8, 123, 118]),
    heat: AURORA,
    seam: "rgb(237,241,236)",
    radius: 2.2,
    decay: 0.86,
  }));
});
const markCanvas = document.querySelector(".wordmark-field");
if (markCanvas) {
  fields.push(new PixelField(markCanvas, {
    cell: glyphCell(markCanvas.dataset.glyph.length),
    paint: glyphPainter(markCanvas.dataset.glyph, [3, 10, 9], [21, 217, 197], [117, 70, 255]),
    seam: "rgb(3,10,9)",
    radius: 2.4,
  }));
}

if (finePointer.matches && !RM) {
  window.addEventListener("pointermove", (event) => {
    for (const f of fields) f.warm(event.clientX, event.clientY);
  }, { passive: true });
}

/* Load moment: the aurora ignites once over 1.4s. Afterwards it only moves with scroll. */
if (sky && !RM) {
  const start = performance.now();
  const ignite = (now) => {
    const k = clamp((now - start) / 1400, 0, 1);
    skyGlow = 1 - (1 - k) ** 3;
    sky.repaint();
    if (k < 1) requestAnimationFrame(ignite);
  };
  requestAnimationFrame(ignite);
}

/* ---------- Statement: words light as you read ---------- */
const statements = [...document.querySelectorAll(".statement")].map((section) => {
  const words = [];
  const walk = (node, hot) => [...node.childNodes].forEach((n) => {
    if (n.nodeType === 1) return walk(n, hot || n.tagName === "EM");
    if (n.nodeType !== 3) return;
    const frag = document.createDocumentFragment();
    n.textContent.split(/(\s+)/).forEach((part) => {
      if (!part) return;
      if (/^\s+$/.test(part)) return frag.append(part);
      const w = document.createElement("span");
      w.className = hot ? "w hot" : "w";
      w.textContent = part;
      words.push(w);
      frag.append(w);
    });
    n.replaceWith(frag);
  });
  walk(section.querySelector("p"), false);
  return { section, words, lit: -1 };
});

/* ---------- Scroll story: one handler, run only when scroll changes ---------- */
const header = document.querySelector(".site-header");
const papers = [...document.querySelectorAll(".paper")];
const heroCopy = document.querySelector(".hero-copy-wrap");
const ask = document.querySelector(".ask");
const tools = [...document.querySelectorAll(".tool")];
const stage = document.querySelector(".product-stage");
const device = document.querySelector(".device-capture");
const species = document.querySelector(".species-visual");
const page = document.querySelector(".page");
const footer = document.querySelector(".site-footer");
const mark = document.querySelector(".wordmark");

function onScroll() {
  const y = window.scrollY;
  const vh = window.innerHeight;

  if (header) {
    header.classList.toggle("is-solid", y > 24);
    const probe = header.offsetHeight / 2;
    document.body.classList.toggle("on-paper", papers.some((p) => {
      const r = p.getBoundingClientRect();
      return r.top <= probe && r.bottom >= probe;
    }));
  }

  for (const st of statements) {
    const r = st.section.getBoundingClientRect();
    const lit = RM ? st.words.length : Math.floor(clamp(-r.top / Math.max(1, r.height - vh), 0, 1) * 1.15 * st.words.length);
    if (lit !== st.lit) {
      st.words.forEach((w, i) => w.classList.toggle("lit", i < lit));
      st.lit = lit;
    }
  }

  if (RM) return;

  if (y < vh * 1.3) {
    if (sky) {
      skyPhase = y * 0.0026;
      sky.repaint();
    }
    // Parallax only in the side-by-side layout; stacked, the copy would slide over the card.
    const wide = window.innerWidth > 1100;
    const fade = wide ? clamp(1 - y / (vh * 0.7), 0, 1) : 1;
    for (const [el, rate] of [[heroCopy, 0.32], [ask, 0.16]]) {
      if (!el) continue;
      el.style.transform = wide ? `translate3d(0,${(y * rate).toFixed(1)}px,0)` : "";
      el.style.opacity = wide ? fade.toFixed(3) : "";
    }
  }

  if (stage && device) {
    const r = stage.getBoundingClientRect();
    const p = clamp((vh - r.top) / (vh * 0.9), 0, 1);
    device.style.setProperty("--rise", `${((1 - p) * 90).toFixed(1)}px`);
  }

  if (window.innerWidth > 760) {
    tools.forEach((card, i) => {
      const next = tools[i + 1];
      if (!next) return;
      const a = card.getBoundingClientRect();
      const cover = clamp((a.bottom - next.getBoundingClientRect().top) / a.height, 0, 1);
      card.style.transform = cover ? `scale(${(1 - cover * 0.05).toFixed(4)})` : "";
      card.style.filter = cover ? `brightness(${(1 - cover * 0.1).toFixed(3)})` : "";
    });
  } else {
    tools.forEach((card) => { card.style.transform = ""; card.style.filter = ""; });
  }

  if (species) {
    const r = species.getBoundingClientRect();
    const p = clamp((vh - r.top) / (vh + r.height), 0, 1);
    species.style.setProperty("--scan", ((p * (r.height - 2)) / 300).toFixed(4));
  }

  if (page && footer && mark) {
    const t = clamp((vh - page.getBoundingClientRect().bottom) / footer.offsetHeight, 0, 1);
    const k = clamp((t - 0.3) / 0.55, 0, 1);
    mark.style.opacity = k.toFixed(3);
    mark.style.transform = `translate3d(0,${((1 - k) * 40).toFixed(1)}px,0)`;
  }
}

let lastY = -1;
let lastW = -1;
function loop() {
  if (window.scrollY !== lastY || window.innerWidth !== lastW) {
    lastY = window.scrollY;
    lastW = window.innerWidth;
    onScroll();
  }
  for (const f of fields) f.frame();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

/* ---------- Pointer light and device depth (fine pointers only) ---------- */
if (finePointer.matches && !RM) {
  document.addEventListener("pointermove", (event) => {
    const surface = event.target.closest?.(".ask-questions label, .tool");
    if (!surface) return;
    const r = surface.getBoundingClientRect();
    surface.style.setProperty("--mx", `${event.clientX - r.left}px`);
    surface.style.setProperty("--my", `${event.clientY - r.top}px`);
  }, { passive: true });
}

function setupDeviceDepth() {
  if (!stage || !device || RM || !finePointer.matches) return;

  stage.addEventListener("pointermove", (event) => {
    const bounds = stage.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    device.style.setProperty("--tilt-x", `${(-y * 4).toFixed(2)}deg`);
    device.style.setProperty("--tilt-y", `${(x * 5).toFixed(2)}deg`);
  });

  stage.addEventListener("pointerleave", () => {
    device.style.removeProperty("--tilt-x");
    device.style.removeProperty("--tilt-y");
  });
}

setupDeviceDepth();
