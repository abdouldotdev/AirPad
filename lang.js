// Bascule EN/FR sans rechargement, avec mémorisation du choix.
(function () {
  function apply(lang) {
    document.querySelectorAll("[data-lang]").forEach(function (node) {
      node.classList.toggle("visible", node.getAttribute("data-lang") === lang);
    });
    document.querySelectorAll(".lang button").forEach(function (button) {
      button.setAttribute("aria-pressed", String(button.dataset.setLang === lang));
    });
    document.documentElement.lang = lang;
    try { localStorage.setItem("airpad-lang", lang); } catch (e) {}
  }

  var stored = null;
  try { stored = localStorage.getItem("airpad-lang"); } catch (e) {}
  var initial = stored || ((navigator.language || "en").toLowerCase().indexOf("fr") === 0 ? "fr" : "en");

  document.addEventListener("DOMContentLoaded", function () {
    apply(initial);
    document.querySelectorAll(".lang button").forEach(function (button) {
      button.addEventListener("click", function () { apply(button.dataset.setLang); });
    });
  });
})();
