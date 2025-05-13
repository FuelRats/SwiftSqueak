function bindShareAnchors(scope = document) {
  scope.querySelectorAll(".share-anchor").forEach(button => {
    if (button.dataset.bound) return; // avoid double binding
    button.dataset.bound = "true";

    button.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();

      const anchor = button.dataset.anchor;
      if (!anchor) return;

      const url = `${window.location.origin}${window.location.pathname}#${anchor}`;

      navigator.clipboard.writeText(url)
        .then(() => {
          button.classList.add("copied");
          setTimeout(() => {
            button.classList.remove("copied");
          }, 1500);
        })
        .catch(err => {
          console.error("Failed to copy anchor:", err);
        });
    });
  });
}

// Run once on initial load
document.addEventListener("DOMContentLoaded", function () {
  bindShareAnchors();
});

// Re-run after HTMX swaps content in
if (document.body) {
  document.body.addEventListener("htmx:afterSwap", function (event) {
    bindShareAnchors(event.target);
  });
} else {
  document.addEventListener("DOMContentLoaded", function () {
    document.body.addEventListener("htmx:afterSwap", function (event) {
      bindShareAnchors(event.target);
    });
  });
}
