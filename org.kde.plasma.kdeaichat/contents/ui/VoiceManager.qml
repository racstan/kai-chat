import QtQuick
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec

Item {
    id: root

    property bool isRecording: false
    property bool isPlaying: false
    property string playingText: ""
    property string currentPlayingChunk: ""
    property string statusText: ""
    property string lastRecognizedText: ""
    readonly property string defaultSttModel: "small"
    property string httpToken: ""
    property bool httpTokenRequestInProgress: false
    property string httpTokenRequestSource: ""
    property var pendingHttpCommands: []
    property var sttStatusXhr: null
    property var ttsStatusXhr: null
    
    // Config aliases for convenience
    property bool enabled: plasmoid.configuration.voiceEnabled || false
    property bool autoSend: plasmoid.configuration.voiceAutoSend !== undefined ? plasmoid.configuration.voiceAutoSend : true
    property bool ttsAuto: plasmoid.configuration.voiceTtsAuto || false
    onTtsAutoChanged: plasmoid.configuration.voiceTtsAuto = ttsAuto

    Component.onCompleted: {
        let isVoiceEnabled = plasmoid.configuration.voiceEnabled || false;
        let isTtsEnabled = plasmoid.configuration.voiceTtsEnabled || false;
        if (!isVoiceEnabled) {
            let killCmd = "systemctl --user disable --now kde-ai-stt.service 2>/dev/null; systemctl --user disable --now kde-ai-tts.service 2>/dev/null; pkill -f 'voice_helper.py --stt-server' 2>/dev/null; pkill -f 'voice_helper.py --tts-server' 2>/dev/null";
            voiceDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(killCmd) + " #startup-sync-voice-off-" + Date.now());
        } else if (!isTtsEnabled) {
            let killCmd = "systemctl --user disable --now kde-ai-tts.service 2>/dev/null; pkill -f 'voice_helper.py --tts-server' 2>/dev/null";
            voiceDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(killCmd) + " #startup-sync-tts-off-" + Date.now());
        }
    }
    
    signal textRecognized(string text)
    signal errorOccurred(string errorText)
    signal envChecked(var result)
    signal setupStatus(string status)

    Component.onDestruction: {
        try { if (root.sttStatusXhr) root.sttStatusXhr.abort(); } catch (e) {}
        try { if (root.ttsStatusXhr) root.ttsStatusXhr.abort(); } catch (e) {}
    }

    readonly property alias voiceDs: voiceDs

    P5Support.DataSource {
        id: voiceDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (stdout === "") {
                if (sourceName === root.httpTokenRequestSource)
                    root._fallbackPendingHttpCommands();
                return;
            }
            let lines = stdout.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (!line) continue;
                try {
                    let resp = JSON.parse(line);
                    handleResponse(resp, sourceName);
                } catch (e) {}
            }
        }
    }

    Timer {
        id: statusPoller
        interval: 300
        repeat: true
        running: root.isRecording || root.isPlaying
        onTriggered: {
            if (root.isRecording && !root.sttStatusXhr) {
                let xhr = new XMLHttpRequest();
                root.sttStatusXhr = xhr;
                xhr.open("GET", "http://127.0.0.1:9015/status", true);
                if (root.httpToken)
                    xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.httpToken);
                xhr.timeout = 2000;
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return;
                    if (root.sttStatusXhr === xhr) root.sttStatusXhr = null;
                    if (xhr.status === 200) {
                        try {
                            let resp = JSON.parse(xhr.responseText);
                            if (resp.status === "recording") {
                                root.statusText = "Recording... [" + (resp.stt_device ? resp.stt_device.toUpperCase() : "CPU") + "]";
                            } else if (resp.status === "transcribing") {
                                root.statusText = "Transcribing... [" + (resp.stt_device ? resp.stt_device.toUpperCase() : "CPU") + "]";
                            } else if (resp.status === "idle" && root.isRecording) {
                                // Likely finished or errored
                                if (resp.stt_result && (resp.stt_result.type === "stt_result" || resp.stt_result.type === "stt_error"))
                                    handleResponse(resp.stt_result, "http_poll");
                            }
                        } catch(e) {}
                    } else if (xhr.status === 401 || xhr.status === 403) {
                        root.httpToken = "";
                        root._requestHttpToken();
                    }
                };
                xhr.ontimeout = function() { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; };
                xhr.onerror = function() { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; };
                try { xhr.send(); } catch (e) { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; }
            }
            if (root.isPlaying && !root.ttsStatusXhr) {
                let xhr = new XMLHttpRequest();
                root.ttsStatusXhr = xhr;
                xhr.open("GET", "http://127.0.0.1:9016/status", true);
                if (root.httpToken)
                    xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.httpToken);
                xhr.timeout = 2000;
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return;
                    if (root.ttsStatusXhr === xhr) root.ttsStatusXhr = null;
                    if (xhr.status === 200) {
                        try {
                            let resp = JSON.parse(xhr.responseText);
                            if (resp.status === "playing") {
                                if (resp.chunk) root.currentPlayingChunk = resp.chunk;
                                root.statusText = "Reading aloud...";
                            } else if (resp.status === "synthesizing") {
                                root.currentPlayingChunk = "";
                                root.statusText = "Generating speech...";
                            } else if (resp.status === "idle" && root.isPlaying) {
                                if (resp.tts_result && (resp.tts_result.type === "tts_error" || resp.tts_result.type === "error"))
                                    handleResponse(resp.tts_result, "http_poll");
                                else {
                                    root.isPlaying = false;
                                    root.currentPlayingChunk = "";
                                    root.statusText = "";
                                }
                            }
                        } catch(e) {}
                    } else if (xhr.status === 401 || xhr.status === 403) {
                        root.httpToken = "";
                        root._requestHttpToken();
                    }
                };
                xhr.ontimeout = function() { if (root.ttsStatusXhr === xhr) root.ttsStatusXhr = null; };
                xhr.onerror = function() { if (root.ttsStatusXhr === xhr) root.ttsStatusXhr = null; };
                try { xhr.send(); } catch (e) { if (root.ttsStatusXhr === xhr) root.ttsStatusXhr = null; }
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 2500
        repeat: false
        property var retryQueue: []
        onTriggered: {
            var queue = retryQueue || [];
            if (queue.length === 0)
                return;
            var item = queue.shift();
            retryQueue = queue;
            sendHttpCommand(item.payload, item.port, item.retries + 1);
            if (queue.length > 0)
                restart();
        }
    }

    function handleResponse(resp, sourceName) {
        if (resp.type === "voice_token") {
            if (sourceName !== root.httpTokenRequestSource)
                return;
            root.httpToken = String(resp.token || "");
            root.httpTokenRequestInProgress = false;
            root.httpTokenRequestSource = "";
            if (!root.httpToken) {
                root._fallbackPendingHttpCommands();
                return;
            }
            let queued = root.pendingHttpCommands || [];
            root.pendingHttpCommands = [];
            for (let i = 0; i < queued.length; i++)
                root._sendHttpCommandNow(queued[i].payload, queued[i].port, queued[i].retries);
        } else if (sourceName === root.httpTokenRequestSource) {
            root._fallbackPendingHttpCommands();
        } else if (resp.type === "env_check") {
            root.envChecked(resp);
        } else if (resp.type === "setup_status") {
            root.setupStatus(resp.status);
        } else if (resp.type === "stt_status") {
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            if (resp.status === "loading_model") root.statusText = "Loading model..." + devTag;
            else if (resp.status === "recording") root.statusText = "Listening..." + devTag;
            else if (resp.status === "transcribing") root.statusText = "Transcribing..." + devTag;
        } else if (resp.type === "stt_result") {
            root.isRecording = false;
            root.statusText = "";
            root.lastRecognizedText = resp.text || "";
            if (root.lastRecognizedText) {
                root.textRecognized(root.lastRecognizedText);
            }
        } else if (resp.type === "stt_error") {
            root.isRecording = false;
            root.statusText = "";
            root.errorOccurred(resp.error || "Unknown STT error");
        } else if (resp.type === "tts_done") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
        } else if (resp.type === "tts_error") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
            root.errorOccurred(resp.error || "Unknown TTS error");
        } else if (resp.type === "tts_status") {
            if (resp.status === "playing") {
                root.isPlaying = true;
                root.statusText = "Reading aloud...";
                if (resp.chunk) {
                    root.currentPlayingChunk = resp.chunk;
                }
            } else if (resp.status === "synthesizing") {
                root.isPlaying = true;
                root.statusText = "Generating speech...";
            } else if (resp.status === "stopping") {
                root.statusText = "";
            } else if (resp.status === "paused") {
                root.statusText = "Paused";
            }
        } else if (resp.type === "tts_started") {
            root.isPlaying = true;
            root.statusText = "Generating speech...";
        } else if (resp.type === "error") {
            root.isRecording = false;
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
            root.errorOccurred(resp.error || "Voice command failed");
        } else if (resp.type === "stt_started") {
            root.isRecording = true;
        } else if (resp.type === "stt_stopped") {
            root.isRecording = false;
            root.statusText = "";
        } else if (resp.type === "tts_stopped") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
        }
    }

    function getVenvPython() {
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = String(Qt.resolvedUrl("./voice/voice_helper.py"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base.endsWith("/contents/ui/voice/voice_helper.py") ? base : "";
    }

    function sendCommand(payload, tag) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let encoded = Sec.base64Encode(payload || "");
        let safeVenvPy = venvPy.startsWith("~/") ? '"$HOME"' + Sec.quoteForShell(venvPy.substring(1)) : Sec.quoteForShell(venvPy);
        let encodedArg = Sec.rawShellSnippetQuote(encoded);
        let cmd = "if [ -f " + safeVenvPy + " ]; then " + safeVenvPy + " " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; else python3 " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; fi";
        let source = "timeout 90s sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-" + (tag || "cmd") + "-" + Date.now();
        voiceDs.connectSource(source);
        return source;
    }

    function _fallbackPendingHttpCommands() {
        let queued = root.pendingHttpCommands || [];
        root.pendingHttpCommands = [];
        root.httpTokenRequestInProgress = false;
        root.httpTokenRequestSource = "";
        for (let i = 0; i < queued.length; i++)
            sendCommand(queued[i].payload);
    }

    function _requestHttpToken() {
        if (root.httpTokenRequestInProgress)
            return;
        root.httpTokenRequestInProgress = true;
        root.httpTokenRequestSource = sendCommand(JSON.stringify({cmd: "get_http_token"}), "token");
    }

    function _sendHttpCommandNow(payload, port, retries) {
        if (retries === undefined) retries = 0;
        let xhr = new XMLHttpRequest();
        let completed = false;
        let retryOrFallback = function() {
            if (completed) return;
            completed = true;
            if (retries < 2) {
                let serviceName = (port === 9015) ? "kde-ai-stt.service" : "kde-ai-tts.service";
                voiceDs.connectSource("systemctl --user start " + serviceName + " #start-" + Date.now());
                var retryQueue = retryTimer.retryQueue || [];
                retryQueue.push({"payload": payload, "port": port, "retries": retries});
                retryTimer.retryQueue = retryQueue;
                if (!retryTimer.running)
                    retryTimer.start();
            } else {
                sendCommand(payload);
            }
        };
        try {
            xhr.open("POST", "http://127.0.0.1:" + port + "/command", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.httpToken);
            xhr.timeout = 300000; // 5 mins max
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || completed)
                    return;
                if (xhr.status === 200) {
                    completed = true;
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        handleResponse(resp, "http");
                    } catch (e) {}
                } else if (xhr.status === 401 || xhr.status === 403) {
                    completed = true;
                    root.httpToken = "";
                    root.pendingHttpCommands = (root.pendingHttpCommands || []).concat([{"payload": payload, "port": port, "retries": retries}]);
                    _requestHttpToken();
                } else {
                    retryOrFallback();
                }
            };
            xhr.ontimeout = retryOrFallback;
            xhr.onerror = retryOrFallback;
            xhr.send(payload);
        } catch (e) {
            retryOrFallback();
        }
    }

    function sendHttpCommand(payload, port, retries) {
        if (!root.httpToken) {
            root.pendingHttpCommands = (root.pendingHttpCommands || []).concat([{"payload": payload, "port": port, "retries": retries === undefined ? 0 : retries}]);
            _requestHttpToken();
            return;
        }
        _sendHttpCommandNow(payload, port, retries);
    }

    function checkEnv() {
        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
        sendCommand(JSON.stringify({
            cmd: "check_env", 
            stt_model_path: sttPath, 
            tts_model_path: ttsPath, 
            venv_path: plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv", 
            espeak_path: plasmoid.configuration.voiceEspeakPath || "",
            gpu_requested: plasmoid.configuration.voiceGpuEnabled || false
        }));
    }

    function runSetup() {
        let base = String(Qt.resolvedUrl("./voice/venv_setup.sh"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        let cmd = "NON_INTERACTIVE=1 bash " + Sec.quoteForShell(base) + " " + Sec.quoteForShell(venvPath);
        voiceDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-setup-" + Date.now());
    }

    function startRecording() {
        root.isRecording = true;
        root.statusText = "Recording...";
        let lang = plasmoid.configuration.voiceLanguage || "en";
        let model = plasmoid.configuration.voiceSttModel || root.defaultSttModel;
        let modelPath = plasmoid.configuration.voiceSttModelPath || "";
        let gpuReq = plasmoid.configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({cmd: "start_stt", duration: 0, language: lang, model: model, model_path: modelPath, gpu_requested: gpuReq}), 9015);
    }

    function stopRecording() {
        root.statusText = "Processing...";
        sendHttpCommand(JSON.stringify({cmd: "stop_stt"}), 9015);
    }


    function playTTS(text) {
        root.isPlaying = true;
        root.playingText = text;
        let voice = plasmoid.configuration.voiceTtsVoice || "";
        let modelPath = plasmoid.configuration.voiceTtsModelPath || "";
        let espeakPath = plasmoid.configuration.voiceEspeakPath || "";
        let gpuReq = plasmoid.configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({cmd: "tts", text: text, voice: voice, lang_code: "a", model_path: modelPath, espeak_path: espeakPath, gpu_requested: gpuReq}), 9016);
    }

    function stopTTS() {
        sendHttpCommand(JSON.stringify({cmd: "stop_tts"}), 9016);
        root.isPlaying = false;
        root.playingText = "";
    }
}
