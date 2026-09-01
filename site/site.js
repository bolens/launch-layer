(() => {
  "use strict";

  const root = document.documentElement;
  root.classList.add("has-js");
  const themeButton = document.querySelector(".theme-toggle");
  const themeLabel = document.querySelector(".theme-label");
  let storedTheme = null;
  try {
    storedTheme = localStorage.getItem("launchlayer-theme");
  } catch (_) {
    // Storage may be disabled. The theme still follows the system preference.
  }

  function setTheme(theme) {
    const light = theme === "light";
    root.dataset.theme = light ? "light" : "dark";
    themeButton.setAttribute("aria-pressed", String(light));
    themeButton.setAttribute("aria-label", light ? "Use dark theme" : "Use light theme");
    themeLabel.textContent = light ? "Dark" : "Light";
  }

  setTheme(storedTheme || (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));
  themeButton.addEventListener("click", () => {
    const next = root.dataset.theme === "light" ? "dark" : "light";
    try {
      localStorage.setItem("launchlayer-theme", next);
    } catch (_) {
      // Keep the selected theme for this page when storage is unavailable.
    }
    setTheme(next);
  });

  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const reveals = document.querySelectorAll(".reveal");
  if (reducedMotion || !("IntersectionObserver" in window)) {
    reveals.forEach((element) => element.classList.add("is-visible"));
  } else {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8%", threshold: 0.08 });
    reveals.forEach((element) => observer.observe(element));
  }

  const releaseLabel = document.querySelector("#release-label");
  const releaseLink = document.querySelector("#release-link");
  fetch("https://api.github.com/repos/bolens/launch-layer/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then((response) => {
      if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
      return response.json();
    })
    .then((release) => {
      releaseLabel.textContent = `${release.tag_name} is the current release`;
      releaseLink.href = release.html_url;
    })
    .catch(() => {
      releaseLabel.textContent = "See GitHub for the current release";
    });
})();
