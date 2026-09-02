(() => {
  "use strict";

  const root = document.documentElement;
  root.classList.add("has-js");
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
