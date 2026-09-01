.pragma library

// Small compatibility table for the standalone translation smoke test. The
// live widget uses Plasma's i18n() so translated strings continue to come
// from the installed catalogues.
var TRANSLATIONS = {
    "de": {
        "OpenAI key:": "OpenAI-Schlüssel:",
        "OpenAI URL:": "OpenAI-URL:",
        "OpenAI model:": "OpenAI-Modell:"
    },
    "es": {
        "OpenAI key:": "Clave de OpenAI:"
    }
};

function translate(text, language) {
    var table = TRANSLATIONS[String(language || "en")] || {};
    return table[String(text)] || String(text);
}
