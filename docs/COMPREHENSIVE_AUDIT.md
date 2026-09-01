# KDE AI Chat Comprehensive Audit

**Date:** 2026-08-21
**Scope:** Current Plasma 6 widget implementation, including the live QML path, Python IPC helpers, voice daemons, scheduler, configuration, tests, and packaging.

## Executive summary

The live implementation is concentrated in `contents/ui/main.qml` and
`contents/ui/FullRepresentationContent.qml`. `ChatEngine.js` and several
supporting modules contain a second, mostly orphaned implementation; they are
not imported by the live widget, although much of the existing test suite tests
them. The widget has useful functionality and a passing Python test suite, but
it was not release-ready because important security, lifecycle, and feature
wiring problems were present.

## Remediation applied in this work

The live path was updated to authenticate and restrict the loopback voice HTTP
servers, use encoded helper IPC, validate URLs/paths/session identifiers, guard
request generations during session changes, restore Pi/OpenCode lifecycle
handling, honor per-chat prompts/models/response limits, repair context
compaction, correlate attachment jobs, clean widget-owned temporary media, and
serialize scheduler writes. API-key KWallet loading now covers custom providers
and successful wallet synchronization removes the corresponding plaintext
configuration fallback. Voice setup now installs the authenticated systemd
units after the virtual environment is repaired. QML static checks, a
translation smoke-test module, and package-manifest checks were added to CI.

The plain configuration fallback remains intentionally available when KWallet
is not installed or cannot be opened; users should treat that fallback as
plaintext and use KWallet for secrets. The generated `.plasmoid` file is a
build artifact and must be rebuilt from the source tree before distribution.

## Validation performed

- `pytest -q`: 208 tests passed, with 4 subtests.
- Python compilation passed.
- Plain `qmllint` checks passed in the available environment, but static linting
does not catch unqualified JavaScript/QML runtime references.
- The standalone QML translation test now has its compatibility module; the
  available local `qmltestrunner` still exits before producing a report, so a
  Plasma/Qt runtime test remains required in CI or a desktop test environment.
- The checked-in/generated `.plasmoid` archive was stale relative to the source
  tree; CI now verifies a fresh package manifest, and the ignored local archive
  must be rebuilt before distribution.

## Baseline findings (before remediation)

The findings below record the original audit evidence and remain useful as a
regression checklist. Their current implementation status is summarized in
“Remediation applied in this work” above; the plain-config and MCP trust-model
limitations remain intentional and documented.

### Critical / high priority

1. **Unauthenticated voice HTTP control.** `voice_helper.py` listens on
   `127.0.0.1:9015` and `:9016`, accepts microphone/TTS/control commands without
a token, and sends `Access-Control-Allow-Origin: *`. A local process or web page
can start recording, poll transcripts, trigger speech, play audio, or stop
voice services.

2. **Unsafe shell construction.** Attachment and export paths, plus voice error
text, are interpolated into commands sent through Plasma's executable data
source (`sh -c`). The export path is placed inside a double-quoted Python
command and can break out with shell metacharacters. Attachment quoting is
better but should use one hardened path. User-controlled paths must be passed
as encoded helper arguments, not embedded in shell/Python source.

3. **Request/session lifecycle races.** Responses are not consistently bound to
the session/request that created them. Switching or deleting a session while a
provider or OpenCode request is active can append the response to the wrong
session or persist it there. OpenCode SSE and XHR completion can also finalize
the same request twice.

4. **Broken live Pi path.** Pi mode has no branch in the live send function,
Pi sessions can be rewritten as provider sessions, and the live Pi completion
handler references an undefined `handlePiResponse`.

5. **Broken live OpenCode error path.** `failOpenCodeRequest()` references
`requestFinalized` from a different lexical scope. Timeout/error handling can
throw a `ReferenceError` and leave loading/queue state inconsistent. The
cleanup tail also lacked exception isolation.

6. **Context compaction is unreachable/broken.** The live gate reads the
nonexistent `compactContextEnabled` key instead of persisted
`enableCompactingContext`. The summarizer treats an array payload as an object,
uses undefined URL/model values, and does not correctly trim/replace compacted
history.

### Functional correctness

7. **Per-chat settings are silently dropped.** Chat settings save memory,
system prompt, response length, and OpenCode overrides, but the live request
builders mostly ignore them. OpenCode model/provider overrides are also ignored.

8. **Global system prompt disappears after the first turn.** Both OpenAI and
Anthropic request paths only send it when `messages.length <= 1`; subsequent
stateless API calls therefore lose the configured instructions.

9. **Multi-select OpenCode questions cannot be submitted.** Selected options
are held in delegate-local state and are not collected into the response.

10. **Attachment extraction has race/correlation problems.** Sending is
possible while extraction is pending, and result matching by substring can
associate an extraction with the wrong file.

11. **Response length is not honored.** The UI stores response-length choices,
but OpenAI sends no corresponding limit and Anthropic uses a hardcoded 1024.

12. **Voice defaults/cancellation are fragile.** The default STT model is empty,
status requests have no reliable timeout, and disconnecting a settings test
source does not necessarily stop the underlying process.

### Security, privacy, and robustness

13. **API keys are not exclusively kept in KWallet.** KWallet values are copied
into the ordinary plasmoid configuration, and custom provider credentials are
stored in `customProvidersJson`. The UI/documentation therefore overstates
at-rest protection.

14. **Markdown links are not validated at the live call site.** Rendered links
are passed to `Qt.openUrlExternally()` without enforcing HTTP(S), allowing
`file:` and other schemes from model-authored content.

15. **Unbounded input/resource use.** Document extraction, zip expansion,
base64 serialization, Markdown rendering, session JSON parsing, and scheduler
payloads have insufficient size/time limits. Large or malformed inputs can
freeze Plasma or consume excessive memory.

16. **Scheduler store/lifecycle weaknesses.** Scheduler and helper writes can
race and overwrite history/settings, malformed numeric fields can terminate
the daemon, and deleting a chat does not remove its schedules.

17. **Helper validation is incomplete.** File paths and generated systemd unit
fields need defense-in-depth validation. Configured executable paths are
interpolated into persistent user systemd units.

18. **MCP/command execution needs stronger boundaries.** Configured MCP
executables run without resource limits or a consistent confirmation policy.

## Architecture and release hygiene

- There are two divergent implementations: live inline QML and orphaned
  `ChatEngine.js`/utility modules. This makes fixes and tests easy to apply to
the wrong code.
- CI runs Python tests only; it does not run QML runtime tests, `qmllint`, or
  packaging consistency checks.
- The generated `.plasmoid` archive is stale and misses current files.
- Documentation and store text describe behavior/settings that do not match the
  live implementation.

## Recommended implementation order

1. Remove shell interpolation for paths/text and authenticate/restrict voice
   HTTP endpoints.
2. Add request/session generation guards, reliable cancellation, and
   exception-safe cleanup.
3. Restore live Pi and OpenCode paths, then fix compaction and per-chat
   settings.
4. Validate links, bound extraction/session/stream resources, and harden the
   scheduler/helper boundary.
5. Make the live path canonical, add QML/static/package regression checks, and
   rebuild the release archive from source.
