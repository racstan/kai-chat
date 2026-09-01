// ChatEngine.js — Unified application logic for KDE AI Chat
// Merged from: js, MainNetwork.js, MainOpenCode.js, MainScheduler.js

// js - Extracted logic for Main
var _pendingStreamingText = "";

function debugLog() {
if (debugMode) {
let args = Array.prototype.slice.call(arguments);
console.log.apply(console, args);
}
}


function sessionHasSchedules(sessionId) {
if (!sessionId)
return false;
for (let i = 0; i < root.schedulesList.length; i++) {
let s = root.schedulesList[i];
if (s && s.enabled && s.chatId === sessionId)
return true;
}
return false;
}


function triggerConfigure() {
if (typeof plasmoid.containment !== "undefined" && typeof plasmoid.containment.configureRequested === "function") {
plasmoid.containment.configureRequested(plasmoid);
} else if (typeof root.plasmoidRef !== "undefined" && typeof root.plasmoidRef.configureRequested === "function") {
root.plasmoidRef.configureRequested();
} else if (typeof plasmoid.configureRequested === "function") {
plasmoid.configureRequested();
} else if (typeof root.plasmoidRef !== "undefined" && typeof root.plasmoidRef.action === "function") {
let act = root.plasmoidRef.action("configure");
if (act && typeof act.trigger === "function")
act.trigger();
} else if (typeof plasmoid.action === "function") {
let act2 = plasmoid.action("configure");
if (act2 && typeof act2.trigger === "function")
act2.trigger();
}
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


function searchNext() {
if (root.searchMatches.length === 0) return;
root.currentSearchMatchIndex = (root.currentSearchMatchIndex + 1) % root.searchMatches.length;
if (root.msgListViewRef) {
root.positionListViewAtIndex(root.searchMatches[root.currentSearchMatchIndex], ListView.Center);
}
}


function searchPrev() {
if (root.searchMatches.length === 0) return;
root.currentSearchMatchIndex = (root.currentSearchMatchIndex - 1 + root.searchMatches.length) % root.searchMatches.length;
if (root.msgListViewRef) {
root.positionListViewAtIndex(root.searchMatches[root.currentSearchMatchIndex], ListView.Center);
}
}


function pad2(v) {
return v < 10 ? ("0" + v) : String(v);
}


function nowTime(ts) {
let d = ts ? new Date(ts) : new Date();
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
return SessionManager.makeSessionId();
}


function reportParseFailure(context, error) {
let msg = (context || "Parse failure") + ": " + (error && error.toString ? error.toString() : String(error || ""));
console.warn(msg);
pushErrorMessage(msg);
}


function makeForkSessionId() {
return SessionManager.makeForkSessionId();
}


function forkSession(messageIndex) {
if (root.currentSessionId === "")
return ;
let idx = sessionIndexById(root.currentSessionId);
if (idx < 0)
return ;
let originalSession = root.sessions[idx];
let forkedMessages = [];
if (originalSession.messages && messageIndex >= 0 && messageIndex < originalSession.messages.length) {
for (let i = 0; i <= messageIndex; i++) {
forkedMessages.push(JSON.parse(JSON.stringify(originalSession.messages[i])));
}
}
let forkId = makeForkSessionId();
let originalTitle = originalSession.text || "New Chat";
let cleanTitle = originalTitle.indexOf("[FK] ") === 0 ? originalTitle.substring(5) : originalTitle;
let forkTitle = "[FK] " + cleanTitle;
let s = {
"value": forkId,
"text": forkTitle,
"createdAt": Date.now(),
"updatedAt": Date.now(),
"archived": false,
"source": originalSession.source || "provider",
"openCodeSessionId": originalSession.openCodeSessionId || "",
"parentSessionId": originalSession.value,
"parentSessionTitle": originalSession.text || "Original Chat",
"readCount": forkedMessages.length,
"messages": forkedMessages
};
root.sessions = [s].concat(root.sessions);
root.openCodeMode = (s.source === "opencode");
root.piMode = (s.source === "pi");
root.currentSessionId = s.value;
root.currentSessionTitle = s.text;
root.messages = forkedMessages;
precomputeBlocksForMessages(root.messages);
root.editingMessageIndex = -1;
root.editingDraft = "";
root.editingSessionId = "";
root.editingSessionDraft = "";
root.renamingCurrentChat = false;
root.currentChatRenameDraft = "";
root.historyOnlyMode = false;
persistSessions();
scrollToBottom();
root.focusInput();
}


function parseSessions(customRaw) {
let raw = customRaw !== undefined ? customRaw : (plasmoid.configuration.chatSessionsJson || "[]");
try {
let arr = typeof raw === "string" ? JSON.parse(raw) : raw;
if (Array.isArray(arr)) {
for (let i = 0; i < arr.length; i++) {
if (!arr[i].messages)
arr[i].messages = [];
if (arr[i].archived === undefined)
arr[i].archived = false;
if (!arr[i].source)
arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";
if (arr[i].readCount === undefined)
arr[i].readCount = arr[i].messages.length;
for (let j = 0; j < arr[i].messages.length; j++) {
if (!arr[i].messages[j].at)
arr[i].messages[j].at = arr[i].updatedAt || arr[i].createdAt || Date.now();
if (!arr[i].messages[j].time)
arr[i].messages[j].time = nowTime(arr[i].messages[j].at);
ensureMessageMetadata(arr[i].messages[j]);
// Block parsing is now done lazily per-session to prevent massive startup lag.
}
if (!arr[i].updatedAt)
arr[i].updatedAt = arr[i].createdAt || Date.now();
}
return arr;
}
return [];
} catch (e) {
return [];
}
}


function checkAndMarkCurrentSessionAsRead() {
if (root.expanded && !root.historyOnlyMode && root.currentSessionId !== "") {
let idx = sessionIndexById(root.currentSessionId);
if (idx >= 0) {
let s = root.sessions[idx];
let currentMsgsCount = root.messages.length;
if (s.readCount !== currentMsgsCount) {
let updated = root.sessions.slice();
let item = Object.assign({
}, updated[idx]);
item.readCount = currentMsgsCount;
item.messages = root.messages;
updated[idx] = item;
root.sessions = updated;
persistSessions();
}
}
}
}


function getHistoryFilePath(customDir) {
let dir = (customDir || "").trim();
if (dir === "")
return "";
if (dir.indexOf("file://") === 0)
dir = decodeURIComponent(dir.slice(7));
let fullPath = dir;
if (!fullPath.endsWith(".json")) {
if (fullPath.endsWith("/"))
fullPath += "kdeaichat_history.json";
else
fullPath += "/kdeaichat_history.json";
}
return fullPath;
}


function migrateHistory(oldPath, newPath) {
let oldFullPath = getHistoryFilePath(oldPath);
let newFullPath = getHistoryFilePath(newPath);
// When switching TO a custom path, always export current in-memory sessions
// to the new location, then fall back to copying the old file if it exists.
let currentJson = JSON.stringify(root.sessions, function(key, value) {
    if (key === "blocks" || key === "lastParsedContent") return undefined;
    return value;
});
let b64Current = base64Encode(currentJson);
let payload = {
"oldFullPath": oldFullPath,
"newFullPath": newFullPath,
"currentB64": b64Current
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " migrate_history " + Sec.rawShellSnippetQuote(b64Payload);
customStorageDs.connectSource(cmd + " #migrate-history-" + Date.now());
}


function persistSessions() {
// Debounce: schedule a flush within the next 1 second. Bursts
// of state changes (streaming tokens, typing, label edits) all
// collapse into a single write instead of one per call.
persistSessionsDebounce.restart();
}


function flushPersistSessions() {
let jsonStr = JSON.stringify(root.sessions, function(key, value) {
    if (key === "blocks" || key === "lastParsedContent") return undefined;
    return value;
});
let b64 = base64Encode(jsonStr);
let dataDir = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat";
let sessionsFile = dataDir + "/sessions.json";
let writeCmd = "mkdir -p " + Sec.quoteForShell(dataDir)
    + " && echo " + Sec.rawShellSnippetQuote(b64)
    + " | base64 -d > " + Sec.quoteForShell(sessionsFile);
customStorageDs.connectSource(writeCmd + " #sessions-write-" + Date.now());
let customDir = (plasmoid.configuration.customHistoryPath || "").trim();
if (customDir !== "") {
let fullPath = getHistoryFilePath(customDir);
let writeCmd2 = "echo " + Sec.rawShellSnippetQuote(b64)
    + " | base64 -d > " + Sec.quoteForShell(fullPath);
customStorageDs.connectSource(writeCmd2 + " #custom-history-write-" + Date.now());
}
}


function sortSessionsByUpdated() {
// Audit 5.3: skip the O(n log n) sort + array reassignment cascade
// when the list is already in canonical order. The reassignment
// was the dominant cost during streaming because it invalidated
// all sidebar binding caches on every save.
if (SessionManager.isSessionOrderCorrect(root.sessions))
return ;
let copy = SessionManager.sortSessionsByUpdated(root.sessions);
root.sessions = copy;
}


function historySessionTint(sessionData) {
if (!sessionData)
return Qt.rgba(root.themeTextColor.r, root.themeTextColor.g, root.themeTextColor.b, 0.05);
if (sessionData.value === root.currentSessionId && (sessionData.source === "opencode" || sessionData.source === "pi"))
return Qt.rgba(0.2, 0.48, 0.92, 0.22);
if (sessionData.source === "opencode" || sessionData.source === "pi")
return Qt.rgba(0.2, 0.48, 0.92, 0.1);
if (sessionData.value === root.currentSessionId)
return Qt.rgba(root.themeHighlightColor.r, root.themeHighlightColor.g, root.themeHighlightColor.b, 0.18);
return Qt.rgba(root.themeTextColor.r, root.themeTextColor.g, root.themeTextColor.b, 0.05);
}


function sessionSubtitle(sessionData) {
let parts = [];
if (sessionData.source === "opencode")
parts.push("OpenCode");
else if (sessionData.source === "pi")
parts.push("Pi Agent");
if (sessionData.archived)
parts.push("Archived");
parts.push("Updated " + root.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()));
return parts.join(" · ");
}


function sessionIndexById(sessionId) {
for (let i = 0; i < root.sessions.length; i++) {
if (root.sessions[i].value === sessionId)
return i;
}
return -1;
}


function createSession(switchToNew) {
let usePi = plasmoid.configuration.usePi;
let useOpenCode = plasmoid.configuration.useOpenCode;
let s = {
"value": makeSessionId(),
"text": "New Chat",
"createdAt": Date.now(),
"updatedAt": Date.now(),
"archived": false,
"source": usePi ? "pi" : (useOpenCode ? "opencode" : "provider"),
"openCodeSessionId": "",
"readCount": 0,
"messages": []
};
root.sessions = [s].concat(root.sessions);
if (switchToNew) {
root.piMode = usePi;
root.openCodeMode = useOpenCode;
root.currentSessionId = s.value;
root.currentSessionTitle = s.text;
root.messages = [];
precomputeBlocksForMessages(root.messages);
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


function loadSessions() {
root.sessions = parseSessions();
if (root.sessions.length === 0)
createSession(true);
let preferred = plasmoid.configuration.lastSessionId || "";
let idx = sessionIndexById(preferred);
if (idx < 0)
idx = 0;
root.currentSessionId = root.sessions[idx].value;
root.currentSessionTitle = root.sessions[idx].text;
root._lastParsedMsgIdx = -1;
root._lastMetaIdx = -1;
root.messages = root.sessions[idx].messages || [];
// onMessagesChanged handles precomputation — no need for explicit call.
if (root.sessions[idx]) {
root.openCodeMode = (root.sessions[idx].source === "opencode");
root.piMode = (root.sessions[idx].source === "pi");
}
sortSessionsByUpdated();
let kcfgData = (plasmoid.configuration.chatSessionsJson || "").trim();
if (kcfgData !== "" && kcfgData !== "[]") {
return;
}
let dataDir = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat";
let sessionsFile = dataDir + "/sessions.json";
let readCmd = "cat " + Sec.quoteForShell(sessionsFile) + " 2>/dev/null || echo '[]'";
customStorageDs.connectSource(readCmd + " #sessions-read-" + Date.now());
}

function precomputeBlocksAndHtmlForMessage(msg) {
    if (!msg) return;
    if (msg.content === undefined || msg.content === null) return;
    if (!msg.blocks || msg.lastParsedContent !== msg.content) {
        try {
            msg.blocks = parseMessageBlocks(msg.content);
            msg.lastParsedContent = msg.content;
        } catch (_) {
            return;
        }
    }
    if (msg.blocks) {
        for (let i = 0; i < msg.blocks.length; i++) {
            let block = msg.blocks[i];
            if (block.type === "text") {
                // Single-slot cache: keyed on themeTextColor hex for instant invalidation on theme change
                let themeKey = root.themeTextColor ? root.themeTextColor.toString() : "x";
                if (block.contentHtmlCache !== themeKey) {
                    block.contentHtmlCache = themeKey;
                    block.contentHtmlResult = MarkdownRenderer.convertMarkdownToHtml(block.content || "", root.popupIsDark);
                }
            }
        }
    }
}


function precomputeBlocksForMessages(msgs) {
    if (!msgs) return;
    for (let j = 0; j < msgs.length; j++) {
        precomputeBlocksAndHtmlForMessage(msgs[j]);
    }
}


let _saveStateDirty = false;
let _saveStateTouch = false;

function saveCurrentSessionState(touchUpdatedAt) {
if (touchUpdatedAt !== false) _saveStateTouch = true;
if (_saveStateDirty) {
// A deferred save is already scheduled and will run on the next tick.
// Skip the redundant persistSessions() call so we don't restart the
// debounce timer (each restart resets the 3-second window).
return ;
}
_saveStateDirty = true;
Qt.callLater(function() {
_saveStateDirty = false;
let doTouch = _saveStateTouch;
_saveStateTouch = false;
_saveCurrentSessionStateImpl(doTouch);
});
persistSessions();
}

function _saveCurrentSessionStateImpl(touchUpdatedAt) {
let idx = sessionIndexById(root.currentSessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let s = Object.assign({}, updated[idx]);
s.text = root.currentSessionTitle || "New Chat";
s.messages = root.messages;
if (root.expanded && !root.historyOnlyMode)
s.readCount = root.messages.length;
else
s.readCount = s.readCount !== undefined ? s.readCount : root.messages.length;
if (touchUpdatedAt !== false)
s.updatedAt = Date.now();
updated[idx] = s;
let prev = root.sessions[idx];
if (prev && s.text === prev.text
&& s.messages === prev.messages
&& s.readCount === prev.readCount
&& (touchUpdatedAt === false || s.updatedAt === prev.updatedAt)) {
return;
}
root.sessions = updated;
if (touchUpdatedAt !== false)
sortSessionsByUpdated();
}


function setCurrentSessionSource(source) {
let idx = sessionIndexById(root.currentSessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let item = Object.assign({
}, updated[idx]);
item.source = source || "provider";
item.archived = false;
updated[idx] = item;
root.sessions = updated;
persistSessions();
}


function setSessionArchived(sessionId, archived) {
let idx = sessionIndexById(sessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let item = Object.assign({
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
saveCurrentSessionState(false);
let idx = sessionIndexById(sessionId);
if (idx < 0)
return ;
root.currentSessionId = root.sessions[idx].value;
root.currentSessionTitle = root.sessions[idx].text;
root._lastParsedMsgIdx = -1;
root._lastMetaIdx = -1;
// Show empty instantly — user sees immediate response.
root.messages = [];
root.openCodeMode = root.sessions[idx] ? (root.sessions[idx].source === "opencode") : false;
root.piMode = root.sessions[idx] ? (root.sessions[idx].source === "pi") : false;
root.editingMessageIndex = -1;
root.editingDraft = "";
root.editingSessionId = "";
root.editingSessionDraft = "";
root.renamingCurrentChat = false;
root.currentChatRenameDraft = "";
// Fill in the real messages during idle time — user can scroll the
// empty state while heavy QML delegate creation happens in background.
let targetMsgs = root.sessions[idx].messages || [];
Qt.callLater(function() {
    root.messages = targetMsgs;
    checkAndMarkCurrentSessionAsRead();
    scrollToBottom();
    root.focusInput();
});
}


function renameCurrentSession(newTitle) {
let title = (newTitle || "").trim();
if (title === "")
title = "New Chat";
root.currentSessionTitle = title;
saveCurrentSessionState(true);
}


function startSessionRename(sessionId) {
let idx = sessionIndexById(sessionId);
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
let idx = sessionIndexById(sessionId);
if (idx < 0)
return ;
let title = (root.editingSessionDraft || "").trim();
if (title === "")
title = "New Chat";
let updated = root.sessions.slice();
let s = Object.assign({
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
let idx = sessionIndexById(sessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
updated.splice(idx, 1);
root.sessions = updated;
if (root.currentSessionId === sessionId) {
let next = root.sessions[0];
root.currentSessionId = next.value;
root.currentSessionTitle = next.text;
root.messages = next.messages || [];
precomputeBlocksForMessages(root.messages);
}
cancelSessionRename();
persistSessions();
// Clean up schedules associated with this session
let payload = {
"sessionId": sessionId
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " delete_session_schedules " + Sec.rawShellSnippetQuote(b64Payload);
schedulerDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-session-delete-" + Date.now());
// Also update root.schedulesList locally
let copy = root.schedulesList.filter(function(s) {
return s.chatId !== sessionId;
});
root.schedulesList = copy;
}


function deleteMessage(index) {
let copy = root.messages.slice();
if (index < 0 || index >= copy.length)
return ;
copy.splice(index, 1);
root.messages = copy;
root.editingMessageIndex = -1;
root.editingDraft = "";
if (root.deferSaveStateTimer) {
    root.deferSaveStateTimer.restart();
} else {
    Qt.callLater(function() {
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
    });
}
}


function isLatestUserMessage(index) {
if (index < 0 || index >= root.messages.length)
return false;
if (root.messages[index].role !== "user")
return false;
for (let i = index + 1; i < root.messages.length; i++) {
if (root.messages[i].role === "user")
return false;
}
return true;
}


function hasSubsequentAssistantMessage(index) {
if (index < 0 || index >= root.messages.length - 1)
return false;
return root.messages[index + 1].role === "assistant";
}


function regenerateReply(index, type) {
if (index < 0 || index >= root.messages.length)
return ;
let userMsg = root.messages[index];
let aiMsg = (index + 1 < root.messages.length) ? root.messages[index + 1] : null;
let instruction = type === "shorter" ? "generate a much shorter version" : "generate a much more detailed and longer version";
let prompt = "";
if (aiMsg && aiMsg.role === "assistant") {
prompt = "I'm looking for a different version of your last response. \n\n" + "My original question was: \"" + userMsg.content + "\"\n" + "Your previous response was: \"" + aiMsg.content + "\"\n\n" + "Please " + instruction + " of that response.";
} else {
prompt = "Please " + instruction + " in response to my question: \"" + userMsg.content + "\"";
}
root.chatInputText = prompt;
sendMessage();
}


function saveEditedMessage() {
let i = root.editingMessageIndex;
if (i < 0 || i >= root.messages.length)
return ;
if ((root.messages[i].role || "") === "error") {
root.editingMessageIndex = -1;
root.editingDraft = "";
return ;
}
// Cancel any active streaming/loading requests first
stopStreaming();
let role = root.messages[i].role || "";
let isQueued = role === "queued";
let copy = isQueued ? root.messages.slice() : root.messages.slice(0, i + 1);
let item = Object.assign({
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
        if (root.sendMessageDelayTimer) {
            root.sendMessageDelayTimer.messageIndex = i;
            root.sendMessageDelayTimer.start();
        } else {
            sendMessageByIndex(i);
        }
    }
}


function getSessionProperty(sessionId, key, defaultValue) {
let idx = sessionIndexById(sessionId);
if (idx < 0)
return defaultValue;
let val = root.sessions[idx][key];
return val !== undefined ? val : defaultValue;
}


function setSessionProperty(sessionId, key, value) {
let idx = sessionIndexById(sessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let item = Object.assign({
}, updated[idx]);
item[key] = value;
updated[idx] = item;
root.sessions = updated;
persistSessions();
}


function appendCompactPromptMessage(chatId) {
let ts = Date.now();
let msgObj = {
"role": "compact_request",
"status": "pending",
"content": "The conversation history has exceeded the configured threshold. Would you like to compact the older history into a concise summary to stay within context limit?",
"time": nowTime(ts),
"at": ts,
"model": "",
"queueId": 0,
"attachments": [],
"isSystem": true
};
appendMessageToSession(chatId, msgObj);
if (chatId === root.currentSessionId) {
if (!root.userScrolledUp)
queueScrollToBottom();
}
}


function respondToCompactRequest(msgIndex, approved) {
let copy = root.messages.slice();
if (msgIndex < 0 || msgIndex >= copy.length)
return;
let msgObj = Object.assign({}, copy[msgIndex]);
if (msgObj.role !== "compact_request")
return;
if (approved) {
msgObj.status = "compacted";
copy[msgIndex] = msgObj;
root.messages = copy;
saveCurrentSessionState(touchSessionsList(root.currentSessionId));
compactSessionContext(root.currentSessionId);
} else {
msgObj.status = "cancelled";
copy[msgIndex] = msgObj;
root.messages = copy;
saveCurrentSessionState(touchSessionsList(root.currentSessionId));
}
}


function touchSessionsList(chatId) {
// Helper to force-notify sessions update on QML side
let idx = sessionIndexById(chatId);
if (idx >= 0) {
let updated = root.sessions.slice();
updated[idx].updatedAt = Date.now();
root.sessions = updated;
}
return true;
}


function checkAndAutoCompact(sessionId) {
let sId = sessionId || root.currentSessionId;
let idx = sessionIndexById(sId);
if (idx < 0)
return ;
let msgs = root.sessions[idx].messages || [];
let lastUserMsg = null;
for (let j = msgs.length - 1; j >= 0; j--) {
if (msgs[j].role === "user" && !msgs[j].isSystem) {
lastUserMsg = msgs[j];
break;
}
}
if (lastUserMsg && lastUserMsg.sc)
return ;
let override = getSessionProperty(sId, "contextOverride", false);
let autoCompact = override ? getSessionProperty(sId, "contextAutoCompact", false) : plasmoid.configuration.globalContextAutoCompact;
if (!autoCompact)
return ;
let threshold = override ? getSessionProperty(sId, "contextCompactThreshold", 10) : plasmoid.configuration.globalContextCompactThreshold;
let compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);
for (let k = compactedCount; k < msgs.length; k++) {
if (msgs[k].role === "compact_request")
return ;
}
let uncompactedCleanCount = 0;
for (let i = compactedCount; i < msgs.length; i++) {
let role = msgs[i].role;
if ((role === "user" || role === "assistant") && !msgs[i].isSystem)
uncompactedCleanCount++;
}
if (uncompactedCleanCount > threshold) {
appendCompactPromptMessage(sId);
}
}


function compactSessionContext(sessionId) {
let sId = sessionId || root.currentSessionId;
let idx = sessionIndexById(sId);
if (idx < 0)
return ;
let msgs = root.sessions[idx].messages || [];
let compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);
let cleanMsgs = [];
for (let i = compactedCount; i < msgs.length; i++) {
let role = msgs[i].role;
if ((role === "user" || role === "assistant") && !msgs[i].isSystem)
cleanMsgs.push({
"index": i,
"role": role,
"content": msgs[i].content
});
}
if (cleanMsgs.length < 3) {
appendSystemMessageToSession(sId, "Not enough messages to compact yet (need at least 3).");
return ;
}
let limitCleanIndex = cleanMsgs.length - 2;
let limitRealIndex = cleanMsgs[limitCleanIndex].index;
let textToSummarize = "";
let oldSummary = getSessionProperty(sId, "compactedSummary", "");
if (oldSummary !== "")
textToSummarize += "[Previous Summary]:\n" + oldSummary + "\n\n";
for (let j = 0; j < limitCleanIndex; j++) {
let prefix = cleanMsgs[j].role === "user" ? "User: " : "AI: ";
textToSummarize += prefix + cleanMsgs[j].content + "\n\n";
}
appendSystemMessageToSession(sId, "Compacting context, please wait...");
let promptText = "Please write a highly concise summary (max 3-4 sentences) of the following conversation history. Keep it extremely brief and factual, focus on user preferences, details of what was discussed/resolved, and any state that needs to be preserved. This summary will be injected into the system prompt of the next turns to maintain context:\n\n" + textToSummarize;
sendBackgroundSummarizationRequest(sId, promptText, limitRealIndex + 1);
}


function sendBackgroundSummarizationRequest(sId, promptText, count) {
let provider = "";
let model = "";
let apiKey = "";
let url = "";
let headers = null;
let isAnthropic = false;
if (root.openCodeMode) {
url = openCodeBaseUrl() + "/v1/chat/completions";
model = (plasmoid.configuration.openCodeModel || "").trim();
provider = "opencode";
} else {
provider = getEffectiveProvider(sId);
let providerCfg = getProviderConfig(provider, sId);
isAnthropic = (providerCfg.type === "anthropic");
if (isAnthropic) {
apiKey = providerCfg.apiKey;
model = providerCfg.model;
} else {
url = providerCfg.baseUrl;
apiKey = providerCfg.apiKey;
model = providerCfg.model;
headers = providerCfg.headers;
}
}
let xhr = new XMLHttpRequest();
if (isAnthropic) {
xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
xhr.setRequestHeader("x-api-key", apiKey);
xhr.setRequestHeader("anthropic-version", "2023-06-01");
xhr.setRequestHeader("content-type", "application/json");
} else {
let fullUrl = url;
if (!fullUrl.endsWith("/chat/completions") && !fullUrl.endsWith("/completions"))
fullUrl = fullUrl.replace(/\/+$/, "") + "/chat/completions";
xhr.open("POST", fullUrl, true);
xhr.setRequestHeader("Content-Type", "application/json");
if (apiKey !== "")
xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
if (headers) {
for (let key in headers) {
xhr.setRequestHeader(key, headers[key]);
}
}
}
xhr.timeout = 30000;
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
try {
let summaryText = "";
let res = JSON.parse(xhr.responseText);
if (isAnthropic) {
if (res.content && res.content.length > 0)
summaryText = res.content[0].text;
} else {
if (res.choices && res.choices.length > 0 && res.choices[0].message)
summaryText = res.choices[0].message.content;
}
summaryText = (summaryText || "").trim();
if (summaryText !== "") {
setSessionProperty(sId, "compactedSummary", summaryText);
setSessionProperty(sId, "compactedMessageCount", count);
if (root.openCodeMode)
setSessionProperty(sId, "openCodeSessionId", "");
appendSystemMessageToSession(sId, "Context compacted successfully. Summary: " + summaryText);
} else {
appendSystemMessageToSession(sId, "Warning: Context compaction returned an empty response.");
}
} catch (e) {
appendSystemMessageToSession(sId, "Warning: Failed to parse compaction response: " + e.toString());
}
} else {
let errMsg = "HTTP " + xhr.status;
try {
let errObj = JSON.parse(xhr.responseText);
if (errObj.error && errObj.error.message)
errMsg += ": " + errObj.error.message;
} catch (e) {
}
appendSystemMessageToSession(sId, "Warning: Context compaction failed: " + errMsg);
}
};
xhr.onerror = function() {
appendSystemMessageToSession(sId, "Warning: Network error while compacting context.");
};
let payload = {
};
if (isAnthropic)
payload = {
"model": model,
"max_tokens": 512,
"messages": [{
"role": "user",
"content": promptText
}]
};
else
payload = {
"model": model,
"max_tokens": 512,
"messages": [{
"role": "user",
"content": promptText
}]
};
try {
xhr.send(JSON.stringify(payload));
} catch (e) {
appendSystemMessageToSession(sId, "Warning: Failed to send compaction request: " + e.toString());
}
}


function updateAutocomplete() {
let txt = (root.msgInputRef ? root.msgInputRef.text : "") || "";
if (txt.startsWith("/")) {
let search = txt.substring(1).toLowerCase();
let filtered = [];
let all = [];
if (root.openCodeMode) {
all.push({
"name": "/help",
"desc": "Show available commands"
});
all.push({
"name": "/version",
"desc": "Show OpenCode version"
});
all.push({
"name": "/session",
"desc": "Show current session info"
});
all.push({
"name": "/schedule",
"desc": "Create/manage schedules (System Scheduler)"
});
} else {
all.push({
"name": "/schedule",
"desc": "Create/manage schedules"
});
}
let templatesRaw = plasmoid.configuration.promptTemplates || "[]";
try {
let templates = JSON.parse(templatesRaw);
for (let t of templates) {
if (t.name) {
let desc = (t.prompt || "").substring(0, 80);
if ((t.prompt || "").length > 80) desc += "…";
all.push({
"name": "/" + t.name,
"desc": desc,
"isTemplate": true
});
}
}
} catch(e) {}
for (let i = 0; i < all.length; i++) {
if (all[i].name.toLowerCase().indexOf("/" + search) === 0 || all[i].name.toLowerCase().substring(1).indexOf(search) >= 0)
filtered.push(all[i]);
}
root.filteredCommands = filtered;
if (filtered.length > 0) {
root.autocompleteActive = true;
if (root.autocompleteSelectedIndex >= filtered.length)
root.autocompleteSelectedIndex = 0;
} else {
root.autocompleteActive = false;
}
} else {
root.autocompleteActive = false;
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
root.streamingResponse = true;
root.streamingContent = "";
root.streamingModel = modelLabel || "";
root.streamingContextItems = [];
root.streamingTokens = null;
root.streamingCost = 0;
}


function updateAssistantStreamingContent(text, modelLabel) {
let incoming = text || "";
if (incoming === "")
return ;
if (modelLabel)
root.streamingModel = modelLabel;

_pendingStreamingText += incoming;
root.streamingResponse = true;
// Use start() not restart() — the repeating timer must not be reset on
// every token or it will never fire during a rapid burst. Calling start()
// on an already-running repeating timer is a no-op, which is what we want.
if (root.streamingBatchTimer && !root.streamingBatchTimer.running)
    root.streamingBatchTimer.start();
}


function flushIntermediateStreaming() {
if (_pendingStreamingText !== "") {
    root.streamingContent = (root.streamingContent || "") + _pendingStreamingText;
    _pendingStreamingText = "";
    if (!root.userScrolledUp)
        queueScrollToBottom();
}
}


function runLocalOpenCodeCommand(cmdText) {
let cmd = cmdText.trim().toLowerCase();
// Strip leading slash or "opencode " prefix
let bare = cmd.startsWith("/") ? cmd.substring(1) : cmd;
// Normalise e.g. "/models extra" → bare = "models"
let verb = bare.split(" ")[0];
root.autocompleteActive = false;
// ── /help ─────────────────────────────────────────────────────────
if (verb === "help") {
pushInfoMessage("**OpenCode commands:**\n" + "- `/help` — this message\n" + "- `/version` — show installed OpenCode version\n" + "- `/session` — show current session info\n" + "\nTo use the full OpenCode TUI, click the terminal icon in the session bar.");
return ;
}
// ── /version ──────────────────────────────────────────────────────
if (verb === "version") {
root.loading = true;
root.openCodeAssistantMessageIndex = -1;
root.openCodeAssistantServerMessageId = "";
root.openCodeErrorShownForRequest = false;
beginAssistantStreaming("OpenCode");
updateAssistantStreamingContent("Checking OpenCode version...\n", "OpenCode");
let token = "opencode-cli-" + Date.now();
opencodeTerminalDs.connectSource("opencode --version #" + token);
return ;
}
// ── /session ──────────────────────────────────────────────────────
if (verb === "session") {
let sid = currentOpenCodeSessionId();
// Session objects are keyed by `value`, not `id` — see
// SessionManager.createSessionObj. The previous code looked
// for `s.id` and always returned -1, which made the
// session-name lookup fall through to "(unnamed)".
let idx = root.sessions.findIndex ? root.sessions.findIndex(function(s) {
return s.value === root.currentSessionId;
}) : -1;
let sessionName = (idx >= 0 && root.sessions[idx]) ? (root.sessions[idx].text || root.sessions[idx].title || "(unnamed)") : "(unnamed)";
if (sid)
pushInfoMessage("**Current OpenCode Session**\n" + "- **Local session:** " + sessionName + "\n" + "- **Remote session ID:** `" + sid + "`\n" + "- **Server:** " + openCodeBaseUrl() + "\n" + "- **Messages in view:** " + root.messages.length);
else
pushInfoMessage("**Current OpenCode Session**\n" + "- **Local session:** " + sessionName + "\n" + "- **Remote session:** Not yet started (send a message to create one)\n" + "- **Server:** " + openCodeBaseUrl());
return ;
}
// ── Unknown ───────────────────────────────────────────────────────
pushErrorMessage("Unknown command: `" + cmdText.trim() + "`\nType `/help` to see available commands.");
}


function syncOpenCodeSessionHistory() {
let remoteSessionId = currentOpenCodeSessionId();
if (!remoteSessionId)
return ;
root.loading = true;
let xhr = new XMLHttpRequest();
xhr.open("GET", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
root.loading = false;
if (xhr.status >= 200 && xhr.status < 300) {
try {
let arr = JSON.parse(xhr.responseText);
if (Array.isArray(arr)) {
let newMsgs = [];
for (let i = 0; i < arr.length; i++) {
let item = arr[i] || {
};
let info = item.info || {
};
let parts = item.parts || [];
let role = info.role || "user";
let modelLabel = (info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode");
let combinedText = "";
let ctx = [];
for (let p = 0; p < parts.length; p++) {
let part = parts[p] || {
};
if (part.type === "text") {
combinedText += part.text || part.content || "";
} else if (part.type === "tool-invocation") {
let toolName = part.toolName || part.tool || "";
let toolArgs = part.args || part.input || {
};
if (toolName !== "") {
let desc = toolName;
if (toolArgs.filePath || toolArgs.path || toolArgs.file)
desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
else if (toolArgs.command)
desc += ": " + String(toolArgs.command).substring(0, 60);
ctx.push(desc);
}
}
}
// Normalize tokens
let normalizedTokens = {
};
if (item.tokens) {
let rawTokens = item.tokens || {
};
normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
if (rawTokens.reasoning !== undefined)
normalizedTokens.reasoning = rawTokens.reasoning;
if (rawTokens.cache !== undefined)
normalizedTokens.cache = rawTokens.cache;
}
let ts = info.createdAt ? new Date(info.createdAt).getTime() : Date.now();
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
// Use the local `sessionIndexById` helper —
// `currentSessionIndex` does not exist on
// `root` and would throw a TypeError at
// runtime.
let idx = sessionIndexById(root.currentSessionId);
if (idx >= 0) {
root.messages = newMsgs;
root.sessions[idx].messages = newMsgs;
saveCurrentSessionState(true);
queueScrollToBottom();
}
}
}
} catch (err) {
reportParseFailure("Failed to parse synced messages", err);
}
} else {
pushErrorMessage("Sync failed: OpenCode returned HTTP " + xhr.status);
}
};
xhr.send();
}


function handleOpenCodeEvent(eventObj) {
let props = eventObj && eventObj.properties ? eventObj.properties : {
};
let sessionId = props.sessionID || "";
if (!sessionId || sessionId !== root.openCodeActiveSessionId)
return ;
if (eventObj.type === "message.updated") {
let info = props.info || {
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
let part = props.part || {
};
if (part.type === "text" && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
updateAssistantStreamingContent(part.text || "", "OpenCode");
// Track tool invocations as context items on the assistant message
if (part.type === "tool-invocation") {
let toolName = part.toolName || part.tool || "";
let toolArgs = part.args || part.input || {
};
let toolState = part.state || "";
if (toolName !== "") {
// Build a concise description of the tool call
let desc = toolName;
if (toolArgs.filePath || toolArgs.path || toolArgs.file)
desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
else if (toolArgs.command)
desc += ": " + String(toolArgs.command).substring(0, 60);
else if (toolArgs.query || toolArgs.pattern)
desc += ": " + (toolArgs.query || toolArgs.pattern);
// Avoid duplicates
let ctx = root.streamingContextItems;
let exists = false;
for (let ci = 0; ci < ctx.length; ci++) {
if (ctx[ci] === desc) {
exists = true;
break;
}
}
if (!exists) {
root.streamingContextItems = ctx.concat([desc]);
}
}
}
} else if (eventObj.type === "session.error") {
if (!root.openCodeErrorShownForRequest) {
root.openCodeErrorShownForRequest = true;
pushErrorMessage(extractReadableError("OpenCode: ", props.error, "Session error."));
}
} else if (eventObj.type === "session.status") {
let status = props.status || {
};
if (status.type === "idle")
finishOpenCodeRequest();
} else if (eventObj.type === "session.idle") {
finishOpenCodeRequest();
} else if (eventObj.type === "permission.asked") {
let p = props.permission || {
};
let permId = p.id || "";
if (permId !== "") {
let tool = p.tool || "";
let args = p.arguments || {
};
let argStr = "";
try {
argStr = typeof args === "string" ? args : JSON.stringify(args, null, 2);
} catch (e) {
argStr = String(args);
}
let msg = {
"role": "permission_request",
"content": "OpenCode is asking for permission to run **" + tool + "**:\n\n```json\n" + argStr + "\n```",
"model": "OpenCode Security",
"id": "perm-" + permId,
"permissionId": permId,
"tool": tool,
"arguments": args,
"status": "pending",
"at": Date.now()
};
root.messages.push(msg);
root.messagesChanged();
saveCurrentSessionState(true);
if (!root.userScrolledUp)
queueScrollToBottom();
}
} else if (eventObj.type === "permission.replied") {
let pr = props.permission || {
};
let pId = pr.id || "";
let response = pr.response || "";
let permissionMsgs = root.messages.slice();
let updated = false;
for (let i = permissionMsgs.length - 1; i >= 0; i--) {
if (permissionMsgs[i].role === "permission_request" && permissionMsgs[i].permissionId === pId) {
permissionMsgs[i].status = (response === "allow" ? "allowed" : "denied");
updated = true;
break;
}
}
if (updated) {
root.messages = permissionMsgs;
saveCurrentSessionState(true);
}
} else if (eventObj.type === "session.next.step.ended") {
let rawTokens = props.tokens || {};
let normalizedTokens = root.streamingTokens || {};
normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : normalizedTokens.input));
normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : normalizedTokens.output));
if (rawTokens.reasoning !== undefined) normalizedTokens.reasoning = rawTokens.reasoning;
if (rawTokens.cache !== undefined) normalizedTokens.cache = rawTokens.cache;
root.streamingTokens = normalizedTokens;
if (props.cost) root.streamingCost = props.cost;
} else if (eventObj.type === "question.asked") {
let requestID = props.requestID || props.id || eventObj.id || "";
if (requestID !== "") {
// Parse full structured questions array from OpenCode
let questions = props.questions || [];
let qText = "";
let parsedQuestions = [];
let allowCustom = true;
if (questions.length > 0) {
// Structured question(s) with options
let parts = [];
for (let qi = 0; qi < questions.length; qi++) {
let qItem = questions[qi];
let header = qItem.header || "";
let questionText = qItem.question || "";
let opts = qItem.options || [];
let multiple = qItem.multiple || false;
let custom = qItem.custom !== undefined ? qItem.custom : true;
if (!custom)
allowCustom = false;
let partText = "";
if (header)
partText += "**" + header + "**: ";
partText += questionText;
if (opts.length > 0) {
let optLabels = [];
for (let oi = 0; oi < opts.length; oi++) optLabels.push(opts[oi].label || "")
partText += "\n\nOptions: " + optLabels.join(", ");
}
if (multiple)
partText += " *(select multiple)*";
parts.push(partText);
parsedQuestions.push({
"header": header,
"question": questionText,
"options": opts,
"multiple": multiple,
"custom": custom
});
}
qText = parts.join("\n\n---\n\n");
} else {
// Fallback: legacy format
let q = props.question || {
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
let alreadyExists = false;
for (let i = 0; i < root.messages.length; i++) {
if (root.messages[i].role === "question_request" && root.messages[i].questionId === requestID) {
alreadyExists = true;
break;
}
}
if (!alreadyExists) {
let msg = {
"role": "question_request",
"content": "OpenCode is asking a question:\n\n**" + qText + "**",
"model": "OpenCode Question",
"id": "question-" + requestID,
"questionId": requestID,
"questions": parsedQuestions,
"allowCustom": allowCustom,
"status": "pending",
"at": Date.now()
};
root.messages.push(msg);
root.messagesChanged();
saveCurrentSessionState(true);
if (!root.userScrolledUp)
queueScrollToBottom();
}
}
} else if (eventObj.type === "question.replied") {
let qId = props.requestID || props.id || eventObj.id || "";
let repliedMsgs = root.messages.slice();
let updated = false;
for (let i = repliedMsgs.length - 1; i >= 0; i--) {
if (repliedMsgs[i].role === "question_request" && repliedMsgs[i].questionId === qId) {
if (repliedMsgs[i].status === "pending" || repliedMsgs[i].status === "answering...") {
repliedMsgs[i].status = "answered";
updated = true;
}
break;
}
}
if (updated) {
root.messages = repliedMsgs;
saveCurrentSessionState(true);
}
} else if (eventObj.type === "question.rejected" || eventObj.type === "question.cancelled") {
let qId2 = props.requestID || props.id || eventObj.id || "";
let dismissedMsgs = root.messages.slice();
let updated = false;
for (let i = dismissedMsgs.length - 1; i >= 0; i--) {
if (dismissedMsgs[i].role === "question_request" && dismissedMsgs[i].questionId === qId2) {
if (dismissedMsgs[i].status === "pending" || dismissedMsgs[i].status === "dismissing...") {
dismissedMsgs[i].status = "dismissed";
updated = true;
}
break;
}
}
if (updated) {
root.messages = dismissedMsgs;
saveCurrentSessionState(true);
}
}
}


function appendSystemMessageToSession(chatId, text) {
let ts = Date.now();
let msgObj = {
"role": "assistant",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": "",
"queueId": 0,
"attachments": [],
"isSystem": true
};
appendMessageToSession(chatId, msgObj);
if (chatId === root.currentSessionId) {
if (!root.userScrolledUp)
queueScrollToBottom();
}
return ts;
}


function removeMessageFromSessionByTimestamp(chatId, timestamp) {
let idx = sessionIndexById(chatId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let s = Object.assign({}, updated[idx]);
let msgs = (s.messages || []).slice();
let originalLength = msgs.length;
msgs = msgs.filter(function(m) {
return m.at !== timestamp;
});
if (msgs.length === originalLength)
return ;
s.messages = msgs;
s.updatedAt = Date.now();
if (chatId === root.currentSessionId) {
root.messages = msgs;
if (root.expanded && !root.historyOnlyMode)
s.readCount = msgs.length;
}
updated[idx] = s;
root.sessions = updated;
persistSessions();
}


function scheduleMessageRemoval(chatId, timestamp, delayMs) {
// Coerce delayMs to a number, clamp to a sane range, then inject
// the numeric form into the QML source. Reject NaN, negative
// values, and values larger than one hour to avoid QML-injection
// via the interpolated string and to keep the timer bounded.
let interval = Number(delayMs);
if (!isFinite(interval) || interval < 0)
interval = 0;
if (interval > 3600000)
interval = 3600000;
let timerObj = Qt.createQmlObject("import QtQuick; Timer { interval: " + interval + "; repeat: false; running: true; }", root, "dynamicRemoveTimer");
timerObj.triggered.connect(function() {
removeMessageFromSessionByTimestamp(chatId, timestamp);
timerObj.destroy();
});
}


function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
let idx = sessionIndexById(chatId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let item = Object.assign({
}, updated[idx]);
item.openCodeSessionId = remoteSessionId || "";
updated[idx] = item;
root.sessions = updated;
persistSessions();
}


function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
let targetIdx = sessionIndexById(chatId);
if (targetIdx < 0) {
failureCallback("Session not found");
return ;
}
let existing = root.sessions[targetIdx].openCodeSessionId || "";
if (existing !== "") {
successCallback(existing);
return ;
}
let fail = function fail(msg) {
if (typeof failureCallback === "function")
failureCallback(msg);
else
pushErrorMessage(msg);
};
let xhr = new XMLHttpRequest();
xhr.open("POST", openCodeBaseUrl() + "/session", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.timeout = 10000;
xhr.ontimeout = function() {
fail("OpenCode: session creation timed out. Check that the server is running at " + openCodeBaseUrl());
};
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
triggerNotificationSound();
try {
let obj = JSON.parse(xhr.responseText);
let remoteId = obj.id || "";
if (remoteId === "") {
fail("OpenCode: server created a session without an id.");
return ;
}
setOpenCodeSessionIdForChatId(chatId, remoteId);
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
try {
let sTitle = root.sessions[targetIdx].title || "KDE AI Chat";
xhr.send(JSON.stringify({
"title": sTitle
}));
} catch (sendError) {
fail("OpenCode: failed to create session: " + sendError);
}
}


function scrollToBottom() {
if (root.msgListViewRef && !root.msgListViewRef.atYEnd)
    root.msgListViewRef.positionViewAtEnd();
}


function queueScrollToBottom() {
if (root.scrollToBottomQueued)
return ;
root.scrollToBottomQueued = true;
Qt.callLater(function() {
    root.scrollToBottomQueued = false;
    scrollToBottom();
});
}


function scrollToMessageByTimestamp(timestamp) {
if (!root.messages) return;
for (let i = 0; i < root.messages.length; i++) {
if (root.messages[i].at === timestamp) {
root.positionListViewAtIndex(i, ListView.Center);
if (root.msgListViewRef) {
let localIdx = root.toLocalMessageIndex(i);
if (localIdx < 0)
return;
root.msgListViewRef.currentIndex = localIdx;
}
break;
}
}
}


function messageTimestampAt(index) {
if (index < 0 || index >= root.messages.length)
return Date.now();
let m = root.messages[index] || {
};
return m.at || Date.now();
}


function messageDayKeyAt(index) {
let d = new Date(messageTimestampAt(index));
return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
}


function dayKeyForTimestamp(ts) {
let d = new Date(ts || Date.now());
return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
}


function ensureMessageMetadata(message) {
if (!message)
return;
let content = message.content || "";
if (message.searchTextSource !== content) {
message.searchText = content.toLowerCase();
message.searchTextSource = content;
}
let ts = message.at || Date.now();
let key = dayKeyForTimestamp(ts);
if (message.dayKey !== key) {
message.dayKey = key;
message.dayBucketLabel = dayBucketLabel(ts);
}
}


function updateMessageMetadata() {
    let msgs = root.messages || [];
    if (msgs.length === 0) return;
    // Fast path: if every message already has metadata, do nothing.
    // This is the common case after append-only changes (user types a
    // message, streaming response comes in token by token) where the
    // existing first-message check above is already cheap, but we still
    // walked the whole array and re-derived counts on every call.
    if (root._lastMetaIdx === msgs.length
        && msgs[0] && msgs[0].dayKey !== undefined && msgs[0].showDayHeader !== undefined
        && msgs[msgs.length - 1] && msgs[msgs.length - 1].dayDividerLabel !== undefined) {
        return;
    }
    let counts = {};
    for (let i = 0; i < msgs.length; i++) {
        let m = msgs[i];
        ensureMessageMetadata(m);
        if (!m) continue;
        counts[m.dayKey] = (counts[m.dayKey] || 0) + 1;
    }
    let previousKey = "";
    for (let j = 0; j < msgs.length; j++) {
        let msg = msgs[j];
        if (!msg) continue;
        msg.showDayHeader = j === 0 || msg.dayKey !== previousKey;
        msg.dayDividerLabel = (msg.dayBucketLabel || dayBucketLabel(msg.at || Date.now())) + " (" + (counts[msg.dayKey] || 0) + ")";
        previousKey = msg.dayKey;
    }
    root._lastMetaIdx = msgs.length;
}


function dayBucketLabel(ts) {
let target = new Date(ts);
let now = new Date();
let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
let targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate());
let daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 8.64e+07);
if (daysDiff === 0)
return "Today";
if (daysDiff === 1)
return "Yesterday";
if (daysDiff === 2)
return "Day before yesterday";
let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear();
}


function countMessagesForDayKey(dayKey) {
let count = 0;
for (let i = 0; i < root.messages.length; i++) {
if (messageDayKeyAt(i) === dayKey)
count++;
}
return count;
}


function dayDividerLabelForIndex(index) {
let msg = root.messages && index >= 0 && index < root.messages.length ? root.messages[index] : null;
if (msg && msg.dayDividerLabel)
return msg.dayDividerLabel;
let key = messageDayKeyAt(index);
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
let currentTop = -1;
for (let offset = 15; offset <= 100; offset += 20) {
currentTop = root.listViewIndexAt(30, root.msgListViewRef.contentY + offset);
if (currentTop >= 0)
break;
}
if (currentTop < 0)
currentTop = root.messages.length;
let target = -1;
for (let i = currentTop - 1; i >= 0; i--) {
let msg = root.messages[i];
if (msg && msg.role === "user") {
target = i;
break;
}
}
if (target >= 0) {
root.userScrolledUp = true;
root.positionListViewAtIndex(target, ListView.Beginning);
} else {
root.userScrolledUp = true;
root.msgListViewRef.positionViewAtBeginning();
}
}


function jumpOneMessageBelow() {
if (!root.msgListViewRef || root.messages.length === 0)
return ;
let currentTop = -1;
for (let offset = 15; offset <= 100; offset += 20) {
currentTop = root.listViewIndexAt(30, root.msgListViewRef.contentY + offset);
if (currentTop >= 0)
break;
}
if (currentTop < 0)
currentTop = -1;
let target = -1;
for (let i = currentTop + 1; i < root.messages.length; i++) {
let msg = root.messages[i];
if (msg && msg.role === "user") {
target = i;
break;
}
}
if (target >= 0) {
let isLastUser = true;
for (let j = target + 1; j < root.messages.length; j++) {
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
root.positionListViewAtIndex(target, ListView.Beginning);
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
let parts = [];
if (tokens.input !== undefined)
parts.push("Input: " + tokens.input);
if (tokens.output !== undefined)
parts.push("Output: " + tokens.output);
if (tokens.reasoning !== undefined && tokens.reasoning > 0)
parts.push("Reasoning: " + tokens.reasoning);
if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);
let res = parts.join(" | ");
if (cost !== undefined && cost > 0)
res += " | Cost: $" + cost.toFixed(5);
return res;
}


function pushInfoMessage(text) {
let ts = Date.now();
root.messages.push({
"role": "assistant",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": "OpenCode",
"isSystem": true
});
root.messagesChanged();
scrollToBottom();
saveCurrentSessionState(true);
}


function appendUserMessage(text, role, attachments, isScheduled) {
let ts = Date.now();
let msgObj = {
"role": role || "user",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": "",
"queueId": role === "queued" ? (++root.queueCounter) : 0,
"attachments": attachments || [],
"sc": !!isScheduled
};
if (root.quotedMessage && (role === "user" || role === "queued")) {
msgObj.quote = {
"role": root.quotedMessage.role,
"content": root.quotedMessage.content,
"model": root.quotedMessage.model || "",
"at": root.quotedMessage.at
};
root.quotedMessage = null;
}
// Defer model update to next frame — concat is instant, QML model processing
// takes 100-200ms which freezes the UI. By deferring, input clears instantly
// and message bubble appears on next frame (16ms — imperceptible).
let pendingMsg = msgObj;
let pendingIdx = root.messages.length;
Qt.callLater(function() {
    root.messages.push(pendingMsg);
    root.messagesChanged();
});
saveCurrentSessionState(true);

if ((role === "user" || role === "queued") && root.currentSessionTitle === "New Chat") {
    let cleanText = (text || "").trim();
    if (cleanText.length > 0) {
        let words = cleanText.split(/\s+/);
        let newTitle = words.slice(0, 5).join(" ");
        if (words.length > 5 || newTitle.length > 30) {
            if (newTitle.length > 30) {
                newTitle = newTitle.substring(0, 30);
            }
            newTitle += "...";
        }
        renameCurrentSession(newTitle);
    }
}
}


function appendSystemMessage(text) {
let ts = Date.now();
root.messages.push({
"role": "assistant",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": "",
"queueId": 0,
"attachments": [],
"isSystem": true
});
root.messagesChanged();
saveCurrentSessionState(true);
if (!root.userScrolledUp)
queueScrollToBottom();
}


function getSchedulesForSession(sessionId) {
let res = [];
for (let i = 0; i < root.schedulesList.length; i++) {
let s = root.schedulesList[i];
if (s && s.chatId === sessionId && !s.archived) {
let isExecuted = false;
if (s.taskType === "single") {
if ((s.lastRunAt && s.lastRunAt !== "") || (s.runCount && s.runCount > 0))
isExecuted = true;
} else {
if (s.limitEnabled && s.runCount >= s.limitCount)
isExecuted = true;
}
if (!isExecuted)
res.push(s);
}
}
return res;
}


function isImageProvider(providerId) {
    return providerId === "pollinations" || providerId === "huggingface-image" || providerId === "together-image" || providerId === "openai-image" || providerId === "google-image" || providerId === "stability-image" || providerId === "replicate-image";
}


function doImageGenerationRequest(text, providerId) {
    let config = plasmoid.configuration;
    if (providerId === "pollinations") {
        let encoded = encodeURIComponent(text);
        let model = config.pollinationsModel || "";
        let baseUrl = (config.pollinationsBaseUrl || "https://image.pollinations.ai").trim().replace(/\/+$/, "");
        let imageUrl = baseUrl + "/prompt/" + encoded + "?width=1024&height=1024&model=" + encodeURIComponent(model) + "&nologo=true";
        let xhr = new XMLHttpRequest();
        xhr.open("GET", imageUrl, true);
        xhr.responseType = "blob";
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                let contentType = xhr.getResponseHeader("Content-Type") || "";
                if (contentType.indexOf("image") >= 0) {
                    let assistantMsg = {
                        "role": "assistant",
                        "content": "",
                        "isImage": true,
                        "imageUrl": imageUrl,
                        "imageProvider": providerId,
                        "time": nowTime(Date.now()),
                        "at": Date.now()
                    };
                    appendMessageToSession(root.currentSessionId, assistantMsg);
                    root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                } else {
                    let body = "";
                    try { body = xhr.responseText || ""; } catch(e) {}
                    pushErrorMessage("Pollinations returned non-image response (status " + xhr.status + "): " + body.substring(0, 200));
                }
            } else {
                let body = "";
                try { body = xhr.responseText || ""; } catch(e) {}
                pushErrorMessage("Pollinations image error: HTTP " + xhr.status + " " + body.substring(0, 200));
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during Pollinations image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send();
        return;
    }
    if (providerId === "together-image") {
        let apiKey = config.togetherImageApiKey || "";
        let model = config.togetherImageModel || "";
        let baseUrl = (config.togetherImageBaseUrl || "https://api.together.xyz/v1").replace(/\/$/, "");
        let url = baseUrl + "/images/generations";
        let xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let imgUrl = (resp.data && resp.data[0] && resp.data[0].url) || "";
                    if (imgUrl) {
                        let msg = {
                            "role": "assistant",
                            "content": "",
                            "isImage": true,
                            "imageUrl": imgUrl,
                            "imageProvider": providerId,
                            "time": nowTime(Date.now()),
                            "at": Date.now()
                        };
                        appendMessageToSession(root.currentSessionId, msg);
                        root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                    } else {
                        pushErrorMessage("No image URL in Together AI response.");
                    }
                } catch (e) {
                    pushErrorMessage("Failed to parse Together AI response: " + e);
                }
            } else {
                pushErrorMessage("Together AI image error: HTTP " + xhr.status + " " + (xhr.responseText || "").substring(0, 200));
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "model": model,
            "prompt": text,
            "n": 1,
            "steps": 4,
            "width": 1024,
            "height": 1024
        }));
        return;
    }
    if (providerId === "huggingface-image") {
        let apiKey = config.huggingfaceImageApiKey || "";
        let model = config.huggingfaceImageModel || "";
        let baseUrl = (config.huggingfaceImageBaseUrl || "https://api-inference.huggingface.co").replace(/\/$/, "");
        let url = baseUrl + "/models/" + model;
        let xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.responseType = "arraybuffer";
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let b64 = btoa(String.fromCharCode.apply(null, new Uint8Array(xhr.response || [])));
                    let dataUrl = "data:image/png;base64," + b64;
                    let msg = {
                        "role": "assistant",
                        "content": "",
                        "isImage": true,
                        "imageUrl": dataUrl,
                        "imageProvider": providerId,
                        "time": nowTime(Date.now()),
                        "at": Date.now()
                    };
                    appendMessageToSession(root.currentSessionId, msg);
                    root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                } catch (e) {
                    pushErrorMessage("Failed to process HuggingFace image response.");
                }
            } else {
                pushErrorMessage("HuggingFace image error: HTTP " + xhr.status);
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during HuggingFace image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "inputs": text
        }));
        return;
    }
    if (providerId === "openai-image") {
        let apiKey = config.apiKey || "";
        let model = config.openaiImageModel || "";
        let baseUrl = (config.baseUrl || "https://api.openai.com/v1").replace(/\/$/, "");
        let url = baseUrl + "/images/generations";
        let xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let imgUrl = (resp.data && resp.data[0] && resp.data[0].url) || "";
                    if (imgUrl) {
                        let msg = {
                            "role": "assistant",
                            "content": "",
                            "isImage": true,
                            "imageUrl": imgUrl,
                            "imageProvider": providerId,
                            "time": nowTime(Date.now()),
                            "at": Date.now()
                        };
                        appendMessageToSession(root.currentSessionId, msg);
                        root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                    } else {
                        pushErrorMessage("No image URL in OpenAI response.");
                    }
                } catch (e) {
                    pushErrorMessage("Failed to parse OpenAI image response: " + e);
                }
            } else {
                pushErrorMessage("OpenAI image error: HTTP " + xhr.status + " " + (xhr.responseText || "").substring(0, 200));
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during OpenAI image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "model": model,
            "prompt": text,
            "n": 1,
            "size": "1024x1024"
        }));
        return;
    }
    if (providerId === "google-image") {
        let apiKey = config.googleApiKey || "";
        let model = config.googleImageModel || "";
        let baseUrl = (config.googleImageBaseUrl || "https://generativelanguage.googleapis.com/v1beta").replace(/\/$/, "");
        let url = baseUrl + "/models/" + model + ":predict";
        let xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let predictions = resp.predictions || [];
                    if (predictions.length > 0 && predictions[0].bytesBase64Encoded) {
                        let b64 = predictions[0].bytesBase64Encoded;
                        let mime = predictions[0].mimeType || "image/png";
                        let dataUrl = "data:" + mime + ";base64," + b64;
                        let msg = {
                            "role": "assistant",
                            "content": "",
                            "isImage": true,
                            "imageUrl": dataUrl,
                            "imageProvider": providerId,
                            "time": nowTime(Date.now()),
                            "at": Date.now()
                        };
                        appendMessageToSession(root.currentSessionId, msg);
                        root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                    } else {
                        pushErrorMessage("No image data in Google Imagen response.");
                    }
                } catch (e) {
                    pushErrorMessage("Failed to parse Google Imagen response: " + e);
                }
            } else {
                pushErrorMessage("Google Imagen error: HTTP " + xhr.status + " " + (xhr.responseText || "").substring(0, 200));
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during Google Imagen generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "instances": [{"prompt": text}],
            "parameters": {"sampleCount": 1}
        }));
        return;
    }
    if (providerId === "stability-image") {
        let apiKey = config.stabilityApiKey || "";
        let model = config.stabilityImageModel || "";
        let baseUrl = (config.stabilityImageBaseUrl || "https://api.stability.ai").replace(/\/$/, "");
        let url = baseUrl + "/v1/generation/" + model + "/text-to-image";
        let xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let artifacts = resp.artifacts || [];
                    if (artifacts.length > 0 && artifacts[0].base64) {
                        let b64 = artifacts[0].base64;
                        let dataUrl = "data:image/png;base64," + b64;
                        let msg = {
                            "role": "assistant",
                            "content": "",
                            "isImage": true,
                            "imageUrl": dataUrl,
                            "imageProvider": providerId,
                            "time": nowTime(Date.now()),
                            "at": Date.now()
                        };
                        appendMessageToSession(root.currentSessionId, msg);
                        root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                    } else {
                        pushErrorMessage("No image data in Stability AI response.");
                    }
                } catch (e) {
                    pushErrorMessage("Failed to parse Stability AI response: " + e);
                }
            } else {
                pushErrorMessage("Stability AI image error: HTTP " + xhr.status + " " + (xhr.responseText || "").substring(0, 200));
            }
            saveCurrentSessionState(true);
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during Stability AI image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "text_prompts": [{"text": text}],
            "cfg_scale": 7,
            "height": 1024,
            "width": 1024,
            "samples": 1
        }));
        return;
    }
    if (providerId === "replicate-image") {
        let apiKey = config.replicateApiKey || "";
        let model = config.replicateImageModel || "";
        let baseUrl = (config.replicateImageBaseUrl || "https://api.replicate.com").replace(/\/$/, "");
        let createUrl = baseUrl + "/v1/models/" + model + "/predictions";
        let xhr = new XMLHttpRequest();
        xhr.open("POST", createUrl, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let predId = resp.id;
                    if (predId) {
                        pollReplicatePrediction(apiKey, baseUrl, predId, providerId);
                    } else {
                        root.loading = false;
                        pushErrorMessage("No prediction ID in Replicate response.");
                        saveCurrentSessionState(true);
                    }
                } catch (e) {
                    root.loading = false;
                    pushErrorMessage("Failed to parse Replicate response: " + e);
                    saveCurrentSessionState(true);
                }
            } else {
                root.loading = false;
                pushErrorMessage("Replicate image error: HTTP " + xhr.status + " " + (xhr.responseText || "").substring(0, 200));
                saveCurrentSessionState(true);
            }
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during Replicate image generation.");
            saveCurrentSessionState(true);
        };
        xhr.send(JSON.stringify({
            "input": {"prompt": text}
        }));
        return;
    }
    pushErrorMessage("Image generation not supported for this provider.");
    root.loading = false;
}

function pollReplicatePrediction(apiKey, baseUrl, predId, providerId) {
    let pollUrl = baseUrl + "/v1/predictions/" + predId;
    let attempts = 0;
    let maxAttempts = 60;
    let pollInterval = 2000;
    function poll() {
        attempts++;
        if (attempts > maxAttempts) {
            root.loading = false;
            pushErrorMessage("Replicate prediction timed out after " + (maxAttempts * pollInterval / 1000) + " seconds.");
            saveCurrentSessionState(true);
            return;
        }
        let xhr = new XMLHttpRequest();
        xhr.open("GET", pollUrl, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (apiKey)
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let status = resp.status;
                    if (status === "succeeded") {
                        let output = resp.output;
                        let imgUrl = "";
                        if (Array.isArray(output) && output.length > 0) {
                            imgUrl = output[0];
                        } else if (typeof output === "string") {
                            imgUrl = output;
                        }
                        if (imgUrl) {
                            let msg = {
                                "role": "assistant",
                                "content": "",
                                "isImage": true,
                                "imageUrl": imgUrl,
                                "imageProvider": providerId,
                                "time": nowTime(Date.now()),
                                "at": Date.now()
                            };
                            appendMessageToSession(root.currentSessionId, msg);
                            root.messages = root.sessions[root.sessionIndexById(root.currentSessionId)].messages;
                            root.loading = false;
                            saveCurrentSessionState(true);
                        } else {
                            root.loading = false;
                            pushErrorMessage("No image URL in Replicate output.");
                            saveCurrentSessionState(true);
                        }
                    } else if (status === "failed" || status === "canceled") {
                        root.loading = false;
                        pushErrorMessage("Replicate prediction failed: " + (resp.error || "Unknown error"));
                        saveCurrentSessionState(true);
                    } else {
                        setTimeout(poll, pollInterval);
                    }
                } catch (e) {
                    root.loading = false;
                    pushErrorMessage("Failed to parse Replicate poll response: " + e);
                    saveCurrentSessionState(true);
                }
            } else {
                root.loading = false;
                pushErrorMessage("Replicate poll error: HTTP " + xhr.status);
                saveCurrentSessionState(true);
            }
        };
        xhr.onerror = function() {
            root.loading = false;
            pushErrorMessage("Network error during Replicate poll.");
            saveCurrentSessionState(true);
        };
        xhr.send();
    }
    poll();
}


function sendMessageByIndex(index) {
resetOpenCodeIdleKillTimer();
let source = root.messages[index] || {
};
let text = (source.content || "").trim();
let hasAttachments = source.attachments && source.attachments.length > 0;
if (!text && !hasAttachments)
return ;
if (!root.openCodeMode && !root.piMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
root.loading = true;
loadKWalletKeysIfNeeded(
function onSuccess() {
root.loading = false;
sendMessageByIndex(index);
},
function onFailure(err) {
root.loading = false;
pushErrorMessage(root.translate("KWallet access failed: ") + err + ". " + root.translate("Please check settings or unlock your wallet."));
}
);
return ;
}
let validationError = validateCurrentSendTarget();
if (validationError !== "") {
pushErrorMessage(validationError);
return ;
}
if ((source.role || "") === "queued") {
let copy = root.messages.slice();
let queued = Object.assign({
}, copy[index]);
queued.role = "user";
queued.at = Date.now();
queued.time = nowTime(queued.at);
copy[index] = queued;
root.messages = copy;
saveCurrentSessionState(true);
}
setCurrentSessionSource(root.piMode ? "pi" : (root.openCodeMode ? "opencode" : "provider"));
if (root.piMode) {
if (text.startsWith("/")) {
runLocalPiCommand(text);
return ;
}
doPiRequest();
return ;
}
if (root.openCodeMode) {
if (text.startsWith("/")) {
runLocalOpenCodeCommand(text);
return ;
}
doOpenCodeRequest();
return ;
}
let effectiveProv = getEffectiveProvider(root.currentSessionId);
if (isImageProvider(effectiveProv)) {
    doImageGenerationRequest(text, effectiveProv);
    return ;
}
let providerCfg = getProviderConfig(effectiveProv, root.currentSessionId);
if (providerCfg.type === "anthropic")
doAnthropicRequest(providerCfg.apiKey, providerCfg.model);
else
doOpenAICompatRequest(providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model);
}


function processNextQueuedMessage() {
if (root.loading)
return ;
for (let i = 0; i < root.messages.length; i++) {
if ((root.messages[i].role || "") === "queued") {
sendMessageByIndex(i);
return ;
}
}
}


function providerDisplayName(providerId) {
return ProviderService.getProviderDisplayName(providerId);
}


function validateOpenCodeConfig() {
let missing = [];
if (!(plasmoid.configuration.openCodeUrl || "").trim())
missing.push("OpenCode URL");
if (!(plasmoid.configuration.openCodeProvider || "").trim())
missing.push("OpenCode provider");
if (!(plasmoid.configuration.openCodeModel || "").trim())
missing.push("OpenCode model");
if (missing.length > 0)
return "Cannot send yet. Configure: " + missing.join(", ") + ".";
return "";
}


function validateProviderConfig(providerId, cfg) {
if (!cfg)
return "Provider configuration missing.";
let missing = [];
let name = providerDisplayName(providerId);
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
return "Cannot send with " + name + ". Missing: " + missing.join(", ") + ".";
if (cfg.baseUrl && cfg.type !== "anthropic") {
let urlTrimmed = cfg.baseUrl.trim();
if (!urlTrimmed.startsWith("http://") && !urlTrimmed.startsWith("https://")) {
return "Invalid URL in " + name + ": URL must start with http:// or https://";
}
}
if (cfg.apiKey) {
let trimmedKey = cfg.apiKey.trim();
if (providerId === "openai" && !trimmedKey.startsWith("sk-")) {
return "Invalid OpenAI API key format: keys should start with 'sk-'";
}
if (providerId === "anthropic" && !trimmedKey.startsWith("sk-ant-")) {
return "Invalid Anthropic API key format: keys should start with 'sk-ant-'";
}
}
return "";
}


function sendMessage() {
try {
let text = (root.chatInputText || "").trim();
let attachments = root.attachedFiles || [];
if (text === "" && attachments.length === 0)
return ;
let maxLen = 100000;
if (text.length > maxLen) {
pushErrorMessage("Message is too long (maximum " + maxLen + " characters).");
return ;
}
// ── /schedule command ──────────────────────────────────────────
let lowerText = text.toLowerCase().replace(/^\//, "").trim();
if (lowerText === "schedule" || lowerText === "schedules" || lowerText === "scheduler" || text.toLowerCase().startsWith("/schedule")) {
let schedText = "";
if (text.toLowerCase().startsWith("/schedule"))
schedText = text.slice("/schedule".length).trim();
else if (text.toLowerCase().startsWith("schedule"))
schedText = text.slice("schedule".length).trim();
else if (text.toLowerCase().startsWith("schedules"))
schedText = text.slice("schedules".length).trim();
else if (text.toLowerCase().startsWith("scheduler"))
schedText = text.slice("scheduler".length).trim();
root.attachedFiles = [];
root.chatInputText = "";
root.clearChatInput();
// 1. Append the user message
appendUserMessage(text, "user", []);
if (schedText !== "") {
// Open dialog prefilled with message
root.handleScheduleCommand(schedText);
} else {
// Trigger a poll now so that the list is fresh when the bubble is rendered!
schedulerPollTimer.triggered();
// Append interactive list inline!
let ts = Date.now();
root.messages.push({
"role": "schedules_list",
"content": "Interactive Schedules Manager",
"time": nowTime(ts),
"at": ts,
"model": "",
"queueId": 0,
"attachments": []
});
root.messagesChanged();
saveCurrentSessionState(true);
if (!root.userScrolledUp)
queueScrollToBottom();
}
return;
}
// ── Template command ──────────────────────────────────────────
if (text.startsWith("/")) {
let cmd = text.substring(1).trim();
let templatesRaw = plasmoid.configuration.promptTemplates || "[]";
try {
let templates = JSON.parse(templatesRaw);
for (let t of templates) {
if (t.name && t.name.toLowerCase() === cmd.toLowerCase()) {
let prompt = t.prompt || "";
root.chatInputText = prompt;
if (root.msgInputRef)
    root.msgInputRef.text = prompt;
root.autocompleteActive = false;
return;
}
}
} catch(e) {}
}
root.attachedFiles = [];
root.chatInputText = "";
root.clearChatInput();
root.userScrolledUp = false;
if (root.loading) {
let queueCount = 0;
for (let idx = 0; idx < root.messages.length; idx++) {
if ((root.messages[idx].role || "") === "queued") {
queueCount++;
}
}
if (queueCount >= 5) {
pushErrorMessage("Too many messages in queue (maximum 5). Please wait for the current request to finish.");
return ;
}
appendUserMessage(text, "queued", attachments);
return ;
}
appendUserMessage(text, "user", attachments);
// Index is current length since appendUserMessage defers the concat
let _msgIdx = root.messages.length;
// One Qt event-loop tick is enough to let the UI paint the cleared input
// before we start the network request — no artificial 50ms delay needed.
Qt.callLater(function() { sendMessageByIndex(_msgIdx); });
} catch (err) {
root.loading = false;
root.activeXhr = null;
pushErrorMessage("Send failed: " + err);
processNextQueuedMessage();
}
}


function getEffectiveProvider(sessionId) {
let sId = sessionId || root.currentSessionId;
let chatProv = getSessionProperty(sId, "chatProvider", "").trim();
if (chatProv !== "") {
return chatProv;
}
return plasmoid.configuration.provider || "openai";
}

function getEffectiveModel(sessionId) {
let sId = sessionId || root.currentSessionId;
let chatMod = getSessionProperty(sId, "chatModel", "").trim();
if (chatMod !== "") {
return chatMod;
}
let prov = getEffectiveProvider(sId);
let cfg = ProviderService.getProviderConfig(prov, plasmoid.configuration);
return cfg.model || "";
}

function getProviderConfig(provider, sessionId) {
let sId = sessionId || root.currentSessionId;
let effProvider = provider || getEffectiveProvider(sId);
let cfg = ProviderService.getProviderConfig(effProvider, plasmoid.configuration);
let sessionModel = getSessionProperty(sId, "chatModel", "").trim();
if (sessionModel !== "")
cfg.model = sessionModel;
return cfg;
}


function translate(text) {
return Translations.translate(text, plasmoid.configuration.language);
}


function isSessionScheduled(sessionId, messagesList) {
let msgs = messagesList;
if (!msgs) {
let idx = sessionIndexById(sessionId || root.currentSessionId);
if (idx >= 0)
msgs = root.sessions[idx].messages || [];
}
if (!msgs || msgs.length === 0)
return false;
// Search from the end for the last user message
for (let i = msgs.length - 1; i >= 0; i--) {
let m = msgs[i];
if (m.role === "user" && !m.isSystem) {
return !!m.sc;
}
}
return false;
}


function injectMemoriesToUserMessage(contentVal, sessionId) {
    let sId = sessionId || root.currentSessionId;
    let chatMemoryEnabled = getSessionProperty(sId, "chatMemoryEnabled", true);
    if (!chatMemoryEnabled) return contentVal;

    let memoryOn = plasmoid.configuration.memoryEnabled || false;
    let memoryTxt = memoryOn ? (plasmoid.configuration.userMemory || "").trim() : "";
    let chatMemoryTxt = getSessionProperty(sId, "chatMemory", "").trim();
    let parts = [];
    if (memoryTxt !== "") {
        parts.push("--- Global Memory ---\n" + memoryTxt + "\n--- End of Global Memory ---");
    }
    if (chatMemoryTxt !== "") {
        parts.push("--- Chat Memory ---\n" + chatMemoryTxt + "\n--- End of Chat Memory ---");
    }
    if (parts.length > 0) {
        contentVal = contentVal + "\n\n[System Instruction: The following are memories. They may or maynot be useful to you.\n" + parts.join("\n\n") + "]";
    }
    return contentVal;
}


function buildEffectiveSystemPrompt(sessionId) {
let sId = sessionId || root.currentSessionId;
let chatSystemPromptEnabled = getSessionProperty(sId, "chatSystemPromptEnabled", true);
if (!chatSystemPromptEnabled) return "";

let globalPrompt = plasmoid.configuration.enableSystemPrompt !== false ? (plasmoid.configuration.systemPrompt || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.") : "";
let chatPrompt = getSessionProperty(sId, "chatSystemPrompt", "").trim();
let base = globalPrompt;
if (chatPrompt !== "") {
    if (base !== "") base += "\n\n";
    base += "--- Chat-specific instructions ---\n" + chatPrompt + "\n--- End chat-specific instructions ---";
}
let responseLength = getSessionProperty(sId, "responseLength", plasmoid.configuration.responseLength || 0);
let responseLengthInstructions = [
"",
"Keep the response short and focused, around 256 output tokens unless the task requires more.",
"Give a balanced response, around 1024 output tokens at most.",
"Give a detailed response, around 4096 output tokens at most.",
"Give a comprehensive response, up to roughly 8192 output tokens when useful."
];
if (responseLength > 0 && responseLength < responseLengthInstructions.length)
base += "\n\nResponse length preference: " + responseLengthInstructions[responseLength];

if (!isSessionScheduled(sId)) {
let summary = getSessionProperty(sId, "compactedSummary", "");
if (summary !== "")
base = base + "\n\n--- Summary of Previous Conversation ---\n" + summary + "\n--- End of Summary ---";
}
return base;
}



function buildContextWindow(messagesList, sessionId) {
let sId = sessionId || root.currentSessionId;
let override = getSessionProperty(sId, "contextOverride", false);
let contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : (plasmoid.configuration.globalContextEnabled !== false);
let limit = override ? getSessionProperty(sId, "contextLimit", 1) : (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1);
let isSched = isSessionScheduled(sId, messagesList);
let compactedCount = isSched ? 0 : getSessionProperty(sId, "compactedMessageCount", 0);
let clean = [];
for (let i = 0; i < messagesList.length; i++) {
let m = messagesList[i];
// Skip messages before the compacted boundary
if (i < compactedCount)
continue;
// Only real conversation turns
if (m.role !== "user" && m.role !== "assistant")
continue;
// Exclude system-status assistant bubbles (info/error injected by the widget)
if (m.isSystem)
continue;
clean.push({
"idx": i,
"msg": m
});
}
if (!contextEnabled) {
// No context: only keep the very last user message
for (let k = clean.length - 1; k >= 0; k--) {
if (clean[k].msg.role === "user")
return [clean[k].msg];
}
return [];
}
// Apply limit (take the last `limit` items)
if (clean.length > limit)
clean = clean.slice(clean.length - limit);
return clean.map(function(e) {
return e.msg;
});
}


function buildOpenAICompatPayload() {
let sys = buildEffectiveSystemPrompt();
let arr = [{
"role": "system",
"content": sys
}];
return arr.concat(_buildMessageArray(root.messages, "", "openai"));
}


function buildAnthropicPayload() {
return _buildMessageArray(root.messages, "", "anthropic");
}


function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
let sys = buildEffectiveSystemPrompt(chatId);
let arr = [{
"role": "system",
"content": sys
}];
return arr.concat(_buildMessageArray(messagesList, chatId, "openai"));
}


function _buildMessageArray(messagesList, chatId, format) {
let arr = [];
let window = buildContextWindow(messagesList, chatId);
let lastUserIdx = -1;
for (let i = window.length - 1; i >= 0; i--) {
    if (window[i].role === "user") {
        lastUserIdx = i;
        break;
    }
}
for (let i = 0; i < window.length; i++) {
let m = window[i];
let contentVal = m.content;
if (m.quote) {
let sender = m.quote.role === "assistant" ? (m.quote.model || "Assistant") : "User";
contentVal = "[Replying to @" + sender + ": \"" + m.quote.content + "\"]\n\n" + contentVal;
}
if (i === lastUserIdx) {
    contentVal = injectMemoriesToUserMessage(contentVal, chatId);
}
if (m.role === "user" && m.attachments && m.attachments.length > 0)
arr.push({
"role": m.role,
"content": buildMessageContent(contentVal, m.attachments, format)
});
else
arr.push({
"role": m.role,
"content": contentVal
});
}
return arr;
}


function appendMessageToSession(chatId, msgObj) {
let idx = sessionIndexById(chatId);
if (idx < 0)
return ;
ensureMessageMetadata(msgObj);
// Pre-compute blocks and HTML so MessageContent.qml renders instantly without jitter.
precomputeBlocksAndHtmlForMessage(msgObj);
let updated = root.sessions.slice();
let s = Object.assign({
}, updated[idx]);
let msgs = (s.messages || []).slice();
msgs.push(msgObj);
s.messages = msgs;
s.updatedAt = Date.now();
if (chatId === root.currentSessionId) {
root.messages = msgs;
if (root.expanded && !root.historyOnlyMode)
s.readCount = msgs.length;
}
updated[idx] = s;
root.sessions = updated;
sortSessionsByUpdated();
persistSessions();
}


function triggerNotificationSound() {
if (!plasmoid.configuration.playNotificationSound)
return ;
soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
}


function respondToPermission(permissionId, approved) {
let sessionId = root.openCodeActiveSessionId;
if (!sessionId) {
let idx = sessionIndexById(root.currentSessionId);
if (idx >= 0)
sessionId = root.sessions[idx].openCodeSessionId || "";
}
if (!sessionId || !permissionId)
return ;

let copy = root.messages.slice();
for (let i = 0; i < copy.length; i++) {
if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
copy[i].status = approved ? "allowing..." : "denying...";
break;
}
}
root.messages = copy;

let xhr = new XMLHttpRequest();
let primaryUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permission/" + permissionId;
let fallbackUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permissions/" + permissionId;
let responseValue = approved ? "allow" : "deny";

function sendToUrl(url, isRetry) {
xhr.open("POST", url, true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
let updatedMsgs = root.messages.slice();
for (let i = 0; i < updatedMsgs.length; i++) {
if (updatedMsgs[i].role === "permission_request" && updatedMsgs[i].permissionId === permissionId) {
updatedMsgs[i].status = approved ? "allowed" : "denied";
break;
}
}
root.messages = updatedMsgs;
saveCurrentSessionState(true);
} else if (xhr.status === 404 && !isRetry) {
sendToUrl(fallbackUrl, true);
} else {
let errorMsgs = root.messages.slice();
for (let i = 0; i < errorMsgs.length; i++) {
if (errorMsgs[i].role === "permission_request" && errorMsgs[i].permissionId === permissionId) {
errorMsgs[i].status = "pending";
break;
}
}
root.messages = errorMsgs;
pushErrorMessage("OpenCode: failed to reply to permission (HTTP " + xhr.status + ").");
}
};
xhr.onerror = function() {
if (!isRetry) {
sendToUrl(fallbackUrl, true);
} else {
let networkMsgs = root.messages.slice();
for (let i = 0; i < networkMsgs.length; i++) {
if (networkMsgs[i].role === "permission_request" && networkMsgs[i].permissionId === permissionId) {
networkMsgs[i].status = "pending";
break;
}
}
root.messages = networkMsgs;
pushErrorMessage("OpenCode: could not reach permission reply server endpoint.");
}
};
xhr.send(JSON.stringify({
"response": responseValue
}));
}

sendToUrl(primaryUrl, false);
}


function submitQuestionAnswer(questionId, questions, customField) {
// Find the question_request message to access its question data
let msgIdx = -1;
for (let i = 0; i < root.messages.length; i++) {
if (root.messages[i].role === "question_request" && root.messages[i].questionId === questionId) {
msgIdx = i;
break;
}
}
if (msgIdx < 0)
return ;
let customText = customField ? (customField.text || "").trim() : "";
// If no structured questions, fallback to custom text only
if (!questions || questions.length === 0) {
if (customText !== "")
respondToQuestion(questionId, customText, false);
return ;
}
// For structured questions, the answer format is array of arrays.
// However since we can't easily traverse QML Repeater children
// to read selected state, we use a simpler approach:
// If user typed custom text, use that as the answer.
// Otherwise this function is called from the Submit button
// and we handle it via the text field.
if (customText !== "") {
respondToQuestion(questionId, customText, false);
} else {
}
}


function respondToQuestion(questionId, answerValue, isReject) {
let sessionId = root.openCodeActiveSessionId;
if (!sessionId) {
let idx = sessionIndexById(root.currentSessionId);
if (idx >= 0)
sessionId = root.sessions[idx].openCodeSessionId || "";
}
if (!questionId)
return ;
let copy = root.messages.slice();
for (let i = 0; i < copy.length; i++) {
if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
copy[i].status = isReject ? "dismissing..." : "answering...";
break;
}
}
root.messages = copy;

let xhr = new XMLHttpRequest();
let action = isReject ? "reject" : "reply";
let urls = [openCodeBaseUrl() + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/questions/" + questionId + "/" + action];
let currentUrlIdx = 0;

function tryNextUrl() {
if (currentUrlIdx >= urls.length) {
let exhaustedMsgs = root.messages.slice();
for (let i = 0; i < exhaustedMsgs.length; i++) {
if (exhaustedMsgs[i].role === "question_request" && exhaustedMsgs[i].questionId === questionId) {
exhaustedMsgs[i].status = "pending";
break;
}
}
root.messages = exhaustedMsgs;
pushErrorMessage("OpenCode: failed to reply to question endpoint.");
return ;
}
let url = urls[currentUrlIdx];
currentUrlIdx++;
xhr.open("POST", url, true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
let updatedMsgs = root.messages.slice();
for (let i = 0; i < updatedMsgs.length; i++) {
if (updatedMsgs[i].role === "question_request" && updatedMsgs[i].questionId === questionId) {
updatedMsgs[i].status = isReject ? "dismissed" : "answered";
updatedMsgs[i].submittedAnswer = answerValue;
break;
}
}
root.messages = updatedMsgs;
saveCurrentSessionState(true);
} else if (xhr.status === 404) {
tryNextUrl();
} else {
let errorMsgs = root.messages.slice();
for (let i = 0; i < errorMsgs.length; i++) {
if (errorMsgs[i].role === "question_request" && errorMsgs[i].questionId === questionId) {
errorMsgs[i].status = "pending";
break;
}
}
root.messages = errorMsgs;
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
let answers = [];
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

tryNextUrl();
}


function stopStreaming() {
if (root.activeXhr) {
try {
root.activeXhr.abort();
} catch (e) {
}
root.activeXhr = null;
}
root.loading = false;
flushStreamingBuffer();
saveCurrentSessionState(true);
processNextQueuedMessage();
}


function convertMarkdownToHtml(markdown) {
if (!markdown)
return "";
let cacheKey = markdown + "_" + (root.themeTextColor ? root.themeTextColor.toString() : "x");
let cached = root._markdownCache.get(cacheKey);
if (cached !== undefined) {
return cached;
}
try {
let html = MarkdownRenderer.convertMarkdownToHtml(markdown, root.popupIsDark);
root._markdownCache.put(cacheKey, html);
return html;
} catch (e) {
console.error("convertMarkdownToHtml failed: " + e);
return String(markdown).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br/>");
}
}


function fileIconName(filename) {
let ext = filename.split('.').pop().toLowerCase();
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


function removeAttachedFile(index) {
let files = root.attachedFiles.slice();
if (index >= 0 && index < files.length) {
files.splice(index, 1);
root.attachedFiles = files;
}
}


function getDocExtractorPath() {
// Resolve the doc-extractor path and refuse anything outside the
// package's `contents/ui/` directory. See `getHelperPath()` for
// the rationale.
let urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
if (urlStr.indexOf("file://") === 0)
urlStr = urlStr.substring(7);
let path = decodeURIComponent(urlStr);
if (path.indexOf("/contents/ui/") === -1)
return "";
return path;
}


function getHelperPath() {
// Resolve the helper path relative to this QML file's package.
// We reject any path that does not point inside the package's
// `contents/ui/` directory — this prevents a compromised
// Qt.resolvedUrl override (e.g. via a symlinked install or
// custom `KDEDIRS` path) from steering the widget at an
// attacker-controlled script.
let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
if (urlStr.indexOf("file://") === 0)
urlStr = urlStr.substring(7);
let path = decodeURIComponent(urlStr);
// The helper must live inside the package's `contents/ui`
// directory. Anything outside (e.g. /tmp, $HOME) is rejected
// and the caller falls back to an empty string so the IPC
// command becomes a no-op instead of executing an arbitrary
// script.
if (path.indexOf("/contents/ui/") === -1)
return "";
return path;
}


function getScriptsPath() {
let helper = getHelperPath();
let parts = helper.split("/");
if (parts.length >= 2) {
parts.splice(parts.length - 2, 2);
return parts.join("/") + "/scripts";
}
return "";
}


function attachFile(fileUrl) {
let localPath = String(fileUrl);
if (localPath.indexOf("file://") === 0)
localPath = localPath.substring(7);
localPath = decodeURIComponent(localPath);
let files = root.attachedFiles.slice();
for (let i = 0; i < files.length; i++) {
if (files[i].path === localPath)
return ;
}
let filename = localPath.substring(localPath.lastIndexOf("/") + 1);
let newFile = {
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
let docExtractorPath = getDocExtractorPath();
let safePath = Sec.validateFilePath(localPath);
if (safePath === "") {
// Refuse to call the helper with an unsafe or non-existent path
console.warn("attachFile: rejected unsafe path");
return;
}
let cmd = "python3 " + Sec.quoteForShell(docExtractorPath) + " " + Sec.quoteForShell(safePath);
fileReaderDs.connectSource(cmd);
}


function parseMessageBlocks(markdown) {
if (!markdown)
return [{
"type": "text",
"content": "",
"lang": ""
}];
let cachedBlocks = root._blocksCache.get(markdown);
if (cachedBlocks !== undefined) {
return cachedBlocks;
}
try {
let blocks = MarkdownRenderer.parseMessageBlocks(markdown);
root._blocksCache.put(markdown, blocks);
return blocks;
} catch (e) {
console.error("parseMessageBlocks failed: " + e);
return [{
"type": "text",
"content": markdown,
"lang": ""
}];
}
}


function tableMarkdownToCsv(tableMarkdown) {
return MarkdownRenderer.tableMarkdownToCsv(tableMarkdown);
}


function buildMessageContent(text, attachments, apiType) {
let docs = [];
let imgs = [];
for (let i = 0; i < attachments.length; i++) {
let att = attachments[i];
if (att.type === "image")
imgs.push(att);
else if (att.type === "text")
docs.push(att);
}
let compiledPrompt = "";
for (let d = 0; d < docs.length; d++) {
compiledPrompt += "[Attached File: " + docs[d].name + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
compiledPrompt += "--- START OF FILE CONTENT ---\n";
compiledPrompt += (docs[d].content || "") + "\n";
compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
}
compiledPrompt += text;
if (imgs.length === 0)
return compiledPrompt;
let contentList = [];
if (compiledPrompt.trim() !== "")
contentList.push({
"type": "text",
"text": compiledPrompt
});
for (let imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
let image = imgs[imgIdx];
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
let docExtractorPath = getDocExtractorPath();
let cmd = "python3 " + Sec.quoteForShell(docExtractorPath) + " --clipboard";
fileReaderDs.connectSource(cmd);
}


function readClipboardText() {
clipboardHelper.text = "";
clipboardHelper.paste();
return clipboardHelper.text;
}


function walletBulkReadCommand(walletName) {
return WalletService.buildBulkReadCommand(walletName, ProviderService.getApiKeyProviderIds());
}


function performExportChat(filePath) {
let isMarkdown = filePath.toLowerCase().endsWith(".md") || filePath.toLowerCase().endsWith(".markdown");
let content = "";
let sessionTitle = root.currentSessionTitle || "Untitled Session";
if (isMarkdown) {
content += "# KDE AI Chat: " + sessionTitle + "\n";
content += "*Exported on " + root.formatDateTime(Date.now()) + "*\n\n";
content += "---\n\n";
for (let i = 0; i < root.messages.length; i++) {
let m = root.messages[i];
let dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
if (m.role === "user") {
content += "### **User**\n";
content += "*Sent on: " + dateStrMsg + "*\n\n";
content += m.content + "\n\n";
content += "---\n\n";
} else if (m.role === "assistant") {
let modelName = m.model || plasmoid.configuration.model || "Assistant";
content += "### **" + modelName + "**\n";
content += "*Sent on: " + dateStrMsg + "*\n\n";
content += m.content + "\n\n";
content += "---\n\n";
} else if (m.role === "error") {
content += "### **System Error**\n";
content += "*Occurred on: " + dateStrMsg + "*\n\n";
content += "> " + m.content + "\n\n";
content += "---\n\n";
}
}
} else {
content += "==================================================\n";
content += "KDE AI Chat: " + sessionTitle + "\n";
content += "Exported on: " + root.formatDateTime(Date.now()) + "\n";
content += "==================================================\n\n";
let rightAlignTxt = function rightAlignTxt(text, width) {
if (!width)
width = 80;
let lines = text.split("\n");
for (let j = 0; j < lines.length; j++) {
let trimmed = lines[j].trim();
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
for (let i = 0; i < root.messages.length; i++) {
let m = root.messages[i];
let dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
if (m.role === "user") {
let userHeader = "User (" + dateStrMsg + "):";
content += " ".repeat(Math.max(0, 80 - userHeader.length)) + userHeader + "\n";
content += rightAlignTxt(m.content, 80) + "\n\n";
content += "--------------------------------------------------\n\n";
} else if (m.role === "assistant") {
let modelName = m.model || plasmoid.configuration.model || "Assistant";
content += modelName + " (" + dateStrMsg + "):\n";
content += m.content + "\n\n";
content += "--------------------------------------------------\n\n";
} else if (m.role === "error") {
content += "System Error (" + dateStrMsg + "):\n";
content += "ERROR: " + m.content + "\n\n";
content += "--------------------------------------------------\n\n";
}
}
}
let b64Str = base64Encode(content);
let payload = {
"filePath": filePath,
"b64Content": b64Str
};
let b64Payload = base64Encode(JSON.stringify(payload));
let safeFilePath = Sec.sanitizeForShell(filePath);
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " export_chat " + Sec.rawShellSnippetQuote(b64Payload) + " && notify-send -i document-export " + Sec.quoteForShell("KDE AI Chat") + " " + Sec.quoteForShell("Chat session successfully exported to " + safeFilePath);
fileReaderDs.connectSource(cmd + " #export-chat-save");
}


function removeLastErrorMessages() {
let copy = root.messages.slice();
while (copy.length > 0) {
let lastRole = copy[copy.length - 1].role;
let lastContent = copy[copy.length - 1].content || "";
if (lastRole === "error" || (lastRole === "assistant" && lastContent.indexOf("Attempting to start") !== -1))
copy.pop();
else
break;
}
root.messages = copy;
saveCurrentSessionState(true);
}


function retryLastFailedMessage() {
let lastUserIdx = -1;
for (let i = root.messages.length - 1; i >= 0; i--) {
if (root.messages[i].role === "user" || root.messages[i].role === "queued") {
lastUserIdx = i;
break;
}
}
if (lastUserIdx >= 0) {
root.loading = true;
sendMessageByIndex(lastUserIdx);
}
}


function resetOpenCodeIdleKillTimer() {
if (typeof openCodeIdleKillTimer === "undefined")
return;
if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
let mins = root.configOpenCodeAutoKillMinutes || 5;
openCodeIdleKillTimer.interval = mins * 60000;
openCodeIdleKillTimer.restart();
} else {
openCodeIdleKillTimer.stop();
}
}


function copyToClipboard(textValue) {
let text = textValue || "";
// Sanitize first so the entire single-quote payload is harmless
// even if the surrounding wrapper is re-evaluated. The wrapper
// now uses a single-quoted string around the inner command so
// the outer `sh -c` cannot perform command substitution on
// the value.
let safe = Sec.sanitizeForShell(text);
let cmd = "sh -c 'if command -v wl-copy >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | xclip -selection clipboard; " + "else echo \"Clipboard tool missing: install wl-clipboard or xclip\" 1>&2; exit 1; fi'";
clipboardDs.connectSource(cmd + " #clipboard-copy");
}


function flushStreamingBuffer() {
flushIntermediateStreaming();
let text = root.streamingContent;
let label = root.streamingModel;
let ctx = root.streamingContextItems;
if (text === "" && ctx.length === 0) {
    root.streamingResponse = false;
    return ;
}
root.streamingContent = "";
root.streamingModel = "";
root.streamingContextItems = [];
root.streamingResponse = false;
let ts = Date.now();
let newMsg = {
"role": "assistant",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": label || "OpenCode",
"contextItems": ctx
};
if (root.streamingTokens) newMsg.tokens = root.streamingTokens;
if (root.streamingCost > 0) newMsg.cost = root.streamingCost;

// Defer precompute + model update to the next event-loop tick. The
// previous code path ran the regex-based precompute synchronously on
// the main thread, which on long messages (multi-KB responses with
// code blocks/tables) caused 50-150ms freezes at the end of every
// stream. Doing the work in Qt.callLater lets the streaming footer
// clear instantly and the bubble appear on the next frame.
Qt.callLater(function() {
    try {
        precomputeBlocksAndHtmlForMessage(newMsg);
    } catch (_) {
        // Non-fatal: the delegate's own convertMarkdownToHtml binding
        // will fall back to a plaintext render if blocks are missing.
    }
    root.messages.push(newMsg);
    root.messagesChanged();
    if (!root.userScrolledUp)
        queueScrollToBottom();
});

root.streamingTokens = null;
root.streamingCost = 0;
}


// ── Voice (STT/TTS) Functions ───────────────────────────────────────────

function getVoiceHelperPath() {
    let base = Qt.resolvedUrl("./voice/voice_helper.py").toString();
    if (base.indexOf("file://") === 0)
        base = base.substring(7);
    return base;
}

function getVenvSetupPath() {
    let base = Qt.resolvedUrl("./voice/venv_setup.sh").toString();
    if (base.indexOf("file://") === 0)
        base = base.substring(7);
    return base;
}

function resolveVenvPath() {
    let path = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
    if (path.charAt(0) === "~") {
        let home = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString();
        if (home.indexOf("file://") === 0)
            home = home.substring(7);
        try { home = decodeURIComponent(home); } catch (e) {}
        path = home + path.substring(1);
    }
    return path;
}

function resetVoiceIdleTimer() {
    if (typeof dataSources !== "undefined" && dataSources && dataSources.voiceIdleTimer) {
        dataSources.voiceIdleTimer.restart();
    }
}

function ensureVoiceDaemonRunning(port, onStarted) {
    let xhr = new XMLHttpRequest();
    xhr.open("GET", "http://127.0.0.1:" + port + "/status", true);
    if (root.voiceManagerRef && root.voiceManagerRef.httpToken)
        xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.voiceManagerRef.httpToken);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                onStarted(true);
            } else {
                startDaemonService(port, onStarted);
            }
        }
    };
    try {
        xhr.send();
    } catch (e) {
        startDaemonService(port, onStarted);
    }
}

function startDaemonService(port, onStarted) {
    let serviceName = (port === 9015) ? "kde-ai-stt.service" : "kde-ai-tts.service";
    let startCmd = "systemctl --user start " + serviceName;
    
    if (root.voiceManagerRef && root.voiceManagerRef.voiceDs) {
        root.voiceManagerRef.voiceDs.connectSource("sh -c " + Sec.quoteForShell(startCmd) + " #start-daemon-on-demand-" + Date.now());
    } else if (typeof dataSources !== "undefined" && dataSources && dataSources.utilityDs) {
        dataSources.utilityDs.connectSource("sh -c " + Sec.quoteForShell(startCmd) + " #start-daemon-on-demand-" + Date.now());
    }

    if (typeof dataSources !== "undefined" && dataSources && dataSources.voiceDaemonStartTimer) {
        dataSources.voiceDaemonStartTimer.port = port;
        dataSources.voiceDaemonStartTimer.elapsed = 0;
        dataSources.voiceDaemonStartTimer.callback = onStarted;
        dataSources.voiceDaemonStartTimer.start();
    } else {
        // Fallback if timer is not ready
        onStarted(false);
    }
}

function sendVoiceCommand(port, payload, fallbackSource) {
    resetVoiceIdleTimer();
    let xhr = new XMLHttpRequest();
    xhr.open("POST", "http://127.0.0.1:" + port + "/command", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    if (root.voiceManagerRef && root.voiceManagerRef.httpToken)
        xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.voiceManagerRef.httpToken);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    handleVoiceResponse(resp, fallbackSource);
                } catch (e) {
                    if (root.voiceManagerRef && root.voiceManagerRef.voiceDs) root.voiceManagerRef.voiceDs.connectSource(fallbackSource);
                    else if (typeof dataSources !== "undefined" && dataSources && dataSources.utilityDs) dataSources.utilityDs.connectSource(fallbackSource);
                }
            } else {
                if (root.voiceManagerRef && root.voiceManagerRef.voiceDs) root.voiceManagerRef.voiceDs.connectSource(fallbackSource);
                else if (typeof dataSources !== "undefined" && dataSources && dataSources.utilityDs) dataSources.utilityDs.connectSource(fallbackSource);
            }
        }
    };
    try {
        xhr.send(JSON.stringify(payload));
    } catch (e) {
        if (root.voiceManagerRef && root.voiceManagerRef.voiceDs) root.voiceManagerRef.voiceDs.connectSource(fallbackSource);
        else if (typeof dataSources !== "undefined" && dataSources && dataSources.utilityDs) dataSources.utilityDs.connectSource(fallbackSource);
    }
}

function checkVoiceEnv() {
    let helperPath = getVoiceHelperPath();
    let venvPath = resolveVenvPath();
    let venvPy = venvPath + "/bin/python3";
    let sttPath = plasmoid.configuration.voiceSttModelPath || "";
    let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
    let espeakPath = plasmoid.configuration.voiceEspeakPath || "";
    let payload = {
        cmd: "check_env",
        stt_model_path: sttPath,
        tts_model_path: ttsPath,
        espeak_path: espeakPath
    };
    let payloadStr = JSON.stringify(payload);
    let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
    let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-env-" + Date.now();
    sendVoiceCommand(9015, payload, sourceName);
}

function startVoiceRecording() {
    if (root.voiceRecording) return;
    root.voiceRecording = true;
    root.voiceSttStatus = "starting_daemon";
    root.voicePendingText = "";
    resetVoiceIdleTimer();

    ensureVoiceDaemonRunning(9015, function(success) {
        if (!root.voiceRecording) return; // User might have stopped/cancelled in the meantime
        root.voiceSttStatus = "loading_model";
        let helperPath = getVoiceHelperPath();
        let venvPath = resolveVenvPath();
        let venvPy = venvPath + "/bin/python3";
        let lang = plasmoid.configuration.voiceLanguage || "en";
        let model = plasmoid.configuration.voiceSttModel || "";
        let modelPath = plasmoid.configuration.voiceSttModelPath || "";
        let payload = {cmd: "start_stt", duration: 300, language: lang, model: model, model_path: modelPath};
        let payloadStr = JSON.stringify(payload);
        let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-stt-" + Date.now();
        sendVoiceCommand(9015, payload, sourceName);
    });
}

function stopVoiceRecording() {
    if (!root.voiceRecording) return;
    root.voiceSttStatus = "stopping";
    resetVoiceIdleTimer();
    if (typeof dataSources !== "undefined" && dataSources && dataSources.voiceDaemonStartTimer) {
        dataSources.voiceDaemonStartTimer.stop();
    }
    let helperPath = getVoiceHelperPath();
    let venvPath = resolveVenvPath();
    let venvPy = venvPath + "/bin/python3";
    let payload = {cmd: "stop_stt"};
    let payloadStr = JSON.stringify(payload);
    let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
    let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-stop-" + Date.now();
    sendVoiceCommand(9015, payload, sourceName);
    // Force-stop after 3 seconds if the daemon doesn't respond
    if (typeof dataSources !== "undefined" && dataSources && dataSources._voiceForceStopTimer) {
        dataSources._voiceForceStopTimer.restart();
    } else {
        root.voiceRecording = false;
        root.voiceSttStatus = "";
    }
}

function triggerTts(text) {
    if (!text || !plasmoid.configuration.voiceTtsEnabled) return;
    // Strip emojis (all Unicode emoji/symbol/pictograph ranges) and
    // markdown formatting characters so TTS sounds natural.
    let clean = text
        // Emoji ranges: Emoticons, Misc Symbols and Pictographs, Transport, Supplemental
        .replace(/[\u{1F600}-\u{1F64F}]/gu, "")   // Emoticons
        .replace(/[\u{1F300}-\u{1F5FF}]/gu, "")   // Misc Symbols and Pictographs
        .replace(/[\u{1F680}-\u{1F6FF}]/gu, "")   // Transport and Map
        .replace(/[\u{1F700}-\u{1F77F}]/gu, "")   // Alchemical Symbols
        .replace(/[\u{1F780}-\u{1F7FF}]/gu, "")   // Geometric Shapes Extended
        .replace(/[\u{1F800}-\u{1F8FF}]/gu, "")   // Supplemental Arrows-C
        .replace(/[\u{1F900}-\u{1F9FF}]/gu, "")   // Supplemental Symbols and Pictographs
        .replace(/[\u{1FA00}-\u{1FA6F}]/gu, "")   // Chess symbols
        .replace(/[\u{1FA70}-\u{1FAFF}]/gu, "")   // Symbols and Pictographs Extended-A
        .replace(/[\u{2600}-\u{26FF}]/gu, "")     // Misc Symbols (☀️ ⭐ etc.)
        .replace(/[\u{2700}-\u{27BF}]/gu, "")     // Dingbats
        .replace(/[\u{FE00}-\u{FE0F}]/gu, "")     // Variation Selectors
        .replace(/[\u{1F1E0}-\u{1F1FF}]/gu, "")   // Flags
        .replace(/\u200D/g, "")                   // Zero-width joiner
        // Strip markdown syntax
        .replace(/\*\*(.+?)\*\*/g, "$1")          // **bold**
        .replace(/\*(.+?)\*/g, "$1")              // *italic*
        .replace(/__(.+?)__/g, "$1")              // __bold__
        .replace(/_(.+?)_/g, "$1")                // _italic_
        .replace(/`{1,3}[^`]*`{1,3}/g, "")       // `code` and ```blocks```
        .replace(/#+\s/g, "")                     // # Headings
        .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1") // [links](url)
        .replace(/^\s*[-*>]\s+/gm, "")           // bullet/quote lines
        .trim();
    if (!clean) return;

    root.ttsPlaying = true;
    root.ttsPaused = false;
    root.voiceTtsStatus = "starting_daemon";
    resetVoiceIdleTimer();

    ensureVoiceDaemonRunning(9016, function(success) {
        if (!root.ttsPlaying) return; // User might have cancelled in the meantime
        root.voiceTtsStatus = "playing";
        let helperPath = getVoiceHelperPath();
        let venvPath = resolveVenvPath();
        let venvPy = venvPath + "/bin/python3";
        let voice = plasmoid.configuration.voiceTtsVoice || "af_heart";
        let ttsModel = plasmoid.configuration.voiceTtsModel || "";
        let ttsModelPath = plasmoid.configuration.voiceTtsModelPath || "";
        let espeakPath = plasmoid.configuration.voiceEspeakPath || "";
        let payload = {
            cmd: "tts",
            text: clean,
            voice: voice,
            lang_code: "a",
            model: ttsModel,
            model_path: ttsModelPath,
            espeak_path: espeakPath
        };
        let payloadStr = JSON.stringify(payload);
        let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-tts-" + Date.now();
        sendVoiceCommand(9016, payload, sourceName);
    });
}

function stopTts() {
    resetVoiceIdleTimer();
    if (typeof dataSources !== "undefined" && dataSources && dataSources.voiceDaemonStartTimer) {
        dataSources.voiceDaemonStartTimer.stop();
    }
    root.voiceTtsStatus = "";
    root.ttsPlaying = false;
    root.ttsPaused = false;
    let helperPath = getVoiceHelperPath();
    let venvPath = resolveVenvPath();
    let venvPy = venvPath + "/bin/python3";
    let payload = {cmd: "stop_tts"};
    let payloadStr = JSON.stringify(payload);
    let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
    let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-stoptts-" + Date.now();
    sendVoiceCommand(9016, payload, sourceName);
}

function pauseTts() {
    resetVoiceIdleTimer();
    let helperPath = getVoiceHelperPath();
    let venvPath = resolveVenvPath();
    let venvPy = venvPath + "/bin/python3";
    let payload = {cmd: "pause_tts"};
    let payloadStr = JSON.stringify(payload);
    let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
    let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-pausetts-" + Date.now();
    sendVoiceCommand(9016, payload, sourceName);
}

function resumeTts() {
    resetVoiceIdleTimer();
    let helperPath = getVoiceHelperPath();
    let venvPath = resolveVenvPath();
    let venvPy = venvPath + "/bin/python3";
    let payload = {cmd: "resume_tts"};
    let payloadStr = JSON.stringify(payload);
    let fullCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
    let sourceName = "sh -c " + Sec.rawShellSnippetQuote(fullCmd) + " #voice-resumetts-" + Date.now();
    sendVoiceCommand(9016, payload, sourceName);
}

function handleVoiceResponse(resp, sourceName) {
let respType = resp.type || "";
resetVoiceIdleTimer();
    if (respType === "env_check") {
        root.voiceEnvResult = resp;
        root.voiceEnvChecked = true;
    } else if (respType === "stt_result") {
        root.voiceRecording = false;
        root.voiceSttStatus = "";
        let text = (resp.text || "").trim();
        if (root.voiceSttTesting) {
            root.voiceSttTesting = false;
            root.voiceSttTestResult = text || "(no speech detected)";
        } else if (text) {
            if (plasmoid.configuration.voiceAutoSend) {
                root.chatInputText = text;
                Qt.callLater(root.sendMessage);
            } else {
                root.chatInputText = text;
            }
        }
    } else if (respType === "stt_error") {
        root.voiceRecording = false;
        root.voiceSttTesting = false;
        root.voiceSttStatus = "";
        root.voiceSttTestResult = "Error: " + (resp.error || "Unknown error");
        pushErrorMessage("Voice error: " + (resp.error || "Unknown error"));
    } else if (respType === "stt_status") {
        root.voiceSttStatus = resp.status;
        // If daemon reports idle/stopped while we think we're recording, clean up
        if (root.voiceRecording && (resp.status === "idle" || resp.status === "stopped" || resp.status === "")) {
            root.voiceRecording = false;
            root.voiceSttStatus = "";
        }
    } else if (respType === "tts_done") {
        root.ttsPlaying = false;
        root.ttsPaused = false;
        root.voiceTtsStatus = "";
    } else if (respType === "tts_error") {
        root.ttsPlaying = false;
        root.ttsPaused = false;
        root.voiceTtsStatus = "";
        pushErrorMessage("Voice Playback Error: " + (resp.error || "Unknown error"));
    } else if (respType === "play_error") {
        pushErrorMessage("Voice Playback Error: " + (resp.error || "Unknown error"));
    } else if (respType === "tts_status") {
        if (resp.status === "playing") {
            root.ttsPlaying = true;
            root.ttsPaused = false;
        } else if (resp.status === "paused") {
            root.ttsPlaying = true;
            root.ttsPaused = true;
        } else if (resp.status === "stopping") {
            root.ttsPlaying = false;
            root.ttsPaused = false;
        }
    } else if (respType === "download_done") {
        // Model downloaded
    } else if (respType === "download_error") {
        pushErrorMessage("Voice model download error: " + (resp.error || "Unknown error"));
    }
}


// ══════════════════════════════════════════════════════════════
// Network / HTTP functions (formerly MainNetwork.js)
// ══════════════════════════════════════════════════════════════

function base64Encode(str) {
    try {
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
    } catch (e) {
        console.error("base64Encode error:", e);
        return "";
    }
}


function base64Decode(str) {
if (!str || str.trim() === "") return "";
try {
return decodeURIComponent(escape(Qt.atob(str)));
} catch (e) {
try {
return Qt.atob(str);
} catch (err) {
return "";
}
}
}


function finishOpenCodeRequest() {
root.loading = false;
root.activeXhr = null;
root.openCodeActiveSessionId = "";
root.openCodeAssistantMessageIndex = -1;
root.openCodeAssistantServerMessageId = "";
root.openCodeErrorShownForRequest = false;
root.streamingResponse = false;
try { flushStreamingBuffer(); } catch (e) { console.error("finishOpenCodeRequest: flushStreamingBuffer failed:", e); }
try { saveCurrentSessionState(true); } catch (e) { console.error("finishOpenCodeRequest: saveCurrentSessionState failed:", e); }
try { triggerNotificationSound(); } catch (e) { console.error("finishOpenCodeRequest: triggerNotificationSound failed:", e); }
try {
if (plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled && plasmoid.configuration.voiceTtsAuto) {
let lastMsg = root.messages[root.messages.length - 1];
if (lastMsg && lastMsg.role === "assistant" && lastMsg.content) {
try { triggerTts(lastMsg.content); } catch (e) { console.error("finishOpenCodeRequest: triggerTts failed:", e); }
}
}
} catch (e) { console.error("finishOpenCodeRequest: TTS gate check failed:", e); }
try { resetOpenCodeIdleKillTimer(); } catch (e) { console.error("finishOpenCodeRequest: resetOpenCodeIdleKillTimer failed:", e); }
try { processNextQueuedMessage(); } catch (e) { console.error("finishOpenCodeRequest: processNextQueuedMessage failed:", e); }
}


function pushErrorMessage(text) {
let ts = Date.now();
let newMsg = {
"role": "error",
"content": text,
"time": nowTime(ts),
"at": ts,
"model": ""
};
// Defer model update to avoid blocking the main thread.
Qt.callLater(function() {
root.messages.push(newMsg);
root.messagesChanged();
if (!root.userScrolledUp)
    root.queueScrollToBottom ? root.queueScrollToBottom() : Qt.callLater(scrollToBottom);
});
// Debounce the session save to avoid blocking the main thread
if (root.deferSaveStateTimer) {
    root.deferSaveStateTimer.restart();
} else {
    Qt.callLater(function() { saveCurrentSessionState(true); });
}
// If the last user message was a schedule, show a desktop notification of the execution failure!
let isSched = false;
for (let i = root.messages.length - 1; i >= 0; i--) {
if (root.messages[i].role === "user") {
if (root.messages[i].sc)
isSched = true;
break;
}
}
if (isSched) {
let safeErr = Sec.sanitizeForShell(text);
let errTitle = "Schedule Execution Failed";
let safeErrTitle = Sec.sanitizeForShell(errTitle);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-execution-notify-err");
}
}


function validateCurrentSendTarget() {
if (root.openCodeMode)
return validateOpenCodeConfig();
if (root.piMode)
return ""; // Pi uses local CLI, no API key needed
let provider = plasmoid.configuration.provider || "openai";
let providerCfg = getProviderConfig(provider);
return validateProviderConfig(provider, providerCfg);
}

function responseMaxTokens(chatId, fallback) {
let sessionId = chatId || root.currentSessionId;
let preference = plasmoid.configuration.responseLength || 0;
if (typeof getSessionProperty === "function")
preference = getSessionProperty(sessionId, "responseLength", preference);
else if (root && typeof root.getSessionProperty === "function")
preference = root.getSessionProperty(sessionId, "responseLength", preference);
let limits = [0, 256, 1024, 4096, 8192];
return preference > 0 && preference < limits.length ? limits[preference] : fallback;
}


function buildAnthropicPayloadForMessages(messagesList, chatId) {
return _buildMessageArray(messagesList, chatId, "anthropic");
}


function handleBackgroundError(chatId, errorMsg, notify, schedId, schedName) {
let errTs = Date.now();
let errMsgObj = {
"role": "assistant",
"content": "Warning: Schedule failed: " + errorMsg,
"time": nowTime(errTs),
"at": errTs,
"model": ""
};
appendMessageToSession(chatId, errMsgObj);
if (notify) {
let safeErr = Sec.sanitizeForShell(errorMsg);
let errTitle = "Schedule Failed: " + (schedName || "Chat");
let safeErrTitle = Sec.sanitizeForShell(errTitle);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
}
if (schedId) {
let payload = {
"schedId": schedId,
"status": errorMsg
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.rawShellSnippetQuote(b64Payload);
soundDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-history-err");
}
}


function doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName) {
let url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
let xhr = new XMLHttpRequest();
let errorHandled = false;
let targetIdx = sessionIndexById(chatId);
if (targetIdx < 0)
return ;
let targetSession = root.sessions[targetIdx];
let messagesList = targetSession.messages || [];
try {
xhr.open("POST", url, true);
xhr.setRequestHeader("Content-Type", "application/json");
if (apiKey !== "")
xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
if (extraHeaders) {
for (let headerName in extraHeaders) {
if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
xhr.setRequestHeader(headerName, extraHeaders[headerName]);
}
}
xhr.timeout = 60000;
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
handleBackgroundError(chatId, "Request timed out after 60 seconds.", notify, schedId, schedName);
};
} catch (setupError) {
handleBackgroundError(chatId, "Failed to start request: " + setupError, notify, schedId, schedName);
return ;
}
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status < 200 || xhr.status >= 300) {
if (errorHandled)
return ;
errorHandled = true;
let err = "Request to " + url + " failed";
if (xhr.status)
err += " (HTTP " + xhr.status + ")";
try {
let eobj = JSON.parse(xhr.responseText);
if (eobj.error) {
if (typeof eobj.error === "string") {
err += " | " + eobj.error;
} else {
if (eobj.error.message)
err = "API Error (" + xhr.status + "): " + eobj.error.message;
}
} else if (eobj.detail)
err += " | " + eobj.detail;
else if (eobj.message)
err += " | " + eobj.message;
} catch (e2) {
}
handleBackgroundError(chatId, err, notify, schedId, schedName);
return ;
}
try {
let parsed = JSON.parse(xhr.responseText);
let finalText = (parsed.choices && parsed.choices[0] && parsed.choices[0].message && parsed.choices[0].message.content) || "";
if (finalText !== "") {
let doneTs = Date.now();
let msgObj = {
"role": "assistant",
"content": finalText,
"time": nowTime(doneTs),
"at": doneTs,
"model": modelLabel || model || ""
};
if (parsed.usage)
msgObj.tokens = {
"input": parsed.usage.prompt_tokens || 0,
"output": parsed.usage.completion_tokens || 0
};
appendMessageToSession(chatId, msgObj);
                if (chatId === root.currentSessionId) {
                    if (!root.userScrolledUp)
                        root.queueScrollToBottom ? root.queueScrollToBottom() : Qt.callLater(scrollToBottom);
                    if (plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled && plasmoid.configuration.voiceTtsAuto) {
                        triggerTts(finalText || "");
                    }
                }
                triggerNotificationSound();
if (notify) {
let safeText = Sec.sanitizeForShell(finalText.substring(0, 150)) + (finalText.length > 150 ? "…" : "");
let title = (schedName || "Scheduled message response ready");
let safeTitle = Sec.sanitizeForShell(title);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
}
} else {
handleBackgroundError(chatId, "The model returned an empty response.", notify, schedId, schedName);
}
} catch (parseError) {
handleBackgroundError(chatId, "Failed to parse response: " + parseError, notify, schedId, schedName);
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
handleBackgroundError(chatId, "Could not reach " + url + ". Check network connectivity.", notify, schedId, schedName);
};
try {
let payload = {
"model": model,
"messages": buildOpenAICompatPayloadForMessages(messagesList, chatId),
"stream": false
};
let maxTokens = responseMaxTokens(chatId, 0);
if (maxTokens > 0)
payload.max_tokens = maxTokens;
xhr.send(JSON.stringify(payload));
} catch (sendError) {
handleBackgroundError(chatId, "Failed to send request: " + sendError, notify, schedId, schedName);
}
}


function doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName) {
let xhr = new XMLHttpRequest();
let errorHandled = false;
let targetIdx = sessionIndexById(chatId);
if (targetIdx < 0)
return ;
let targetSession = root.sessions[targetIdx];
let messagesList = targetSession.messages || [];
try {
xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.setRequestHeader("x-api-key", apiKey);
xhr.setRequestHeader("anthropic-version", "2023-06-01");
xhr.timeout = 60000;
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
handleBackgroundError(chatId, "Request timed out after 60 seconds.", notify, schedId, schedName);
};
} catch (setupError) {
handleBackgroundError(chatId, "Failed to start request: " + setupError, notify, schedId, schedName);
return ;
}
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
try {
let obj = JSON.parse(xhr.responseText);
let text = "";
if (obj.content && obj.content.length) {
for (let i = 0; i < obj.content.length; i++) {
if (obj.content[i].type === "text")
text += obj.content[i].text;
}
}
let ts = Date.now();
let msgObj = {
"role": "assistant",
"content": text || "(empty response)",
"time": nowTime(ts),
"at": ts,
"model": model || ""
};
if (obj.usage)
msgObj.tokens = {
"input": obj.usage.input_tokens || 0,
"output": obj.usage.output_tokens || 0
};
appendMessageToSession(chatId, msgObj);
if (chatId === root.currentSessionId) {
if (!root.userScrolledUp)
root.queueScrollToBottom ? root.queueScrollToBottom() : Qt.callLater(scrollToBottom);
}
triggerNotificationSound();
if (chatId === root.currentSessionId && plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled && plasmoid.configuration.voiceTtsAuto) {
triggerTts(text || "");
}
if (notify) {
let safeText = Sec.sanitizeForShell((text || "").substring(0, 150)) + ((text || "").length > 150 ? "…" : "");
let title = (schedName || "Scheduled message response ready");
let safeTitle = Sec.sanitizeForShell(title);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
}
} catch (e) {
handleBackgroundError(chatId, "Failed to parse Anthropic response", notify, schedId, schedName);
}
} else {
if (errorHandled)
return ;
errorHandled = true;
let err = "Anthropic HTTP " + xhr.status;
try {
let eobj = JSON.parse(xhr.responseText);
if (eobj.error) {
if (typeof eobj.error === "string") {
err += " | " + eobj.error;
} else {
if (eobj.error.message)
err = "Anthropic Error (" + xhr.status + "): " + eobj.error.message;
if (eobj.error.type)
err = "[" + eobj.error.type + "] " + err;
}
}
} catch (e2) {
}
handleBackgroundError(chatId, err, notify, schedId, schedName);
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
handleBackgroundError(chatId, "Could not reach Anthropic API. Check network status.", notify, schedId, schedName);
};
try {
xhr.send(JSON.stringify({
"model": model,
"max_tokens": responseMaxTokens(chatId, 1024),
"system": buildEffectiveSystemPrompt(chatId),
"messages": buildAnthropicPayloadForMessages(messagesList, chatId)
}));
} catch (sendError) {
handleBackgroundError(chatId, "Failed to send request: " + sendError, notify, schedId, schedName);
}
}


function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
let url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
let xhr = new XMLHttpRequest();
let errorHandled = false;
let lastUserText = "";
for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
if ((root.messages[mIdx].role || "") === "user") {
lastUserText = root.messages[mIdx].content || "";
break;
}
}
let dedupKey = root.reqDedupKey(plasmoid.configuration.provider || "openai", model, lastUserText, root.currentSessionId);
if (!root.reqDedupTryClaim(dedupKey)) {
pushErrorMessage("Duplicate request ignored: a response to this message is already in flight.");
return ;
}
try {
xhr.open("POST", url, true);
xhr.setRequestHeader("Content-Type", "application/json");
if (apiKey !== "")
xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
if (extraHeaders) {
for (let headerName in extraHeaders) {
if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
xhr.setRequestHeader(headerName, extraHeaders[headerName]);
}
}
xhr.timeout = 90000;
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
finishOpenCodeRequest();
pushErrorMessage("Request timed out after 90 seconds.");
};
} catch (setupError) {
root.reqDedupRelease(dedupKey);
pushErrorMessage("Failed to start request: " + setupError);
return ;
}
root.loading = true;
root.activeXhr = xhr;
beginAssistantStreaming(modelLabel || model || "");

let offset = 0;
let buffer = "";
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
return ;
let delta = xhr.responseText.slice(offset);
offset = xhr.responseText.length;
buffer += delta;
let lines = buffer.split("\n");
buffer = lines.pop();
for (let i = 0; i < lines.length; i++) {
let line = lines[i].trim();
if (!line || line.indexOf("data:") !== 0)
continue;
let data = line.slice(5).trim();
if (data === "[DONE]") {
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
return ;
}
try {
let parsed = JSON.parse(data);
let content = (parsed.choices && parsed.choices[0] && parsed.choices[0].delta && parsed.choices[0].delta.content) || "";
if (content) {
updateAssistantStreamingContent(content, modelLabel || model);
}
} catch (e) {
}
}
if (xhr.readyState === XMLHttpRequest.DONE) {
root.reqDedupRelease(dedupKey);
if (!errorHandled) {
if (xhr.status < 200 || xhr.status >= 300) {
let err = "Request to " + Sec.scrubSecrets(url) + " failed (HTTP " + xhr.status + ")";
pushErrorMessage(err);
}
finishOpenCodeRequest();
}
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Could not reach " + Sec.scrubSecrets(url));
};
try {
let payload = {
"model": model,
"messages": buildOpenAICompatPayload(),
"stream": true
};
let maxTokens = responseMaxTokens("", 0);
if (maxTokens > 0)
payload.max_tokens = maxTokens;
xhr.send(JSON.stringify(payload));
} catch (sendError) {
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Failed to send request: " + sendError);
}
}


function doAnthropicRequest(apiKey, model) {
if (!apiKey) {
pushErrorMessage("Anthropic API key missing in settings.");
processNextQueuedMessage();
return ;
}
let xhr = new XMLHttpRequest();
let errorHandled = false;
let lastUserText = "";
for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
if ((root.messages[mIdx].role || "") === "user") {
lastUserText = root.messages[mIdx].content || "";
break;
}
}
let dedupKey = root.reqDedupKey("anthropic", model, lastUserText, root.currentSessionId);
if (!root.reqDedupTryClaim(dedupKey)) {
pushErrorMessage("Duplicate request ignored: a response to this message is already in flight.");
return ;
}
root.loading = true;
root.activeXhr = xhr;
beginAssistantStreaming(model || "");
try {
xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.setRequestHeader("x-api-key", apiKey);
xhr.setRequestHeader("anthropic-version", "2023-06-01");
xhr.timeout = 90000;
} catch (setupError) {
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Failed to start Anthropic request: " + setupError);
return ;
}
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
finishOpenCodeRequest();
root.reqDedupRelease(dedupKey);
pushErrorMessage("Request timed out after 90 seconds.");
};
let offset = 0;
let buffer = "";
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
return ;
let delta = xhr.responseText.slice(offset);
offset = xhr.responseText.length;
buffer += delta;
let lines = buffer.split("\n");
buffer = lines.pop();
for (let i = 0; i < lines.length; i++) {
let line = lines[i].trim();
if (!line || line.indexOf("data:") !== 0)
continue;
let dataStr = line.slice(5).trim();
try {
let data = JSON.parse(dataStr);
if (data.type === "content_block_delta" && data.delta && data.delta.text) {
updateAssistantStreamingContent(data.delta.text, model);
} else if (data.type === "message_stop") {
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
return ;
}
} catch (e) {
}
}
if (xhr.readyState === XMLHttpRequest.DONE) {
root.reqDedupRelease(dedupKey);
if (!errorHandled) {
if (xhr.status < 200 || xhr.status >= 300) {
pushErrorMessage("Anthropic request failed (HTTP " + xhr.status + ")");
}
finishOpenCodeRequest();
}
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Could not reach https://api.anthropic.com/v1/messages.");
};
try {
xhr.send(JSON.stringify({
"model": model,
"max_tokens": responseMaxTokens("", 1024),
"system": buildEffectiveSystemPrompt(),
"messages": buildAnthropicPayload(),
"stream": true
}));
} catch (sendError) {
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Failed to send Anthropic request: " + sendError);
}
}


// ══════════════════════════════════════════════════════════════
// OpenCode server functions (formerly MainOpenCode.js)
// ══════════════════════════════════════════════════════════════


function openCodeBaseUrl() {
return root.openCodeBaseUrlVal;
}


function currentOpenCodeSessionId() {
let sId = root.currentSessionId;
let override = getSessionProperty(sId, "contextOverride", false);
let contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : plasmoid.configuration.globalContextEnabled;
if (!contextEnabled)
return "";
let idx = sessionIndexById(sId);
if (idx < 0)
return "";
return root.sessions[idx].openCodeSessionId || "";
}


function setCurrentOpenCodeSessionId(remoteSessionId) {
let idx = sessionIndexById(root.currentSessionId);
if (idx < 0)
return ;
let updated = root.sessions.slice();
let item = Object.assign({
}, updated[idx]);
item.openCodeSessionId = remoteSessionId || "";
updated[idx] = item;
root.sessions = updated;
persistSessions();
}


function clearCurrentOpenCodeSessionIfNeeded() {
if (!root.openCodeMode)
return ;
setCurrentOpenCodeSessionId("");
}


function sanitizeOpenCodeStartCommand(cmd) {
    let raw = (cmd || "").trim();
    if (raw === "") {
        return 'pidfile="${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).pid"; logf="${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >"$logf" 2>&1 < /dev/null & echo $! >"$pidfile"; echo ok';
    }
    if (raw.indexOf("opencode serve") >= 0 && raw.indexOf("< /dev/null") < 0) {
        if (raw.indexOf("2>&1") >= 0) {
            raw = raw.replace("2>&1", "2>&1 < /dev/null");
        } else {
            if (raw.endsWith("&")) {
                raw = raw.slice(0, -1).trim() + " < /dev/null &";
            } else {
                raw = raw + " < /dev/null";
            }
        }
    }
    // Ensure nohup + backgrounding for proper detaching (no subshells, to preserve $! for PID capture)
    if (raw.indexOf("nohup") < 0) {
        raw = "nohup " + raw;
    }
    if (!raw.endsWith("&")) {
        raw = raw + " &";
    }
    if (raw.indexOf("< /dev/null") < 0) {
        raw = raw.replace(/&$/, "< /dev/null &");
    }
    let pidfile = '"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).pid"';
    raw = raw + " echo $! >" + pidfile + "; echo ok";
    return raw;
}


function ensureOpenCodeEventStream() {
if (root.openCodeEventXhr)
return ;
let xhr = new XMLHttpRequest();
let buffer = "";
let offset = 0;
let url = openCodeBaseUrl() + "/event";
root.openCodeEventXhr = xhr;
xhr.open("GET", url, true);
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
return ;
let delta = xhr.responseText.slice(offset);
offset = xhr.responseText.length;
buffer += delta;
while (true) {
let split = buffer.indexOf("\n\n");
if (split < 0)
break;
let block = buffer.slice(0, split);
buffer = buffer.slice(split + 2);
let lines = block.split("\n");
for (let i = 0; i < lines.length; i++) {
if (lines[i].indexOf("data:") !== 0)
continue;
try {
let eventObj = JSON.parse(lines[i].slice(5).trim());
handleOpenCodeEvent(eventObj);
} catch (eventError) {
}
}
}
if (xhr.readyState === XMLHttpRequest.DONE) {
root.openCodeEventXhr = null;
if (root.openCodeMode)
openCodeReconnectTimer.start();
}
};
xhr.onerror = function() {
root.openCodeEventXhr = null;
if (root.openCodeMode)
openCodeReconnectTimer.start();
};
try {
xhr.send();
} catch (streamError) {
root.openCodeEventXhr = null;
if (root.openCodeMode)
openCodeReconnectTimer.start();
}
}


function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
let existing = currentOpenCodeSessionId();
if (existing !== "") {
successCallback(existing);
return ;
}
let fail = function fail(msg) {
if (typeof failureCallback === "function")
failureCallback(msg);
else
pushErrorMessage(msg);
};
let xhr = new XMLHttpRequest();
xhr.open("POST", openCodeBaseUrl() + "/session", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.timeout = 10000;
xhr.ontimeout = function() {
fail("OpenCode: session creation timed out. Check that the server is running at " + openCodeBaseUrl());
};
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
triggerNotificationSound();
try {
let obj = JSON.parse(xhr.responseText);
let remoteId = obj.id || "";
if (remoteId === "") {
fail("OpenCode: server created a session without an id.");
return ;
}
setCurrentOpenCodeSessionId(remoteId);
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
try {
xhr.send(JSON.stringify({
"title": root.currentSessionTitle || "KDE AI Chat"
}));
} catch (sendError) {
fail("OpenCode: failed to create session: " + sendError);
}
}


function ensureOpenCodeServerRunning(chatId, successCallback, failureCallback) {
if (root.openCodeStarting) {
if (successCallback) {
let sCbs = root.openCodeStartSuccessCallbacks.slice();
sCbs.push(successCallback);
root.openCodeStartSuccessCallbacks = sCbs;
}
if (failureCallback) {
let fCbs = root.openCodeStartFailureCallbacks.slice();
fCbs.push(failureCallback);
root.openCodeStartFailureCallbacks = fCbs;
}
return;
}
root.openCodeStarting = true;
root.openCodeStartSuccessCallbacks = successCallback ? [successCallback] : [];
root.openCodeStartFailureCallbacks = failureCallback ? [failureCallback] : [];
let checkFinished = false;
let completed = false;
let resolveSuccess = function() {
if (completed) return;
completed = true;
root.openCodeStarting = false;
let successCbs = root.openCodeStartSuccessCallbacks;
root.openCodeStartSuccessCallbacks = [];
root.openCodeStartFailureCallbacks = [];
for (let i = 0; i < successCbs.length; i++) {
successCbs[i]();
}
};
let resolveFailure = function(msg) {
if (completed) return;
completed = true;
root.openCodeStarting = false;
let failureCbs = root.openCodeStartFailureCallbacks;
root.openCodeStartSuccessCallbacks = [];
root.openCodeStartFailureCallbacks = [];
if (failureCbs.length > 0) {
for (let i = 0; i < failureCbs.length; i++) {
failureCbs[i](msg);
}
} else {
if (chatId)
appendSystemMessageToSession(chatId, "Warning: " + msg);
else
pushErrorMessage(msg);
}
};
function handleSuccess() {
if (checkFinished) return;
checkFinished = true;
resolveSuccess();
}
function handleNotRunning(err) {
if (checkFinished) return;
checkFinished = true;
if (plasmoid.configuration.autoStartOpenCodeServer) {
let startCmd = sanitizeOpenCodeStartCommand(plasmoid.configuration.openCodeStartCommand);
let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
opencodeServerDs.connectSource("sh -c '" + envPrefix + startCmd.replace(/'/g, "'\\''") + "' #ensure-opencode-startup-" + Date.now());
if (chatId) {
let ts1 = appendSystemMessageToSession(chatId, translate("Starting OpenCode server, please wait..."));
scheduleMessageRemoval(chatId, ts1, 3000);
}
openCodeStartPollTimer.successCb = function() {
if (chatId) {
let ts2 = appendSystemMessageToSession(chatId, translate("Session restarted."));
scheduleMessageRemoval(chatId, ts2, 3000);
}
resolveSuccess();
};
openCodeStartPollTimer.failureCb = function(msg) {
resolveFailure(msg);
};
openCodeStartPollTimer.retriesLeft = 6;
openCodeStartPollTimer.start();
} else {
resolveFailure("OpenCode server is not running. Please start it or enable \"Auto-start OpenCode server\" in General settings.");
}
}
let checkUrl = openCodeBaseUrl() + "/config/providers";
let xhr = new XMLHttpRequest();
xhr.open("GET", checkUrl, true);
xhr.timeout = 1500;
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300)
handleSuccess();
else
handleNotRunning("HTTP " + xhr.status);
};
xhr.onerror = function() {
handleNotRunning("Transport error");
};
xhr.ontimeout = function() {
handleNotRunning("Timeout");
};
try {
xhr.send();
} catch (e) {
handleNotRunning(e.toString());
}
}
function runLocalPiCommand(cmdText) {
let bare = cmdText.trim();
if (bare.startsWith("/")) bare = bare.substring(1);
let verb = bare.split(" ")[0].toLowerCase();
root.autocompleteActive = false;
if (verb === "help") {
pushInfoMessage("**Pi commands:**\n- `/help` \u2014 this message\n- `/version` \u2014 show installed Pi version");
return;
}
if (verb === "version") {
root.loading = true;
beginAssistantStreaming("Pi Agent");
updateAssistantStreamingContent("Checking Pi version...", "Pi Agent");
let piEnvPfx = "export PATH=\"$PATH:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin\"; ";
piTerminalDs.connectSource("sh -c " + Sec.quoteForShell(piEnvPfx + "pi --version") + " #pi-cli-" + Date.now());
return;
}
pushErrorMessage("Unknown Pi command: `" + cmdText.trim() + "`\nType `/help` to see available commands.");
}

function doPiRequest() {
root.loading = true;
// Set up streaming bubble so user sees a "Thinking..." indicator
beginAssistantStreaming("Pi Agent");
updateAssistantStreamingContent("Thinking...", "Pi Agent");
let sessionId = "kde-ai-chat-" + root.currentSessionId;
let lastUserMsg = "";
for (let i = root.messages.length - 1; i >= 0; i--) {
if (root.messages[i].role === "user") {
lastUserMsg = root.messages[i].content;
break;
}
}
let piProvider = (plasmoid && plasmoid.configuration && plasmoid.configuration.piProvider) ? plasmoid.configuration.piProvider.trim() : "";
let piModel = (plasmoid && plasmoid.configuration && plasmoid.configuration.piModel) ? plasmoid.configuration.piModel.trim() : "";
let extraArgs = "";
if (piProvider) extraArgs += " --provider " + Sec.quoteForShell(piProvider);
if (piModel) extraArgs += " --model " + Sec.quoteForShell(piModel);
let piEnvPrefix = "export PATH=\"$PATH:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin\"; ";
let piArgs = "pi --session-id " + Sec.quoteForShell(sessionId) + " --mode text" + extraArgs + " -p " + Sec.quoteForShell(lastUserMsg);
let cmd = "sh -c " + Sec.quoteForShell(piEnvPrefix + piArgs + " 2>/dev/null") + " #pi-req-" + Date.now();
piTerminalDs.connectSource(cmd);
}

function handlePiResponse(sourceName, stdout, stderr, exitCode) {
// Stop spinner
root.loading = false;
if (exitCode !== 0) {
// Kill the streaming bubble on error
root.streamingResponse = false;
root.streamingContent = "";
root.streamingModel = "";
let errStr = (stderr || stdout || "").trim();
if (errStr === "") errStr = "Pi process exited with code " + exitCode;
pushErrorMessage("Pi agent failed: " + errStr);
try { processNextQueuedMessage(); } catch (e) {}
return;
}
let res = (stdout || "").trim();
// Replace the "Thinking..." placeholder with the real response by
// overwriting the streaming content and then flushing it to root.messages
root.streamingContent = res;
root.streamingModel = "Pi Agent";
try { flushStreamingBuffer(); } catch (e) { console.error("handlePiResponse: flushStreamingBuffer failed:", e); }
try { saveCurrentSessionState(true); } catch (e) { console.error("handlePiResponse: saveCurrentSessionState failed:", e); }
try { triggerNotificationSound(); } catch (e) {}
try { processNextQueuedMessage(); } catch (e) {}
}

function doOpenCodeRequest() {
let requestFinalized = false;
function failOpenCodeRequest(message) {
if (requestFinalized)
return ;
requestFinalized = true;
if (!root.openCodeErrorShownForRequest) {
root.openCodeErrorShownForRequest = true;
pushErrorMessage(message);
}
finishOpenCodeRequest();
}
ensureOpenCodeServerRunning(root.currentSessionId, function() {
ensureOpenCodeEventStream();
root.loading = true;
root.streamingResponse = false;
root.openCodeAssistantMessageIndex = -1;
root.openCodeAssistantServerMessageId = "";
root.openCodeErrorShownForRequest = false;
ensureCurrentOpenCodeSession(function(remoteSessionId) {
let xhr = new XMLHttpRequest();
let modelId = (plasmoid.configuration.openCodeModel || "").trim();
let providerId = (plasmoid.configuration.openCodeProvider || "").trim();
root.activeXhr = xhr;
root.openCodeActiveSessionId = remoteSessionId;
xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.timeout = 15000;
xhr.ontimeout = function() {
failOpenCodeRequest("OpenCode: message request timed out at " + openCodeBaseUrl());
};
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (requestFinalized)
return ;
if (xhr.status < 200 || xhr.status >= 300) {
if (xhr.status === 404)
setCurrentOpenCodeSessionId("");
let suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
failOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
return ;
}
try {
let obj = JSON.parse(xhr.responseText);
if (obj.info && obj.info.id)
root.openCodeAssistantServerMessageId = obj.info.id;
if (obj.info && obj.info.error && !root.openCodeErrorShownForRequest) {
root.openCodeErrorShownForRequest = true;
pushErrorMessage(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
}
if (obj.parts && obj.parts.length > 0) {
let combined = "";
for (let i = 0; i < obj.parts.length; i++) {
if (obj.parts[i].type === "text")
combined += obj.parts[i].text || obj.parts[i].content || "";
}
if (combined !== "")
updateAssistantStreamingContent(combined, providerId + "/" + modelId);
else if (!root.openCodeErrorShownForRequest && root.openCodeAssistantMessageIndex < 0)
updateAssistantStreamingContent("(empty response)", providerId + "/" + modelId);
}
} catch (parseResponseError) {
}
requestFinalized = true;
finishOpenCodeRequest();
};
xhr.onerror = function() {
failOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.");
};
try {
let lastMsg = null;
for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
if (root.messages[mIdx].role === "user") {
lastMsg = root.messages[mIdx];
break;
}
}
if (!lastMsg) {
failOpenCodeRequest("No user message found to send.");
return ;
}
let userContent = lastMsg.content || "";
userContent = injectMemoriesToUserMessage(userContent, root.currentSessionId);
if (lastMsg.quote) {
let sender = lastMsg.quote.role === "assistant" ? (lastMsg.quote.model || "Assistant") : "User";
userContent = "[Replying to @" + sender + ": \"" + lastMsg.quote.content + "\"]\n\n" + userContent;
}
let parts = [];
if (lastMsg.attachments && lastMsg.attachments.length > 0) {
let payload = buildMessageContent(userContent, lastMsg.attachments, "openai");
if (typeof payload === "string") {
parts.push({
"type": "text",
"text": payload
});
} else {
for (let p = 0; p < payload.length; p++) {
let item = payload[p];
if (item.type === "text") {
parts.push({
"type": "text",
"text": item.text
});
} else if (item.type === "image_url") {
let mType = item.image_url.url.split(";")[0].split(":")[1];
parts.push({
"type": "file",
"mime": mType,
"url": item.image_url.url
});
}
}
}
} else {
parts.push({
"type": "text",
"text": userContent
});
}
xhr.send(JSON.stringify({
"model": {
"providerID": providerId,
"modelID": modelId
},
"system": buildEffectiveSystemPrompt(),
"parts": parts
}));
} catch (sendError) {
failOpenCodeRequest("OpenCode: failed to send request: " + sendError);
}
}, function(errorMessage) {
if (!root.openCodeErrorShownForRequest) {
root.openCodeErrorShownForRequest = true;
pushErrorMessage(errorMessage);
}
finishOpenCodeRequest();
});
}, function(err) {
failOpenCodeRequest(err);
});
}


function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
let requestFinalized = false;
function failBackgroundOpenCodeRequest(message) {
if (requestFinalized)
return ;
requestFinalized = true;
handleBackgroundError(chatId, message, notify, schedId, schedName);
}
ensureOpenCodeServerRunning(chatId, function() {
ensureOpenCodeSessionForChatId(chatId, function(remoteSessionId) {
let xhr = new XMLHttpRequest();
let modelId = (plasmoid.configuration.openCodeModel || "").trim();
let providerId = (plasmoid.configuration.openCodeProvider || "").trim();
xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.timeout = 60000;
xhr.ontimeout = function() {
failBackgroundOpenCodeRequest("OpenCode: message request timed out at " + openCodeBaseUrl());
};
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (requestFinalized)
return ;
if (xhr.status < 200 || xhr.status >= 300) {
if (xhr.status === 404)
setOpenCodeSessionIdForChatId(chatId, "");
let suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
failBackgroundOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
return ;
}
try {
let obj = JSON.parse(xhr.responseText);
let combined = "";
if (obj.parts && obj.parts.length > 0) {
for (let i = 0; i < obj.parts.length; i++) {
if (obj.parts[i].type === "text")
combined += obj.parts[i].text || obj.parts[i].content || "";
}
}
if (obj.info && obj.info.error) {
failBackgroundOpenCodeRequest(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
return ;
}
if (combined !== "") {
let doneTs = Date.now();
let msgObj = {
"role": "assistant",
"content": combined,
"time": nowTime(doneTs),
"at": doneTs,
"model": providerId + "/" + modelId,
"queueId": 0,
"attachments": []
};
appendMessageToSession(chatId, msgObj);
triggerNotificationSound();
if (notify) {
let safeText = Sec.sanitizeForShell(combined.substring(0, 150)) + (combined.length > 150 ? "…" : "");
let title = (schedName || "Scheduled message response ready");
let safeTitle = Sec.sanitizeForShell(title);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
}
} else {
failBackgroundOpenCodeRequest("The model returned an empty response.");
}
} catch (parseResponseError) {
failBackgroundOpenCodeRequest("Failed to parse response: " + parseResponseError);
}
requestFinalized = true;
};
xhr.onerror = function() {
failBackgroundOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.");
};
try {
let finalContent = injectMemoriesToUserMessage(messageText, chatId);
xhr.send(JSON.stringify({
"role": "user",
"content": finalContent,
"stream": false
}));
} catch (sendError) {
failBackgroundOpenCodeRequest("Failed to send message: " + sendError);
}
}, function(sessionErr) {
failBackgroundOpenCodeRequest(sessionErr);
});
}, function(serverErr) {
failBackgroundOpenCodeRequest(serverErr);
});
}



// ══════════════════════════════════════════════════════════════
// Scheduler functions (formerly MainScheduler.js)
// ══════════════════════════════════════════════════════════════


function handleScheduleCommand(messageText) {
scheduleCommandDialog.prefillMessage = messageText;
scheduleCommandDialog.chatId = root.currentSessionId;
scheduleCommandDialog.chatName = root.currentSessionTitle || "Current chat";
scheduleCommandDialog.open();
}


function toggleScheduleEnabled(schedId, newEnabled) {
let payload = {
"schedId": schedId,
"enabled": newEnabled
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " toggle_schedule " + Sec.rawShellSnippetQuote(b64Payload);
schedulerDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-toggle-" + Date.now());
// Update local schedulesList immediately
let copy = root.schedulesList.slice();
for (let i = 0; i < copy.length; i++) {
if (copy[i].id === schedId) {
let s = Object.assign({
}, copy[i]);
s.enabled = newEnabled;
if (newEnabled)
s.nextRunAt = "";
copy[i] = s;
}
}
root.schedulesList = copy;
root.appendSystemMessage(newEnabled ? "Schedule resumed successfully." : "Schedule paused successfully.");
}


function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
if (!chatId || !messageText)
return ;
// Switch to the correct session
let idx = sessionIndexById(chatId);
if (idx < 0) {
console.warn("injectScheduledMessage: Target session " + chatId + " not found, ignoring schedule execution.");
return ;
}
if (chatId !== root.currentSessionId) {
executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
return ;
}
// If KWallet mode is active and keys are not loaded yet, load them first.
if (!root.openCodeMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
loadKWalletKeysIfNeeded(
function onSuccess() {
injectScheduledMessage(chatId, messageText, notify, schedId, schedName);
},
function onFailure(err) {
let errMsg = "KWallet access failed: " + err;
pushErrorMessage(errMsg);
if (notify) {
let safeErr = Sec.sanitizeForShell(errMsg);
let errTitle = "Schedule Failed: " + (schedName || root.currentSessionTitle || "Chat");
let safeErrTitle = Sec.sanitizeForShell(errTitle);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
}
if (schedId) {
let historyPayload = {
"schedId": schedId,
"status": errMsg
};
let b64HistoryPayload = base64Encode(JSON.stringify(historyPayload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.rawShellSnippetQuote(b64HistoryPayload);
soundDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-history-err");
}
}
);
return ;
}
// Play the custom scheduled execution sound
let soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
// Validate provider/model configuration before executing
let validationError = validateCurrentSendTarget();
if (validationError !== "") {
// Push validation error into chat window
pushErrorMessage(validationError);
// Display critical desktop notification popup of the configuration failure
if (notify) {
let safeErr = Sec.sanitizeForShell(validationError);
let errTitle = "Schedule Failed: " + (schedName || root.currentSessionTitle || "Chat");
let safeErrTitle = Sec.sanitizeForShell(errTitle);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
}
// Sync the detailed failure back to the scheduler's run history log
if (schedId) {
let historyPayload = {
"schedId": schedId,
"status": validationError
};
let b64HistoryPayload = base64Encode(JSON.stringify(historyPayload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.rawShellSnippetQuote(b64HistoryPayload);
soundDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-history-err");
}
return ;
}
// Append user message
appendUserMessage(messageText, "user", [], true);
// Trigger LLM generation
sendMessageByIndex(root.messages.length - 1);
// Show a desktop notification
if (notify) {
let safeText = Sec.sanitizeForShell(messageText.substring(0, 150)) + (messageText.length > 150 ? "…" : "");
let title = "Scheduled: " + (root.currentSessionTitle || "Chat");
let safeTitle = Sec.sanitizeForShell(title);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify");
}
}


function executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName) {
// If KWallet mode is active and keys are not loaded yet, load them first.
if (!root.openCodeMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
loadKWalletKeysIfNeeded(
function onSuccess() {
executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
},
function onFailure(err) {
handleBackgroundError(chatId, "KWallet access failed: " + err, notify, schedId, schedName);
}
);
return ;
}
let soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
let validationError = validateCurrentSendTarget();
if (validationError !== "") {
handleBackgroundError(chatId, validationError, notify, schedId, schedName);
return ;
}
let userTs = Date.now();
let userMsgObj = {
"role": "user",
"content": messageText,
"time": nowTime(userTs),
"at": userTs,
"model": "",
"attachments": [],
"sc": true
};
appendMessageToSession(chatId, userMsgObj);
if (notify) {
let safeText = Sec.sanitizeForShell(messageText.substring(0, 150)) + (messageText.length > 150 ? "…" : "");
let sIdx = sessionIndexById(chatId);
let sTitle = (sIdx >= 0 && root.sessions[sIdx].title) ? root.sessions[sIdx].title : "Chat";
let title = "Scheduled: " + sTitle;
let safeTitle = Sec.sanitizeForShell(title);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify");
}
if (root.openCodeMode) {
doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName);
return ;
}
let provider = plasmoid.configuration.provider || "openai";
let providerCfg = getProviderConfig(provider);
if (providerCfg.type === "anthropic")
doBackgroundAnthropicRequest(chatId, providerCfg.apiKey, providerCfg.model, messageText, notify, schedId, schedName);
else
doBackgroundOpenAICompatRequest(chatId, providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model, messageText, notify, schedId, schedName);
}


function applyKWalletKeyToMemory(targetId, secretValue) {
let configKey = ProviderService.getApiKeyConfigKey(targetId);
if (configKey) {
plasmoid.configuration[configKey] = secretValue;
}
}


function triggerKWalletCallbacks(success, errorMsg) {
let successList = root.kwalletLoadSuccessCallbacks || [];
let failureList = root.kwalletLoadFailureCallbacks || [];
root.kwalletLoadSuccessCallbacks = [];
root.kwalletLoadFailureCallbacks = [];
root.kwalletLoading = false;
if (success) {
for (let i = 0; i < successList.length; i++) {
try {
successList[i]();
} catch(e) {
console.error("Error in KWallet success callback:", e);
}
}
} else {
for (let j = 0; j < failureList.length; j++) {
try {
failureList[j](errorMsg);
} catch(e) {
console.error("Error in KWallet failure callback:", e);
}
}
}
}


function loadKWalletKeysIfNeeded(onSuccess, onFailure) {
    if (root.openCodeMode) {
        if (typeof onSuccess === "function")
            onSuccess();
        return ;
    }
    if (plasmoid.configuration.keyStorageMode !== 2) {
if (typeof onSuccess === "function")
onSuccess();
return ;
}
if (root.kwalletKeysLoaded) {
if (typeof onSuccess === "function")
onSuccess();
return ;
}
if (typeof onSuccess === "function") {
root.kwalletLoadSuccessCallbacks.push(onSuccess);
}
if (typeof onFailure === "function") {
root.kwalletLoadFailureCallbacks.push(onFailure);
}
if (root.kwalletLoading) {
return ;
}
// kwalletPermanentlyFailed is set after 3 consecutive failures.
// No further automatic prompts are shown until the user clicks
// "Refresh from KWallet" which resets both this flag and kwalletOpenAttempts.
if (root.kwalletPermanentlyFailed) {
debugLog("[KAI-DEBUG] loadKWalletKeysIfNeeded: permanently failed, not retrying. User must click Refresh.");
triggerKWalletCallbacks(false, root.kwalletFailReason || "KWallet sync failed");
return ;
}
if (root.kwalletOpenAttempts >= 3) {
let reason = "KWallet sync failed (3 attempts). Please click 'Refresh from KWallet' in settings.";
debugLog("[KAI-DEBUG] loadKWalletKeysIfNeeded open attempts limit of 3 exceeded. Setting permanently failed.");
root.kwalletPermanentlyFailed = true;
root.kwalletFailReason = reason;
root.kwalletLoading = false;
triggerKWalletCallbacks(false, reason);
return ;
}
root.kwalletLoading = true;
let walletName = (plasmoid.configuration.kwalletName || "").trim() || "kdewallet";
kwalletStartupDs.connectSource(walletBulkReadCommand(walletName, root.configKwalletAutoPrompt) + " #kwallet-startup-load");
}
