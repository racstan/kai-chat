import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support 2.0 as P5Support

import "api.js" as Api

KCM.SimpleKCM {
    id: configPage

    property alias cfg_sysInfoOS: sysInfoOSCheck.checked
    property alias cfg_sysInfoShell: sysInfoShellCheck.checked
    property alias cfg_sysInfoHostname: sysInfoHostnameCheck.checked
    property alias cfg_sysInfoKernel: sysInfoKernelCheck.checked
    property alias cfg_sysInfoDesktop: sysInfoDesktopCheck.checked
    property alias cfg_sysInfoUser: sysInfoUserCheck.checked
    property alias cfg_sysInfoCPU: sysInfoCPUCheck.checked
    property alias cfg_sysInfoMemory: sysInfoMemoryCheck.checked
    property alias cfg_sysInfoGPU: sysInfoGPUCheck.checked
    property alias cfg_sysInfoDisk: sysInfoDiskCheck.checked
    property alias cfg_sysInfoNetwork: sysInfoNetworkCheck.checked
    property alias cfg_sysInfoLocale: sysInfoLocaleCheck.checked
    property alias cfg_sysInfoDateTime: sysInfoDateTimeCheck.checked
    property alias cfg_systemPrompt: customPromptArea.text
    property alias cfg_enableSystemPrompt: enableSystemPromptCheck.checked
    property alias cfg_enableMemory: enableMemoryCheck.checked
    property alias cfg_userMemory: userMemoryArea.text

    property alias cfg_contextMessageLimit: contextMessageLimitField.value
    property alias cfg_enableCompactingContext: enableCompactingContextCheck.checked
    property alias cfg_compactContextAfter: compactContextAfterField.value

    readonly property bool showGuides: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true) : true

    property var sysInfo: ({})
    property int sysInfoPending: 0
    property var pendingSysInfoCommands: ({})

    function resetToDefaults() {
        sysInfoOSCheck.checked = false;
        sysInfoShellCheck.checked = false;
        sysInfoHostnameCheck.checked = false;
        sysInfoKernelCheck.checked = false;
        sysInfoDesktopCheck.checked = false;
        sysInfoUserCheck.checked = false;
        sysInfoCPUCheck.checked = false;
        sysInfoMemoryCheck.checked = false;
        sysInfoGPUCheck.checked = false;
        sysInfoDiskCheck.checked = false;
        sysInfoNetworkCheck.checked = false;
        sysInfoLocaleCheck.checked = false;
        sysInfoDateTimeCheck.checked = false;
        enableSystemPromptCheck.checked = true;
        customPromptArea.text = "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        enableMemoryCheck.checked = false;
        userMemoryArea.text = "";
        contextMessageLimitField.value = -1;
        enableCompactingContextCheck.checked = false;
        compactContextAfterField.value = 10;
    }

    function triggerPreviewUpdate() {
        var cmds = [];
        if (cfg_sysInfoOS)       cmds.push("cat /etc/os-release");
        if (cfg_sysInfoShell)    cmds.push("echo $SHELL");
        if (cfg_sysInfoHostname) cmds.push("hostname");
        if (cfg_sysInfoKernel)   cmds.push("uname -a");
        if (cfg_sysInfoDesktop)  cmds.push("echo $XDG_CURRENT_DESKTOP");
        if (cfg_sysInfoUser)     cmds.push("whoami");
        if (cfg_sysInfoCPU)      cmds.push("lscpu");
        if (cfg_sysInfoMemory)   cmds.push("free -h");
        if (cfg_sysInfoGPU)      cmds.push("bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"");
        if (cfg_sysInfoDisk)     cmds.push("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT");
        if (cfg_sysInfoNetwork)  cmds.push("ip -br addr show");
        if (cfg_sysInfoLocale)   cmds.push("echo $LANG");

        if (cmds.length === 0) {
            sysInfo = {};
            return;
        }

        var newPending = {};
        for (var i = 0; i < cmds.length; i++) {
            newPending[cmds[i]] = true;
            sysInfoDs.connectSource(cmds[i]);
        }
        pendingSysInfoCommands = newPending;
        sysInfoPending = cmds.length;
    }

    onCfg_sysInfoOSChanged: triggerPreviewUpdate()
    onCfg_sysInfoShellChanged: triggerPreviewUpdate()
    onCfg_sysInfoHostnameChanged: triggerPreviewUpdate()
    onCfg_sysInfoKernelChanged: triggerPreviewUpdate()
    onCfg_sysInfoDesktopChanged: triggerPreviewUpdate()
    onCfg_sysInfoUserChanged: triggerPreviewUpdate()
    onCfg_sysInfoCPUChanged: triggerPreviewUpdate()
    onCfg_sysInfoMemoryChanged: triggerPreviewUpdate()
    onCfg_sysInfoGPUChanged: triggerPreviewUpdate()
    onCfg_sysInfoDiskChanged: triggerPreviewUpdate()
    onCfg_sysInfoNetworkChanged: triggerPreviewUpdate()
    onCfg_sysInfoLocaleChanged: triggerPreviewUpdate()

    Component.onCompleted: triggerPreviewUpdate()

    P5Support.DataSource {
        id: sysInfoDs
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var output = data["stdout"] ? data["stdout"].trim() : "";
            if (pendingSysInfoCommands[source]) {
                var pending = pendingSysInfoCommands;
                delete pending[source];
                pendingSysInfoCommands = pending;

                var info = Object.assign({}, sysInfo);

                switch (source) {
                    case "hostname": info.hostname = output; break;
                    case "uname -a": info.kernel = output; break;
                    case "whoami": info.user = output; break;
                    case "echo $SHELL": info.shell = output; break;
                    case "cat /etc/os-release":
                        var lines = output.split("\\n");
                        for (var i = 0; i < lines.length; i++) {
                            if (lines[i].indexOf("PRETTY_NAME=") === 0) {
                                info.osRelease = lines[i].replace("PRETTY_NAME=", "").replace(/"/g, "");
                                break;
                            }
                        }
                        if (!info.osRelease) info.osRelease = output.substring(0, 100);
                        break;
                    case "echo $XDG_CURRENT_DESKTOP": info.desktop = output; break;
                    case "lscpu":
                        var cpuLines = output.split("\\n");
                        var cpuInfo = {};
                        for (var j = 0; j < cpuLines.length; j++) {
                            var parts = cpuLines[j].split(":");
                            if (parts.length >= 2) {
                                var key = parts[0].trim();
                                var val = parts.slice(1).join(":").trim();
                                if (["Model name", "CPU(s)", "Architecture", "Thread(s) per core", "Core(s) per socket"].indexOf(key) !== -1) {
                                    cpuInfo[key] = val;
                                }
                            }
                        }
                        info.cpu = cpuInfo["Model name"] || "unknown";
                        info.cpuCores = (cpuInfo["CPU(s)"] || "?") + " threads, " + (cpuInfo["Core(s) per socket"] || "?") + " cores";
                        info.cpuArch = cpuInfo["Architecture"] || "";
                        break;
                    case "free -h": info.memory = output; break;
                    case "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT": info.disk = output; break;
                    case "bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"": info.gpu = output || "unknown"; break;
                    case "ip -br addr show": info.network = output; break;
                    case "echo $LANG": info.locale = output; break;
                }

                sysInfo = info;
                sysInfoPending--;
                disconnectSource(source);
            }
        }
    }

    Kirigami.FormLayout {
        id: formLayout
        wideMode: false
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 35

        // ── System Prompt ─────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("System Prompt")
        }

        // Interactive guide
        Rectangle {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: sysPromptGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: sysPromptGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                    text: "<b>System Prompt</b> is injected before every conversation.<br>" +
                          "<b>System Info</b> automatically appends live system details.<br><br>" +
                          "<b>How to use:</b><br>" +
                          "1. <b>Enable</b> the system prompt below.<br>" +
                          "2. Write <b>custom instructions</b> (e.g. &quot;You are a helpful Linux assistant&quot;).<br>" +
                          "3. Toggle <b>System Info</b> fields to include live OS/CPU/memory data.<br>" +
                          "4. Check the <b>preview</b> to see the final prompt sent to the AI."
                }
            }
        }

        QQC2.CheckBox {
            id: enableSystemPromptCheck
            Kirigami.FormData.label: i18n("Enable system prompt:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            text: checked ? i18n("Enabled — instructions sent before every chat") : i18n("Disabled")
        }

        GridLayout {
            visible: enableSystemPromptCheck.checked
            Kirigami.FormData.label: i18n("System Info:")
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            QQC2.CheckBox { id: sysInfoOSCheck;        text: i18n("OS") }
            QQC2.CheckBox { id: sysInfoShellCheck;     text: i18n("Shell") }
            QQC2.CheckBox { id: sysInfoHostnameCheck;  text: i18n("Hostname") }
            QQC2.CheckBox { id: sysInfoKernelCheck;    text: i18n("Kernel") }
            QQC2.CheckBox { id: sysInfoDesktopCheck;   text: i18n("Desktop") }
            QQC2.CheckBox { id: sysInfoUserCheck;      text: i18n("User") }
            QQC2.CheckBox { id: sysInfoCPUCheck;       text: i18n("CPU") }
            QQC2.CheckBox { id: sysInfoMemoryCheck;    text: i18n("Memory") }
            QQC2.CheckBox { id: sysInfoGPUCheck;       text: i18n("GPU") }
            QQC2.CheckBox { id: sysInfoDiskCheck;      text: i18n("Block Devices") }
            QQC2.CheckBox { id: sysInfoNetworkCheck;   text: i18n("Network") }
            QQC2.CheckBox { id: sysInfoLocaleCheck;    text: i18n("Locale") }
            QQC2.CheckBox { id: sysInfoDateTimeCheck;  text: i18n("Date/Time") }
        }

        QQC2.ScrollView {
            id: customPromptScroll
            visible: enableSystemPromptCheck.checked
            Kirigami.FormData.label: i18n("Custom Instructions:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                id: customPromptArea
                maximumLength: 100000
                placeholderText: i18n("Additional instructions for the LLM…")
                wrapMode: Text.Wrap
                width: customPromptScroll.width
            }
        }

        QQC2.ScrollView {
            id: previewScroll
            visible: enableSystemPromptCheck.checked
            Kirigami.FormData.label: i18n("System Prompt Preview:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                readOnly: true
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: Api.buildSystemPrompt(configPage.sysInfo, configPage.cfg_systemPrompt, { sysInfoDateTime: configPage.cfg_sysInfoDateTime })
                width: previewScroll.width
            }
        }

        // ── Memory ───────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Memory")
        }

        Rectangle {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: memoryGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: memoryGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                    text: "<b>Memory Guide</b><br><br>" +
                          "The AI Memory block allows the assistant to 'remember' things across all your conversations.<br><br>" +
                          "• <b>Enable memory:</b> Turn this on to insert your memory block into the system prompt behind the scenes.<br>" +
                          "• <b>Memory Content:</b> You can write facts about yourself, preferences, or rules you want the AI to always know.<br>" +
                          "• Passwords and API keys can be securely referenced using the KWallet integration syntax."
                }
            }
        }

        QQC2.CheckBox {
            id: enableMemoryCheck
            Kirigami.FormData.label: i18n("Enable memory:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            text: checked ? i18n("Enabled — facts remembered across chats") : i18n("Disabled")
        }

        QQC2.ScrollView {
            id: userMemoryScroll
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: i18n("Memory Content:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                id: userMemoryArea
                maximumLength: 100000
                placeholderText: i18n("Facts or preferences you want the assistant to remember across all chats...")
                wrapMode: Text.Wrap
                width: userMemoryScroll.width
            }
        }

        QQC2.ScrollView {
            id: memoryPreviewScroll
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: i18n("Memory Preview:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: Kirigami.Units.gridUnit * 4
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            clip: true

            QQC2.TextArea {
                readOnly: true
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: Api.buildMemoryBlock({ enableMemory: configPage.cfg_enableMemory, userMemory: configPage.cfg_userMemory })
                width: memoryPreviewScroll.width
            }
        }

        // ── Context ──────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Context")
        }

        Rectangle {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: contextGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: contextGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                    text: "<b>Context limits</b> dictate how many past messages the AI is allowed to read.<br><br>" +
                          "<b>Auto-compact context:</b> When enabled, older messages will be summarized into a single dense summary block, saving token costs and keeping the AI focused."
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Context limit:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            QQC2.SpinBox {
                id: contextMessageLimitField
                from: -1
                to: 9999
            }
            QQC2.Label {
                text: i18n("messages (-1 = unlimited)")
                opacity: 0.72
                font: Kirigami.Theme.smallFont
            }
        }

        QQC2.CheckBox {
            id: enableCompactingContextCheck
            Kirigami.FormData.label: i18n("Auto-compact context:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            text: checked ? i18n("Enabled — old messages summarised automatically") : i18n("Disabled")
        }

        RowLayout {
            visible: enableCompactingContextCheck.checked
            Kirigami.FormData.label: i18n("Compact after:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            QQC2.SpinBox {
                id: compactContextAfterField
                from: 1
                to: 9999
            }
            QQC2.Label {
                text: i18n("messages")
                opacity: 0.72
                font: Kirigami.Theme.smallFont
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Advanced")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Reset settings:")
            text: i18n("Reset to defaults")
            onClicked: configPage.resetToDefaults()
        }
    }
}
