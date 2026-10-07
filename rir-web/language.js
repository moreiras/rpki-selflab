// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The rpki-selflab authors
// ============================================================================
// Shared language-switching mechanism for the lab's two panels (this registry
// panel and the main dashboard). This is the registry panel's copy - kept as
// two copies (one per container/build context) rather than one shared HTTP
// origin, since the file is tiny and the two panels are served by different
// containers.
//
// Each page defines its own I18N dictionary and its own onLanguageChange()
// function (called whenever the language changes, to re-render the page).
// This file only owns: which language is active, persisting the choice, and
// the small language-switcher widget in the header.
// ============================================================================

const LANGUAGES = ["en", "es", "pt"];
const LANGUAGE_NAMES = { pt: "Português", es: "Español", en: "English" };
const HTML_LANG = { pt: "pt-BR", es: "es", en: "en" };
const STORAGE_KEY = "rpki-selflab-language";

// ?lang=xx in the page's URL (the dashboard passes its own language to the
// registry panel this way) wins over anything saved or suggested.
function urlLanguage() {
  try { const v = new URLSearchParams(location.search).get("lang"); return LANGUAGES.includes(v) ? v : null; }
  catch (_) { return null; }
}

function currentLanguage() {
  if (urlLanguage()) return urlLanguage();
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (LANGUAGES.includes(v)) return v;
  } catch (_) { /* private mode / blocked storage: fall through */ }
  return (window.DEFAULT_LANGUAGE && LANGUAGES.includes(window.DEFAULT_LANGUAGE))
    ? window.DEFAULT_LANGUAGE : "pt";
}

// Called once, the first time we learn the lab's default language (from
// lab.conf, via /api/status.json). Only takes effect if the viewer hasn't
// already picked a language of their own on this browser.
function suggestDefaultLanguage(language) {
  if (!LANGUAGES.includes(language)) return;
  window.DEFAULT_LANGUAGE = language;
  let alreadyChosen = !!urlLanguage();
  try { alreadyChosen = alreadyChosen || LANGUAGES.includes(localStorage.getItem(STORAGE_KEY)); } catch (_) {}
  if (!alreadyChosen) setLanguage(language, /* silent */ true, /* persist */ false);
}

// persist: false only applies the language to the page, without recording
// it as this browser's own choice (so lab.conf's default can still win).
function setLanguage(language, silent, persist = true) {
  if (!LANGUAGES.includes(language)) return;
  if (persist) { try { localStorage.setItem(STORAGE_KEY, language); } catch (_) {} }
  // a choice made on this page also replaces a ?lang= that came in the URL
  if (persist && urlLanguage() && urlLanguage() !== language) {
    try { const u = new URL(location.href); u.searchParams.set("lang", language); history.replaceState(null, "", u); } catch (_) {}
  }
  else window.DEFAULT_LANGUAGE = language;
  document.documentElement.lang = HTML_LANG[language];
  document.querySelectorAll(".language-switcher button").forEach(b => {
    b.classList.toggle("active", b.dataset.language === language);
  });
  if (!silent && typeof onLanguageChange === "function") onLanguageChange(language);
}

function buildLanguageSwitcher(container) {
  if (!container) return;
  container.innerHTML = LANGUAGES.map(i =>
    `<button data-language="${i}" title="${LANGUAGE_NAMES[i]}" aria-label="${LANGUAGE_NAMES[i]}">${i.toUpperCase()}</button>`
  ).join("");
  container.querySelectorAll("button").forEach(b => {
    b.onclick = () => setLanguage(b.dataset.language);
  });
  setLanguage(currentLanguage(), /* silent */ true, /* persist */ false);
}
