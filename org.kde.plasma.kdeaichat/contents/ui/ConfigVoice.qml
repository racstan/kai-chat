import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec

KCM.SimpleKCM {
    id: page

    property bool voiceEnvChecked: false
    property var voiceEnvResult: null
    property bool voiceSetupRunning: false
    property int voiceSetupProgress: 0
    property bool sttTesting: false
    property bool ttsPlaying: false
    property string voiceSetupStatus: ""
    property string sttTestResult: ""
    property string ttsTestResult: ""
    property string activeSttSource: ""
    property string activeTtsSource: ""
    property string activeCheckSource: ""

    readonly property bool hasPlasmoidConfig: typeof plasmoid !== 'undefined' && plasmoid !== null && plasmoid.configuration !== undefined
    property bool cfg_showInteractiveGuides: hasPlasmoidConfig ? (plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true) : true
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceGpuEnabled: voiceGpuToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceTtsAuto: voiceTtsAutoToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked
    property alias cfg_voiceSttModelPath: sttPathField.text
    property alias cfg_voiceTtsModelPath: ttsPathField.text
    property alias cfg_voiceLanguage: sttLanguageBox.currentValue
    property alias cfg_voiceTtsVoice: ttsVoiceField.text
    property alias cfg_voiceVenvPath: enginePathField.text

    function resetToDefaults() {
        voiceEnabledToggle.checked = false;
        voiceGpuToggle.checked = false;
        voiceTtsEnabledToggle.checked = false;
        voiceTtsAutoToggle.checked = false;
        voiceAutoSendToggle.checked = true;
        sttLanguageBox.currentValue = "en";
        sttPathField.text = "";
        ttsPathField.text = "";
        ttsVoiceField.text = "";
        enginePathField.text = "~/.local/share/kdeaichat/venv";
    }

    P5Support.DataSource {
        id: voicePageDs
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            let stderr = (data["stderr"] || "").trim();
            disconnectSource(sourceName);
            clearWatchdogForSource(sourceName);

            if (stdout === "") {
                if (stderr !== "") {
                    voiceSetupRunning = false;
                    sttTesting = false;
                    ttsPlaying = false;
                    voiceSetupStatus = stderr.split("\n").slice(-3).join("\n");
                } else if (sourceName === activeCheckSource) {
                    activeCheckSource = "";
                    voiceSetupRunning = false;
                    voiceSetupStatus = i18n("Status check returned no data. Repair the engine, then check again.");
                } else if (sourceName === activeSttSource) {
                    activeSttSource = "";
                    sttTesting = false;
                    sttTestResult = i18n("STT returned no data. Check the selected STT folder and engine status.");
                } else if (sourceName === activeTtsSource) {
                    activeTtsSource = "";
                    ttsPlaying = false;
                    ttsTestResult = i18n("TTS returned no data. Check the selected TTS folder, voice name, and engine status.");
                }
                return;
            }

            let lines = stdout.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (!line) continue;
                try {
                    handleVoicePageResponse(JSON.parse(line), sourceName);
                } catch (e) {
                }
            }
        }
    }

    function handleVoicePageResponse(resp, sourceName) {
        if (!resp.type) {
            if (sourceName === activeCheckSource) {
                activeCheckSource = "";
                voiceSetupRunning = false;
                voiceSetupStatus = i18n("Status check did not start the voice helper. Repair the engine, then check again.");
            } else if (sourceName === activeSttSource) {
                activeSttSource = "";
                sttTesting = false;
                sttTestResult = i18n("STT helper did not start. Repair the engine, then test again.");
            } else if (sourceName === activeTtsSource) {
                activeTtsSource = "";
                ttsPlaying = false;
                ttsTestResult = i18n("TTS helper did not start. Repair the engine, then test again.");
            }
            return;
        }
        if (sourceName === activeCheckSource && resp.type === "env_check") activeCheckSource = "";
        if (sourceName === activeSttSource && (resp.type === "stt_result" || resp.type === "stt_error")) activeSttSource = "";
        if (sourceName === activeTtsSource && (resp.type === "tts_done" || resp.type === "tts_error")) activeTtsSource = "";
        if (resp.type === "env_check") {
            voiceEnvResult = resp;
            voiceEnvChecked = true;
            voiceSetupRunning = false;
            voiceSetupStatus = voiceReady() ? i18n("Ready. Voice input and read-aloud can use the selected folders.") : explainEnvProblem(resp);
        } else if (resp.type === "setup_status") {
            if (resp.percent !== undefined) {
                voiceSetupProgress = resp.percent;
            }
            if (resp.status === "creating_venv") {
                voiceSetupStatus = i18n("Creating voice engine...");
            } else if (resp.status === "upgrading_pip") {
                voiceSetupStatus = i18n("Preparing Python packages...");
            } else if (resp.status === "installing_pytorch") {
                voiceSetupStatus = i18n("Installing speech runtime...");
            } else if (resp.status === "installing_spacy") {
                voiceSetupStatus = i18n("Installing NLP packages...");
            } else if (resp.status === "installing_dependencies") {
                voiceSetupStatus = i18n("Installing STT/TTS support packages...");
            } else if (resp.status === "installing_kokoro") {
                voiceSetupStatus = i18n("Installing text-to-speech support...");
            } else if (resp.status === "done") {
                voiceSetupStatus = i18n("Engine ready. Rechecking folders...");
                runEnvCheck();
            }
        } else if (resp.type === "setup_error" || resp.type === "error") {
            voiceSetupRunning = false;
            sttTesting = false;
            ttsPlaying = false;
            voiceSetupStatus = resp.error || i18n("Voice engine setup failed.");
        } else if (resp.type === "stt_status") {
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            if (resp.status === "loading_model") sttTestResult = i18n("Loading STT model...") + devTag;
            else if (resp.status === "recording") sttTestResult = i18n("Recording. Speak now...") + devTag;
            else if (resp.status === "transcribing") sttTestResult = i18n("Transcribing...") + devTag;
        } else if (resp.type === "stt_result") {
            sttTesting = false;
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            sttTestResult = resp.text && resp.text.length > 0 ? resp.text + devTag : i18n("No speech detected.") + devTag;
        } else if (resp.type === "stt_error") {
            sttTesting = false;
            sttTestResult = i18n("STT error: ") + (resp.error || i18n("Unknown error"));
        } else if (resp.type === "tts_status") {
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            if (resp.status === "synthesizing") ttsTestResult = i18n("Creating speech...") + devTag;
            else if (resp.status === "playing") {
                ttsPlaying = true;
                ttsTestResult = i18n("Playing test audio...") + devTag;
            }
        } else if (resp.type === "tts_done") {
            ttsPlaying = false;
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            ttsTestResult = i18n("TTS test finished.") + devTag;
        } else if (resp.type === "tts_error") {
            ttsPlaying = false;
            ttsTestResult = i18n("TTS error: ") + (resp.error || i18n("Unknown error"));
        }
    }

    function getVenvPath() {
        return hasPlasmoidConfig ? (plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv") : "~/.local/share/kdeaichat/venv";
    }

    function getVenvPython() {
        return getVenvPath() + "/bin/python3";
    }

    function getHelperPath() {
        let base = String(Qt.resolvedUrl("./voice/voice_helper.py"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base.endsWith("/contents/ui/voice/voice_helper.py") ? base : "";
    }

    function getSetupPath() {
        let base = String(Qt.resolvedUrl("./voice/venv_setup.sh"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base.endsWith("/contents/ui/voice/venv_setup.sh") ? base : "";
    }

    function getSystemHelperPath() {
        let base = String(Qt.resolvedUrl("./kde_ai_helper.py"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base.endsWith("/contents/ui/kde_ai_helper.py") ? base : "";
    }

    function installVoiceServices() {
        let helperPath = getSystemHelperPath();
        if (!helperPath)
            return;
        let servicePayload = JSON.stringify({
            "venvPy": getVenvPython(),
            "espeakPath": hasPlasmoidConfig ? (plasmoid.configuration.voiceEspeakPath || "") : "",
            "voiceEnabled": !!voiceEnabledToggle.checked,
            "voiceTtsEnabled": !!voiceTtsEnabledToggle.checked
        });
        let encoded = Sec.base64Encode(servicePayload);
        let venvPy = getVenvPython();
        let safeVenvPy = venvPy.startsWith("~/") ? '"$HOME"' + Sec.quoteForShell(venvPy.substring(1)) : Sec.quoteForShell(venvPy);
        let command = "if [ -f " + safeVenvPy + " ]; then python3 "
            + Sec.quoteForShell(helperPath) + " setup_venv_services " + Sec.rawShellSnippetQuote(encoded) + "; fi";
        voicePageDs.connectSource("timeout 30s sh -c " + Sec.rawShellSnippetQuote(command) + " #voice-services-" + Date.now());
    }

    function sendVoiceCommand(payload, tag) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let safeVenvPy = venvPy.startsWith("~/") ? '"$HOME"' + Sec.quoteForShell(venvPy.substring(1)) : Sec.quoteForShell(venvPy);
        let timeoutSeconds = tag === "check" ? 25 : (tag === "stt-test" ? 75 : 90);
        let encodedPayload = Sec.base64Encode(payload || "");
        let encodedArg = Sec.rawShellSnippetQuote(encodedPayload);
        let cmd = "if [ -f " + safeVenvPy + " ]; then " + safeVenvPy + " " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; else python3 " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; fi";
        let source = "timeout " + timeoutSeconds + "s sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-" + (tag || "cmd") + "-" + Date.now();
        voicePageDs.connectSource(source);
        return source;
    }

    function runEnvCheck() {
        voiceSetupRunning = true;
        voiceEnvChecked = false;
        voiceSetupStatus = firstSetupHint();
        let payload = JSON.stringify({
            cmd: "check_env",
            stt_model_path: sttPathField.text || "",
            tts_model_path: ttsPathField.text || "",
            venv_path: getVenvPath(),
            espeak_path: hasPlasmoidConfig ? (plasmoid.configuration.voiceEspeakPath || "") : "",
            gpu_requested: hasPlasmoidConfig ? (plasmoid.configuration.voiceGpuEnabled || false) : false
        });
        activeCheckSource = sendVoiceCommand(payload, "check");
        checkWatchdog.restart();
    }

    function runVoiceSetup() {
        voiceSetupRunning = true;
        voiceSetupProgress = 0;
        voiceSetupStatus = i18n("Preparing voice engine. This installs code support only; it does not download models.");
        let mode = voiceGpuToggle.checked ? "gpu" : "cpu";
        let setupPath = getSetupPath();
        let helperPath = getSystemHelperPath();
        if (!setupPath || !helperPath) {
            voiceSetupRunning = false;
            voiceSetupStatus = i18n("Voice setup files are unavailable.");
            return;
        }
        let servicePayload = JSON.stringify({
            "venvPy": getVenvPython(),
            "espeakPath": hasPlasmoidConfig ? (plasmoid.configuration.voiceEspeakPath || "") : "",
            "voiceEnabled": !!voiceEnabledToggle.checked,
            "voiceTtsEnabled": !!voiceTtsEnabledToggle.checked
        });
        let encodedServicePayload = Sec.base64Encode(servicePayload);
        let cmd = "NON_INTERACTIVE=1 bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(getVenvPath()) + " " + Sec.quoteForShell(mode)
            + " && python3 " + Sec.quoteForShell(helperPath) + " setup_venv_services " + Sec.rawShellSnippetQuote(encodedServicePayload);
        voicePageDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-setup-" + Date.now());
    }

    function sttReady() {
        return voiceEnvResult && voiceEnvResult.stt_ready;
    }

    function ttsReady() {
        return voiceEnvResult && voiceEnvResult.tts_ready;
    }

    function voiceReady() {
        return sttReady() && (!voiceTtsEnabledToggle.checked || ttsReady());
    }

    function repairNeeded() {
        if (!voiceEnvChecked || !voiceEnvResult) return false;
        if (!voiceEnvResult.venv_ready || !voiceEnvResult.faster_whisper_ok || !voiceEnvResult.sounddevice_ok) return true;
        if (voiceTtsEnabledToggle.checked && !voiceEnvResult.tts_ready) return true;
        if (voiceGpuToggle.checked && !voiceEnvResult.torch_cuda_version) return true;
        return false;
    }

    function cancelSttTest() {
        if (activeSttSource !== "") {
            voicePageDs.disconnectSource(activeSttSource);
            activeSttSource = "";
        }
        // The test may be running in a separate one-shot helper process. The
        // stop marker makes cancellation effective even after its UI source is
        // disconnected.
        sendVoiceCommand(JSON.stringify({cmd: "stop_stt"}), "stt-cancel");
        sttTesting = false;
        sttTestResult = i18n("Recording stopped.");
    }

    function cancelTtsTest() {
        if (activeTtsSource !== "") {
            voicePageDs.disconnectSource(activeTtsSource);
            activeTtsSource = "";
        }
        sendVoiceCommand(JSON.stringify({cmd: "stop_tts"}), "tts-cancel");
        ttsPlaying = false;
        ttsTestResult = i18n("Speech stopped.");
    }

    function clearWatchdogForSource(sourceName) {
        if (sourceName === activeCheckSource) checkWatchdog.stop();
        if (sourceName === activeSttSource) sttWatchdog.stop();
        if (sourceName === activeTtsSource) ttsWatchdog.stop();
    }

    function firstSetupHint() {
        return i18n("Checking folders, microphone, audio output, and engine packages. This should finish in under 30 seconds.");
    }

    function explainEnvProblem(resp) {
        if (!resp.stt_model_path_ok)
            return i18n("Not ready: STT folder is empty or does not contain recognizable model files.");
        if (!resp.venv_exists)
            return i18n("Not ready: voice engine folder is missing. Press Repair Engine.");
        if (!resp.sounddevice_ok || !resp.numpy_ok || !resp.faster_whisper_ok)
            return i18n("Not ready: speech engine packages are missing or broken. Press Repair Engine.");
        if (!resp.mic_available)
            return i18n("Not ready: no microphone was detected.");
        if (voiceTtsEnabledToggle.checked && !resp.tts_model_path_ok)
            return i18n("Not ready: TTS folder is empty or does not contain recognizable model files.");
        if (voiceTtsEnabledToggle.checked && !(resp.paplay_available || resp.aplay_available))
            return i18n("Not ready: no audio output player was found.");
        if (voiceTtsEnabledToggle.checked && !resp.tts_ready) {
            if (!resp.espeak_available && (resp.tts_model_type === "kokoro-82m" || resp.tts_model_type === "espeak-ng"))
                return i18n("Not ready: The selected TTS model requires 'espeak-ng' to be installed on your system.");
            return i18n("Not ready: selected TTS folder needs engine support. Press Repair Engine or choose a compatible folder.");
        }
        return i18n("Not ready. Check the rows below.");
    }

    Timer {
        id: checkWatchdog
        interval: 30000
        repeat: false
        onTriggered: {
            if (page.activeCheckSource !== "") {
                voicePageDs.disconnectSource(page.activeCheckSource);
                page.activeCheckSource = "";
                page.voiceSetupRunning = false;
                page.voiceSetupStatus = i18n("Status check timed out. The helper did not answer within 30 seconds. Repair the engine or select a smaller/local model folder.");
            }
        }
    }

    Timer {
        id: sttWatchdog
        interval: 80000
        repeat: false
        onTriggered: {
            if (page.activeSttSource !== "") {
                voicePageDs.disconnectSource(page.activeSttSource);
                page.activeSttSource = "";
                page.sttTesting = false;
                page.sttTestResult = i18n("STT test timed out. Check microphone permission, selected STT folder, and engine status.");
            }
        }
    }

    Timer {
        id: ttsWatchdog
        interval: 95000
        repeat: false
        onTriggered: {
            if (page.activeTtsSource !== "") {
                voicePageDs.disconnectSource(page.activeTtsSource);
                page.activeTtsSource = "";
                page.ttsPlaying = false;
                page.ttsTestResult = i18n("TTS test timed out. Check the selected TTS folder, voice name, audio output, and engine status.");
            }
        }
    }

    function statusText(ok, goodText, badText) {
        return ok ? "✓ " + goodText : "✗ " + badText;
    }

    FolderDialog {
        id: sttFolderDialog
        title: i18n("Select STT Model Folder")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7));
            sttPathField.text = path;
            if (hasPlasmoidConfig) plasmoid.configuration.voiceSttModelPath = path;
            runEnvCheck();
        }
    }

    FolderDialog {
        id: ttsFolderDialog
        title: i18n("Select TTS Model Folder")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7));
            ttsPathField.text = path;
            if (hasPlasmoidConfig) plasmoid.configuration.voiceTtsModelPath = path;
            runEnvCheck();
        }
    }

    Kirigami.FormLayout {
        id: formLayout
        width: page.width || 500
        wideMode: false
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 36

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Voice (Beta)")
        }

        Rectangle {
            visible: page.cfg_showInteractiveGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: introGuide.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: introGuide
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.4
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: i18n("<b>First-time Setup Guide (Beta):</b><br>1. Click the 'Readme Guide' button below for full instructions.<br>2. Click <b>Repair Engine</b> to install dependencies.<br>3. To automatically download the default models, simply leave the STT and TTS folder paths empty.<br>4. If you already have models (Faster Whisper, Kokoro, Piper), you can browse and select their folders.<br>5. Click <b>Check &amp; Test</b> to verify everything works.<br><b>Note: Currently, voice mode only supports NVIDIA GPUs. AMD and other GPU architectures are not supported.</b>")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth

            QQC2.Button {
                text: i18n("Readme Guide")
                icon.name: "help-contextual"
                onClicked: Qt.openUrlExternally("https://github.com/racstan/KDE-AI-Chat/blob/master/VOICE_SETUP.md")
            }
        }

        QQC2.CheckBox {
            id: voiceEnabledToggle
            Kirigami.FormData.label: i18n("Voice:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: hasPlasmoidConfig ? (plasmoid.configuration.voiceEnabled || false) : false
            text: checked ? i18n("Enabled") : i18n("Disabled")
            onToggled: {
                if (hasPlasmoidConfig) plasmoid.configuration.voiceEnabled = checked;
                if (checked) {
                    installVoiceServices();
                    runEnvCheck();
                } else {
                    let killCmd = "systemctl --user disable --now kde-ai-stt.service 2>/dev/null; systemctl --user disable --now kde-ai-tts.service 2>/dev/null; pkill -f 'voice_helper.py --stt-server' 2>/dev/null; pkill -f 'voice_helper.py --tts-server' 2>/dev/null";
                    voicePageDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(killCmd) + " #kill-voice-" + Date.now());
                }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Voice:</b> Enables the microphone button in chat. It does not download or choose models for you.")
        }


        QQC2.CheckBox {
            id: voiceGpuToggle
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("GPU Usage (NVIDIA only):")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            text: checked ? i18n("Enabled (CUDA)") : i18n("Disabled (CPU only)")
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>GPU Usage:</b> Enables CUDA hardware acceleration. <b>Note: Currently only NVIDIA GPU (CUDA) is supported. AMD and other GPU architectures are not supported.</b> Turning this on requires you to press <b>Repair Engine</b> below to install the heavy CUDA packages (~3GB). Turn off if your device doesn't have an NVIDIA GPU.")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("STT folder:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: sttPathField
                Layout.fillWidth: true
                text: hasPlasmoidConfig ? (plasmoid.configuration.voiceSttModelPath || "") : ""
                placeholderText: i18n("Select an STT model folder")
                onEditingFinished: {
                    if (hasPlasmoidConfig) plasmoid.configuration.voiceSttModelPath = text;
                    runEnvCheck();
                }
            }

            QQC2.Button {
                icon.name: "folder-open"
                text: i18n("Browse")
                onClicked: sttFolderDialog.open()
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>STT folder:</b> Pick the folder that contains your speech-to-text model files.")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Language:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth

            QQC2.ComboBox {
                id: sttLanguageBox
                Layout.fillWidth: true
                textRole: "text"
                valueRole: "value"
                model: [
                    { text: i18n("Auto detect"), value: "auto" },
                    { text: i18n("English"), value: "en" },
                    { text: i18n("Hindi"), value: "hi" },
                    { text: i18n("Spanish"), value: "es" },
                    { text: i18n("French"), value: "fr" },
                    { text: i18n("German"), value: "de" },
                    { text: i18n("Japanese"), value: "ja" },
                    { text: i18n("Korean"), value: "ko" },
                    { text: i18n("Chinese"), value: "zh" }
                ]
                Component.onCompleted: {
                    let current = hasPlasmoidConfig ? (plasmoid.configuration.voiceLanguage || "auto") : "auto";
                    for (let i = 0; i < model.length; i++) {
                        if (model[i].value === current) {
                            currentIndex = i;
                            return;
                        }
                    }
                    currentIndex = 0;
                }
                onActivated: { if (hasPlasmoidConfig) plasmoid.configuration.voiceLanguage = currentValue; }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Language:</b> Use Auto for multilingual models. Use English for English-only models.")
        }

        QQC2.CheckBox {
            id: voiceTtsEnabledToggle
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Read aloud:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: hasPlasmoidConfig ? (plasmoid.configuration.voiceTtsEnabled || false) : false
            text: checked ? i18n("Enabled") : i18n("Disabled")
            onCheckedChanged: {
                if (hasPlasmoidConfig) plasmoid.configuration.voiceTtsEnabled = checked;
                if (checked && voiceEnabledToggle.checked) {
                    installVoiceServices();
                } else if (!checked) {
                    let killCmd = "systemctl --user disable --now kde-ai-tts.service 2>/dev/null; pkill -f 'voice_helper.py --tts-server' 2>/dev/null";
                    voicePageDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(killCmd) + " #kill-tts-" + Date.now());
                }
                if (voiceEnabledToggle.checked) runEnvCheck();
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Read aloud:</b> Enables text-to-speech. Leave it off if you only want microphone input.")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("TTS folder:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: ttsPathField
                Layout.fillWidth: true
                text: hasPlasmoidConfig ? (plasmoid.configuration.voiceTtsModelPath || "") : ""
                placeholderText: i18n("Select a TTS model folder")
                onEditingFinished: {
                    if (hasPlasmoidConfig) plasmoid.configuration.voiceTtsModelPath = text;
                    runEnvCheck();
                }
            }

            QQC2.Button {
                icon.name: "folder-open"
                text: i18n("Browse")
                onClicked: ttsFolderDialog.open()
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>TTS folder:</b> Pick the folder that contains your text-to-speech model files.")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("Voice name:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth

            QQC2.TextField {
                id: ttsVoiceField
                Layout.fillWidth: true
                text: hasPlasmoidConfig ? (plasmoid.configuration.voiceTtsVoice || "") : ""
                placeholderText: i18n("Voice id or name")
                onEditingFinished: { if (hasPlasmoidConfig) plasmoid.configuration.voiceTtsVoice = text; }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Voice name:</b> Use the voice id expected by the selected TTS model. If the model has voice files, use the file name without its extension.")
        }

        QQC2.CheckBox {
            id: voiceTtsAutoToggle
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("Auto read:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: hasPlasmoidConfig ? (plasmoid.configuration.voiceTtsAuto || false) : false
            text: checked ? i18n("Speak every AI reply") : i18n("Manual only")
            onCheckedChanged: { if (hasPlasmoidConfig) plasmoid.configuration.voiceTtsAuto = checked; }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Auto read:</b> Turn this on only if every AI response should be spoken automatically.")
        }

        QQC2.CheckBox {
            id: voiceAutoSendToggle
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Auto-send:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: hasPlasmoidConfig ? (plasmoid.configuration.voiceAutoSend !== undefined ? plasmoid.configuration.voiceAutoSend : true) : true
            text: checked ? i18n("Send transcript immediately") : i18n("Put transcript in the input box")
            onCheckedChanged: { if (hasPlasmoidConfig) plasmoid.configuration.voiceAutoSend = checked; }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Auto-send:</b> Keep on for hands-free chat. Turn off if you want to edit the transcript before sending.")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Status:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                visible: voiceSetupRunning
                running: voiceSetupRunning
                Layout.preferredWidth: Kirigami.Units.gridUnit
                Layout.preferredHeight: Kirigami.Units.gridUnit
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: voiceSetupStatus || i18n("Select folders, then check status.")
                    color: voiceReady() ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                }

                QQC2.ProgressBar {
                    visible: voiceSetupRunning && voiceSetupProgress > 0
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: voiceSetupProgress
                }
            }

            QQC2.Button {
                text: i18n("Check")
                icon.name: "view-refresh"
                onClicked: runEnvCheck()
            }

            QQC2.Button {
                text: i18n("Repair Engine")
                icon.name: "tools-wizard"
                visible: repairNeeded()
                enabled: !voiceSetupRunning
                onClicked: runVoiceSetup()
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("Check validates folders, microphone, audio output, and required packages. Repair Engine appears only when package support is missing or broken.")
        }

        Rectangle {
            visible: voiceEnabledToggle.checked && voiceEnvChecked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: statusGrid.implicitHeight + Kirigami.Units.gridUnit
            radius: 4
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
            border.width: 1

            GridLayout {
                id: statusGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: Kirigami.Units.gridUnit * 0.5
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                rowSpacing: Kirigami.Units.smallSpacing * 0.5

                QQC2.Label { text: i18n("STT folder:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: statusText(page.voiceEnvResult && page.voiceEnvResult.stt_model_path_ok, i18n("Valid"), i18n("Invalid or empty"))
                    color: page.voiceEnvResult && page.voiceEnvResult.stt_model_path_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("STT engine:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: statusText(page.voiceEnvResult && page.voiceEnvResult.faster_whisper_ok && page.voiceEnvResult.sounddevice_ok, i18n("Ready"), i18n("Repair engine"))
                    color: page.voiceEnvResult && page.voiceEnvResult.faster_whisper_ok && page.voiceEnvResult.sounddevice_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("TTS folder:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: voiceTtsEnabledToggle.checked ? statusText(page.voiceEnvResult && page.voiceEnvResult.tts_model_path_ok, i18n("Valid"), i18n("Invalid or empty")) : i18n("Disabled")
                    color: !voiceTtsEnabledToggle.checked || (page.voiceEnvResult && page.voiceEnvResult.tts_model_path_ok) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("TTS engine:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: voiceTtsEnabledToggle.checked ? statusText(page.voiceEnvResult && page.voiceEnvResult.tts_ready, i18n("Ready"), (page.voiceEnvResult && !page.voiceEnvResult.espeak_available && (page.voiceEnvResult.tts_model_type === "kokoro-82m" || page.voiceEnvResult.tts_model_type === "espeak-ng") ? i18n("espeak-ng missing") : i18n("Repair engine"))) : i18n("Disabled")
                    color: !voiceTtsEnabledToggle.checked || (page.voiceEnvResult && page.voiceEnvResult.tts_ready) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label {
                    visible: voiceTtsEnabledToggle.checked && page.voiceEnvResult && !page.voiceEnvResult.tts_ready && !page.voiceEnvResult.espeak_available && (page.voiceEnvResult.tts_model_type === "kokoro-82m" || page.voiceEnvResult.tts_model_type === "espeak-ng")
                    text: i18n("Install espeak-ng:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                RowLayout {
                    visible: voiceTtsEnabledToggle.checked && page.voiceEnvResult && !page.voiceEnvResult.tts_ready && !page.voiceEnvResult.espeak_available && (page.voiceEnvResult.tts_model_type === "kokoro-82m" || page.voiceEnvResult.tts_model_type === "espeak-ng")
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.TextField {
                        id: espeakInstallCommand
                        text: "sudo apt install espeak-ng"
                        readOnly: true
                        Layout.fillWidth: true
                        
                        P5Support.DataSource {
                            engine: "executable"
                            connectedSources: ["command -v dnf >/dev/null && echo 'dnf' || (command -v pacman >/dev/null && echo 'pacman' || echo 'apt')"]
                            onNewData: function(sourceName, data) {
                                let pm = (data["stdout"] || "").trim();
                                if (pm === "dnf") espeakInstallCommand.text = "sudo dnf install espeak-ng";
                                else if (pm === "pacman") espeakInstallCommand.text = "sudo pacman -S espeak-ng";
                                disconnectSource(sourceName);
                            }
                        }
                    }
                }
                
                QQC2.Label { text: i18n("Virtual env:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: statusText(page.voiceEnvResult && page.voiceEnvResult.venv_ready, i18n("Configured"), page.voiceEnvResult && page.voiceEnvResult.venv_exists ? i18n("Broken/Missing Libs") : i18n("Not created"))
                    color: page.voiceEnvResult && page.voiceEnvResult.venv_ready ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                
                QQC2.Label { text: i18n("GPU mode:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: (hasPlasmoidConfig && plasmoid.configuration.voiceGpuEnabled) ? i18n("Enabled (CUDA)") : i18n("Disabled")
                    color: (hasPlasmoidConfig && plasmoid.configuration.voiceGpuEnabled) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                
                QQC2.Label { text: i18n("GPU libraries:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && page.voiceEnvResult.torch_cuda_version ? "✓ " + i18n("Installed (CUDA %1)", page.voiceEnvResult.torch_cuda_version) : "✗ " + i18n("Missing")
                    color: page.voiceEnvResult && page.voiceEnvResult.torch_cuda_version ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("Microphone:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: statusText(page.voiceEnvResult && page.voiceEnvResult.mic_available, i18n("Available"), i18n("Not found"))
                    color: page.voiceEnvResult && page.voiceEnvResult.mic_available ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("Audio output:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: statusText(page.voiceEnvResult && (page.voiceEnvResult.paplay_available || page.voiceEnvResult.aplay_available), i18n("Available"), i18n("Not found"))
                    color: page.voiceEnvResult && (page.voiceEnvResult.paplay_available || page.voiceEnvResult.aplay_available) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Test STT:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: page.sttTesting ? i18n("Stop") : i18n("Record 5 sec")
                icon.name: page.sttTesting ? "media-playback-stop" : "audio-input-microphone"
                enabled: page.sttTesting || !page.ttsPlaying
                onClicked: {
                    if (page.sttTesting) {
                        page.cancelSttTest();
                        return;
                    }
                    page.sttTesting = true;
                    page.sttTestResult = i18n("Loading STT model...");
                    page.activeSttSource = sendVoiceCommand(JSON.stringify({
                        cmd: "start_stt",
                        duration: 5,
                        language: sttLanguageBox.currentValue || "auto",
                        model_path: sttPathField.text || "",
                        gpu_requested: voiceGpuToggle.checked
                    }), "stt-test");
                    sttWatchdog.restart();
                }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Test STT:</b> Records five seconds, transcribes it, and shows the text below.")
        }

        QQC2.Label {
            visible: voiceEnabledToggle.checked && page.sttTestResult.length > 0
            Kirigami.FormData.label: i18n("Transcript:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            text: page.sttTestResult
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("Test TTS:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: page.ttsPlaying ? i18n("Stop") : i18n("Speak")
                icon.name: page.ttsPlaying ? "media-playback-stop" : "audio-speakers"
                enabled: page.ttsPlaying || !page.sttTesting
                onClicked: {
                    if (page.ttsPlaying) {
                        page.cancelTtsTest();
                        return;
                    }
                    page.ttsPlaying = true;
                    page.ttsTestResult = i18n("Creating speech...");
                    page.activeTtsSource = sendVoiceCommand(JSON.stringify({
                        cmd: "tts",
                        text: i18n("Voice setup is ready."),
                        voice: ttsVoiceField.text || "",
                        lang_code: "a",
                        model_path: ttsPathField.text || "",
                        espeak_path: hasPlasmoidConfig ? (plasmoid.configuration.voiceEspeakPath || "") : "",
                        gpu_requested: voiceGpuToggle.checked
                    }), "tts-test");
                    ttsWatchdog.restart();
                }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Test TTS:</b> Speaks a short sentence with the selected TTS folder and voice name.")
        }

        QQC2.Label {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked && page.ttsTestResult.length > 0
            Kirigami.FormData.label: i18n("TTS result:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            text: page.ttsTestResult
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Engine folder:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth

            QQC2.TextField {
                id: enginePathField
                Layout.fillWidth: true
                text: hasPlasmoidConfig ? (plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv") : "~/.local/share/kdeaichat/venv"
                onEditingFinished: {
                    if (hasPlasmoidConfig) plasmoid.configuration.voiceVenvPath = text;
                    runEnvCheck();
                }
            }
        }

        QQC2.Label {
            visible: page.cfg_showInteractiveGuides && voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: i18n("<b>Engine folder:</b> Stores the small Python environment used to run your selected models. This is not a model folder.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Advanced")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Reset settings:")
            text: i18n("Reset to defaults")
            onClicked: page.resetToDefaults()
        }
    }
}
