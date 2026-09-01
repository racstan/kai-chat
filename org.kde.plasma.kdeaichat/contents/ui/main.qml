import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import "api.js" as Api
import "ProviderService.js" as ProviderService
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus
import QtCore
import "Security.js" as Sec

PlasmoidItem {
    id: root

    // The icon value may be a KDE icon name or an image file path chosen in
    // Settings → Other (see customIconIsImage below).
    Plasmoid.icon: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon) ? plasmoid.configuration.customIcon : "dialog-messages"

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []
    property var attachedFiles: []
    property bool historyOnlyMode: false
    property bool loading: false
    property var activeXhr: null
    property var openCodeEventXhr: null
    property string openCodeActiveSessionId: ""
    property int openCodeAssistantMessageIndex: -1
    property string openCodeAssistantServerMessageId: ""
    property string openCodeAssistantModelLabel: "OpenCode"
    property bool openCodeErrorShownForRequest: false
    property bool openCodeRequestFinalized: false
    property int requestGeneration: 0
    property string activeRequestSessionId: ""
    property var pendingPiRequests: ({})
    property int piRequestCounter: 0
    property var pendingAttachmentRequests: ({})
    property int attachmentRequestCounter: 0
    property bool schedulerPollInFlight: false
    property string schedulerResumeSessionId: ""
    property var compactionXhr: null
    property string compactionSessionId: ""
    property int compactionGeneration: 0
    property bool streamingResponse: false
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    property string currentStreamExtractedReasoning: ""
    readonly property int maxMessageChars: 2000000
    property int currentStreamIndex: -1
    property int playingMessageIndex: -1
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property bool openCodeMode: plasmoid.configuration.useOpenCode
    property bool piMode: plasmoid.configuration.usePi
    property string openCodeAgent: plasmoid.configuration.openCodeAgent || ""
    property string openCodeWorkspaceCwd: plasmoid.configuration.openCodeWorkspaceCwd || ""
    property bool openCodeUseAgentModel: plasmoid.configuration.openCodeUseAgentModel !== false
    property var openCodeAgentsList: []
    property var openCodeProvidersList: []
    property var openCodeModelsList: []
    property var piProviderCandidates: []
    property var piProviderModelMap: ({})
    property bool piModelsFetching: false
    property var piModelFetchWaiters: []
    property bool fetchingAgentsInProgress: false
    property bool fetchingOpenCodeConfig: false
    property var openCodeAgentFetchWaiters: []
    property bool desktopSelectionEnabled: plasmoid.configuration.desktopSelectionEnabled === true
    property bool voiceEnabled: plasmoid.configuration.voiceEnabled === true
    property bool voiceTtsEnabled: plasmoid.configuration.voiceTtsEnabled === true
    property string compiledSystemPrompt: ""
    property string compiledMemoryBlock: ""
    property var sysInfo: ({
    })
    property var pendingSysInfoCommands: ({
    })
    property int sysInfoPending: 0
    property bool compactingContext: false
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
    property bool userScrolledUp: false
    // Keep the viewport stable while a response grows.  A response must not
    // yank the user to the newest bubble; only an explicit jump-to-latest
    // action releases this lock.
    property bool responseScrollLocked: false
    property real responseScrollY: 0
    property bool responseScrollUserMoved: false
    property bool restoringResponseScroll: false
    property bool titleGenerationInProgress: false
    property string titleGenerationSessionId: ""
    property bool plasmaShellWatchdogRunning: false
    // Tool-call context is kept separate from the visible chat model. This
    // lets an OpenAI-compatible provider complete an MCP round-trip without
    // rendering protocol messages as ordinary chat bubbles.
    property var mcpFollowupMessages: []
    property int mcpToolRound: 0
    property var mcpPendingOperations: ({})
    property int mcpOperationCounter: 0
    property int queueCounter: 0
    property int popupPreferredWidth: plasmoid.configuration.customPopupWidth > 0 ? plasmoid.configuration.customPopupWidth : 760
    property int popupPreferredHeight: plasmoid.configuration.customPopupHeight > 0 ? plasmoid.configuration.customPopupHeight : 760
    readonly property bool popupIsDark: {
        var mode = plasmoid.configuration.appearanceMode || 0;
        if (mode === 1)
            return false;

        if (mode === 2)
            return true;

        return Qt.styleHints.colorScheme === Qt.Dark;
    }
    property bool keysLoaded: false
    property var walletApiKeys: ({})
    property bool _initialLoadDone: false
    property string sessionHistoryLoadError: ""
    property bool sessionHistoryLoadBlocked: false

    signal clearChatInput()

    VoiceManager {
        id: voiceManager

        onTextRecognized: function(text) {
            if (voiceManager.autoSend) {
                root.chatInputText = text;
                root.sendMessage();
            } else {
                root.chatInputText += (root.chatInputText ? " " : "") + text;
            }
        }

        onErrorOccurred: function(errorText) {
            console.error("Voice Error: " + errorText);
            // Optionally show a notification
            let message = Sec.sanitizeForShell(errorText || "Unknown voice error");
            root.fileReaderDs.connectSource("notify-send -i dialog-error " + Sec.quoteForShell("Voice Error") + " " + Sec.quoteForShell(message) + " #voice-error");
        }
    }

    // Expose voiceManager as a root property so dynamically loaded children
    // (e.g. FullRepresentationContent via Loader) can access it via root.voiceManager
    property var voiceManagerRef: voiceManager

    function ensureWalletLoaded() {
        if (!keysLoaded) {
            keysLoaded = true;
            loadKWalletKeysAtStartup();
        }
    }

    function scheduleWalletReload() {
        walletReloadTimer.restart();
    }

    function focusInput() {
        Qt.callLater(function() {
            if (typeof msgInput !== "undefined" && msgInput) {
                msgInput.forceActiveFocus();
                if (typeof msgInput.focusTimerRef !== "undefined" && msgInput.focusTimerRef)
                    msgInput.focusTimerRef.start();

            }
        });
    }

    function fetchPiModels(callback) {
        if (callback)
            root.piModelFetchWaiters = (root.piModelFetchWaiters || []).concat([callback]);
        if (root.piModelsFetching)
            return;
        root.piModelsFetching = true;
        piDiscoveryDs.connectSource("python3 " + Sec.quoteForShell(root.getHelperPath()) + " get_pi_models #pi-models-" + Date.now());
    }

    function triggerInitialLoad() {
        if (_initialLoadDone)
            return ;

        _initialLoadDone = true;
        startupTimer.stop(); // Stop background timer if we triggered early
        // Load sessions immediately so UI has chat list / current chat ready
        loadSessions();
        // Defer wallet and sys info slightly so initial layout/rendering is unblocked
        lazyWalletTimer.start();
        lazySysInfoTimer.start();
    }

    function pad2(v) {
        return v < 10 ? ("0" + v) : String(v);
    }

    function nowTime(ts) {
        var d = ts ? new Date(ts) : new Date();
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }

    function formatDateTime(ts) {
        return new Date(ts).toLocaleString(undefined, {
            "year": "numeric",
            "month": "short",
            "day": "2-digit",
            "hour": "2-digit",
            "minute": "2-digit"
        });
    }

    function makeSessionId() {
        return "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000);
    }

    function parseSessions() {
        root.sessionHistoryLoadError = "";
        root.sessionHistoryLoadBlocked = false;
        var raw = String(plasmoid.configuration.chatSessionsJson || "[]");
        if (raw.length > 25000000) {
            root.sessionHistoryLoadError = "Stored chat history is too large to load safely.";
            root.sessionHistoryLoadBlocked = true;
            return [];
        }
        try {
            var arr = JSON.parse(raw);
            if (!Array.isArray(arr)) return [];
            var valid = [];
            var seenIds = {};
            for (var i = 0; i < arr.length; i++) {
                if (!arr[i] || typeof arr[i] !== "object") continue;
                var session = arr[i];
                session.value = Sec.validateSessionId(session.value) || makeSessionId();
                while (seenIds[session.value]) session.value = makeSessionId();
                seenIds[session.value] = true;
                if (!Array.isArray(session.messages)) session.messages = [];
                session.messages = session.messages.filter(function(message) {
                    return message && typeof message === "object";
                });
                if (session.archived === undefined) session.archived = false;
                if (["provider", "opencode", "pi"].indexOf(session.source) < 0)
                    session.source = session.openCodeSessionId ? "opencode" : "provider";
                for (var j = 0; j < session.messages.length; j++) {
                    var message = session.messages[j];
                    if (message.content === undefined || message.content === null)
                        message.content = "";
                    else if (typeof message.content !== "string")
                        message.content = String(message.content);
                    if (message.content.length > root.maxMessageChars) {
                        message.content = message.content.substring(0, root.maxMessageChars) + "\n[message truncated]";
                        if (!root.sessionHistoryLoadError)
                            root.sessionHistoryLoadError = "One or more stored messages exceeded the safe display limit and were truncated.";
                    }
                    if (!message.at) message.at = session.updatedAt || session.createdAt || Date.now();
                    if (!message.time) message.time = nowTime(message.at);
                }
                if (!session.updatedAt) session.updatedAt = session.createdAt || Date.now();
                valid.push(session);
            }
            return valid;
        } catch (e) {
            root.sessionHistoryLoadError = "Stored chat history could not be parsed. It was left untouched.";
            root.sessionHistoryLoadBlocked = true;
            return [];
        }
    }

    function persistSessions() {
        if (root.sessionHistoryLoadBlocked)
            return;
        try {
            var encoded = JSON.stringify(root.sessions);
            if (encoded.length > 25000000) {
                root.sessionHistoryLoadError = "Chat history is too large to persist safely; older messages should be removed or exported.";
                console.warn("KDE AI Chat: session history is too large to persist.");
                return;
            }
            root.sessionHistoryLoadError = "";
            plasmoid.configuration.chatSessionsJson = encoded;
            plasmoid.configuration.lastSessionId = root.currentSessionId;
        } catch (e) {
            console.error("KDE AI Chat: failed to persist sessions:", e);
        }
    }

    function sortSessionsByUpdated() {
        var copy = root.sessions.slice();
        copy.sort(function(a, b) {
            if (!!a.archived !== !!b.archived)
                return a.archived ? 1 : -1;

            return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0);
        });
        root.sessions = copy;
    }

    function historySessionTint(sessionData) {
        if (!sessionData)
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05);

        if (sessionData.value === root.currentSessionId && sessionData.source === "opencode")
            return Qt.rgba(0.2, 0.48, 0.92, 0.22);

        if (sessionData.source === "opencode")
            return Qt.rgba(0.2, 0.48, 0.92, 0.1);

        if (sessionData.value === root.currentSessionId)
            return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18);

        return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05);
    }

    function sessionSubtitle(sessionData) {
        var parts = [];
        if (sessionData.source === "opencode")
            parts.push("OpenCode");

        if (sessionData.archived)
            parts.push("Archived");

        parts.push("Updated " + root.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()));
        return parts.join(" · ");
    }

    function sessionIndexById(sessionId) {
        for (var i = 0; i < root.sessions.length; i++) {
            if (root.sessions[i].value === sessionId)
                return i;

        }
        return -1;
    }

    // Session overrides are deliberately stored on the session object rather
    // than in global plasmoid configuration.  This makes provider/model
    // changes apply to the current chat immediately without affecting other
    // chats.
    function getSessionProperty(sessionId, key, defaultValue) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0 || !root.sessions[idx] || root.sessions[idx][key] === undefined || root.sessions[idx][key] === null)
            return defaultValue;
        return root.sessions[idx][key];
    }

    function setSessionProperty(sessionId, key, value) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return;
        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        session[key] = value;
        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId) {
            // Keep the live mode in sync with a setting saved in the dialog.
            if (key === "source") {
                root.openCodeMode = value === "opencode";
                root.piMode = value === "pi";
            }
        }
        persistSessions();
    }

    // Apply a dialog's complete draft in one model update.  Per-chat settings
    // are shown in the history sidebar, so assigning root.sessions once is
    // important: a dozen individual writes otherwise rebuild that ListView
    // a dozen times and can make plasmashell appear hung.
    function setSessionOverrides(sessionId, overrides) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0 || !overrides)
            return false;

        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var previousSource = session.source || "provider";
        var changed = false;
        for (var key in overrides) {
            if (!Object.prototype.hasOwnProperty.call(overrides, key))
                continue;
            if (session[key] !== overrides[key])
                changed = true;
            session[key] = overrides[key];
        }
        if (!changed)
            return true;
        if (session.source !== "opencode" && previousSource === "opencode")
            session.openCodeSessionId = "";
        if (session.value === root.currentSessionId) {
            session.messages = root.messages.slice();
            session.text = root.currentSessionTitle || session.text;
        }

        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId) {
            root.openCodeMode = session.source === "opencode";
            root.piMode = session.source === "pi";
            root.openCodeAgent = session.openCodeAgent || "";
            root.openCodeWorkspaceCwd = session.openCodeWorkspaceCwd || "";
        }
        persistSessions();
        return true;
    }

    function getEffectiveProvider(sessionId) {
        var override = String(getSessionProperty(sessionId, "chatProvider", "") || "").trim();
        return override || plasmoid.configuration.provider || "openai";
    }

    function getEffectiveModel(sessionId) {
        var override = String(getSessionProperty(sessionId, "chatModel", "") || "").trim();
        if (override)
            return override;
        return getProviderConfig(getEffectiveProvider(sessionId), sessionId).model || "";
    }

    function _mcpServers() {
        var raw = String(plasmoid.configuration.mcpServersJson || "");
        if (!raw || raw.length > 200000)
            return [];
        try {
            var servers = JSON.parse(raw);
            return Array.isArray(servers) ? servers.slice(0, 32) : [];
        } catch (e) {
            return [];
        }
    }

    function _mcpFunctionName(serverId, toolName) {
        return "mcp_" + String(serverId || "server").replace(/[^A-Za-z0-9_-]/g, "_")
            + "_" + String(toolName || "tool").replace(/[^A-Za-z0-9_-]/g, "_");
    }

    function mcpToolDefinitions() {
        if (plasmoid.configuration.enableMcpTools !== true)
            return [];

        var defs = [{
            "type": "function",
            "function": {
                "name": "web_search",
                "description": "Search the public web and return a few relevant results.",
                "parameters": {
                    "type": "object",
                    "properties": {"query": {"type": "string", "description": "The search query"}},
                    "required": ["query"]
                }
            }
        }];
        var servers = _mcpServers();
        var totalTools = 0;
        for (var i = 0; i < servers.length && totalTools < 100; i++) {
            var server = servers[i] || {};
            var tools = Array.isArray(server.tools) ? server.tools : [];
            for (var j = 0; j < tools.length && totalTools < 100; j++) {
                var tool = tools[j] || {};
                if (!tool.name)
                    continue;
                defs.push({
                    "type": "function",
                    "function": {
                        "name": _mcpFunctionName(server.id || server.name, tool.name),
                        "description": tool.description || ("MCP tool " + tool.name),
                        "parameters": tool.inputSchema || tool.parameters || {"type": "object"}
                    }
                });
                totalTools++;
            }
        }
        return defs;
    }

    function _mcpResultText(data) {
        var stdout = data && data["stdout"] ? String(data["stdout"]).trim() : "";
        if (stdout.length > 500000)
            stdout = stdout.substring(0, 500000) + "\n[tool output truncated]";
        if (!stdout)
            return JSON.stringify({"status": "error", "message": String((data && data["stderr"]) || "MCP helper returned no output")});
        try {
            return JSON.stringify(JSON.parse(stdout));
        } catch (e) {
            return JSON.stringify({"status": "ok", "raw": stdout});
        }
    }

    function _startMcpOperation(command, payload, callback) {
        var token = "#mcp-tool-" + (++root.mcpOperationCounter) + "-" + Date.now();
        root.mcpPendingOperations[token] = callback;
        var encoded = Sec.base64Encode(JSON.stringify(payload || {}));
        var cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " "
            + command + " " + Sec.rawShellSnippetQuote(encoded);
        fileReaderDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " " + token);
    }

    function executeMcpTool(toolName, argumentsObject, callback) {
        var args = argumentsObject || {};
        if (toolName === "web_search") {
            _startMcpOperation("mcp_web_search", {"query": String(args.query || "")}, callback);
            return;
        }
        var servers = _mcpServers();
        for (var i = 0; i < servers.length; i++) {
            var server = servers[i] || {};
            var tools = Array.isArray(server.tools) ? server.tools : [];
            for (var j = 0; j < tools.length; j++) {
                var tool = tools[j] || {};
                if (_mcpFunctionName(server.id || server.name, tool.name) !== toolName)
                    continue;
                _startMcpOperation("mcp_query", {
                    "serverCommand": server.command || "",
                    "serverArgs": Array.isArray(server.args) ? server.args : [],
                    "method": "tools/call",
                    "params": {"name": tool.name, "arguments": args}
                }, callback);
                return;
            }
        }
        callback(JSON.stringify({"status": "error", "message": "Unknown MCP tool: " + toolName}));
    }

    function configuredSessionSource() {
        if (plasmoid.configuration.useOpenCode === true)
            return "opencode";
        if (plasmoid.configuration.usePi === true)
            return "pi";
        return "provider";
    }

    function applySessionSource(session) {
        var source = session && session.source ? String(session.source) : configuredSessionSource();
        if (source !== "opencode" && source !== "pi")
            source = "provider";
        root.openCodeMode = source === "opencode";
        root.piMode = source === "pi";
        root.openCodeAgent = session && session.openCodeAgent !== undefined
            ? String(session.openCodeAgent || "") : String(plasmoid.configuration.openCodeAgent || "");
        root.openCodeWorkspaceCwd = session && session.openCodeWorkspaceCwd !== undefined
            ? String(session.openCodeWorkspaceCwd || "") : String(plasmoid.configuration.openCodeWorkspaceCwd || "");
        return source;
    }

    function requestIsCurrent(sessionId, generation) {
        return !!sessionId && root.currentSessionId === sessionId
            && root.activeRequestSessionId === sessionId
            && root.requestGeneration === generation;
    }

    function invalidateActiveRequest(processQueue) {
        var cancelledSessionId = root.activeRequestSessionId;
        root.requestGeneration++;
        var piRequests = root.pendingPiRequests || {};
        var piKeys = Object.keys(piRequests);
        for (var piIndex = 0; piIndex < piKeys.length; piIndex++) {
            var piEntry = piRequests[piKeys[piIndex]];
            if (piEntry && piEntry.sessionId === cancelledSessionId) {
                if (piEntry.source) {
                    try { piTerminalDs.disconnectSource(piEntry.source); } catch (e) {}
                }
                delete piRequests[piKeys[piIndex]];
            }
        }
        root.pendingPiRequests = piRequests;
        root.activeRequestSessionId = "";
        if (root.activeXhr) {
            try { root.activeXhr.abort(); } catch (e) {}
            root.activeXhr = null;
        }
        root.openCodeActiveSessionId = "";
        root.openCodeRequestFinalized = true;
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        root.resetProviderStreamingState();
        root.loading = false;
        root.compactionGeneration++;
        if (root.compactionXhr) {
            try { root.compactionXhr.abort(); } catch (e) {}
            root.compactionXhr = null;
            root.compactionSessionId = "";
            root.compactingContext = false;
        }
        if (processQueue)
            processNextQueuedMessage();
    }

    function beginRequest(sessionId) {
        root.requestGeneration++;
        root.activeRequestSessionId = sessionId;
        root.openCodeRequestFinalized = false;
        return root.requestGeneration;
    }

    function handleMcpToolCalls(toolCalls, requestArgs, assistantMessage) {
        if (!Array.isArray(toolCalls) || toolCalls.length === 0)
            return false;
        toolCalls = toolCalls.slice(0, 20);
        if (root.mcpToolRound >= 3) {
            root.mcpFollowupMessages = [];
            pushErrorMessage("MCP tool-call limit reached; the model did not finish after three tool rounds.");
            processNextQueuedMessage();
            return true;
        }

        root.loading = true;
        var results = [];
        var next = function(index) {
            if (!requestIsCurrent(requestArgs.sessionId, requestArgs.generation)) {
                root.mcpFollowupMessages = [];
                return;
            }
            if (index >= toolCalls.length) {
                root.mcpFollowupMessages = root.mcpFollowupMessages.concat([{
                    "role": "assistant",
                    "content": assistantMessage.content || "",
                    "tool_calls": toolCalls
                }]);
                for (var r = 0; r < results.length; r++)
                    root.mcpFollowupMessages.push(results[r]);
                root.mcpToolRound++;
                doOpenAICompatRequest(requestArgs.baseUrl, requestArgs.apiKey, requestArgs.model,
                    requestArgs.extraHeaders, requestArgs.modelLabel, requestArgs.sessionId, requestArgs.generation);
                return;
            }
            var call = toolCalls[index] || {};
            var fn = call.function || {};
            var parsedArgs = {};
            try {
                if (typeof fn.arguments === "string" && fn.arguments.length <= 200000)
                    parsedArgs = JSON.parse(fn.arguments);
                else if (typeof fn.arguments !== "string")
                    parsedArgs = fn.arguments || {};
            } catch (e) {
                parsedArgs = {};
            }
            executeMcpTool(fn.name || "", parsedArgs, function(resultText) {
                results.push({
                    "role": "tool",
                    "tool_call_id": call.id || ("mcp-call-" + index),
                    "content": resultText
                });
                next(index + 1);
            });
        };
        next(0);
        return true;
    }

    function createSession(switchToNew) {
        if (switchToNew && root.loading)
            invalidateActiveRequest(false);
        var s = {
            "value": makeSessionId(),
            "text": "New Chat",
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": configuredSessionSource(),
            "openCodeSessionId": "",
            "messages": []
        };
        root.sessions = [s].concat(root.sessions);
        if (switchToNew) {
            root.currentSessionId = s.value;
            root.currentSessionTitle = s.text;
            root.messages = [];
            applySessionSource(s);
            resetResponseScrollPosition();
        root.playingMessageIndex = -1;
        if (voiceManager && voiceManager.isPlaying) { voiceManager.stopTTS(); }
            root.currentStreamIndex = -1;
            root.currentStreamText = "";
            root.currentStreamReasoning = "";
            root.currentStreamExtractedReasoning = "";
            root.streamingResponse = false;
            root.editingMessageIndex = -1;
            root.editingDraft = "";
            root.editingSessionId = "";
            root.editingSessionDraft = "";
            root.renamingCurrentChat = false;
            root.currentChatRenameDraft = "";
            root.historyOnlyMode = false;
            root.focusInput();
        }
        persistSessions();
    }

    function resetUnreadableSessionHistory() {
        root.sessionHistoryLoadError = "";
        root.sessionHistoryLoadBlocked = false;
        root.sessions = [];
        createSession(true);
    }

    function loadSessions() {
        root.sessions = parseSessions();
        if (root.sessions.length === 0)
            createSession(true);

        var preferred = plasmoid.configuration.lastSessionId || "";
        var idx = sessionIndexById(preferred);
        if (idx < 0)
            idx = 0;

        root.currentSessionId = root.sessions[idx].value;
        root.currentSessionTitle = root.sessions[idx].text;
        root.messages = root.sessions[idx].messages || [];
        applySessionSource(root.sessions[idx]);
        sortSessionsByUpdated();
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var s = Object.assign({
        }, updated[idx]);
        s.text = root.currentSessionTitle || "New Chat";
        s.messages = root.messages;
        if (touchUpdatedAt !== false)
            s.updatedAt = Date.now();

        updated[idx] = s;
        root.sessions = updated;
        if (touchUpdatedAt !== false)
            sortSessionsByUpdated();

        persistSessions();
    }

    function setCurrentSessionSource(source) {
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.source = source || "provider";
        item.archived = false;
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function setSessionArchived(sessionId, archived) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.archived = !!archived;
        item.updatedAt = Date.now();
        updated[idx] = item;
        root.sessions = updated;
        sortSessionsByUpdated();
        persistSessions();
    }

    function switchSession(sessionId) {
        if (!sessionId || sessionId === root.currentSessionId)
            return ;

        // A response must never be allowed to write into the newly selected
        // session. Invalidate callbacks before changing the active model.
        invalidateActiveRequest(false);
        saveCurrentSessionState(false);
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        root.currentSessionId = root.sessions[idx].value;
        root.currentSessionTitle = root.sessions[idx].text;
        root.messages = root.sessions[idx].messages || [];
        applySessionSource(root.sessions[idx]);
        root.playingMessageIndex = -1;
        if (voiceManager && voiceManager.isPlaying) { voiceManager.stopTTS(); }
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        root.editingSessionId = "";
        root.editingSessionDraft = "";
        root.renamingCurrentChat = false;
        root.currentChatRenameDraft = "";
        persistSessions();
        resetResponseScrollPosition();
        scrollToBottom(true);
        root.focusInput();
        if (!root.loading)
            Qt.callLater(root.processNextQueuedMessage);
    }

    function renameCurrentSession(newTitle) {
        var title = (newTitle || "").trim();
        if (title === "")
            title = "New Chat";

        root.currentSessionTitle = title;
        saveCurrentSessionState(true);
    }

    function startSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        root.editingSessionId = sessionId;
        root.editingSessionDraft = root.sessions[idx].text || "";
    }

    function cancelSessionRename() {
        root.editingSessionId = "";
        root.editingSessionDraft = "";
    }

    function saveSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var title = (root.editingSessionDraft || "").trim();
        if (title === "")
            title = "New Chat";

        var updated = root.sessions.slice();
        var s = Object.assign({
        }, updated[idx]);
        s.text = title;
        s.updatedAt = Date.now();
        updated[idx] = s;
        root.sessions = updated;
        if (root.currentSessionId === sessionId)
            root.currentSessionTitle = title;

        sortSessionsByUpdated();
        persistSessions();
        cancelSessionRename();
    }

    function deleteSession(sessionId) {
        if (root.sessions.length <= 1)
            return ;

        if (sessionId === root.currentSessionId)
            invalidateActiveRequest(false);
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        updated.splice(idx, 1);
        root.sessions = updated;
        var helper = getHelperPath();
        if (helper) {
            var deletePayload = Sec.base64Encode(JSON.stringify({"sessionId": sessionId}));
            fileReaderDs.connectSource("python3 " + Sec.quoteForShell(helper) + " delete_session_schedules " + Sec.rawShellSnippetQuote(deletePayload) + " #delete-session-schedules-" + Date.now());
        }
        if (root.currentSessionId === sessionId) {
            var next = root.sessions[0];
            root.currentSessionId = next.value;
            root.currentSessionTitle = next.text;
            root.messages = next.messages || [];
            applySessionSource(next);
        }
        cancelSessionRename();
        persistSessions();
    }

    function deleteMessage(index) {
        var copy = root.messages.slice();
        if (index < 0 || index >= copy.length)
            return ;

        copy.splice(index, 1);
        root.messages = copy;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
    }

    function saveEditedMessage() {
        var i = root.editingMessageIndex;
        if (i < 0 || i >= root.messages.length)
            return ;

        if ((root.messages[i].role || "") === "error") {
            root.editingMessageIndex = -1;
            root.editingDraft = "";
            return ;
        }
        // Cancel any active streaming/loading requests first
        stopStreaming();
        var role = root.messages[i].role || "";
        var isQueued = role === "queued";
        var copy = isQueued ? root.messages.slice() : root.messages.slice(0, i + 1);
        var item = Object.assign({
        }, copy[i]);
        item.content = root.editingDraft;
        item.at = Date.now();
        item.time = nowTime(item.at);
        copy[i] = item;
        root.messages = copy;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
        // Re-run from edited user prompt so assistant response reflects the new text.
        if (role === "user") {
            root.userScrolledUp = false;
            sendMessageByIndex(i);
        }
    }

    function openCodeBaseUrl() {
        var raw = String(plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim();
        var valid = Sec.validateHttpUrl(raw);
        if (!valid) return "";
        return valid.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    }

    function currentOpenCodeSessionId(sessionId) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return "";

        return Sec.validateRemoteSessionId(root.sessions[idx].openCodeSessionId || "");
    }

    function setCurrentOpenCodeSessionId(remoteSessionId, sessionId) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.openCodeSessionId = Sec.validateRemoteSessionId(remoteSessionId || "");
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        if (!root.openCodeMode)
            return ;

        setCurrentOpenCodeSessionId("");
    }

    function openOpenCodeInTerminal(sessionId) {
        var sid = Sec.validateRemoteSessionId(sessionId || currentOpenCodeSessionId() || "");
        var safeSid = Sec.sanitizeForShell(sid);
        var runCmd = safeSid ? ("opencode --session " + Sec.quoteForShell(safeSid)) : "opencode";
        var fullTerminalCmd = "konsole -e " + runCmd + " || x-terminal-emulator -e " + runCmd + " || xterm -e " + runCmd;
        soundDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(fullTerminalCmd) + " #open-terminal-" + Date.now());
    }

    function captureScreenRegion() {
        var timestamp = Date.now();
        var savePath = "/tmp/kdeaichat_shot_" + timestamp + ".png";
        var cmd = "umask 077 && spectacle -r -b -n -o " + Sec.quoteForShell(savePath);
        fileReaderDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #spectacle-shot-" + timestamp + "|" + savePath);
    }

    function syncOpenCodeSessionHistory() {
        var sessionId = root.currentSessionId;
        var generation = beginRequest(sessionId);
        var remoteSessionId = currentOpenCodeSessionId(sessionId);
        if (!remoteSessionId) {
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            return;
        }
        root.loading = true;
        var xhr = new XMLHttpRequest();
        root.activeXhr = xhr;
        try { xhr.open("GET", openCodeBaseUrl() + "/session/" + encodeURIComponent(remoteSessionId) + "/message", true); } catch (e) {
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage("Sync failed: invalid OpenCode endpoint.");
            return;
        }
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (!requestIsCurrent(sessionId, generation))
                return;
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    if (xhr.responseText.length > 10000000)
                        throw new Error("OpenCode history response is too large");
                    var arr = JSON.parse(xhr.responseText);
                    if (Array.isArray(arr)) {
                        var newMsgs = [];
                        for (var i = 0; i < Math.min(arr.length, 500); i++) {
                            var item = arr[i] || {};
                            var info = item.info || {};
                            var parts = item.parts || [];
                            var role = info.role || "user";
                            var modelLabel = (info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode");
                            var combinedText = "";
                            var ctx = [];
                            for (var p = 0; p < parts.length; p++) {
                                var part = parts[p] || {};
                                if (part.type === "text") {
                                    combinedText += part.text || part.content || "";
                                } else if (part.type === "tool-invocation") {
                                    var toolName = part.toolName || part.tool || "";
                                    var toolArgs = part.args || part.input || {};
                                    if (toolName !== "") {
                                        var desc = toolName;
                                        if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                                            desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                                        else if (toolArgs.command)
                                            desc += ": " + String(toolArgs.command).substring(0, 60);
                                        ctx.push(desc);
                                    }
                                }
                            }
                            if (combinedText.length > root.maxMessageChars)
                                combinedText = combinedText.substring(0, root.maxMessageChars) + "\n[history message truncated]";
                            var normalizedTokens = {};
                            if (item.tokens) {
                                var rawTokens = item.tokens || {};
                                normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                                normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                                if (rawTokens.reasoning !== undefined) normalizedTokens.reasoning = rawTokens.reasoning;
                                if (rawTokens.cache !== undefined) normalizedTokens.cache = rawTokens.cache;
                            }
                            var ts = info.createdAt ? new Date(info.createdAt).getTime() : Date.now();
                            newMsgs.push({
                                "role": role,
                                "content": combinedText || "(empty)",
                                "model": role === "user" ? "You" : modelLabel,
                                "id": info.id || ("msg-" + i),
                                "at": ts,
                                "time": nowTime(ts),
                                "contextItems": ctx,
                                "tokens": normalizedTokens.input !== undefined ? normalizedTokens : undefined,
                                "cost": item.cost || undefined,
                                "openCodeSessionId": remoteSessionId
                            });
                        }
                        if (newMsgs.length > 0) {
                            var idx = sessionIndexById(root.currentSessionId);
                            if (idx >= 0) {
                                root.messages = newMsgs;
                                var updated = root.sessions.slice();
                                var sItem = Object.assign({}, updated[idx]);
                                sItem.messages = newMsgs;
                                updated[idx] = sItem;
                                root.sessions = updated;
                                saveCurrentSessionState(true);
                                scrollToBottom();
                            }
                        }
                    }
                } catch (err) {
                    pushErrorMessage("Failed to parse synced messages: " + err);
                }
            } else {
                pushErrorMessage("Sync failed: OpenCode returned HTTP " + xhr.status);
            }
        };
        xhr.onerror = function() {
            if (!requestIsCurrent(sessionId, generation)) return;
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage("Sync failed: Could not reach OpenCode server at " + openCodeBaseUrl());
        };
        try { xhr.send(); } catch (e) {
            if (requestIsCurrent(sessionId, generation)) {
                root.loading = false;
                root.activeXhr = null;
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Sync failed: " + e);
            }
        }
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        if (errObj) {
            if (errObj.data && errObj.data.message)
                return prefix + errObj.data.message;

            if (errObj.message)
                return prefix + errObj.message;

            if (errObj.name)
                return prefix + errObj.name;

        }
        return prefix + (fallbackText || "Unknown error");
    }

    function beginAssistantStreaming(modelLabel) {
        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel;

    }

    function updateAssistantStreamingContent(text, modelLabel) {
        var incoming = String(text || "");
        if (incoming === "")
            return ;
        if (incoming.length > root.maxMessageChars)
            incoming = incoming.substring(0, root.maxMessageChars);

        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel;

        if (root.openCodeAssistantMessageIndex < 0) {
            var ts = Date.now();
            root.messages = root.messages.concat([{
                "role": "assistant",
                "content": "",
                "reasoning": "",
                "time": nowTime(ts),
                "at": ts,
                "model": root.openCodeAssistantModelLabel || "OpenCode"
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.currentStreamIndex = root.openCodeAssistantMessageIndex;
            root.currentStreamText = incoming;
            root.streamingResponse = true;
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);

            return ;
        }
        var existing = root.currentStreamText || "";
        var newText = "";
        if (incoming.indexOf(existing) === 0)
            newText = incoming;
        else if (existing.indexOf(incoming) === 0)
            newText = existing;
        else
            newText = existing + incoming;
        root.currentStreamText = newText.length > root.maxMessageChars
            ? newText.substring(0, root.maxMessageChars) + "\n[response truncated]"
            : newText;
        root.streamingResponse = root.currentStreamText !== "";
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    function appendAssistantReasoning(text) {
        var incoming = String(text || "");
        if (incoming === "")
            return;
        if (incoming.length > root.maxMessageChars)
            incoming = incoming.substring(0, root.maxMessageChars);

        if (root.openCodeAssistantMessageIndex < 0 && root.currentStreamIndex < 0) {
            var ts = Date.now();
            root.messages = root.messages.concat([{
                "role": "assistant",
                "content": "",
                "reasoning": "",
                "time": nowTime(ts),
                "at": ts,
                "model": root.openCodeAssistantModelLabel || ""
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.currentStreamIndex = root.openCodeAssistantMessageIndex;
            root.streamingResponse = true;
        }
        root.currentStreamReasoning = (root.currentStreamReasoning + incoming).substring(0, root.maxMessageChars);
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);
    }

    function finishOpenCodeRequest(requestSessionId, requestGeneration) {
        if (requestSessionId !== undefined && !requestIsCurrent(requestSessionId, requestGeneration))
            return;
        if (!root.activeRequestSessionId || root.openCodeRequestFinalized)
            return;
        root.openCodeRequestFinalized = true;

        if (root.openCodeAssistantMessageIndex >= 0 && root.currentStreamIndex === root.openCodeAssistantMessageIndex) {
            var msgs = root.messages.slice();
            if (msgs[root.openCodeAssistantMessageIndex]) {
                msgs[root.openCodeAssistantMessageIndex].content = root.currentStreamText;
                msgs[root.openCodeAssistantMessageIndex].reasoning = root.currentStreamReasoning;
                root.messages = msgs;
            }
            root.currentStreamIndex = -1;
            root.currentStreamText = "";
            root.currentStreamReasoning = "";
            root.currentStreamExtractedReasoning = "";
        }
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

        root.loading = false;
        root.activeXhr = null;
        root.openCodeActiveSessionId = "";
        root.activeRequestSessionId = "";
        root.requestGeneration++;
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        root.streamingResponse = false;
        try { saveCurrentSessionState(true); } catch (e) { console.error("OpenCode cleanup save failed:", e); }
        try { triggerNotificationSound(); } catch (e) { console.error("OpenCode notification failed:", e); }
        try { processNextQueuedMessage(); } catch (e) { console.error("OpenCode queue processing failed:", e); }
    }

    function ensureOpenCodeEventStream() {
        // OpenCode delivers incremental updates over this side-channel.  When
        // the user opts out of streaming, rely on the completed /message
        // response instead and do not keep an SSE connection alive.
        if (plasmoid.configuration.disableStreaming === true) {
            if (root.openCodeEventXhr) {
                root.openCodeEventXhr.abort();
                root.openCodeEventXhr = null;
            }
            return ;
        }

        if (root.openCodeEventXhr)
            return ;
        if (!openCodeBaseUrl())
            return ;

        var xhr = new XMLHttpRequest();
        var buffer = "";
        var offset = 0;
        var overflowed = false;
        var url = openCodeBaseUrl() + "/event";
        root.openCodeEventXhr = xhr;
        try { xhr.open("GET", url, true); } catch (e) {
            root.openCodeEventXhr = null;
            return;
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.responseText.length > 20000000) {
                overflowed = true;
                try { xhr.abort(); } catch (e) {}
                root.openCodeEventXhr = null;
                return;
            }
            var delta = xhr.responseText.slice(offset);
            offset = xhr.responseText.length;
            buffer += delta;
            if (buffer.length > 1000000) {
                overflowed = true;
                buffer = "";
                try { xhr.abort(); } catch (e) {}
                root.openCodeEventXhr = null;
                return;
            }
            while (true) {
                var split = buffer.indexOf("\n\n");
                if (split < 0)
                    break;

                var block = buffer.slice(0, split);
                buffer = buffer.slice(split + 2);
                var lines = block.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("data:") !== 0)
                        continue;

                    try {
                        var eventObj = JSON.parse(lines[i].slice(5).trim());
                        handleOpenCodeEvent(eventObj);
                    } catch (eventError) {
                    }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.openCodeEventXhr = null;
                if (!overflowed && root.openCodeMode && plasmoid.configuration.disableStreaming !== true)
                    Qt.callLater(ensureOpenCodeEventStream);

            }
        };
        xhr.onerror = function() {
            root.openCodeEventXhr = null;
        };
        try {
            xhr.send();
        } catch (streamError) {
            root.openCodeEventXhr = null;
        }
    }

    function _notifyOpenCodeAgentFetchWaiters() {
        var waiters = root.openCodeAgentFetchWaiters || [];
        root.openCodeAgentFetchWaiters = [];
        for (var i = 0; i < waiters.length; i++) {
            if (waiters[i])
                Qt.callLater(waiters[i]);
        }
    }

    function normalizeOpenCodeAgents(payload) {
        var values = [];
        function isSubagent(name, metadata) {
            var mode = metadata && (metadata.mode || metadata.agentMode || metadata.type || metadata.kind);
            if (mode && /sub[-_ ]?agent|internal/i.test(String(mode)))
                return true;
            if (metadata && (metadata.hidden === true || metadata.internal === true || metadata.isSubagent === true))
                return true;
            // OpenCode exposes these implementation agents through /agent as
            // well. They are not selectable top-level agent profiles.
            return ["compaction", "explore", "general", "summary", "title"].indexOf(String(name).toLowerCase()) >= 0;
        }
        function add(value, keyName) {
            var name = typeof value === "string" ? value : (value && (value.id || value.name || value.value || value.text));
            name = name || keyName || "";
            if (isSubagent(name, value))
                return;
            if (name && typeof name === "string" && name.length <= 128 && values.indexOf(name) < 0 && values.length < 100)
                values.push(name);
        }
        function read(value) {
            if (!value)
                return;
            if (Array.isArray(value)) {
                for (var i = 0; i < value.length; i++) add(value[i]);
                return;
            }
            if (typeof value !== "object") {
                add(value);
                return;
            }
            var known = ["agents", "agent", "data", "items", "all", "connected"];
            var found = false;
            for (var k = 0; k < known.length; k++) {
                if (value[known[k]] !== undefined) {
                    read(value[known[k]]);
                    found = true;
                }
            }
            if (!found) {
                var keys = Object.keys(value);
                for (var j = 0; j < keys.length; j++) {
                    if (keys[j] !== "default" && keys[j] !== "default_agent")
                        add(value[keys[j]], keys[j]);
                }
            }
        }
        read(payload);
        var result = [];
        for (var n = 0; n < values.length; n++)
            result.push({ "text": values[n], "value": values[n] });
        return result;
    }

    function _finishOpenCodeAgents(list, defaultAgent) {
        root.openCodeAgentsList = list || [];
        var selectedAgent = "";
        for (var i = 0; i < root.openCodeAgentsList.length; i++) {
            if (root.openCodeAgentsList[i].value === defaultAgent || root.openCodeAgentsList[i].value === root.openCodeAgent) {
                selectedAgent = root.openCodeAgentsList[i].value;
                break;
            }
        }
        if (!selectedAgent && root.openCodeAgentsList.length > 0)
            selectedAgent = root.openCodeAgentsList[0].value;
        if (selectedAgent)
            root.openCodeAgent = selectedAgent;
        root.fetchingAgentsInProgress = false;
        _notifyOpenCodeAgentFetchWaiters();
    }

    function fetchOpenCodeAgents(callback) {
        if (root.fetchingAgentsInProgress) {
            if (callback)
                root.openCodeAgentFetchWaiters = (root.openCodeAgentFetchWaiters || []).concat([callback]);
            return null;
        }
        root.fetchingAgentsInProgress = true;
        root.openCodeAgentFetchWaiters = callback ? [callback] : [];

        var baseUrl = openCodeBaseUrl();
        if (!baseUrl) {
            _finishOpenCodeAgents([], "");
            return null;
        }
        var agentEndpoint = baseUrl + "/agent";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", agentEndpoint, true);
        xhr.timeout = 1000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    if (xhr.responseText.length > 2000000)
                        throw new Error("agent response is too large");
                    var data = JSON.parse(xhr.responseText);
                    var agentList = normalizeOpenCodeAgents(data);
                    if (agentList.length > 0) {
                        _finishOpenCodeAgents(agentList, data.default_agent || data.default || "");
                        return;
                    }
                } catch (e) {}
            }
            runFallbackAgentFileFetch();
        };
        xhr.ontimeout = function() {
            runFallbackAgentFileFetch();
        };
        xhr.onerror = function() {
            runFallbackAgentFileFetch();
        };
        try {
            xhr.send();
        } catch (err) {
            runFallbackAgentFileFetch();
        }
    }

    function fetchOpenCodeProvidersAndModels(callback) {
        // Treat every refresh as a snapshot. Keeping the previous arrays when
        // the server returns an empty/error response made the sidebar claim a
        // refresh while visibly showing stale provider/model choices.
        root.openCodeProvidersList = [];
        root.openCodeModelsList = [];
        var baseUrl = openCodeBaseUrl();
        if (!baseUrl) {
            root.openCodeProvidersList = [];
            root.openCodeModelsList = [];
            root.fetchingOpenCodeConfig = false;
            if (callback) callback();
            return;
        }
        var endpoints = [baseUrl + "/config/providers", baseUrl + "/provider"];
        var endpointIndex = 0;
        function requestNext() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", endpoints[endpointIndex], true);
            xhr.timeout = 2000;
            var requestFinished = false;
            var finish = function(success) {
                if (requestFinished) return;
                requestFinished = true;
                if (success || endpointIndex >= endpoints.length - 1) {
                    if (callback) callback();
                    return;
                }
                endpointIndex++;
                requestNext();
            };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        if (xhr.responseText.length > 2000000)
                            throw new Error("provider response is too large");
                        var data = JSON.parse(xhr.responseText);
                        var allProvs = data.providers || data.all || data.connected || [];
                        var provList = [];
                        var modelList = [];
                        for (var i = 0; i < allProvs.length; i++) {
                            var p = allProvs[i];
                            var providerId = p && (p.id || p.name);
                            if (providerId) {
                                provList.push({ "id": providerId, "name": p.name || providerId });
                                if (p.models && typeof p.models === "object") {
                                    var mKeys = Object.keys(p.models);
                                    for (var j = 0; j < mKeys.length; j++)
                                        modelList.push(providerId + "/" + mKeys[j]);
                                }
                            }
                        }
                        root.openCodeProvidersList = provList;
                        root.openCodeModelsList = modelList;
                        finish(provList.length > 0);
                        return;
                    } catch (e) {}
                }
                finish(false);
            };
            xhr.ontimeout = function() { finish(false); };
            xhr.onerror = function() { finish(false); };
            try { xhr.send(); } catch (e) { finish(false); }
        }
        requestNext();
    }

    function runFallbackAgentFileFetch() {
        var cmd = "python3 -c \""
            + "import json, os, glob; "
            + "paths = [os.path.expanduser('~/.config/opencode/opencode.json'), './opencode.json']; "
            + "agents = []; default = ''; "
            + "for p in paths:\n"
            + "    if os.path.exists(p):\n"
            + "        try:\n"
            + "            d = json.load(open(p))\n"
            + "            ag = d.get('agent', {})\n"
            + "            if isinstance(ag, dict):\n"
            + "                for n, spec in ag.items():\n"
            + "                    item = dict(spec) if isinstance(spec, dict) else {}\n"
            + "                    item['name'] = n; item['id'] = n; agents.append(item)\n"
            + "            if d.get('default_agent'): default = d.get('default_agent')\n"
            + "        except Exception: pass\n"
            + "unique = {}; "
            + "for item in agents:\n"
            + "    key = item.get('id') or item.get('name') if isinstance(item, dict) else item\n"
            + "    if key and key not in unique: unique[key] = item\n"
            + "agents = list(unique.values()); "
            + "print(json.dumps({'agents': agents, 'default': default}))"
            + "\" #fetch-opencode-agents";
        fileReaderDs.connectSource(cmd);
    }

    function fetchDesktopSelection() {
        // Read the X11 primary selection (currently selected text on desktop)
        // Uses xsel or xclip as fallback. The result pre-fills the chat input and opens the panel.
        var cmd = "xsel --primary --output 2>/dev/null || xclip -out -selection primary 2>/dev/null #desktop-selection";
        fileReaderDs.connectSource(cmd);
    }

    function handleOpenCodeEvent(eventObj) {
        var props = eventObj && eventObj.properties ? eventObj.properties : {
        };
        var sessionId = props.sessionID || props.sessionId || "";
        if (!sessionId || sessionId !== root.openCodeActiveSessionId)
            return ;

        if (eventObj.type === "message.updated") {
            var info = props.info || {
            };
            if (info.role === "assistant") {
                root.openCodeAssistantServerMessageId = info.id || root.openCodeAssistantServerMessageId;
                beginAssistantStreaming((info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode"));
                if (info.error && !root.openCodeErrorShownForRequest) {
                    root.openCodeErrorShownForRequest = true;
                    pushErrorMessage(extractReadableError("OpenCode: ", info.error, "Request failed."));
                }
            }
        } else if (eventObj.type === "message.part.updated") {
            var part = props.part || {
            };
            if (part.type === "text" && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
                updateAssistantStreamingContent(part.text || "", "OpenCode");

            if ((part.type === "reasoning" || part.type === "thinking" || part.type === "step-start" || part.type === "step") && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
                appendAssistantReasoning(part.text || part.content || part.summary || part.title || "");

            // Track tool invocations as context items on the assistant message
            if (part.type === "tool-invocation" && root.openCodeAssistantMessageIndex >= 0) {
                var toolName = part.toolName || part.tool || "";
                var toolArgs = part.args || part.input || {
                };
                var toolState = part.state || "";
                if (toolName !== "") {
                    var copy = root.messages.slice();
                    var item = Object.assign({
                    }, copy[root.openCodeAssistantMessageIndex]);
                    var ctx = item.contextItems || [];
                    // Build a concise description of the tool call
                    var desc = toolName;
                    if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                        desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                    else if (toolArgs.command)
                        desc += ": " + String(toolArgs.command).substring(0, 60);
                    else if (toolArgs.query || toolArgs.pattern)
                        desc += ": " + (toolArgs.query || toolArgs.pattern);
                    // Avoid duplicates
                    var exists = false;
                    for (var ci = 0; ci < ctx.length; ci++) {
                        if (ctx[ci] === desc) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        ctx = ctx.concat([desc]);
                        item.contextItems = ctx;
                        copy[root.openCodeAssistantMessageIndex] = item;
                        root.messages = copy;
                    }
                }
            }
        } else if (eventObj.type === "session.error") {
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(extractReadableError("OpenCode: ", props.error, "Session error."));
            }
        } else if (eventObj.type === "session.status") {
            var status = props.status || {
            };
            if (status.type === "idle")
                finishOpenCodeRequest();

        } else if (eventObj.type === "session.idle") {
            finishOpenCodeRequest();
        } else if (eventObj.type === "permission.asked") {
            var p = props.permission || {
            };
            var permId = String(p.id || "").substring(0, 256);
            if (permId !== "") {
                var tool = String(p.tool || "").substring(0, 256);
                var args = p.arguments || {
                };
                var argStr = "";
                try {
                    argStr = typeof args === "string" ? args : JSON.stringify(args, null, 2);
                } catch (e) {
                    argStr = String(args);
                }
                var msg = {
                    "role": "permission_request",
                    "content": "OpenCode is asking for permission to run **" + tool + "**:\n\n```json\n" + argStr + "\n```",
                    "model": "OpenCode Security",
                    "id": "perm-" + permId,
                    "permissionId": permId,
                    "tool": tool,
                    "arguments": args,
                    "openCodeSessionId": sessionId,
                    "status": "pending",
                    "at": Date.now()
                };
                root.messages = root.messages.concat([msg]);
                saveCurrentSessionState(true);
                if (!root.userScrolledUp)
                    Qt.callLater(scrollToBottom);

            }
        } else if (eventObj.type === "permission.replied") {
            var pr = props.permission || {
            };
            var pId = pr.id || "";
            var response = pr.response || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "permission_request" && copy[i].permissionId === pId) {
                    copy[i].status = (response === "allow" ? "allowed" : "denied");
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "session.next.step.ended") {
            var copy = root.messages.slice();
            var updated = false;
            for (var idx = copy.length - 1; idx >= 0; idx--) {
                if (copy[idx].role === "assistant") {
                    var item = Object.assign({
                    }, copy[idx]);
                    item.tokens = props.tokens;
                    item.cost = props.cost;
                    copy[idx] = item;
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.asked") {
            var requestID = String(props.requestID || props.id || eventObj.id || "").substring(0, 256);
            if (requestID !== "") {
                // Parse full structured questions array from OpenCode
                var questions = Array.isArray(props.questions) ? props.questions.slice(0, 20) : [];
                var qText = "";
                var parsedQuestions = [];
                var allowCustom = true;
                if (questions.length > 0) {
                    // Structured question(s) with options
                    var parts = [];
                    for (var qi = 0; qi < questions.length; qi++) {
                        var qItem = questions[qi] && typeof questions[qi] === "object" ? questions[qi] : {};
                        var header = String(qItem.header || "").substring(0, 256);
                        var questionText = String(qItem.question || "").substring(0, 4000);
                        var opts = Array.isArray(qItem.options) ? qItem.options.slice(0, 100) : [];
                        var multiple = qItem.multiple === true;
                        var custom = qItem.custom !== undefined ? qItem.custom === true : true;
                        if (!custom)
                            allowCustom = false;

                        var partText = "";
                        if (header)
                            partText += "**" + header + "**: ";

                        partText += questionText;
                        if (opts.length > 0) {
                            var optLabels = [];
                            for (var oi = 0; oi < opts.length; oi++) {
                                var option = opts[oi] && typeof opts[oi] === "object" ? opts[oi] : {};
                                optLabels.push(String(option.label || "").substring(0, 512));
                            }
                            partText += "\n\nOptions: " + optLabels.join(", ");
                        }
                        if (multiple)
                            partText += " *(select multiple)*";

                        parts.push(partText);
                        parsedQuestions.push({
                            "header": header,
                            "question": questionText,
                            "options": opts.map(function(option) {
                                var safeOption = option && typeof option === "object" ? Object.assign({}, option) : {};
                                safeOption.label = String(safeOption.label || "").substring(0, 512);
                                safeOption.description = String(safeOption.description || "").substring(0, 1000);
                                return safeOption;
                            }),
                            "multiple": multiple,
                            "custom": custom
                        });
                    }
                    qText = parts.join("\n\n---\n\n");
                } else {
                    // Fallback: legacy format
                    var q = props.question || {
                    };
                    if (typeof props.question === "string")
                        qText = props.question;
                    else if (q.text)
                        qText = q.text;
                    else if (q.content)
                        qText = q.content;
                    else
                        qText = props.text || props.content || "OpenCode requires clarification.";
                }
                var alreadyExists = false;
                for (var i = 0; i < root.messages.length; i++) {
                    if (root.messages[i].role === "question_request" && root.messages[i].questionId === requestID) {
                        alreadyExists = true;
                        break;
                    }
                }
                if (!alreadyExists) {
                    var msg = {
                        "role": "question_request",
                        "content": "OpenCode is asking a question:\n\n**" + qText + "**",
                        "model": "OpenCode Question",
                        "id": "question-" + requestID,
                        "questionId": requestID,
                        "questions": parsedQuestions,
                        "allowCustom": allowCustom,
                        "openCodeSessionId": sessionId,
                        "status": "pending",
                        "at": Date.now()
                    };
                    root.messages = root.messages.concat([msg]);
                    saveCurrentSessionState(true);
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom);

                    // Send desktop notification so user sees the question even if plasmoid is collapsed
                    if (plasmoid.configuration.playNotificationSound) {
                        var shortQText = qText.length > 80 ? qText.substring(0, 77) + "..." : qText;
                        soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u normal -i dialog-question \"OpenCode needs your input\" " + Sec.quoteForShell(shortQText) + " #opencode-question-notify");
                        triggerNotificationSound();
                    }
                }
            }
        } else if (eventObj.type === "question.replied") {
            var qId = props.requestID || props.id || eventObj.id || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "answering...") {
                        copy[i].status = "answered";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.rejected" || eventObj.type === "question.cancelled") {
            var qId = props.requestID || props.id || eventObj.id || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "dismissing...") {
                        copy[i].status = "dismissed";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        }
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback, requestSessionId, requestGeneration) {
        var sessionId = requestSessionId || root.activeRequestSessionId || root.currentSessionId;
        var generation = requestGeneration !== undefined ? requestGeneration : root.requestGeneration;
        var isCurrent = function() { return requestIsCurrent(sessionId, generation); };
        var existing = currentOpenCodeSessionId(sessionId);
        if (existing !== "") {
            if (isCurrent())
                successCallback(existing);
            return;
        }
        var xhr = new XMLHttpRequest();
        var finished = false;
        var fail = function(message) {
            if (finished || !isCurrent()) return;
            finished = true;
            root.activeXhr = null;
            failureCallback(message);
        };
        try {
            xhr.open("POST", openCodeBaseUrl() + "/session", true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
            xhr.ontimeout = function() {
                fail("OpenCode: session creation timed out" + (xhr.timeout > 0 ? " after " + (xhr.timeout / 1000) + " seconds." : "."));
            };
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || finished)
                    return;
                if (!isCurrent()) return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        if (xhr.responseText.length > 1000000)
                            throw new Error("session response is too large");
                        var obj = JSON.parse(xhr.responseText);
                        var remoteId = Sec.validateRemoteSessionId(obj.id || "");
                        if (remoteId === "") {
                            fail("OpenCode: server created a session without a valid id.");
                            return;
                        }
                        finished = true;
                        root.activeXhr = null;
                        setCurrentOpenCodeSessionId(remoteId, sessionId);
                        successCallback(remoteId);
                    } catch (parseError) {
                        fail("OpenCode: could not parse session creation response.");
                    }
                } else {
                    fail("OpenCode: failed to create a server session (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                fail("OpenCode: could not reach " + openCodeBaseUrl() + "/session. Check that the server is still running.");
            };
            root.activeXhr = xhr;
            var sessionPayload = {"title": root.currentSessionTitle || "KDE AI Chat"};
            var cwd = getSessionProperty(sessionId, "openCodeWorkspaceCwd", root.openCodeWorkspaceCwd || "");
            if (cwd && String(cwd).trim() !== "")
                sessionPayload.directory = String(cwd).trim();
            xhr.send(JSON.stringify(sessionPayload));
        } catch (sendError) {
            fail("OpenCode: failed to create session: " + sendError);
        }
    }

    function doOpenCodeRequest(requestSessionId, requestGeneration) {
        var sessionId = requestSessionId || root.activeRequestSessionId || root.currentSessionId;
        var generation = requestGeneration !== undefined ? requestGeneration : root.requestGeneration;
        var requestFinalized = false;
        var isCurrent = function() { return requestIsCurrent(sessionId, generation); };
        function failOpenCodeRequest(message) {
            if (requestFinalized || !isCurrent())
                return;
            requestFinalized = true;
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(message);
            }
            finishOpenCodeRequest(sessionId, generation);
        }

        ensureOpenCodeEventStream();
        if (!isCurrent()) return;
        root.loading = true;
        root.streamingResponse = false;
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        ensureCurrentOpenCodeSession(function(remoteSessionId) {
            if (!isCurrent() || requestFinalized) return;
            var xhr = new XMLHttpRequest();
            var modelId = String(getSessionProperty(sessionId, "openCodeModel", plasmoid.configuration.openCodeModel || "") || "").trim();
            var providerId = String(getSessionProperty(sessionId, "openCodeProvider", plasmoid.configuration.openCodeProvider || "") || "").trim();
            var agentName = String(getSessionProperty(sessionId, "openCodeAgent", root.openCodeAgent || "") || "").trim();
            var useAgentModel = getSessionProperty(sessionId, "openCodeUseAgentModel", root.openCodeUseAgentModel) !== false;
            root.activeXhr = xhr;
            root.openCodeActiveSessionId = remoteSessionId;
            try {
                xhr.open("POST", openCodeBaseUrl() + "/session/" + encodeURIComponent(remoteSessionId) + "/message", true);
                xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
                xhr.ontimeout = function() {
                    failOpenCodeRequest("OpenCode: request timed out" + (xhr.timeout > 0 ? " after " + (xhr.timeout / 1000) + " seconds." : "."));
                };
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE || requestFinalized || !isCurrent())
                        return;
                    if (xhr.status < 200 || xhr.status >= 300) {
                        var suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
                        failOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
                        return;
                    }
                    try {
                        if (xhr.responseText.length > 10000000)
                            throw new Error("OpenCode response is too large");
                        var obj = JSON.parse(xhr.responseText);
                        if (obj.info && obj.info.id)
                            root.openCodeAssistantServerMessageId = obj.info.id;
                        if (obj.info && obj.info.error && !root.openCodeErrorShownForRequest) {
                            root.openCodeErrorShownForRequest = true;
                            pushErrorMessage(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
                        }
                        if (obj.parts && obj.parts.length > 0) {
                            var combined = "";
                            var combinedReasoning = "";
                            for (var i = 0; i < obj.parts.length; i++) {
                                if (obj.parts[i].type === "text")
                                    combined += String(obj.parts[i].text || obj.parts[i].content || "");
                                else if (obj.parts[i].type === "reasoning" || obj.parts[i].type === "thinking" || obj.parts[i].type === "step")
                                    combinedReasoning += obj.parts[i].text || obj.parts[i].content || obj.parts[i].summary || "";
                            }
                            if (combined.length > root.maxMessageChars)
                                combined = combined.substring(0, root.maxMessageChars) + "\n[response truncated]";
                            if (combinedReasoning.length > root.maxMessageChars)
                                combinedReasoning = combinedReasoning.substring(0, root.maxMessageChars) + "\n[reasoning truncated]";
                            if (combinedReasoning !== "") appendAssistantReasoning(combinedReasoning);
                            var responseLabel = providerId && modelId ? providerId + "/" + modelId : "OpenCode";
                            if (combined !== "") updateAssistantStreamingContent(combined, responseLabel);
                            else if (!root.openCodeErrorShownForRequest && root.openCodeAssistantMessageIndex < 0)
                                updateAssistantStreamingContent("(empty response)", responseLabel);
                        }
                    } catch (parseResponseError) {
                        failOpenCodeRequest("OpenCode: could not parse the server response.");
                        return;
                    }
                    requestFinalized = true;
                    finishOpenCodeRequest(sessionId, generation);
                };
                xhr.onerror = function() {
                    failOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.");
                };

                var lastMsg = root.messages[root.messages.length - 1] || {};
                var parts = [];
                if (lastMsg.attachments && lastMsg.attachments.length > 0) {
                    var messagePayload = buildMessageContent(lastMsg.content || "", lastMsg.attachments, "openai");
                    if (typeof messagePayload === "string") {
                        parts.push({"type": "text", "text": messagePayload});
                    } else {
                        for (var p = 0; p < messagePayload.length; p++) {
                            var part = messagePayload[p];
                            if (part.type === "text") {
                                parts.push({"type": "text", "text": part.text});
                            } else if (part.type === "image_url" && part.image_url && part.image_url.url) {
                                var mimeParts = part.image_url.url.split(";")[0].split(":");
                                parts.push({"type": "file", "mime": mimeParts[1] || "image/jpeg", "url": part.image_url.url});
                            }
                        }
                    }
                } else {
                    parts.push({"type": "text", "text": lastMsg.content || ""});
                }
                var systemParts = [];
                var effectiveSystem = buildEffectiveSystemPrompt(sessionId);
                var effectiveMemory = buildEffectiveMemoryBlock(sessionId);
                if (effectiveSystem) systemParts.push(effectiveSystem);
                if (effectiveMemory) systemParts.push(effectiveMemory);
                var reqPayload = {"parts": parts};
                if (!agentName || !useAgentModel) {
                    reqPayload.model = {"providerID": providerId, "modelID": modelId};
                }
                if (agentName) reqPayload.agent = agentName;
                if (systemParts.length > 0) reqPayload.system = systemParts.join("\n\n");
                xhr.send(JSON.stringify(reqPayload));
            } catch (sendError) {
                failOpenCodeRequest("OpenCode: failed to send request: " + sendError);
            }
        }, function(errorMessage) {
            if (!isCurrent() || requestFinalized) return;
            requestFinalized = true;
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(errorMessage);
            }
            finishOpenCodeRequest(sessionId, generation);
        }, sessionId, generation);
    }

    function finishPiRequest(sessionId, generation) {
        if (!requestIsCurrent(sessionId, generation))
            return;
        root.loading = false;
        root.activeXhr = null;
        root.activeRequestSessionId = "";
        root.streamingResponse = false;
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.requestGeneration++;
        try { saveCurrentSessionState(true); } catch (e) { console.error("Pi session save failed:", e); }
        try { triggerNotificationSound(); } catch (e) { console.error("Pi notification failed:", e); }
        try { processNextQueuedMessage(); } catch (e) { console.error("Pi queue processing failed:", e); }
    }

    function runPiCommand(payload, sessionId, generation, messageId) {
        if (!requestIsCurrent(sessionId, generation))
            return;
        var marker = "pi-request-" + (++root.piRequestCounter) + "-" + Date.now();
        var pending = Object.assign({}, root.pendingPiRequests || {});
        pending[marker] = {"sessionId": sessionId, "generation": generation, "messageId": messageId || ""};
        root.pendingPiRequests = pending;
        var helper = root.getHelperPath();
        if (!helper) {
            delete pending[marker];
            root.pendingPiRequests = pending;
            pushErrorMessage("Pi helper is not available in the installed widget.");
            finishPiRequest(sessionId, generation);
            return;
        }
        var encoded = Sec.base64Encode(JSON.stringify(payload || {}));
        var command = "python3 " + Sec.quoteForShell(helper) + " run_pi " + Sec.rawShellSnippetQuote(encoded);
        var source = command + " #" + marker;
        pending[marker].source = source;
        root.pendingPiRequests = pending;
        piTerminalDs.connectSource(source);
    }

    function runLocalPiCommand(cmdText, sessionId, generation) {
        var bare = String(cmdText || "").trim();
        if (bare.charAt(0) === "/") bare = bare.substring(1);
        var verb = bare.split(/\s+/)[0].toLowerCase();
        if (verb === "help") {
            var ts = Date.now();
            root.messages = root.messages.concat([{"role": "assistant", "content": "**Pi commands:**\n- `/help` — show available commands\n- `/version` — show the installed Pi version", "model": "Pi Agent", "time": nowTime(ts), "at": ts}]);
            finishPiRequest(sessionId, generation);
            return;
        }
        if (verb === "version") {
            var id = "pi-version-" + Date.now();
            var versionTs = Date.now();
            root.messages = root.messages.concat([{"role": "assistant", "content": "Checking Pi version…", "model": "Pi Agent", "time": nowTime(versionTs), "at": versionTs, "id": id}]);
            runPiCommand({"version": true}, sessionId, generation, id);
            return;
        }
        pushErrorMessage("Unknown Pi command: `" + String(cmdText || "").trim() + "`\nType `/help` to see available commands.");
        finishPiRequest(sessionId, generation);
    }

    function doPiRequest(sessionId, generation) {
        if (!requestIsCurrent(sessionId, generation))
            return;
        var lastMsg = root.messages[root.messages.length - 1] || {};
        var prompt = String(lastMsg.content || "");
        if (prompt.trim().charAt(0) === "/") {
            root.loading = true;
            runLocalPiCommand(prompt, sessionId, generation);
            return;
        }
        if (lastMsg.attachments && lastMsg.attachments.length > 0) {
            var attachmentPrompt = buildMessageContent(prompt, lastMsg.attachments, "openai");
            if (typeof attachmentPrompt === "string") prompt = attachmentPrompt;
            else {
                prompt += "\n\n[Image attachments were supplied to the chat; describe them if supported by the Pi provider.]";
                for (var ai = 0; ai < attachmentPrompt.length; ai++)
                    if (attachmentPrompt[ai].type === "text") prompt += "\n" + attachmentPrompt[ai].text;
            }
        }
        if (prompt.length > 100000) {
            pushErrorMessage("Pi prompt is too large. Keep Pi prompts under 100,000 characters.");
            finishPiRequest(sessionId, generation);
            return;
        }
        var messageId = "pi-response-" + Date.now() + "-" + root.piRequestCounter;
        var ts = Date.now();
        root.messages = root.messages.concat([{"role": "assistant", "content": "Thinking…", "model": "Pi Agent", "time": nowTime(ts), "at": ts, "id": messageId}]);
        root.loading = true;
        root.streamingResponse = true;
        saveCurrentSessionState(true);
        runPiCommand({
            "sessionId": "kde-ai-chat-" + sessionId,
            "provider": String(getSessionProperty(sessionId, "chatProvider", plasmoid.configuration.piProvider || "") || "").trim(),
            "model": String(getSessionProperty(sessionId, "chatModel", plasmoid.configuration.piModel || "") || "").trim(),
            "prompt": prompt,
            "timeout": Number(plasmoid.configuration.requestTimeout || 60)
        }, sessionId, generation, messageId);
    }

    function handlePiResponse(sourceName, stdout, stderr, exitCode) {
        var keys = Object.keys(root.pendingPiRequests || {});
        var marker = "";
        for (var i = 0; i < keys.length; i++) {
            if (sourceName.indexOf(keys[i]) !== -1) { marker = keys[i]; break; }
        }
        if (!marker)
            return;
        var pending = root.pendingPiRequests[marker];
        var remaining = Object.assign({}, root.pendingPiRequests);
        delete remaining[marker];
        root.pendingPiRequests = remaining;
        var response = {};
        try { response = JSON.parse(String(stdout || "").trim()); } catch (e) {}
        var code = response.exitCode !== undefined ? Number(response.exitCode) : Number(exitCode || 0);
        var out = response.stdout !== undefined ? String(response.stdout || "") : String(stdout || "");
        var err = response.stderr !== undefined ? String(response.stderr || "") : String(stderr || "");
        if (!requestIsCurrent(pending.sessionId, pending.generation))
            return;
        if (code !== 0) {
            var failed = root.messages.slice();
            for (var fi = failed.length - 1; fi >= 0; fi--) {
                if (failed[fi].id === pending.messageId) { failed.splice(fi, 1); break; }
            }
            root.messages = failed;
            pushErrorMessage("Pi agent failed: " + (err.trim() || out.trim() || ("process exited with code " + code)));
            finishPiRequest(pending.sessionId, pending.generation);
            return;
        }
        var result = out.trim() || "(empty response)";
        var updated = root.messages.slice();
        for (var ui = 0; ui < updated.length; ui++) {
            if (updated[ui].id === pending.messageId) {
                updated[ui] = Object.assign({}, updated[ui], {"content": result, "model": "Pi Agent"});
                break;
            }
        }
        root.messages = updated;
        finishPiRequest(pending.sessionId, pending.generation);
    }

    function resetProviderStreamingState() {
        if (root.currentStreamIndex >= 0 && root.currentStreamIndex < root.messages.length) {
            var copy = root.messages.slice();
            var current = copy[root.currentStreamIndex];
            if (current && current.role === "assistant") {
                if (root.currentStreamText)
                    current.content = root.currentStreamText;
                if (root.currentStreamReasoning)
                    current.reasoning = root.currentStreamReasoning;
                if (!current.content && !current.reasoning)
                    copy.splice(root.currentStreamIndex, 1);
                root.messages = copy;
            }
        }
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;
    }

    function captureResponseScrollPosition() {
        if (root.responseScrollLocked)
            return;
        root.responseScrollLocked = true;
        root.responseScrollUserMoved = false;
        root.responseScrollY = root.msgListViewRef ? root.msgListViewRef.contentY : 0;
    }

    function restoreResponseScrollPosition() {
        if (!root.responseScrollLocked || root.responseScrollUserMoved || !root.msgListViewRef)
            return;
        var targetY = root.responseScrollY;
        Qt.callLater(function() {
            if (!root.responseScrollLocked || root.responseScrollUserMoved || !root.msgListViewRef)
                return;
            root.restoringResponseScroll = true;
            var view = root.msgListViewRef;
            var minY = view.originY;
            var maxY = Math.max(minY, view.contentHeight - view.height);
            view.contentY = Math.max(minY, Math.min(targetY, maxY));
            root.restoringResponseScroll = false;
        });
    }

    function resetResponseScrollPosition() {
        root.responseScrollLocked = false;
        root.responseScrollUserMoved = false;
        root.responseScrollY = 0;
    }

    function scrollToBottom(force) {
        if (force) {
            resetResponseScrollPosition();
            root.userScrolledUp = false;
        } else if (root.responseScrollLocked) {
            return;
        }
        Qt.callLater(function() {
            if (!force && root.responseScrollLocked)
                return;
            if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                root.msgListViewRef.positionViewAtIndex(root.msgListViewRef.count - 1, ListView.End);
                root.msgListViewRef.positionViewAtEnd();
            }
        });
    }

    function messageTimestampAt(index) {
        if (index < 0 || index >= root.messages.length)
            return Date.now();

        var m = root.messages[index] || {
        };
        return m.at || Date.now();
    }

    function messageDayKeyAt(index) {
        var d = new Date(messageTimestampAt(index));
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function dayBucketLabel(ts) {
        var target = new Date(ts);
        var now = new Date();
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        var targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate());
        var daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 8.64e+07);
        if (daysDiff === 0)
            return "Today";

        if (daysDiff === 1)
            return "Yesterday";

        if (daysDiff === 2)
            return "Day before yesterday";

        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear();
    }

    function countMessagesForDayKey(dayKey) {
        var count = 0;
        for (var i = 0; i < root.messages.length; i++) {
            if (messageDayKeyAt(i) === dayKey)
                count++;

        }
        return count;
    }

    function dayDividerLabelForIndex(index) {
        var key = messageDayKeyAt(index);
        return dayBucketLabel(messageTimestampAt(index)) + " (" + countMessagesForDayKey(key) + ")";
    }

    function formatMessageTime(message, index) {
        if (message && message.time)
            return message.time;

        return nowTime(messageTimestampAt(index));
    }

    function jumpOneMessageAbove() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = root.messages.length;

        var target = -1;
        for (var i = currentTop - 1; i >= 0; i--) {
            var msg = root.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            root.userScrolledUp = true;
            root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
        } else {
            root.userScrolledUp = true;
            root.msgListViewRef.positionViewAtBeginning();
        }
    }

    function jumpOneMessageBelow() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = -1;

        var target = -1;
        for (var i = currentTop + 1; i < root.messages.length; i++) {
            var msg = root.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            var isLastUser = true;
            for (var j = target + 1; j < root.messages.length; j++) {
                if (root.messages[j] && root.messages[j].role === "user") {
                    isLastUser = false;
                    break;
                }
            }
            if (isLastUser) {
                if (root.userScrolledUp) {
                    root.userScrolledUp = false;
                    root.scrollToBottom();
                }
            } else {
                root.userScrolledUp = true;
                root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
            }
        } else {
            if (root.userScrolledUp) {
                root.userScrolledUp = false;
                root.scrollToBottom();
            }
        }
    }

    function formatTokensUsage(tokens, cost) {
        if (!tokens)
            return "";

        var parts = [];
        if (tokens.input !== undefined)
            parts.push("Input: " + tokens.input);

        if (tokens.output !== undefined)
            parts.push("Output: " + tokens.output);

        if (tokens.reasoning !== undefined && tokens.reasoning > 0)
            parts.push("Reasoning: " + tokens.reasoning);

        if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
            parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);

        var res = parts.join(" | ");
        if (cost !== undefined && cost > 0)
            res += " | Cost: $" + cost.toFixed(5);

        return res;
    }

    function pushErrorMessage(text) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "error",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": ""
        }]);
        scrollToBottom();
        saveCurrentSessionState(true);
    }

    function retryFailedMessage(index) {
        if (index < 0 || index >= root.messages.length) return;
        var role = root.messages[index].role || "";
        if (role !== "error") return;
        
        var lastUserIdx = -1;
        for (var i = index - 1; i >= 0; i--) {
            var r = root.messages[i].role || "";
            if (r === "user" || r === "queued") {
                lastUserIdx = i;
                break;
            }
        }
        
        if (lastUserIdx >= 0) {
            stopStreaming();
            var copy = root.messages.slice(0, lastUserIdx + 1);
            root.messages = copy;
            clearCurrentOpenCodeSessionIfNeeded();
            saveCurrentSessionState(true);
            root.userScrolledUp = false;
            sendMessageByIndex(lastUserIdx);
        }
    }

    function regenerateResponse(index, promptModifier) {
        if (index <= 0 || index >= root.messages.length) return;
        var role = root.messages[index].role || "";
        if (role !== "assistant" && role !== "opencode_assistant") return;
        
        var lastUserIdx = index - 1;
        var userRole = root.messages[lastUserIdx].role || "";
        if (userRole !== "user" && userRole !== "queued") return;
        
        stopStreaming();
        var copy = root.messages.slice(0, lastUserIdx + 1);
        
        if (promptModifier) {
            var item = Object.assign({}, copy[lastUserIdx]);
            item.content = item.content + "\n\n" + promptModifier;
            item.at = Date.now();
            item.time = nowTime(item.at);
            copy[lastUserIdx] = item;
        }
        
        root.messages = copy;
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
        root.userScrolledUp = false;
        sendMessageByIndex(lastUserIdx);
    }

    function appendUserMessage(text, role, attachments) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": role || "user",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": role === "queued" ? (++root.queueCounter) : 0,
            "attachments": attachments || []
        }]);
        saveCurrentSessionState(true);
        if (!root.userScrolledUp && !root.responseScrollLocked)
            Qt.callLater(scrollToBottom);

    }

    function validateCurrentSendTarget() {
        if (root.openCodeMode)
            return validateOpenCodeConfig(root.currentSessionId);
        if (root.piMode)
            return "";

        var provider = root.getEffectiveProvider ? root.getEffectiveProvider(root.currentSessionId) : (plasmoid.configuration.provider || "openai");
        var providerCfg = getProviderConfig(provider, root.currentSessionId);
        return validateProviderConfig(provider, providerCfg);
    }

    function sendMessageByIndex(index) {
        // A normal user message starts a fresh MCP exchange.  Follow-up
        // requests from handleMcpToolCalls call the provider directly so
        // their protocol messages remain intact.
        root.mcpFollowupMessages = [];
        root.mcpToolRound = 0;
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;

        var source = root.messages[index] || {
        };
        captureResponseScrollPosition();
        var text = (source.content || "").trim();
        var hasAttachments = source.attachments && source.attachments.length > 0;
        if (!text && !hasAttachments)
            return ;

        var validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            pushErrorMessage(validationError);
            restoreResponseScrollPosition();
            return ;
        }
        if ((source.role || "") === "queued") {
            var copy = root.messages.slice();
            var queued = Object.assign({
            }, copy[index]);
            queued.role = "user";
            queued.at = Date.now();
            queued.time = nowTime(queued.at);
            copy[index] = queued;
            root.messages = copy;
            saveCurrentSessionState(true);
        }
        var requestSessionId = root.currentSessionId;
        var requestSource = root.openCodeMode ? "opencode" : (root.piMode ? "pi" : "provider");
        setCurrentSessionSource(requestSource);
        var requestGeneration = beginRequest(requestSessionId);
        if (root.openCodeMode) {
            doOpenCodeRequest(requestSessionId, requestGeneration);
            return ;
        }
        if (root.piMode) {
            doPiRequest(requestSessionId, requestGeneration);
            return ;
        }
        var provider = root.getEffectiveProvider(requestSessionId);
        var providerCfg = getProviderConfig(provider, requestSessionId);
        if (providerCfg.type === "anthropic")
            doAnthropicRequest(providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, requestSessionId, requestGeneration);
        else
            doOpenAICompatRequest(providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model, requestSessionId, requestGeneration);
    }

    function processNextQueuedMessage() {
        if (root.loading)
            return ;

        for (var i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].role || "") === "queued") {
                sendMessageByIndex(i);
                return ;
            }
        }
        // A scheduled trigger belongs to its target chat even when that chat
        // is not currently visible. Rotate through scheduled queues only when
        // the active request is idle; ordinary user queues stay attached to
        // their original chat and are never cancelled by this scan.
        for (var s = 0; s < root.sessions.length; s++) {
            var session = root.sessions[s] || {};
            if (session.value === root.currentSessionId) continue;
            var messages = Array.isArray(session.messages) ? session.messages : [];
            for (var m = 0; m < messages.length; m++) {
                if (messages[m] && messages[m].role === "queued" && messages[m].scheduled) {
                    if (!root.schedulerResumeSessionId)
                        root.schedulerResumeSessionId = root.currentSessionId;
                    root.switchSession(session.value);
                    return ;
                }
            }
        }
        if (root.schedulerResumeSessionId && root.schedulerResumeSessionId !== root.currentSessionId) {
            var resumeId = root.schedulerResumeSessionId;
            root.schedulerResumeSessionId = "";
            if (root.sessionIndexById(resumeId) >= 0) {
                root.switchSession(resumeId);
                return ;
            }
        }
        root.schedulerResumeSessionId = "";
        restoreResponseScrollPosition();
    }

    function _cleanGeneratedTitle(value) {
        var title = String(value || "").replace(/```[\s\S]*?```/g, "").trim();
        title = title.replace(/^['"`]+|['"`]+$/g, "").replace(/\s+/g, " ").trim();
        if (title.length > 80)
            title = title.substring(0, 77).replace(/\s+\S*$/, "") + "…";
        return title;
    }

    function maybeGenerateChatTitle() {
        if (plasmoid.configuration.autoNameChats === false || root.openCodeMode
                || root.titleGenerationInProgress || !root.currentSessionId)
            return;
        var currentTitle = (root.currentSessionTitle || "").trim().toLowerCase();
        if (currentTitle !== "" && currentTitle !== "new chat")
            return;

        var firstUser = "";
        var assistantCount = 0;
        for (var i = 0; i < root.messages.length; i++) {
            if (!firstUser && root.messages[i].role === "user")
                firstUser = String(root.messages[i].content || "").trim();
            if (root.messages[i].role === "assistant")
                assistantCount++;
        }
        if (!firstUser || assistantCount === 0)
            return;

        var sessionId = root.currentSessionId;
        var cfg = getProviderConfig(root.getEffectiveProvider(sessionId), sessionId);
        if (!cfg || !cfg.model || !cfg.baseUrl || (!cfg.allowEmptyKey && !cfg.apiKey))
            return;
        root.titleGenerationInProgress = true;
        root.titleGenerationSessionId = sessionId;

        var xhr = new XMLHttpRequest();
        var endpoint = String(cfg.baseUrl).replace(/\/$/, "");
        var isAnthropic = cfg.type === "anthropic";
        if (isAnthropic) {
            if (!endpoint.endsWith("/messages")) endpoint += "/messages";
        } else {
            endpoint += "/chat/completions";
        }
        var finished = false;
        function finish() {
            if (finished) return;
            finished = true;
            root.titleGenerationInProgress = false;
            root.titleGenerationSessionId = "";
        }
        xhr.timeout = 8000;
        xhr.ontimeout = finish;
        xhr.onerror = finish;
        try {
            xhr.open("POST", endpoint, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (isAnthropic) {
                xhr.setRequestHeader("x-api-key", cfg.apiKey);
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            } else if (cfg.apiKey) {
                xhr.setRequestHeader("Authorization", "Bearer " + cfg.apiKey);
            }
            if (cfg.headers) {
                for (var headerName in cfg.headers)
                    if (Object.prototype.hasOwnProperty.call(cfg.headers, headerName) && cfg.headers[headerName])
                        xhr.setRequestHeader(headerName, cfg.headers[headerName]);
            }
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300 && root.currentSessionId === sessionId) {
                    try {
                        if (xhr.responseText.length > 1000000)
                            throw new Error("title response is too large");
                        var response = JSON.parse(xhr.responseText);
                        var raw = isAnthropic
                            ? ((response.content && response.content[0] && response.content[0].text) || "")
                            : (((response.choices || [])[0] || {}).message || {}).content || "";
                        var title = _cleanGeneratedTitle(raw);
                        if (title && (root.currentSessionTitle || "New Chat").trim().toLowerCase() === "new chat") {
                            root.currentSessionTitle = title;
                            saveCurrentSessionState(false);
                        }
                    } catch (e) {}
                }
                finish();
            };
            var prompt = "Create a concise 3-6 word title for this conversation. Return only the title, no quotes or punctuation.\n\nUser message:\n" + firstUser.substring(0, 1200);
            var body = isAnthropic ? {
                model: cfg.model,
                max_tokens: 32,
                messages: [{ role: "user", content: prompt }]
            } : {
                model: cfg.model,
                stream: false,
                messages: [
                    { role: "system", content: "You name chats concisely." },
                    { role: "user", content: prompt }
                ]
            };
            xhr.send(JSON.stringify(body));
        } catch (e) {
            finish();
        }
    }

    function runPlasmaShellWatchdog(action) {
        if (!getHelperPath()) {
            plasmaShellWatchdogRunning = false;
            return;
        }
        var encoded = Sec.base64Encode(JSON.stringify({"action": action}));
        var token = "#plasmashell-watchdog-" + Date.now();
        var command = "python3 " + Sec.quoteForShell(getHelperPath())
            + " plasmashell_watchdog " + Sec.rawShellSnippetQuote(encoded) + " " + token;
        fileReaderDs.connectSource(command);
        plasmaShellWatchdogRunning = action !== "stop";
    }

    function syncPlasmaShellWatchdog() {
        if (plasmoid.configuration.autoRestartPlasmaShell === true) {
            runPlasmaShellWatchdog("start");
            plasmaShellHeartbeatTimer.start();
        } else {
            plasmaShellHeartbeatTimer.stop();
            if (plasmaShellWatchdogRunning)
                runPlasmaShellWatchdog("stop");
        }
    }

    function providerDisplayName(providerId) {
        return ProviderService.getProviderDisplayName(providerId, plasmoid.configuration);
    }

    function validateOpenCodeConfig(sessionId) {
        var missing = [];
        if (!openCodeBaseUrl())
            missing.push("a valid OpenCode HTTP(S) URL");
        var provider = String(getSessionProperty(sessionId, "openCodeProvider", plasmoid.configuration.openCodeProvider || "") || "").trim();
        var model = String(getSessionProperty(sessionId, "openCodeModel", plasmoid.configuration.openCodeModel || "") || "").trim();
        var agent = String(getSessionProperty(sessionId, "openCodeAgent", root.openCodeAgent || "") || "").trim();
        if (!provider && !agent)
            missing.push("OpenCode provider or agent");
        if (!model && !agent)
            missing.push("OpenCode model or agent");
        if (missing.length > 0)
            return "Cannot send yet. Configure: " + missing.join(", ") + ".";
        return "";
    }

    function validateProviderConfig(providerId, cfg) {
        if (!cfg)
            return "Provider configuration missing.";

        var missing = [];
        var name = providerDisplayName(providerId);
        if (!providerId)
            missing.push("provider");

        if (!cfg.baseUrl && cfg.type !== "anthropic")
            missing.push("base URL");

        if (!cfg.model)
            missing.push("model");

        if (cfg.type === "anthropic" && !cfg.apiKey)
            missing.push("API key");

        if (cfg.type !== "anthropic" && !cfg.allowEmptyKey && !cfg.apiKey)
            missing.push("API key");

        if (missing.length > 0)
            return "⚠️ Cannot send message with " + name + ". Missing: " + missing.join(", ") + ". Please open Widget Settings (Configure KDE AI Chat) to set your API key or model.";

        return "";
    }

    function sendMessage() {
        ensureWalletLoaded();
        try {
            var text = (root.chatInputText || "").trim();
            var attachments = root.attachedFiles || [];

            // Process Prompt Templates
            if (text.startsWith("/")) {
                var firstSpaceIndex = text.indexOf(" ");
                if (firstSpaceIndex === -1) firstSpaceIndex = text.indexOf("\n");
                var templateName = text.substring(1, firstSpaceIndex > -1 ? firstSpaceIndex : text.length).trim();
                var templatesStr = plasmoid.configuration.promptTemplates || "[]";
                try {
                    var templates = JSON.parse(templatesStr);
                    for (var i = 0; i < templates.length; i++) {
                        if (templates[i].name === templateName) {
                            var restOfText = firstSpaceIndex > -1 ? text.substring(firstSpaceIndex).trim() : "";
                            text = templates[i].prompt + (restOfText ? "\n\n" + restOfText : "");
                            break;
                        }
                    }
                } catch (e) {
                    console.log("Error parsing prompt templates:", e);
                }
            }

            if (text.length > 200000) {
                pushErrorMessage("Message is too large. Keep messages under 200,000 characters.");
                return;
            }
            if (text === "" && attachments.length === 0)
                return ;
            if (!attachmentsReadyToSend()) {
                pushErrorMessage("Please wait for attached files to finish loading before sending.");
                return;
            }

            for (var cleanupIndex = 0; cleanupIndex < attachments.length; cleanupIndex++)
                cleanupTemporaryAttachment(attachments[cleanupIndex].path || "");
            root.attachedFiles = [];
            root.chatInputText = "";
            root.clearChatInput();
            if (root.loading) {
                appendUserMessage(text, "queued", attachments);
                return ;
            }
            appendUserMessage(text, "user", attachments);
            sendMessageByIndex(root.messages.length - 1);
        } catch (err) {
            root.loading = false;
            root.activeXhr = null;
            pushErrorMessage("Send failed: " + err);
            processNextQueuedMessage();
        }
    }

    function getProviderConfig(provider, sessionId) {
        var providerId = provider || getEffectiveProvider(sessionId || root.currentSessionId);
        var cfg = ProviderService.getProviderConfig(providerId, plasmoid.configuration);
        cfg.baseUrl = Sec.validateHttpUrl(cfg.baseUrl);
        var walletKey = root.walletApiKeys ? String(root.walletApiKeys[providerId] || "").trim() : "";
        if (walletKey)
            cfg.apiKey = walletKey;
        var sessionModel = String(getSessionProperty(sessionId || root.currentSessionId, "chatModel", "") || "").trim();
        if (sessionModel)
            cfg.model = sessionModel;
        return cfg;
    }

    function buildEffectiveSystemPrompt(sessionId) {
        var enabled = getSessionProperty(sessionId, "chatSystemPromptEnabled", true) !== false;
        if (!enabled)
            return "";
        var parts = [];
        if (plasmoid.configuration.enableSystemPrompt !== false && compiledSystemPrompt)
            parts.push(compiledSystemPrompt);
        var chatPrompt = String(getSessionProperty(sessionId, "chatSystemPrompt", "") || "").trim();
        if (chatPrompt)
            parts.push("--- Chat-specific instructions ---\n" + chatPrompt + "\n--- End chat-specific instructions ---");
        var responseLength = Number(getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var instructions = ["", "Keep the response short and focused, around 256 output tokens unless the task requires more.", "Give a balanced response, around 1024 output tokens at most.", "Give a detailed response, around 4096 output tokens at most.", "Give a comprehensive response, up to roughly 8192 output tokens when useful."];
        if (responseLength > 0 && responseLength < instructions.length)
            parts.push("Response length preference: " + instructions[responseLength]);
        return parts.join("\n\n");
    }

    function buildEffectiveMemoryBlock(sessionId) {
        if (getSessionProperty(sessionId, "chatMemoryEnabled", true) === false)
            return "";
        var parts = [];
        if (compiledMemoryBlock)
            parts.push(compiledMemoryBlock);
        var chatMemory = String(getSessionProperty(sessionId, "chatMemory", "") || "").trim();
        if (chatMemory)
            parts.push("## Chat Memory\nThe following facts are specific to this conversation:\n" + chatMemory);
        return parts.join("\n\n");
    }

    function responseMaxTokens(sessionId, defaultValue) {
        var selected = Number(getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var limits = [defaultValue || 0, 512, 1024, 4096, 8192];
        return selected >= 0 && selected < limits.length ? limits[selected] : (defaultValue || 0);
    }

    function latestCompactedSummary(sessionId) {
        var list = sessionId && sessionId !== root.currentSessionId ? (root.sessions[sessionIndexById(sessionId)] || {}).messages || [] : root.messages;
        for (var i = list.length - 1; i >= 0; i--) {
            if (list[i].role === "system_compacted")
                return String(list[i].content || "");
        }
        return "";
    }

    function limitContextMessages(messageRoles) {
        var list = Array.isArray(messageRoles) ? messageRoles.slice() : [];
        var configured = Number(plasmoid.configuration.contextMessageLimit);
        var maxMessages = configured >= 0 ? Math.min(100, configured + 1) : 100;
        if (list.length > maxMessages)
            list = list.slice(list.length - maxMessages);
        var totalChars = 0;
        var firstKept = list.length;
        for (var i = list.length - 1; i >= 0; i--) {
            var size = 0;
            try { size = JSON.stringify(list[i]).length; } catch (e) { size = String(list[i].content || "").length; }
            if (totalChars + size > 6000000 && firstKept < list.length)
                break;
            totalChars += size;
            firstKept = i;
        }
        return list.slice(firstKept);
    }

    function buildOpenAICompatPayload(sessionId) {
        var targetSessionId = sessionId || root.currentSessionId;
        var arr = [];
        var effectiveSystem = buildEffectiveSystemPrompt(targetSessionId);
        var effectiveMemory = buildEffectiveMemoryBlock(targetSessionId);
        if (effectiveSystem)
            arr.push({"role": "system", "content": effectiveSystem});
        if (effectiveMemory)
            arr.push({"role": "system", "content": effectiveMemory});

        var messageRoles = [];
        var latestCompactedContent = "";
        
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "system_compacted") {
                latestCompactedContent = m.content;
                messageRoles = []; // clear earlier messages!
            } else if (m.role === "user" || m.role === "assistant") {
                messageRoles.push(m);
            }
        }
        
        if (latestCompactedContent) {
            arr.push({
                "role": "system",
                "content": "Previous conversation summary: " + latestCompactedContent
            });
        }

        messageRoles = limitContextMessages(messageRoles);

        for (var j = 0; j < messageRoles.length; j++) {
            var rm = messageRoles[j];
            if (rm.role === "user" && rm.attachments && rm.attachments.length > 0) {
                var payloadContent = buildMessageContent(rm.content, rm.attachments, "openai");
                arr.push({
                    "role": rm.role,
                    "content": payloadContent
                });
            } else {
                arr.push({
                    "role": rm.role,
                    "content": rm.content
                });
            }
        }
        // Tool-call and tool-result messages are protocol context only; do
        // not add them to the visible chat history.
        for (var k = 0; k < root.mcpFollowupMessages.length; k++)
            arr.push(root.mcpFollowupMessages[k]);
        return arr;
    }

    function buildAnthropicPayload() {
        var arr = [];
        var messageRoles = [];
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "user" || m.role === "assistant") {
                messageRoles.push(m);
            }
        }

        messageRoles = limitContextMessages(messageRoles);

        for (var j = 0; j < messageRoles.length; j++) {
            var rm = messageRoles[j];
            if (rm.role === "user" && rm.attachments && rm.attachments.length > 0) {
                var payloadContent = buildMessageContent(rm.content, rm.attachments, "anthropic");
                arr.push({
                    "role": rm.role,
                    "content": payloadContent
                });
            } else {
                arr.push({
                    "role": rm.role,
                    "content": rm.content
                });
            }
        }
        return arr;
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel, requestSessionId, requestGeneration) {
        var sessionId = requestSessionId || root.activeRequestSessionId || root.currentSessionId;
        var generation = requestGeneration !== undefined ? requestGeneration : root.requestGeneration;
        var isCurrent = function() { return requestIsCurrent(sessionId, generation); };
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        var requestFinished = false;
        if (!isCurrent())
            return;
        try {
            xhr.open("POST", url, true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
            xhr.ontimeout = function() {
                if (errorHandled || requestFinished || !isCurrent())
                    return ;

                errorHandled = true;
                requestFinished = true;
                root.loading = false;
                root.activeXhr = null;
                resetProviderStreamingState();
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Request to " + url + " timed out" + (xhr.timeout > 0 ? " after " + (xhr.timeout / 1000) + " seconds." : "."));
                processNextQueuedMessage();
            };
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "") {
                console.log("DEBUG: Sending authenticated request to " + Sec.scrubSecrets(url));
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
            } else {
                console.log("DEBUG: Sending request without Authorization header (empty key) to " + Sec.scrubSecrets(url));
            }
            if (extraHeaders) {
                for (var headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName]);

                }
            }
        } catch (setupError) {
            if (isCurrent()) {
                root.loading = false;
                root.activeXhr = null;
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Failed to start request: " + setupError);
                processNextQueuedMessage();
            }
            return ;
        }
        root.loading = true;
        root.activeXhr = xhr;
        var mcpTools = mcpToolDefinitions();
        // Tool calls require the complete assistant message, so keep this
        // request non-streaming even when normal streaming is enabled.
        var useStreaming = plasmoid.configuration.disableStreaming !== true && mcpTools.length === 0;
        var buffer = "";
        var offset = 0;
        var fullText = "";
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            if (requestFinished || !isCurrent())
                return;

            if (xhr.status < 200 || xhr.status >= 300) {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (requestFinished || !isCurrent())
                        return;
                    root.loading = false;
                    root.activeXhr = null;
                    if (errorHandled)
                        return ;

                    errorHandled = true;
                    requestFinished = true;
                    resetProviderStreamingState();
                    root.activeRequestSessionId = "";
                    root.requestGeneration++;
                    var err = "Request to " + url + " failed (HTTP " + xhr.status + ")";
                    if (xhr.status === 401) {
                        err = "Authentication Failed (HTTP 401): Please verify that your API key is correct and not missing.";
                    }
                    try {
                        var eobj = JSON.parse(xhr.responseText);
                        if (eobj.error && eobj.error.message)
                            err += ": " + eobj.error.message;
                        else if (eobj.error)
                            err += ": " + JSON.stringify(eobj.error);
                        else if (eobj.message)
                            err += ": " + eobj.message;
                        else if (eobj.detail)
                            err += ": " + eobj.detail;
                    } catch (e) {
                    }
                    pushErrorMessage(err);
                    processNextQueuedMessage();
                }
                return ;
            }

            if (!useStreaming) {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (requestFinished || !isCurrent())
                        return;
                    root.loading = false;
                    root.activeXhr = null;
                    try {
                        var respObj = JSON.parse(xhr.responseText);
                        var choices = respObj.choices || [];
                        var firstChoice = choices[0] || {};
                        if (mcpTools.length > 0 && firstChoice.message && firstChoice.message.tool_calls) {
                            handleMcpToolCalls(firstChoice.message.tool_calls, {
                                "baseUrl": baseUrl,
                                "apiKey": apiKey,
                                "model": model,
                                "extraHeaders": extraHeaders,
                                "modelLabel": modelLabel,
                                "sessionId": sessionId,
                                "generation": generation
                            }, firstChoice.message);
                            return;
                        }
                        var msgContent = (firstChoice.message ? firstChoice.message.content : "") || "";
                        var msgReasoning = (firstChoice.message ? (firstChoice.message.reasoning || firstChoice.message.reasoning_content || firstChoice.message.thought || "") : "") || "";
                        if (typeof msgContent !== "string") msgContent = JSON.stringify(msgContent);
                        if (typeof msgReasoning !== "string") msgReasoning = JSON.stringify(msgReasoning);

                        var displayReasoning = msgReasoning;
                        var displayText = msgContent;
                        var thinkStart = displayText.indexOf("<think>");
                        while (thinkStart !== -1) {
                            var thinkEnd = displayText.indexOf("</think>", thinkStart);
                            if (thinkEnd !== -1) {
                                var extracted = displayText.substring(thinkStart + 7, thinkEnd);
                                if (displayReasoning === "") displayReasoning = extracted;
                                else displayReasoning += "\n" + extracted;
                                displayText = displayText.substring(0, thinkStart) + displayText.substring(thinkEnd + 8);
                            } else {
                                var extracted = displayText.substring(thinkStart + 7);
                                if (displayReasoning === "") displayReasoning = extracted;
                                else displayReasoning += "\n" + extracted;
                                displayText = displayText.substring(0, thinkStart);
                                break;
                            }
                            thinkStart = displayText.indexOf("<think>");
                        }

                        var ts = Date.now();
                        if (displayText.length > root.maxMessageChars)
                            displayText = displayText.substring(0, root.maxMessageChars) + "\n[response truncated]";
                        if (displayReasoning.length > root.maxMessageChars)
                            displayReasoning = displayReasoning.substring(0, root.maxMessageChars) + "\n[reasoning truncated]";
                        var resMsg = {
                            "role": "assistant",
                            "content": displayText || "(empty response)",
                            "time": nowTime(ts),
                            "at": ts,
                            "model": modelLabel || model || ""
                        };
                        if (displayReasoning !== "") resMsg.reasoning = displayReasoning;
                        if (respObj.usage) {
                            resMsg.tokens = {
                                "input": respObj.usage.prompt_tokens || respObj.usage.input_tokens || 0,
                                "output": respObj.usage.completion_tokens || respObj.usage.output_tokens || 0
                            };
                        }
                        root.messages = root.messages.concat([resMsg]);
                        requestFinished = true;
                        root.activeRequestSessionId = "";
                        root.requestGeneration++;
                        if (!root.userScrolledUp) Qt.callLater(scrollToBottom);
                        try { triggerNotificationSound(); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
                        try { saveCurrentSessionState(true); } catch (saveErr) { console.error("Session save failed:", saveErr); }
                        maybeGenerateChatTitle();
                        processNextQueuedMessage();
                    } catch (parseErr) {
                        requestFinished = true;
                        root.activeRequestSessionId = "";
                        root.requestGeneration++;
                        pushErrorMessage("Failed to parse non-streaming response: " + parseErr.toString());
                        processNextQueuedMessage();
                    }
                }
                return;
            }

            if (xhr.responseText.length > 20000000) {
                requestFinished = true;
                errorHandled = true;
                root.loading = false;
                root.activeXhr = null;
                resetProviderStreamingState();
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                try { xhr.abort(); } catch (e) {}
                pushErrorMessage("Provider response exceeded the safe size limit.");
                processNextQueuedMessage();
                return;
            }
            var delta = xhr.responseText.slice(offset);
            offset = xhr.responseText.length;
            buffer += delta;
            while (true) {
                var split = buffer.indexOf("\n");
                if (split < 0)
                    break;

                var line = buffer.slice(0, split).trim();
                buffer = buffer.slice(split + 1);
                if (line.indexOf("data: ") === 0) {
                    var dataStr = line.slice(6);
                    if (dataStr === "[DONE]")
                        continue;

                    try {
                        var obj = JSON.parse(dataStr);
                        if (obj.choices && obj.choices.length > 0 && obj.choices[0].delta) {
                            var streamDelta = obj.choices[0].delta;
                            var reasoningDelta = String(streamDelta.reasoning || streamDelta.reasoning_content || streamDelta.thinking || streamDelta.thought || "");
                            if (reasoningDelta !== "")
                                root.currentStreamReasoning = (root.currentStreamReasoning + reasoningDelta).substring(0, root.maxMessageChars);

                            if (streamDelta.content) {
                                fullText += typeof streamDelta.content === "string" ? streamDelta.content : JSON.stringify(streamDelta.content);
                                if (fullText.length > root.maxMessageChars)
                                    fullText = fullText.substring(0, root.maxMessageChars) + "\n[response truncated]";
                            }
                            
                            var displayReasoning = "";
                            var displayText = fullText;
                            
                            var thinkStart = displayText.indexOf("<think>");
                            while (thinkStart !== -1) {
                                var thinkEnd = displayText.indexOf("</think>", thinkStart);
                                if (thinkEnd !== -1) {
                                    var extracted = displayText.substring(thinkStart + 7, thinkEnd);
                                    if (displayReasoning === "") displayReasoning = extracted;
                                    else displayReasoning += "\n" + extracted;
                                    displayText = displayText.substring(0, thinkStart) + displayText.substring(thinkEnd + 8);
                                } else {
                                    var extracted = displayText.substring(thinkStart + 7);
                                    if (displayReasoning === "") displayReasoning = extracted;
                                    else displayReasoning += "\n" + extracted;
                                    displayText = displayText.substring(0, thinkStart);
                                    break;
                                }
                                thinkStart = displayText.indexOf("<think>");
                            }

                            if (streamDelta.content || reasoningDelta !== "") {
                            if (root.currentStreamIndex < 0) {
                                var ts = Date.now();
                                root.messages = root.messages.concat([{
                                    "role": "assistant",
                                    "content": "",
                                    "reasoning": "",
                                    "time": nowTime(ts),
                                    "at": ts,
                                    "model": modelLabel || model || ""
                                }]);
                                root.currentStreamIndex = root.messages.length - 1;
                                root.streamingResponse = true;
                            }
                            root.currentStreamText = displayText;
                            root.currentStreamExtractedReasoning = displayReasoning;
                            if (!root.userScrolledUp)
                                Qt.callLater(scrollToBottom);

                            }
                        }
                    } catch (e) {
                    }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (requestFinished || !isCurrent())
                    return;
                requestFinished = true;
                root.loading = false;
                root.activeXhr = null;
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                if (root.currentStreamIndex >= 0) {
                    var msgs = root.messages.slice();
                    msgs[root.currentStreamIndex].content = root.currentStreamText;
                    
                    var finalReasoning = root.currentStreamReasoning;
                    if (root.currentStreamExtractedReasoning !== "") {
                        if (finalReasoning !== "") finalReasoning += "\n" + root.currentStreamExtractedReasoning;
                        else finalReasoning = root.currentStreamExtractedReasoning;
                    }
                    
                    msgs[root.currentStreamIndex].reasoning = finalReasoning;
                    root.messages = msgs;
                } else if (fullText === "" && xhr.status >= 200 && xhr.status < 300) {
                    pushErrorMessage("The model returned an empty response.");
                }
                root.currentStreamIndex = -1;
                root.currentStreamText = "";
                root.currentStreamReasoning = "";
                root.currentStreamExtractedReasoning = "";
                root.streamingResponse = false;
                if (!root.userScrolledUp)
                    Qt.callLater(scrollToBottom);

                try { triggerNotificationSound(); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
                try { saveCurrentSessionState(true); } catch (saveErr) { console.error("Session save failed:", saveErr); }
                maybeGenerateChatTitle();
                processNextQueuedMessage();
            }
        };
        xhr.onerror = function() {
            if (errorHandled || requestFinished || !isCurrent())
                return;

            errorHandled = true;
            requestFinished = true;
            root.loading = false;
            root.activeXhr = null;
            resetProviderStreamingState();
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage("Could not reach " + url + ". Check the server URL and whether that endpoint accepts API requests.");
            processNextQueuedMessage();
        };
        try {
            var requestBody = {
                "model": model,
                "messages": buildOpenAICompatPayload(sessionId),
                "stream": useStreaming
            };
            var maxTokens = responseMaxTokens(sessionId, 0);
            if (maxTokens > 0)
                requestBody.max_tokens = maxTokens;
            if (mcpTools.length > 0) {
                requestBody.tools = mcpTools;
                requestBody.tool_choice = "auto";
            }
            xhr.send(JSON.stringify(requestBody));
        } catch (sendError) {
            if (isCurrent() && !requestFinished) {
                requestFinished = true;
                root.loading = false;
                root.activeXhr = null;
                resetProviderStreamingState();
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Failed to send request: " + sendError);
                processNextQueuedMessage();
            }
        }
    }

    function doAnthropicRequest(baseUrl, apiKey, model, extraHeaders, requestSessionId, requestGeneration) {
        var sessionId = requestSessionId || root.activeRequestSessionId || root.currentSessionId;
        var generation = requestGeneration !== undefined ? requestGeneration : root.requestGeneration;
        var isCurrent = function() { return requestIsCurrent(sessionId, generation); };
        if (!apiKey) {
            if (isCurrent()) {
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Anthropic API key missing in settings.");
                processNextQueuedMessage();
            }
            return;
        }
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        var requestFinished = false;
        var endpoint = (baseUrl || "https://api.anthropic.com/v1").replace(/\/$/, "");
        if (!endpoint.endsWith("/messages"))
            endpoint += "/messages";
        var finishError = function(message) {
            if (errorHandled || requestFinished || !isCurrent()) return;
            errorHandled = true;
            requestFinished = true;
            root.loading = false;
            root.activeXhr = null;
            resetProviderStreamingState();
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage(message);
            processNextQueuedMessage();
        };
        if (!isCurrent()) return;
        try {
            xhr.open("POST", endpoint, true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
            xhr.ontimeout = function() {
                finishError("Anthropic request timed out" + (xhr.timeout > 0 ? " after " + (xhr.timeout / 1000) + " seconds." : "."));
            };
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", apiKey);
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            if (extraHeaders) {
                for (var headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName]);
                }
            }
            root.loading = true;
            root.activeXhr = xhr;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || requestFinished || !isCurrent())
                    return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        var obj = JSON.parse(xhr.responseText);
                        var text = "";
                        var reasoningText = "";
                        if (obj.content && obj.content.length) {
                            for (var i = 0; i < obj.content.length; i++) {
                                if (obj.content[i].type === "text")
                                    text += String(obj.content[i].text || "");
                                else if (obj.content[i].type === "thinking" || obj.content[i].type === "reasoning" || obj.content[i].type === "thought")
                                    reasoningText += obj.content[i].thinking || obj.content[i].thought || obj.content[i].text || "";
                            }
                        }
                        if (text.length > root.maxMessageChars)
                            text = text.substring(0, root.maxMessageChars) + "\n[response truncated]";
                        if (reasoningText.length > root.maxMessageChars)
                            reasoningText = reasoningText.substring(0, root.maxMessageChars) + "\n[reasoning truncated]";
                        var ts = Date.now();
                        var msgObj = {"role": "assistant", "content": text || "(empty response)", "time": nowTime(ts), "at": ts, "model": model || ""};
                        if (reasoningText !== "") msgObj.reasoning = reasoningText;
                        if (obj.usage)
                            msgObj.tokens = {"input": obj.usage.input_tokens || 0, "output": obj.usage.output_tokens || 0};
                        root.messages = root.messages.concat([msgObj]);
                    } catch (e) {
                        finishError("Failed to parse Anthropic response");
                        return;
                    }
                } else {
                    var err = "Anthropic HTTP " + xhr.status;
                    try {
                        var eobj = JSON.parse(xhr.responseText);
                        if (eobj.error) {
                            if (typeof eobj.error === "string") err += " | " + eobj.error;
                            else {
                                if (eobj.error.message) err = "Anthropic Error (" + xhr.status + "): " + eobj.error.message;
                                if (eobj.error.type) err = "[" + eobj.error.type + "] " + err;
                            }
                        }
                    } catch (e2) {}
                    finishError(err);
                    return;
                }
                requestFinished = true;
                root.loading = false;
                root.activeXhr = null;
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                try { triggerNotificationSound(); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
                try { saveCurrentSessionState(true); } catch (saveErr) { console.error("Session save failed:", saveErr); }
                maybeGenerateChatTitle();
                processNextQueuedMessage();
            };
            xhr.onerror = function() {
                finishError("Could not reach " + endpoint + ". Check network access and API configuration.");
            };
            var maxTokens = responseMaxTokens(sessionId, 1024);
            var anthropicReqBody = {"model": model, "max_tokens": maxTokens, "messages": buildAnthropicPayload(sessionId)};
            var systemPromptParts = [];
            var effectiveSystem = buildEffectiveSystemPrompt(sessionId);
            var effectiveMemory = buildEffectiveMemoryBlock(sessionId);
            var compactedSummary = latestCompactedSummary(sessionId);
            if (effectiveSystem) systemPromptParts.push(effectiveSystem);
            if (effectiveMemory) systemPromptParts.push(effectiveMemory);
            if (compactedSummary) systemPromptParts.push("Previous conversation summary: " + compactedSummary);
            if (systemPromptParts.length > 0)
                anthropicReqBody.system = systemPromptParts.join("\n\n");
            xhr.send(JSON.stringify(anthropicReqBody));
        } catch (sendError) {
            finishError("Failed to send Anthropic request: " + sendError);
        }
    }

    function triggerNotificationSound() {
        if (plasmoid.configuration.playNotificationSound) {
            soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
        }

        if (voiceManager && voiceManager.enabled && (voiceManager.ttsAuto || voiceManager.callModeActive)) {
            // Find the last assistant message
            for (var i = root.messages.length - 1; i >= 0; i--) {
                if (root.messages[i].role === "assistant") {
                    var text = (root.messages[i].content || "").trim();
                    if (text) {
                        root.playingMessageIndex = i;
                        voiceManager.playTTS(text);
                    }
                    break;
                }
            }
        }
        
        Qt.callLater(checkAndTriggerCompaction);
    }

    function checkAndTriggerCompaction() {
        if (plasmoid.configuration.enableCompactingContext !== true || root.compactingContext || root.openCodeMode || root.piMode)
            return;
        var limit = Number(plasmoid.configuration.compactContextAfter) || 0;
        if (limit <= 0)
            return;
        var count = 0;
        var lastCompactedIdx = -1;
        for (var i = root.messages.length - 1; i >= 0; i--) {
            if (root.messages[i].role === "system_compacted") {
                lastCompactedIdx = i;
                break;
            }
            if (root.messages[i].role === "user" || root.messages[i].role === "assistant")
                count++;
        }
        if (count > limit)
            runContextCompaction(lastCompactedIdx + 1, root.messages.length);
    }

    function runContextCompaction(startIdx, endIdx) {
        if (root.compactingContext || root.openCodeMode || root.piMode)
            return;
        var sessionId = root.currentSessionId;
        var token = ++root.compactionGeneration;
        var textToSummarize = "";
        for (var i = startIdx; i < endIdx; i++) {
            var m = root.messages[i] || {};
            if (m.role === "user" || m.role === "assistant")
                textToSummarize += String(m.role).toUpperCase() + ": " + String(m.content || "") + "\n\n";
        }
        if (!textToSummarize.trim())
            return;
        // Keep background summarisation from becoming a second memory/DoS
        // vector while retaining a useful recent history snapshot.
        if (textToSummarize.length > 120000)
            textToSummarize = textToSummarize.substring(textToSummarize.length - 120000);
        var cfg = getProviderConfig(getEffectiveProvider(sessionId), sessionId);
        if (!cfg || !cfg.baseUrl || !cfg.model || (!cfg.allowEmptyKey && !cfg.apiKey))
            return;
        var isAnthropic = cfg.type === "anthropic";
        var url = String(cfg.baseUrl).replace(/\/$/, "");
        if (isAnthropic) {
            if (!url.endsWith("/messages")) url += "/messages";
        } else if (!url.endsWith("/chat/completions") && !url.endsWith("/completions")) {
            url += "/chat/completions";
        }
        var prompt = "Please summarize the following conversation concisely for future turns. Return only a factual summary, preserving important decisions, preferences, and unresolved tasks.\n\n" + textToSummarize;
        var xhr = new XMLHttpRequest();
        root.compactingContext = true;
        root.compactionXhr = xhr;
        root.compactionSessionId = sessionId;
        var done = false;
        var clear = function() {
            if (done) return false;
            done = true;
            if (root.compactionSessionId === sessionId && root.compactionGeneration === token) {
                root.compactionXhr = null;
                root.compactionSessionId = "";
                root.compactingContext = false;
                return true;
            }
            return false;
        };
        try {
            xhr.open("POST", url, true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 30000;
            xhr.setRequestHeader("Content-Type", "application/json");
            if (isAnthropic) {
                xhr.setRequestHeader("x-api-key", cfg.apiKey);
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            } else if (cfg.apiKey) {
                xhr.setRequestHeader("Authorization", "Bearer " + cfg.apiKey);
            }
            if (cfg.headers) {
                for (var headerName in cfg.headers)
                    if (Object.prototype.hasOwnProperty.call(cfg.headers, headerName) && cfg.headers[headerName])
                        xhr.setRequestHeader(headerName, cfg.headers[headerName]);
            }
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || done)
                    return;
                if (root.compactionSessionId !== sessionId || root.compactionGeneration !== token || root.currentSessionId !== sessionId) {
                    done = true;
                    return;
                }
                if (xhr.status < 200 || xhr.status >= 300) {
                    clear();
                    return;
                }
                try {
                    var response = JSON.parse(xhr.responseText);
                    var summary = "";
                    if (isAnthropic) {
                        for (var bi = 0; bi < (response.content || []).length; bi++)
                            if (response.content[bi].type === "text") summary += response.content[bi].text || "";
                    } else {
                        summary = (((response.choices || [])[0] || {}).message || {}).content || "";
                    }
                    summary = String(summary).trim();
                    if (!summary) { clear(); return; }
                    var current = root.messages.slice();
                    var insertAt = Math.min(Math.max(0, endIdx), current.length);
                    current.splice(insertAt, 0, {"role": "system_compacted", "content": summary, "at": Date.now(), "time": nowTime(Date.now())});
                    root.messages = current;
                    clear();
                    saveCurrentSessionState(true);
                } catch (e) {
                    clear();
                }
            };
            xhr.ontimeout = function() { clear(); };
            xhr.onerror = function() { clear(); };
            var body = isAnthropic
                ? {"model": cfg.model, "max_tokens": 512, "messages": [{"role": "user", "content": prompt}]}
                : {"model": cfg.model, "max_tokens": 512, "messages": [{"role": "user", "content": prompt}]};
            xhr.send(JSON.stringify(body));
        } catch (e) {
            clear();
        }
    }

    function respondToPermission(permissionId, approved) {
        function sendToUrl(url, isRetry) {
            xhr.open("POST", url, true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
            xhr.ontimeout = function() {
                if (!isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: permission response timed out.");
                }
            };
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = approved ? "allowed" : "denied";
                            break;
                        }
                    }
                    root.messages = copy;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404 && !isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: failed to reply to permission (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                if (!isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: could not reach permission reply server endpoint.");
                }
            };
            xhr.send(JSON.stringify({
                "response": responseValue
            }));
        }

        var sessionId = root.openCodeActiveSessionId;
        var permissionIndex = -1;
        for (var pi = 0; pi < root.messages.length; pi++) {
            if (root.messages[pi].role === "permission_request" && root.messages[pi].permissionId === permissionId) {
                permissionIndex = pi;
                break;
            }
        }
        if (permissionIndex >= 0 && root.messages[permissionIndex].openCodeSessionId)
            sessionId = root.messages[permissionIndex].openCodeSessionId;
        if (!sessionId) {
            var idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";
        }
        sessionId = Sec.validateRemoteSessionId(sessionId);
        if (!sessionId || !permissionId)
            return ;

        var copy = root.messages.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                copy[i].status = approved ? "allowing..." : "denying...";
                break;
            }
        }
        root.messages = copy;
        var xhr = new XMLHttpRequest();
        var safePermissionId = encodeURIComponent(String(permissionId));
        var encodedSessionId = encodeURIComponent(sessionId);
        var primaryUrl = openCodeBaseUrl() + "/session/" + encodedSessionId + "/permission/" + safePermissionId;
        var fallbackUrl = openCodeBaseUrl() + "/session/" + encodedSessionId + "/permissions/" + safePermissionId;
        var responseValue = approved ? "allow" : "deny";
        sendToUrl(primaryUrl, false);
    }

    function _questionMessageIndex(questionId) {
        for (var i = 0; i < root.messages.length; i++)
            if (root.messages[i].role === "question_request" && root.messages[i].questionId === questionId)
                return i;
        return -1;
    }

    function questionOptionSelected(questionId, questionIndex, label) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return false;
        var selected = root.messages[idx].selectedAnswers || [];
        var row = selected[questionIndex];
        return Array.isArray(row) && row.indexOf(String(label || "")) >= 0;
    }

    function toggleQuestionOption(questionId, questionIndex, label, multiple) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return;
        var copy = root.messages.slice();
        var item = Object.assign({}, copy[idx]);
        var selected = Array.isArray(item.selectedAnswers) ? item.selectedAnswers.slice() : [];
        var row = Array.isArray(selected[questionIndex]) ? selected[questionIndex].slice() : [];
        var value = String(label || "");
        if (multiple) {
            var existing = row.indexOf(value);
            if (existing >= 0) row.splice(existing, 1); else row.push(value);
        } else {
            row = [value];
        }
        selected[questionIndex] = row;
        item.selectedAnswers = selected;
        copy[idx] = item;
        root.messages = copy;
        saveCurrentSessionState(true);
    }

    // Collect selected options from the question UI and submit the answer.
    function submitQuestionAnswer(questionId, questions, customField) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return;
        var customText = customField ? String(customField.text || "").trim() : "";
        if (!questions || questions.length === 0) {
            if (customText) respondToQuestion(questionId, customText, false);
            return;
        }
        var selected = root.messages[idx].selectedAnswers || [];
        var answers = [];
        var hasAnswer = false;
        var firstEmpty = -1;
        for (var i = 0; i < questions.length; i++) {
            var row = Array.isArray(selected[i]) ? selected[i].slice() : [];
            if (row.length > 0) hasAnswer = true;
            else if (firstEmpty < 0) firstEmpty = i;
            answers.push(row);
        }
        if (customText) {
            if (firstEmpty >= 0) answers[firstEmpty] = [customText];
            else if (answers.length > 0) answers[answers.length - 1].push(customText);
            hasAnswer = true;
        }
        if (hasAnswer)
            respondToQuestion(questionId, answers, false);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        function tryNextUrl() {
            if (currentUrlIdx >= urls.length) {
                var copy = root.messages.slice();
                for (var i = 0; i < copy.length; i++) {
                    if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                        copy[i].status = "pending";
                        break;
                    }
                }
                root.messages = copy;
                pushErrorMessage("OpenCode: failed to reply to question endpoint.");
                return ;
            }
            var url = urls[currentUrlIdx];
            currentUrlIdx++;
            xhr.open("POST", url, true);
            xhr.timeout = plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0;
            xhr.ontimeout = function() {
                tryNextUrl();
            };
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = isReject ? "dismissed" : "answered";
                            copy[i].submittedAnswer = answerValue;
                            break;
                        }
                    }
                    root.messages = copy;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404) {
                    tryNextUrl();
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: failed to reply to question (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                tryNextUrl();
            };
            try {
                if (isReject) {
                    xhr.send(JSON.stringify({
                    }));
                } else {
                    // Send in OpenCode's expected format: { answers: [["label"]] }
                    var answers = [];
                    if (typeof answerValue === "object" && Array.isArray(answerValue))
                        answers = answerValue;
                    else
                        answers = [[String(answerValue || "")]];
                    xhr.send(JSON.stringify({
                        "answers": answers
                    }));
                }
            } catch (err) {
                tryNextUrl();
            }
        }

        var sessionId = root.openCodeActiveSessionId;
        var questionIndex = _questionMessageIndex(questionId);
        if (questionIndex >= 0 && root.messages[questionIndex].openCodeSessionId)
            sessionId = root.messages[questionIndex].openCodeSessionId;
        if (!sessionId) {
            var idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";
        }
        sessionId = Sec.validateRemoteSessionId(sessionId);
        if (!sessionId || !questionId)
            return ;

        var copy = root.messages.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                copy[i].status = isReject ? "dismissing..." : "answering...";
                break;
            }
        }
        root.messages = copy;
        var xhr = new XMLHttpRequest();
        var action = isReject ? "reject" : "reply";
        var safeQuestionId = encodeURIComponent(String(questionId));
        var encodedSessionId = encodeURIComponent(sessionId);
        var urls = [openCodeBaseUrl() + "/question/" + safeQuestionId + "/" + action, openCodeBaseUrl() + "/session/" + encodedSessionId + "/question/" + safeQuestionId + "/" + action, openCodeBaseUrl() + "/session/" + encodedSessionId + "/questions/" + safeQuestionId + "/" + action];
        var currentUrlIdx = 0;
        tryNextUrl();
    }

    function stopStreaming() {
        invalidateActiveRequest(false);
        try { saveCurrentSessionState(true); } catch (e) { console.error("Stop save failed:", e); }
        processNextQueuedMessage();
    }

    function fileIconName(filename) {
        var ext = filename.split('.').pop().toLowerCase();
        if (ext === 'pdf')
            return 'document-pdf';

        if (ext === 'csv')
            return 'text-csv';

        if (ext === 'docx' || ext === 'doc')
            return 'document-word';

        if (ext === 'md' || ext === 'txt')
            return 'text-plain';

        return 'document-text';
    }

    function attachmentsReadyToSend() {
        for (var i = 0; i < root.attachedFiles.length; i++) {
            if (root.attachedFiles[i].loading || root.attachedFiles[i].error)
                return false;
        }
        return true;
    }

    function cleanupTemporaryAttachment(path) {
        var value = String(path || "");
        if (value.indexOf("/tmp/kdeaichat_clip_") !== 0 && value.indexOf("/tmp/kdeaichat_shot_") !== 0)
            return;
        var extractor = getDocExtractorPath();
        var safePath = Sec.validateFilePath(value);
        if (extractor && safePath)
            fileReaderDs.connectSource("python3 " + Sec.quoteForShell(extractor) + " --cleanup " + Sec.quoteForShell(safePath) + " #cleanup-attachment-" + Date.now());
    }

    function removeAttachedFile(index) {
        var files = root.attachedFiles.slice();
        if (index < 0 || index >= files.length)
            return;
        var removedPath = files[index].path || "";
        cleanupTemporaryAttachment(removedPath);
        var pending = Object.assign({}, root.pendingAttachmentRequests || {});
        var keys = Object.keys(pending);
        for (var p = 0; p < keys.length; p++) {
            var entry = pending[keys[p]] || {};
            var path = typeof entry === "string" ? entry : entry.path;
            if (path === removedPath) {
                if (typeof entry === "object" && entry.source) {
                    try { fileReaderDs.disconnectSource(entry.source); } catch (e) {}
                }
                delete pending[keys[p]];
            }
        }
        root.pendingAttachmentRequests = pending;
        files.splice(index, 1);
        root.attachedFiles = files;
    }

    function getDocExtractorPath() {
        var urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/doc_extractor.py") ? path : "";
    }

    function attachFile(fileUrl) {
        var localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0)
            localPath = localPath.substring(7);

        localPath = decodeURIComponent(localPath);
        var files = root.attachedFiles.slice();
        if (files.length >= 10) {
            pushErrorMessage("You can attach at most 10 files per message.");
            return;
        }
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === localPath)
                return ;

        }
        var filename = localPath.substring(localPath.lastIndexOf("/") + 1);
        var newFile = {
            "path": localPath,
            "name": filename,
            "loading": true,
            "error": "",
            "type": "",
            "content": "",
            "mimeType": "",
            "size": 0
        };
        files.push(newFile);
        root.attachedFiles = files;
        var docExtractorPath = getDocExtractorPath();
        var safePath = Sec.validateFilePath(localPath);
        if (!docExtractorPath || !safePath) {
            files.pop();
            root.attachedFiles = files;
            pushErrorMessage("Unable to attach this file: unsupported or unsafe path.");
            return;
        }
        var marker = "extract-file-" + (++root.attachmentRequestCounter) + "-" + Date.now();
        var pending = Object.assign({}, root.pendingAttachmentRequests || {});
        var cmd = "timeout 60s python3 " + Sec.quoteForShell(docExtractorPath) + " " + Sec.quoteForShell(safePath);
        var source = cmd + " #" + marker;
        pending[marker] = {"path": safePath, "source": source};
        root.pendingAttachmentRequests = pending;
        fileReaderDs.connectSource(source);
    }

    function buildMessageContent(text, attachments, apiType) {
        var docs = [];
        var imgs = [];
        var skippedImageCount = 0;
        var imageChars = 0;
        for (var i = 0; i < attachments.length; i++) {
            var att = attachments[i] || {};
            if (att.type === "image") {
                var imageSize = String(att.content || "").length;
                if (imageChars + imageSize <= 20000000) {
                    imgs.push(att);
                    imageChars += imageSize;
                } else {
                    skippedImageCount++;
                }
            } else if (att.type === "text")
                docs.push(att);
        }
        var compiledPrompt = skippedImageCount > 0
            ? "[" + skippedImageCount + " image attachment(s) omitted because the request image limit was reached.]\n"
            : "";
        for (var d = 0; d < docs.length; d++) {
            if (compiledPrompt.length > 5000000)
                break;
            compiledPrompt += "[Attached File: " + String(docs[d].name || "file") + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
            compiledPrompt += "--- START OF FILE CONTENT ---\n";
            var remainingDocChars = Math.max(0, 5000000 - compiledPrompt.length - 40);
            var docContent = String(docs[d].content || "");
            if (docContent.length > remainingDocChars)
                docContent = docContent.substring(0, remainingDocChars) + "\n[file content truncated]";
            compiledPrompt += docContent + "\n";
            compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
        }
        compiledPrompt += text;
        if (imgs.length === 0)
            return compiledPrompt;

        var contentList = [];
        if (compiledPrompt.trim() !== "")
            contentList.push({
                "type": "text",
                "text": compiledPrompt
            });

        for (var imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
            var image = imgs[imgIdx];
            if (apiType === "anthropic")
                contentList.push({
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": image.mimeType || "image/jpeg",
                        "data": image.content
                    }
                });
            else
                contentList.push({
                    "type": "image_url",
                    "image_url": {
                        "url": "data:" + (image.mimeType || "image/jpeg") + ";base64," + image.content
                    }
                });
        }
        return contentList;
    }

    function checkClipboardForAttachments() {
        var docExtractorPath = getDocExtractorPath();
        if (!docExtractorPath) {
            pushErrorMessage("Attachment extractor is not available in the installed widget.");
            return;
        }
        var cmd = "timeout 20s python3 " + Sec.quoteForShell(docExtractorPath) + " --clipboard";
        fileReaderDs.connectSource(cmd + " #clipboard-attachments");
    }

    function readClipboardText() {
        clipboardHelper.text = "";
        clipboardHelper.paste();
        return clipboardHelper.text;
    }

    function copyTextToClipboard(textToCopy) {
        clipboardHelper.text = textToCopy || "";
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    function walletCall(member, args, resolve, reject) {
        var reply;
        try {
            reply = DBus.SessionBus.asyncCall({
                "service": "org.kde.kwalletd6",
                "path": "/modules/kwalletd6",
                "iface": "org.kde.KWallet",
                "member": member,
                "arguments": args
            });
        } catch (e) {
            if (reject) reject(String(e));
            else console.warn("KDE AI Chat: wallet unavailable:", e);
            return;
        }
        reply.finished.connect(function() {
            if (reply.isError) {
                if (reject)
                    reject(reply.error);

            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && val.hasOwnProperty("value"))
                    val = val.value;

                if (resolve)
                    resolve(val);

            }
        });
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        var strVal = String(secretValue || "");
        var keys = Object.assign({}, root.walletApiKeys || {});
        if (strVal)
            keys[targetId] = strVal;
        else
            delete keys[targetId];
        root.walletApiKeys = keys;
    }

    function loadKWalletKeysAtStartup() {
        var walletName = "kdewallet";
        walletCall("wallets", [], function(wallets) {
            root.walletApiKeys = ({});
            if (!Array.isArray(wallets) || wallets.indexOf(walletName) === -1)
                return ;

            walletCall("open", [walletName, new DBus.int64(0), "org.kde.plasma.kdeaichat"], function(handle) {
                if (handle < 0)
                    return ;

                walletCall("hasFolder", [new DBus.int32(handle), "KaiChat", "org.kde.plasma.kdeaichat"], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                        return ;
                    }
                    walletCall("passwordList", [new DBus.int32(handle), "KaiChat", "org.kde.plasma.kdeaichat"], function(passwordsMap) {
                        if (passwordsMap) {
                            var targets = ProviderService.getApiKeyProviderIds();
                            var supported = ProviderService.getSupportedProviders(plasmoid.configuration);
                            for (var si = 0; si < supported.length; si++) {
                                var customId = String(supported[si] || "");
                                if (/^custom_[A-Za-z0-9._:-]{1,100}$/.test(customId) && targets.indexOf(customId) < 0)
                                    targets.push(customId);
                            }
                            for (var i = 0; i < targets.length; i++) {
                                var targetId = targets[i];
                                var key = "kai-chat-" + targetId + "-api-key";
                                if (passwordsMap[key])
                                    applyKWalletKeyToMemory(targetId, passwordsMap[key]);

                            }
                        }
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                    });
                });
            });
        });
    }

    function performExportChat(filePath) {
        var isMarkdown = filePath.toLowerCase().endsWith(".md") || filePath.toLowerCase().endsWith(".markdown");
        var content = "";
        var sessionTitle = root.currentSessionTitle || "Untitled Session";
        var now = new Date();
        var dateStr = now.toLocaleDateString() + " " + now.toLocaleTimeString();
        if (isMarkdown) {
            content += "# 💬 KDE AI Chat: " + sessionTitle + "\n";
            content += "*Exported on " + dateStr + "*\n\n";
            content += "---\n\n";
            for (var i = 0; i < root.messages.length; i++) {
                var m = root.messages[i];
                if (m.role === "user") {
                    content += "<div align=\"right\">\n\n";
                    content += "### 👤 **User** (" + (m.time || "") + ")\n";
                    content += m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += "<div align=\"left\">\n\n";
                    content += "### 🤖 **" + modelName + "** (" + (m.time || "") + ")\n";
                    content += m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                } else if (m.role === "error") {
                    content += "<div align=\"left\">\n\n";
                    content += "### ❌ **System Error** (" + (m.time || "") + ")\n";
                    content += "> " + m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                }
            }
        } else {
            content += "==================================================\n";
            content += "💬 KDE AI Chat: " + sessionTitle + "\n";
            content += "Exported on: " + dateStr + "\n";
            content += "==================================================\n\n";
            var rightAlignTxt = function rightAlignTxt(text, width) {
                if (!width)
                    width = 80;

                var lines = text.split("\n");
                for (var j = 0; j < lines.length; j++) {
                    var trimmed = lines[j].trim();
                    if (trimmed.length === 0) {
                        lines[j] = "";
                        continue;
                    }
                    if (trimmed.length >= width)
                        lines[j] = trimmed;
                    else
                        lines[j] = " ".repeat(width - trimmed.length) + trimmed;
                }
                return lines.join("\n");
            };
            for (var i = 0; i < root.messages.length; i++) {
                var m = root.messages[i];
                if (m.role === "user") {
                    var userHeader = "👤 User (" + (m.time || "") + "):";
                    content += " ".repeat(Math.max(0, 80 - userHeader.length)) + userHeader + "\n";
                    content += rightAlignTxt(m.content, 80) + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += "🤖 " + modelName + " (" + (m.time || "") + "):\n";
                    content += m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "error") {
                    content += "❌ System Error (" + (m.time || "") + "):\n";
                    content += "ERROR: " + m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                }
            }
        }
        var safePath = Sec.validateFilePath(filePath);
        var helper = getHelperPath();
        if (!safePath || !helper) {
            pushErrorMessage("Export cancelled: invalid destination or helper unavailable.");
            return;
        }
        if (content.length > 500000) {
            pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var payload = {
            "filePath": safePath,
            "b64Content": Sec.base64Encode(content)
        };
        var encoded = Sec.base64Encode(JSON.stringify(payload));
        if (encoded.length > 900000) {
            pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var cmd = "python3 " + Sec.quoteForShell(helper) + " export_chat " + Sec.rawShellSnippetQuote(encoded)
            + " && (notify-send -i document-export " + Sec.quoteForShell("KDE AI Chat") + " "
            + Sec.quoteForShell("Chat session successfully exported to " + safePath) + " || true)";
        fileReaderDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #export-chat-save");
    }

    function initSystemPrompt() {
        var options = {
            "sysInfoDateTime": plasmoid.configuration.sysInfoDateTime,
            "enableMemory": plasmoid.configuration.enableMemory,
            "userMemory": String(plasmoid.configuration.userMemory || "").substring(0, 100000)
        };
        compiledSystemPrompt = Api.buildSystemPrompt(sysInfo, String(plasmoid.configuration.systemPrompt || "").substring(0, 100000), options);
        let lang = plasmoid.configuration.uiLanguage || "en";
        if (lang !== "en") {
            let langMap = { "zh": "Mandarin Chinese", "hi": "Hindi", "es": "Spanish", "fr": "French", "ru": "Russian", "pt": "Portuguese", "de": "German" };
            if (langMap[lang]) {
                compiledSystemPrompt += "\n\nCRITICAL INSTRUCTION: You MUST respond to all user queries in " + langMap[lang] + ", unless the user explicitly requests otherwise.";
            }
        }
        compiledMemoryBlock = Api.buildMemoryBlock(options);
    }

    function regatherSysInfo() {
        sysInfo = {
        };
        var cmds = [];
        if (plasmoid.configuration.sysInfoOS)
            cmds.push("cat /etc/os-release");

        if (plasmoid.configuration.sysInfoShell)
            cmds.push("echo $SHELL");

        if (plasmoid.configuration.sysInfoHostname)
            cmds.push("hostname");

        if (plasmoid.configuration.sysInfoKernel)
            cmds.push("uname -a");

        if (plasmoid.configuration.sysInfoDesktop)
            cmds.push("echo $XDG_CURRENT_DESKTOP");

        if (plasmoid.configuration.sysInfoUser)
            cmds.push("whoami");

        if (plasmoid.configuration.sysInfoCPU)
            cmds.push("lscpu");

        if (plasmoid.configuration.sysInfoMemory)
            cmds.push("free -h");

        if (plasmoid.configuration.sysInfoGPU)
            cmds.push("bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"");

        if (plasmoid.configuration.sysInfoDisk)
            cmds.push("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT");

        if (plasmoid.configuration.sysInfoNetwork)
            cmds.push("ip -br addr show");

        if (plasmoid.configuration.sysInfoLocale)
            cmds.push("echo $LANG");

        if (cmds.length === 0) {
            initSystemPrompt();
            return ;
        }
        sysInfoPending = cmds.length;
        pendingSysInfoCommands = {
        };
        for (var i = 0; i < cmds.length; i++) {
            pendingSysInfoCommands[cmds[i]] = true;
            sysInfoDs.connectSource(cmds[i]);
        }
    }

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    preferredRepresentation: compactRepresentation
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode) {
            root.focusInput();
            Qt.callLater(function() { root.scrollToBottom(true); });
        }
    }
    onExpandedChanged: {
        if (expanded) {
            root.triggerInitialLoad();
            root.focusInput();
            deferredScrollTimer.restart();
        }
    }
    Component.onCompleted: {
        // Build a usable prompt immediately; the deferred system-information
        // probe will refresh it once its results arrive.
        root.initSystemPrompt();
        root.syncPlasmaShellWatchdog();
    }
    onMessagesChanged: {
        if (!root.historyOnlyMode && !root.userScrolledUp && !root.responseScrollLocked)
            Qt.callLater(scrollToBottom);

    }

    Timer {
        id: deferredScrollTimer

        interval: 100
        repeat: false
        onTriggered: {
            root.scrollToBottom(false);
        }
    }

    Timer {
        id: startupTimer

        interval: 1000
        running: true
        repeat: false
        onTriggered: {
            root.triggerInitialLoad();
        }
    }

    Timer {
        id: plasmaShellHeartbeatTimer
        interval: 5000
        repeat: true
        running: plasmoid.configuration.autoRestartPlasmaShell === true
        onTriggered: root.runPlasmaShellWatchdog("heartbeat")
    }

    Connections {
        target: plasmoid.configuration
        function onAutoRestartPlasmaShellChanged() {
            root.syncPlasmaShellWatchdog();
        }
    }

    Timer {
        id: lazyWalletTimer

        interval: 150
        repeat: false
        onTriggered: {
            root.ensureWalletLoaded();
        }
    }

    Timer {
        id: walletReloadTimer
        interval: 250
        repeat: false
        onTriggered: {
            root.keysLoaded = false;
            root.ensureWalletLoaded();
        }
    }

    Timer {
        id: lazySysInfoTimer

        interval: 300
        repeat: false
        onTriggered: {
            if (plasmoid.configuration.gatheredSysInfo) {
                try {
                    root.sysInfo = JSON.parse(plasmoid.configuration.gatheredSysInfo);
                    root.initSystemPrompt();
                } catch (e) {
                    root.regatherSysInfo();
                }
            } else {
                root.regatherSysInfo();
            }
        }
    }

    Connections {
        function onSysInfoOSChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoShellChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoHostnameChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoKernelChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDesktopChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoUserChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoCPUChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoMemoryChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoGPUChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDiskChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoNetworkChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoLocaleChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDateTimeChanged() {
            initSystemPrompt();
        }

        function onSystemPromptChanged() {
            initSystemPrompt();
        }

        function onEnableMemoryChanged() {
            initSystemPrompt();
        }

        function onUserMemoryChanged() {
            initSystemPrompt();
        }

        function onApiKeyChanged() { scheduleWalletReload(); }
        function onAnthropicApiKeyChanged() { scheduleWalletReload(); }
        function onGroqApiKeyChanged() { scheduleWalletReload(); }
        function onDeepSeekApiKeyChanged() { scheduleWalletReload(); }
        function onMiniMaxApiKeyChanged() { scheduleWalletReload(); }
        function onFireworksApiKeyChanged() { scheduleWalletReload(); }
        function onGoogleApiKeyChanged() { scheduleWalletReload(); }
        function onOpenRouterApiKeyChanged() { scheduleWalletReload(); }
        function onMistralApiKeyChanged() { scheduleWalletReload(); }
        function onCloudflareApiKeyChanged() { scheduleWalletReload(); }
        function onNvidiaApiKeyChanged() { scheduleWalletReload(); }
        function onHuggingFaceApiKeyChanged() { scheduleWalletReload(); }
        function onXaiApiKeyChanged() { scheduleWalletReload(); }
        function onLitellmApiKeyChanged() { scheduleWalletReload(); }
        function onMaritacaApiKeyChanged() { scheduleWalletReload(); }
        function onPerplexityApiKeyChanged() { scheduleWalletReload(); }
        function onCustomProvidersJsonChanged() { scheduleWalletReload(); }
        function onWalletKeysRevisionChanged() { scheduleWalletReload(); }

        target: plasmoid.configuration
    }

    P5Support.DataSource {
        id: soundDs

        engine: "executable"
        connectedSources: []
    }

    P5Support.DataSource {
        id: piTerminalDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = Number(data["exit code"]);
            if (isNaN(exitCode)) exitCode = 1;
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            disconnectSource(sourceName);
            root.handlePiResponse(sourceName, stdout, stderr, exitCode);
        }
    }

    P5Support.DataSource {
        id: piDiscoveryDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || "";
            var providers = [];
            var modelMap = {};
            try {
                var payload = JSON.parse(stdout);
                var rows = payload.providers || [];
                for (var i = 0; i < rows.length; i++) {
                    var row = rows[i] || {};
                    var id = row.id || row.provider || "";
                    if (!id) continue;
                    var models = Array.isArray(row.models) ? row.models : [];
                    providers.push({"text": id, "value": id});
                    modelMap[id] = models;
                }
            } catch (e) {}
            root.piProviderCandidates = providers;
            root.piProviderModelMap = modelMap;
            root.piModelsFetching = false;
            disconnectSource(sourceName);
            var waiters = root.piModelFetchWaiters || [];
            root.piModelFetchWaiters = [];
            for (var w = 0; w < waiters.length; w++)
                if (waiters[w]) waiters[w](providers, modelMap);
        }
    }

    P5Support.DataSource {
        id: fileReaderDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = Number(data["exit code"]);
            if (isNaN(exitCode)) exitCode = 1;
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            if (sourceName.indexOf("#mcp-tool-") !== -1) {
                var mcpToken = sourceName.substring(sourceName.indexOf("#mcp-tool-"));
                var mcpCallback = root.mcpPendingOperations[mcpToken];
                delete root.mcpPendingOperations[mcpToken];
                disconnectSource(sourceName);
                if (mcpCallback)
                    mcpCallback({"exit code": exitCode, "stdout": stdout, "stderr": stderr});
                return ;
            }
            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        var res = JSON.parse(stdout);
                        if (res.status === "success") {
                            var currentFiles = root.attachedFiles.slice();
                            if (res.mode === "files" && res.files) {
                                for (var f = 0; f < Math.min(res.files.length, 10 - currentFiles.length); f++) {
                                    var fInfo = res.files[f];
                                    var exists = false;
                                    for (var idx = 0; idx < currentFiles.length; idx++) {
                                        if (currentFiles[idx].path === fInfo.path) {
                                            exists = true;
                                            break;
                                        }
                                    }
                                    if (!exists)
                                        currentFiles.push({
                                            "name": fInfo.filename || fInfo.name,
                                            "path": fInfo.path,
                                            "type": fInfo.type,
                                            "content": fInfo.content,
                                            "mimeType": fInfo.mimeType,
                                            "size": fInfo.size,
                                            "loading": false,
                                            "error": ""
                                        });

                                }
                            } else if (res.mode === "image" && res.file && currentFiles.length < 10) {
                                var fInfo = res.file;
                                var exists = false;
                                for (var idx = 0; idx < currentFiles.length; idx++) {
                                    if (currentFiles[idx].path === fInfo.path) {
                                        exists = true;
                                        break;
                                    }
                                }
                                if (!exists)
                                    currentFiles.push({
                                        "name": fInfo.name,
                                        "path": fInfo.path,
                                        "type": fInfo.type,
                                        "content": fInfo.content,
                                        "mimeType": fInfo.mimeType,
                                        "size": fInfo.size,
                                        "loading": false,
                                        "error": ""
                                    });

                            }
                            root.attachedFiles = currentFiles;
                        }
                    } catch (e) {
                        console.log("Failed to parse clipboard data: " + e);
                    }
                }
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#spectacle-shot-") !== -1) {
                if (exitCode === 0) {
                    var parts = sourceName.split("|");
                    if (parts.length > 1) {
                        var shotPath = parts[1].trim();
                        if (shotPath !== "")
                            attachFile("file://" + shotPath);
                    }
                } else {
                    pushErrorMessage("Screen region capture cancelled or failed.");
                }
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#fetch-opencode-agents") !== -1) {
                var fallbackAgents = [];
                var fallbackDefault = "";
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        var agentData = JSON.parse(stdout.trim());
                        fallbackAgents = normalizeOpenCodeAgents(agentData);
                        fallbackDefault = agentData.default || agentData.default_agent || "";
                    } catch (e) {
                        console.log("Failed to parse opencode agents: " + e);
                    }
                }
                _finishOpenCodeAgents(fallbackAgents, fallbackDefault);
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#plasmashell-watchdog-") !== -1) {
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#export-chat-save") !== -1) {
                if (exitCode !== 0)
                    pushErrorMessage("Export failed: " + (stderr.trim() || stdout.trim() || ("helper exited with code " + exitCode)));
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#desktop-selection") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    var selText = stdout.trim();
                    if (selText !== "") {
                        root.chatInputText = selText;
                        plasmoid.expanded = true;
                    }
                }
                disconnectSource(sourceName);
                return ;
            }
            var matchedIndex = -1;
            var files = root.attachedFiles.slice();
            var attachmentPath = "";
            var requestKeys = Object.keys(root.pendingAttachmentRequests || {});
            for (var rk = 0; rk < requestKeys.length; rk++) {
                if (sourceName.indexOf(requestKeys[rk]) !== -1) {
                    var pendingEntry = root.pendingAttachmentRequests[requestKeys[rk]] || {};
                    attachmentPath = typeof pendingEntry === "string" ? pendingEntry : (pendingEntry.path || "");
                    var remainingRequests = Object.assign({}, root.pendingAttachmentRequests);
                    delete remainingRequests[requestKeys[rk]];
                    root.pendingAttachmentRequests = remainingRequests;
                    break;
                }
            }
            if (!attachmentPath) {
                disconnectSource(sourceName);
                return;
            }
            for (var i = 0; i < files.length; i++) {
                if (files[i].path === attachmentPath) {
                    matchedIndex = i;
                    break;
                }
            }
            if (matchedIndex === -1) {
                disconnectSource(sourceName);
                return;
            }
            var fileObj = Object.assign({
            }, files[matchedIndex]);
            fileObj.loading = false;
            if (exitCode !== 0 || stderr.trim() !== "") {
                fileObj.error = stderr.trim() || ("Command exited with code " + exitCode);
            } else {
                try {
                    var res = JSON.parse(stdout);
                    if (res.status === "success") {
                        fileObj.type = res.type;
                        fileObj.content = res.content;
                        fileObj.mimeType = res.mimeType;
                        fileObj.size = res.size;
                    } else {
                        fileObj.error = res.message || "Failed to extract file contents";
                    }
                } catch (e) {
                    fileObj.error = "Failed to parse extractor output: " + e;
                }
            }
            files[matchedIndex] = fileObj;
            root.attachedFiles = files;
            disconnectSource(sourceName);
        }
    }

    FileDialog {
        id: fileDialog

        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Documents (*.pdf *.docx *.csv *.txt *.md *.json)", "All files (*)"]
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; i++) {
                root.attachFile(selectedFiles[i]);
            }
        }
    }

    FileDialog {
        id: exportFileDialog

        title: "Export Chat Session"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown files (*.md)", "Plain text files (*.txt)"]
        onAccepted: {
            var path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.performExportChat(path);
        }
    }

    FolderDialog {
        id: workspaceFolderDialog

        title: "Select OpenCode Working Directory"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.openCodeWorkspaceCwd = path;
            plasmoid.configuration.openCodeWorkspaceCwd = path;
        }
    }

    // Text editor acting as helper to interact with OS text clipboard (copy / paste)
    // Placed offscreen so selection/clipboard actions function correctly in all Qt versions
    TextEdit {
        id: clipboardHelper

        x: -9999
        y: -9999
        width: 1
        height: 1
        visible: true
    }

    P5Support.DataSource {
        id: sysInfoDs

        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var output = data["stdout"] ? data["stdout"].trim() : "";
            if (pendingSysInfoCommands[source]) {
                delete pendingSysInfoCommands[source];
                switch (source) {
                case "hostname":
                    sysInfo.hostname = output;
                    break;
                case "uname -a":
                    sysInfo.kernel = output;
                    break;
                case "whoami":
                    sysInfo.user = output;
                    break;
                case "echo $SHELL":
                    sysInfo.shell = output;
                    break;
                case "cat /etc/os-release":
                    var lines = output.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("PRETTY_NAME=") === 0) {
                            sysInfo.osRelease = lines[i].replace("PRETTY_NAME=", "").replace(/"/g, "");
                            break;
                        }
                    }
                    if (!sysInfo.osRelease)
                        sysInfo.osRelease = output.substring(0, 100);

                    break;
                case "echo $XDG_CURRENT_DESKTOP":
                    sysInfo.desktop = output;
                    break;
                case "lscpu":
                    var cpuLines = output.split("\n");
                    var cpuInfo = {
                    };
                    for (var j = 0; j < cpuLines.length; j++) {
                        var parts = cpuLines[j].split(":");
                        if (parts.length >= 2) {
                            var key = parts[0].trim();
                            var val = parts.slice(1).join(":").trim();
                            if (["Model name", "CPU(s)", "Architecture", "Thread(s) per core", "Core(s) per socket"].indexOf(key) !== -1)
                                cpuInfo[key] = val;

                        }
                    }
                    sysInfo.cpu = cpuInfo["Model name"] || "unknown";
                    sysInfo.cpuCores = (cpuInfo["CPU(s)"] || "?") + " threads, " + (cpuInfo["Core(s) per socket"] || "?") + " cores";
                    sysInfo.cpuArch = cpuInfo["Architecture"] || "";
                    break;
                case "free -h":
                    sysInfo.memory = output;
                    break;
                case "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT":
                    sysInfo.disk = output;
                    break;
                case "bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"":
                    sysInfo.gpu = output || "unknown";
                    break;
                case "ip -br addr show":
                    sysInfo.network = output;
                    break;
                case "echo $LANG":
                    sysInfo.locale = output;
                    break;
                }
                sysInfoPending--;
                if (sysInfoPending === 0) {
                    plasmoid.configuration.gatheredSysInfo = JSON.stringify(sysInfo);
                    initSystemPrompt();
                }
                disconnectSource(source);
            }
        }
    }

    function getHelperPath() {
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        let path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
    }

    function enqueueSchedulerTrigger(trigger) {
        if (!trigger || !trigger.chatId || !trigger.message)
            return false;
        var idx = root.sessionIndexById(String(trigger.chatId));
        if (idx < 0) {
            console.warn("Scheduler trigger: chatId not found in sessions:", trigger.chatId);
            return false;
        }
        if (!root.schedulerResumeSessionId && root.currentSessionId !== String(trigger.chatId))
            root.schedulerResumeSessionId = root.currentSessionId;
        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var messages = session.value === root.currentSessionId ? root.messages.slice() : (session.messages || []).slice();
        var ts = Date.now();
        messages.push({
            "role": "queued",
            "content": String(trigger.message),
            "time": root.nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": ++root.queueCounter,
            "attachments": [],
            "scheduled": true,
            "scheduleName": String(trigger.name || "Scheduled task")
        });
        session.messages = messages;
        session.updatedAt = ts;
        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId)
            root.messages = messages;
        root.persistSessions();
        return true;
    }

    P5Support.DataSource {
        id: schedulerDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let out = data["stdout"] ? data["stdout"] : "";
            if (sourceName.indexOf("poll_pending_triggers") >= 0) {
                root.schedulerPollInFlight = false;
                schedulerPollTimeout.stop();
            }

            schedulerDs.disconnectSource(sourceName);

            if (out.trim() === "")
                return;

            if (sourceName.indexOf("poll_pending_triggers") >= 0) {
                try {
                    let parsed = JSON.parse(out);
                    let pending = parsed.pending || [];
                    for (let i = 0; i < pending.length; i++) {
                        let p = pending[i];
                        if (root.enqueueSchedulerTrigger(p)) {
                            console.log("Scheduler trigger:", p.name, "-> chatId:", p.chatId);
                            if (p.notify) {
                                root.triggerNotificationSound();
                                let escMsg = String(p.name || "Scheduled task") + ": " + String(p.message);
                                let notifyCmd = "notify-send -i dialog-messages 'KDE AI Chat - Scheduler' " + Sec.quoteForShell(escMsg);
                                soundDs.connectSource(notifyCmd + " #sched-notify-" + Date.now());
                            }
                        }
                    }
                    if (!root.loading)
                        root.processNextQueuedMessage();
                } catch (e) {
                    console.warn("Failed to parse pending triggers JSON:", e);
                }
            }
        }
    }

    Timer {
        id: schedulerPollTimeout
        interval: 10000
        repeat: false
        onTriggered: root.schedulerPollInFlight = false
    }

    Timer {
        id: schedulerPollTimer
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            // Don't poll until sessions are loaded so sessionIndexById works
            if (!root._initialLoadDone || root.schedulerPollInFlight)
                return;

            let localShare = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
            if (localShare.indexOf("file://") === 0) {
                localShare = localShare.substring(7);
            }
            localShare = decodeURIComponent(localShare);
            let pendingDir = localShare + "/kdeaichat/pending";
            let helper = root.getHelperPath();
            if (!helper) return;
            let cmd = "[ -d " + Sec.quoteForShell(pendingDir) + " ] && [ \"$(ls -A " + Sec.quoteForShell(pendingDir) + " 2>/dev/null)\" ] && python3 " + Sec.quoteForShell(helper) + " poll_pending_triggers";
            root.schedulerPollInFlight = true;
            schedulerPollTimeout.restart();
            schedulerDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #poll_pending_triggers-" + Date.now());
        }
    }

    // True when the custom widget icon is an image file (not a KDE icon name).
    function customIconIsImage() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return false;
        var s = v.trim().toLowerCase();
        if (s.indexOf("file://") === 0 || s.charAt(0) === "/")
            return true;
        return s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg")
            || s.endsWith(".gif") || s.endsWith(".webp") || s.endsWith(".svg")
            || s.endsWith(".svgz") || s.endsWith(".bmp");
    }

    // Turns the stored icon value (a file path) into a QML-usable source URL.
    function customIconImageSource() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return "";
        if (v.indexOf("file://") === 0)
            return v;
        return "file://" + v;
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        // Custom image icons (including animated GIFs) are rendered with an
        // Image element; KDE icon names fall back to Kirigami.Icon.
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: root.customIconIsImage()
            source: root.customIconImageSource()
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: !root.customIconIsImage()
            source: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon)
                ? plasmoid.configuration.customIcon : "dialog-messages"
        }
    }

    fullRepresentation: Item {
        implicitWidth: root.popupPreferredWidth
        implicitHeight: root.popupPreferredHeight
        Layout.minimumWidth: 500
        Layout.minimumHeight: 620
        Layout.preferredWidth: root.popupPreferredWidth
        Layout.preferredHeight: root.popupPreferredHeight
        Component.onCompleted: {
            root.focusInput();
        }
        onVisibleChanged: {
            if (visible) {
                root.focusInput();
                Qt.callLater(root.scrollToBottom);
            }
        }
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorGroup: root.popupIsDark ? Kirigami.Theme.Dark : Kirigami.Theme.Light
        Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
        Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
        Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
        Kirigami.Theme.highlightColor: "#3182ce"

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            radius: 8
        }

        Loader {
            id: mainContentLoader

            anchors.fill: parent
            active: root.expanded || root._initialLoadDone
            source: "FullRepresentationContent.qml"

            onStatusChanged: {
                console.log("Loader status changed:", status, (status === Loader.Error ? "ERROR!" : ""));
                if (status === Loader.Error) {
                    console.log("Error string:", sourceComponent ? sourceComponent.errorString() : "No sourceComponent");
                }
            }
        }

    }

}
