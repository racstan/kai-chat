.pragma library

/**
 * Security — central helpers for safe shell embedding, URL validation,
 * and file-path sanitization.
 *
 * The widget's IPC layer (`P5Support.DataSource` with `engine: "executable"`)
 * runs every command through `sh -c '…'`, which means any `$`, backtick,
 * `(` or `)` in an interpolated string becomes live shell grammar after
 * the outer single-quote context is closed by the inner escape. The
 * older single-quote-only escape left the door open for command
 * substitution when the outer wrapper was a double-quoted string.
 *
 * Use these helpers everywhere a user-controlled or LLM-controlled
 * string is embedded in a shell pipeline or a URL.
 *
 * @module Security
 */

let _ALLOWED_URL_SCHEMES = ["http:", "https:", "mailto:"];
let _SAFE_PATH_CHARS = /^[A-Za-z0-9._\/+@:=\-]+$/;
let _SAFE_SESSION_ID = /^[A-Za-z0-9._:-]{1,128}$/;
let _MAX_SHELL_ARG_LEN = 4096;

/**
 * Build a string that is safe to embed inside a single-quoted shell
 * argument (`'…'`). Replaces every single quote with the standard
 * POSIX close-quote / escaped-quote / open-quote sequence and
 * removes the shell metacharacters that would otherwise be
 * re-evaluated by the outer wrapper.
 *
 * - Strips: `$`, backtick, `(`, `)`, `\`, `;`, `&`, `|`, `<`, `>`,
 *           newline, carriage-return, NUL, BEL.
 * - Length-clamped to `_MAX_SHELL_ARG_LEN` to bound memory use.
 * - Non-ASCII characters are preserved (UTF-8 safe for `sh -c`).
 *
 * @param {string} s  Raw value (null/undefined treated as empty).
 * @returns {string}  Sanitized value safe to embed in `'…'`.
 */
function sanitizeForShell(s) {
    if (s === null || s === undefined)
        return "";
    let out = String(s);
    // Drop the characters that, even after single-quote escaping, can
    // trigger command substitution, backgrounding, or pipeline chaining
    // when the surrounding wrapper re-evaluates the resulting string.
    out = out.replace(/[\$\(\)\\\`\;\&\|\<\>\n\r\0\x07]/g, "");
    // Clamp to a reasonable upper bound to keep individual command
    // lines predictable.
    if (out.length > _MAX_SHELL_ARG_LEN)
        out = out.substring(0, _MAX_SHELL_ARG_LEN);
    // Now apply the standard single-quote escape for the remaining
    // apostrophes so the value lands inside the outer `'…'`.
    return out.replace(/'/g, "'\\''");
}

/**
 * Validate a URL before opening it externally or embedding it in HTML.
 *
 * Returns the original URL only when its scheme is on the allowlist
 * (`http:`, `https:`, `mailto:`) and the URL parses cleanly. Returns
 * the empty string for every other input (including `javascript:`,
 * `file:`, `data:`, `about:`, custom schemes, malformed input, and
 * `null` / `undefined`).
 *
 * @param {string} url  The URL to validate.
 * @returns {string}    The original URL if allowed, or `""`.
 */
function validateUrl(url) {
    if (url === null || url === undefined)
        return "";
    let s = String(url).trim();
    if (s === "")
        return "";
    if (/[\u0000-\u001f\u007f]/.test(s))
        return "";
    let lower = s.toLowerCase();
    if (lower.indexOf("mailto:") === 0) {
        let address = s.substring("mailto:".length).trim();
        return address && !/[\s<>"'`]/.test(address) ? s : "";
    }
    // HTTP(S) links need an actual authority. The old prefix check accepted
    // values such as `https:?x`, which are not external web URLs.
    if (lower.indexOf("http://") !== 0 && lower.indexOf("https://") !== 0)
        return "";
    let authority = s.substring(s.indexOf("://") + 3).split(/[\/?#]/, 1)[0];
    if (!authority || /[\s<>"'`]/.test(authority) || authority.indexOf("@") >= 0)
        return "";
    return s;
}

/**
 * Escape a URL for safe inclusion in an HTML `href` attribute.
 *
 * Strips characters that could break out of the double-quoted context
 * or inject JavaScript handlers. The result is also validated by
 * `validateUrl()` so `javascript:`, `data:`, etc. are rejected.
 *
 * @param {string} url  Raw URL.
 * @returns {string}    Sanitized URL safe for `href="…"`, or `""`.
 */
function validateHttpUrl(url) {
    let validated = validateUrl(url);
    if (validated === "" || !/^(?:http|https):\/\//i.test(validated))
        return "";
    return validated;
}

function safeHref(url) {
    let validated = validateUrl(url);
    if (validated === "")
        return "";
    // Defense in depth: drop any double-quote, backtick, or angle
    // bracket that could escape the attribute value.
    return validated.replace(/[\"\`<>]/g, "");
}

/**
 * Validate a local file path before embedding it in a shell command.
 *
 * Allows only characters that are common in real filenames and rejects
 * everything that could be exploited to break out of the quoted
 * argument. Path traversal segments (`..`) are also rejected.
 *
 * Returns `""` for any non-string input, paths containing
 * traversal sequences, or paths with disallowed characters.
 *
 * @param {string} p  Raw file path.
 * @returns {string}  Sanitized path, or `""` if invalid.
 */
function validateFilePath(p) {
    if (p === null || p === undefined)
        return "";
    let s = String(p);
    if (s === "" || s.length > _MAX_SHELL_ARG_LEN || s.charAt(0) === "~")
        return "";
    if (/[\u0000\n\r]/.test(s))
        return "";
    // Spaces, Unicode, quotes and ordinary filename punctuation are valid
    // path data. Shell metacharacters remain rejected at this boundary even
    // though callers also quote the argument.
    if (/[\$()\\`;&|<>]/.test(s))
        return "";
    let segments = s.split("/");
    for (let i = 0; i < segments.length; i++) {
        if (segments[i] === "..")
            return "";
    }
    return s;
}

/**
 * Validate a local session id before using it as an identifier in persisted
 * chat state. Use validateRemoteSessionId() for server-issued URL ids.
 *
 * Allows common local/server identifier punctuation up to a reasonable
 * length. Returns `""`
 * for anything else so the caller can fail fast.
 *
 * @param {string} id  Raw session id.
 * @returns {string}   Sanitized id, or `""` if invalid.
 */
function validateSessionId(id) {
    if (id === null || id === undefined)
        return "";
    let s = String(id);
    if (!_SAFE_SESSION_ID.test(s))
        return "";
    return s;
}

/**
 * Validate a server-issued OpenCode session id. OpenCode ids are normally
 * `ses_…`, but older/newer servers may include dots, colons, or other
 * non-path punctuation. Reject only control characters and path separators;
 * callers must still URI-encode this value before placing it in a URL path.
 */
function validateRemoteSessionId(id) {
    if (id === null || id === undefined)
        return "";
    let s = String(id);
    if (s.length < 1 || s.length > 256 || s === "." || s === "..")
        return "";
    if (/[\u0000-\u001f\u007f\/#?\s]/.test(s))
        return "";
    return s;
}

/**
 * Convenience wrapper: sanitize a string and return it wrapped in
 * shell single quotes, ready to be interpolated directly into a
 * `sh -c '…'` command. Use this as a drop-in replacement for the
 * old `shellEscape()` style calls.
 *
 *     cmd = "sh -c 'notify-send \"KDE AI Chat\" \"" + Sec.quoteForShell(title) + "\" " + Sec.quoteForShell(body) + " '"
 *
 * @param {string} s  Raw value.
 * @returns {string}  Quoted, sanitized value (`'…'` with escapes).
 */
function quoteForShell(s) {
    return "'" + sanitizeForShell(s) + "'";
}

/**
 * Escape single quotes only, wrapping the string in outer single quotes.
 * This is intended ONLY for shell snippets (like custom start/stop/status
 * commands) that legitimately require shell metacharacters ($ ; & | < >).
 *
 * @param {string} s  Raw shell snippet.
 * @returns {string}  Single-quoted string with internal single quotes escaped.
 */
function rawShellSnippetQuote(s) {
    if (s === null || s === undefined)
        return "''";
    let out = String(s);
    return "'" + out.replace(/'/g, "'\\''") + "'";
}


/**
 * Redact common secret-bearer patterns from a string before it is shown
 * to the user or written to a log.
 *
 * Targets:
 *   - `Authorization: Bearer …` / `Authorization: Basic …` headers
 *   - `api_key=…`, `apikey=…`, `key=…`, `token=…` query parameters
 *   - JSON keys: `"api_key"`, `"apiKey"`, `"access_token"`, `"secret"`
 *   - Sk- prefixed OpenAI-style keys (`sk-…`, `sk-proj-…`)
 *
 * The redaction replaces the value (not the key) with `***` so the
 * surrounding URL / log line is still readable. Patterns are
 * case-insensitive on the key side and only match keys surrounded by
 * reasonable delimiters so we don't mangle unrelated text.
 *
 * @param {string} s  Raw value (null/undefined treated as empty).
 * @returns {string}  Redacted string safe to display.
 */
function scrubSecrets(s) {
    if (s === null || s === undefined)
        return "";
    let out = String(s);
    if (out.length > 8192)
        out = out.substring(0, 8192);
    // Authorization: Bearer xxx / Basic xxx (header form, possibly multi-line)
    out = out.replace(/(authorization\s*:\s*(?:bearer|basic|token|api[_-]?key)\s+)[^\s,;"'<>]+/gi, "$1***");
    // Query parameters with secret-looking names
    out = out.replace(/((?:api[_-]?key|apikey|access[_-]?token|secret[_-]?key|token|key)=)([^&\s"'<>]+)/gi, "$1***");
    // JSON / object-style key/value pairs in body text
    out = out.replace(/("(?:api[_-]?key|apiKey|access[_-]?token|accessToken|secret|secretKey|token)"\s*:\s*")([^"]+)(")/gi, "$1***$3");
    // OpenAI-style sk- keys (20+ chars after prefix). Limited to `[A-Za-z0-9_-]`
    out = out.replace(/\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/g, "sk-***");
    return out;
}

/**
 * A safe, standard, pure-JavaScript implementation of Base64 encoding.
 * Unlike Qt.btoa(string) in newer Qt versions, this does not emit deprecation
 * warnings and behaves identically across all Qt 5 and Qt 6 versions.
 *
 * @param {string} str  The raw string to encode.
 * @returns {string}    Base64 encoded string.
 */
function base64Encode(str) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let binStr = unescape(encodeURIComponent(str));
    let out = '';
    let i = 0;
    const len = binStr.length;
    while (i < len) {
        const c1 = binStr.charCodeAt(i++) & 0xff;
        if (i === len) {
            out += chars.charAt(c1 >> 2);
            out += chars.charAt((c1 & 0x3) << 4);
            out += '==';
            break;
        }
        const c2 = binStr.charCodeAt(i++);
        if (i === len) {
            out += chars.charAt(c1 >> 2);
            out += chars.charAt(((c1 & 0x3) << 4) | ((c2 & 0xf0) >> 4));
            out += chars.charAt((c2 & 0xf) << 2);
            out += '=';
            break;
        }
        const c3 = binStr.charCodeAt(i++);
        out += chars.charAt(c1 >> 2);
        out += chars.charAt(((c1 & 0x3) << 4) | ((c2 & 0xf0) >> 4));
        out += chars.charAt(((c2 & 0xf) << 2) | ((c3 & 0xc0) >> 6));
        out += chars.charAt(c3 & 0x3f);
    }
    return out;
}

