const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

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

document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const target = document.querySelector(link.getAttribute("href"));
    if (!target || reduceMotion.matches) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: "smooth", block: "start" });
    history.replaceState(null, "", link.getAttribute("href"));
  });
});

function setupRevealMotion() {
  const revealItems = [...document.querySelectorAll("[data-reveal]")];
  if (reduceMotion.matches || !("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("is-visible"));
    return;
  }

  document.documentElement.classList.add("motion-ready");
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.16, rootMargin: "0px 0px -8%" });

  revealItems.forEach((item) => observer.observe(item));
}

function setupDeviceDepth() {
  const stage = document.querySelector(".product-stage");
  const device = document.querySelector(".device-capture");
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");
  if (!stage || !device || reduceMotion.matches || !finePointer.matches) return;

  stage.addEventListener("pointermove", (event) => {
    const bounds = stage.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    device.style.setProperty("--tilt-x", `${(-y * 4).toFixed(2)}deg`);
    device.style.setProperty("--tilt-y", `${(x * 5).toFixed(2)}deg`);
    device.style.setProperty("--lift-y", "-4px");
  });

  stage.addEventListener("pointerleave", () => {
    device.style.removeProperty("--tilt-x");
    device.style.removeProperty("--tilt-y");
    device.style.removeProperty("--lift-y");
  });
}

setupRevealMotion();
setupDeviceDepth();
