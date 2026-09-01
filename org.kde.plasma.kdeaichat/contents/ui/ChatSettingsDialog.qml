import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ProviderService.js" as ProviderService

// A non-modal right-side drawer. It stays attached to the chat instead of
// covering the whole conversation, and owns a draft until Apply is pressed.
Rectangle {
    id: page

    property var rootRef: null
    property Item hostItem: null
    property bool sidebarOpen: false
    property string _sessionId: ""
    property string _sessionTitle: ""
    property string _mode: "provider"
    property string _provider: ""
    property string _model: ""
    property string _ocAgent: ""
    property string _ocProvider: ""
    property string _ocModel: ""
    property string _ocCwd: ""
    property bool _memoryEnabled: true
    property string _memory: ""
    property bool _systemEnabled: true
    property string _system: ""
    property int _responseLength: 0
    property string _piProvider: ""
    property string _piModel: ""
    property var _piProviders: []
    property var _piModels: []
    property var _modelCandidates: []
    property int _generation: 0
    property bool _busy: false
    property string _status: ""
    property bool _draftDirty: false
    property bool _loadingDraft: false

    function _get(key, fallback) {
        if (rootRef && typeof rootRef.getSessionProperty === "function")
            return rootRef.getSessionProperty(_sessionId, key, fallback);
        return fallback;
    }

    function _invalidate() {
        _generation += 1;
        _busy = false;
        _status = "";
    }

    function _requestToken() {
        _busy = true;
        return { generation: _generation, sessionId: _sessionId };
    }

    function _current(token) {
        return token && token.generation === _generation && token.sessionId === _sessionId;
    }

    function _providerEntries() {
        var cfg = rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration : null;
        var global = cfg ? (cfg.provider || "openai") : "openai";
        var result = [{ text: "Default · " + ProviderService.getProviderDisplayName(global, cfg), value: "" }];
        var configured = ProviderService.getConfiguredProviders(cfg);
        var walletKeys = rootRef ? (rootRef.walletApiKeys || {}) : {};
        var supported = ProviderService.getSupportedProviders(cfg);
        for (var w = 0; w < supported.length; w++) {
            if (walletKeys[supported[w]] && configured.indexOf(supported[w]) < 0)
                configured.push(supported[w]);
        }
        for (var i = 0; i < configured.length; i++)
            result.push({ text: ProviderService.getProviderDisplayName(configured[i], cfg), value: configured[i] });
        return result;
    }

    function _names(items, sentinel) {
        var result = [sentinel];
        for (var i = 0; i < (items || []).length; i++) {
            var item = items[i];
            var value = typeof item === "string" ? item : (item && (item.value || item.id || item.name || item.text));
            if (value && result.indexOf(value) < 0)
                result.push(value);
        }
        return result;
    }

    function _applyLists() {
        providerCombo.model = _providerEntries();
        providerCombo.currentIndex = 0;
        for (var i = 0; i < providerCombo.model.length; i++) {
            if (providerCombo.model[i].value === _provider) {
                providerCombo.currentIndex = i;
                break;
            }
        }
        modelCombo.model = _modelCandidates;
        modelCombo.editText = _model;
        agentCombo.model = _names(rootRef ? rootRef.openCodeAgentsList : [], "(default agent)");
        agentCombo.editText = _ocAgent || "";
        ocProviderCombo.model = _names(rootRef ? rootRef.openCodeProvidersList : [], "(default provider)");
        ocProviderCombo.editText = _ocProvider || "";
        ocModelCombo.model = _names(rootRef ? rootRef.openCodeModelsList : [], "(default model)");
        ocModelCombo.editText = _ocModel || "";
    }

    function _load(sessionId) {
        _invalidate();
        _sessionId = sessionId || "";
        var source = _get("source", "");
        if (!source)
            source = rootRef && rootRef.openCodeMode ? "opencode" : "provider";
        _sessionTitle = rootRef && rootRef.currentSessionTitle ? rootRef.currentSessionTitle : "Current Chat";
        _mode = source;
        _provider = _get("chatProvider", "");
        _model = _get("chatModel", "");
        _ocAgent = _get("openCodeAgent", "");
        _ocProvider = _get("openCodeProvider", "");
        _ocModel = _get("openCodeModel", "");
        _ocCwd = _get("openCodeWorkspaceCwd", "");
        _memoryEnabled = _get("chatMemoryEnabled", true);
        _memory = _get("chatMemory", "");
        _systemEnabled = _get("chatSystemPromptEnabled", true);
        _system = _get("chatSystemPrompt", "");
        _responseLength = _get("responseLength", 0) || 0;
        var globalPiProvider = rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.piProvider || "") : "";
        var globalPiModel = rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.piModel || "") : "";
        _piProvider = _get("chatProvider", globalPiProvider);
        if (!_piProvider) _piProvider = globalPiProvider;
        _piModel = _get("chatModel", globalPiModel);
        if (!_piModel) _piModel = globalPiModel;
        _piProviders = rootRef ? (rootRef.piProviderCandidates || []) : [];
        _piModels = rootRef && rootRef.piProviderModelMap ? (rootRef.piProviderModelMap[_piProvider] || []) : [];
        _modelCandidates = [];
        _draftDirty = false;
        _loadingDraft = true;
        _applyLists();
        cwdField.text = _ocCwd;
        memoryCheck.checked = _memoryEnabled;
        memoryArea.text = _memory;
        systemCheck.checked = _systemEnabled;
        systemArea.text = _system;
        responseLengthCombo.currentIndex = _responseLength;
        _loadingDraft = false;
        // Always refresh the active source when opening. The old UI skipped
        // refreshes when a per-chat override was empty or keys loaded late.
        Qt.callLater(function() {
            if (_sessionId !== sessionId || !page.visible)
                return;
            if (_mode === "opencode")
                _refreshOpenCode(function() { _refreshAgents(); });
            else if (_mode === "pi")
                _refreshPi();
            else
                _refreshModels(false);
        });
    }

    function openForSession(sessionId) {
        if (!rootRef)
            return;
        _load(sessionId);
        open();
    }

    function open() { sidebarOpen = true; }
    function close() { sidebarOpen = false; }

    function toggleForSession(sessionId) {
        if (visible && _sessionId === sessionId) {
            close();
            return;
        }
        openForSession(sessionId);
    }

    function _selectedProvider() {
        if (providerCombo.currentIndex > 0 && providerCombo.model)
            return providerCombo.model[providerCombo.currentIndex].value || "";
        return rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.provider || "openai") : "openai";
    }

    function _refreshModels(showStatus) {
        if (_busy || !rootRef || !rootRef.plasmoid)
            return;
        var provider = _selectedProvider();
        var token = _requestToken();
        if (showStatus)
            _status = "Refreshing models…";
        ProviderService.fetchModelsForProvider(provider, rootRef.plasmoid.configuration,
            function(models) {
                if (!_current(token)) return;
                _busy = false;
                _modelCandidates = models || [];
                modelCombo.model = _modelCandidates;
                if (!_model && _modelCandidates.length > 0)
                    _model = _modelCandidates[0];
                modelCombo.editText = _model;
                _status = _modelCandidates.length > 0 ? ("Loaded " + _modelCandidates.length + " models") : "No models returned";
            },
            function(errorText) {
                if (!_current(token)) return;
                _busy = false;
                _status = "Model refresh failed: " + errorText;
            });
    }

    function _refreshAgents() {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeAgents !== "function")
            return;
        var token = _requestToken();
        _status = "Refreshing agents…";
        rootRef.fetchOpenCodeAgents(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            _status = (rootRef.openCodeAgentsList || []).length > 0
                ? ("Loaded " + rootRef.openCodeAgentsList.length + " agent(s)")
                : "No agents reported by OpenCode";
        });
    }

    function _refreshOpenCode(done) {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeProvidersAndModels !== "function") {
            if (done) done();
            return;
        }
        var token = _requestToken();
        _status = "Refreshing OpenCode providers…";
        rootRef.fetchOpenCodeProvidersAndModels(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            var providerCount = (rootRef.openCodeProvidersList || []).length;
            var modelCount = (rootRef.openCodeModelsList || []).length;
            _status = providerCount > 0
                ? ("Loaded " + providerCount + " provider(s), " + modelCount + " model(s)")
                : "OpenCode returned no providers or models";
            if (done) done();
        });
    }

    function _refreshPi() {
        if (_busy || !rootRef || typeof rootRef.fetchPiModels !== "function")
            return;
        var token = _requestToken();
        _status = "Refreshing Pi providers and models…";
        rootRef.fetchPiModels(function(providers, modelMap) {
            if (!_current(token)) return;
            _piProviders = providers || [];
            var models = modelMap || {};
            _piModels = models[_piProvider] || [];
            _busy = false;
            _status = _piProviders.length > 0 ? ("Loaded " + _piProviders.length + " Pi providers") : "Pi returned no providers";
        });
    }

    function _save() {
        _invalidate();
        if (!rootRef || !_sessionId) {
            close();
            return;
        }
        var agent = agentCombo.editText.trim();
        var ocProvider = ocProviderCombo.editText.trim();
        var ocModel = ocModelCombo.editText.trim();
        if (agent === "(default agent)") agent = "";
        if (ocProvider === "(default provider)") ocProvider = "";
        if (ocModel === "(default model)") ocModel = "";
        var selected = _selectedProvider();
        var overrides = {
            source: _mode,
            chatProvider: _mode === "pi" ? _piProvider : (selected === (rootRef.plasmoid.configuration.provider || "openai") ? "" : selected),
            chatModel: _mode === "pi" ? _piModel : modelCombo.editText.trim(),
            openCodeAgent: agent,
            openCodeProvider: ocProvider,
            openCodeModel: ocModel,
            openCodeWorkspaceCwd: cwdField.text.trim(),
            chatMemoryEnabled: memoryCheck.checked,
            chatMemory: memoryArea.text,
            chatSystemPromptEnabled: systemCheck.checked,
            chatSystemPrompt: systemArea.text,
            responseLength: responseLengthCombo.currentIndex
        };
        if (typeof rootRef.setSessionOverrides === "function")
            rootRef.setSessionOverrides(_sessionId, overrides);
        else if (typeof rootRef.setSessionProperty === "function") {
            for (var key in overrides)
                rootRef.setSessionProperty(_sessionId, key, overrides[key]);
        }
        if (_mode === "pi" && rootRef.plasmoid && rootRef.plasmoid.configuration) {
            rootRef.plasmoid.configuration.piProvider = _piProvider;
            rootRef.plasmoid.configuration.piModel = _piModel;
        }
        _draftDirty = false;
        close();
    }

    function _reset() {
        _invalidate();
        _load(_sessionId);
    }

    function _setMode(mode) {
        if (_mode === mode) return;
        _invalidate();
        _mode = mode;
        _modelCandidates = [];
        _draftDirty = true;
        _applyLists();
        if (mode === "opencode")
            _refreshOpenCode(function() { _refreshAgents(); });
        else if (mode === "pi")
            _refreshPi();
        else if (mode === "provider")
            _refreshModels(false);
    }

    visible: sidebarOpen
    z: 1000
    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    width: Math.min(410, Math.max(340, (parent ? parent.width : 760) * 0.44))
    color: Kirigami.Theme.backgroundColor
    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.45)
    border.width: 1
    focus: sidebarOpen
    Keys.onEscapePressed: page.close()
    onSidebarOpenChanged: if (!sidebarOpen) page._invalidate()

    Connections {
        target: page.rootRef
        function onCurrentSessionIdChanged() {
            if (page.visible && page.rootRef && page.rootRef.currentSessionId !== page._sessionId)
                page._load(page.rootRef.currentSessionId);
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Select OpenCode workspace"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            cwdField.text = path;
            if (!page._loadingDraft) page._draftDirty = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 72
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.14)
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                Kirigami.Icon { source: "preferences-other"; implicitWidth: 25; implicitHeight: 25 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PC3.Label { text: "Chat settings"; font.family: Kirigami.Theme.defaultFont.family; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize; Layout.fillWidth: true }
                    PC3.Label { text: page._sessionTitle; font.family: Kirigami.Theme.defaultFont.family; opacity: 0.65; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                PC3.ToolButton {
                    icon.name: "window-close"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Close sidebar"
                    onClicked: page.close()
                }
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ColumnLayout {
                width: Math.max(0, page.width - 28)
                anchors.margins: 14
                spacing: 12

                PC3.Label {
                    text: "RESPONSE MODE"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                    opacity: 0.62
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    PC3.Button { text: "Provider"; checkable: true; checked: page._mode === "provider"; Layout.fillWidth: true; onClicked: page._setMode("provider") }
                    PC3.Button { text: "OpenCode"; checkable: true; checked: page._mode === "opencode"; Layout.fillWidth: true; onClicked: page._setMode("opencode") }
                    PC3.Button { text: "Pi"; checkable: true; checked: page._mode === "pi"; Layout.fillWidth: true; onClicked: page._setMode("pi") }
                }

                Rectangle {
                    visible: page._mode === "provider"
                    Layout.fillWidth: true
                    implicitHeight: providerColumn.implicitHeight + 24
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.045)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    ColumnLayout {
                        id: providerColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        PC3.Label { text: "Provider and model"; font.bold: true }
                        QQC2.ComboBox {
                            id: providerCombo
                            Layout.fillWidth: true
                            textRole: "text"
                            valueRole: "value"
                            onActivated: {
                                page._provider = currentValue || "";
                                page._model = "";
                                page._modelCandidates = [];
                                if (!page._loadingDraft) page._draftDirty = true;
                                page._refreshModels(true);
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            QQC2.ComboBox {
                                id: modelCombo
                                Layout.fillWidth: true
                                editable: true
                                onActivated: { page._model = currentText; if (!page._loadingDraft) page._draftDirty = true; }
                                onEditTextChanged: { if (activeFocus) { page._model = editText; if (!page._loadingDraft) page._draftDirty = true; } }
                            }
                            PC3.ToolButton {
                                icon.name: "view-refresh"
                                enabled: !page._busy
                                onClicked: page._refreshModels(true)
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Refresh models"
                            }
                        }
                        PC3.Label {
                            text: "Choose a configured provider, then select or type its model."
                            wrapMode: Text.WordWrap
                            opacity: 0.62
                            Layout.fillWidth: true
                        }
                    }
                }

                Rectangle {
                    visible: page._mode === "opencode"
                    Layout.fillWidth: true
                    implicitHeight: openCodeColumn.implicitHeight + 24
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.045)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    ColumnLayout {
                        id: openCodeColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label { text: "OpenCode"; font.bold: true; Layout.fillWidth: true }
                            PC3.ToolButton { icon.name: "view-refresh"; enabled: !page._busy; onClicked: page._refreshOpenCode(function() { page._refreshAgents(); }) }
                        }
                        QQC2.Label { text: "Provider"; opacity: 0.7 }
                        QQC2.ComboBox { id: ocProviderCombo; Layout.fillWidth: true; editable: true; onEditTextChanged: { page._ocProvider = editText; if (!page._loadingDraft) page._draftDirty = true; } }
                        QQC2.Label { text: "Model"; opacity: 0.7 }
                        QQC2.ComboBox { id: ocModelCombo; Layout.fillWidth: true; editable: true; onEditTextChanged: { page._ocModel = editText; if (!page._loadingDraft) page._draftDirty = true; } }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Agent"; opacity: 0.7; Layout.fillWidth: true }
                            PC3.ToolButton { icon.name: "view-refresh"; enabled: !page._busy; onClicked: page._refreshAgents() }
                        }
                        QQC2.ComboBox { id: agentCombo; Layout.fillWidth: true; editable: true; onEditTextChanged: { page._ocAgent = editText; if (!page._loadingDraft) page._draftDirty = true; } }
                        QQC2.Label { text: "Workspace"; opacity: 0.7 }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.TextField { id: cwdField; Layout.fillWidth: true; maximumLength: 4096; placeholderText: "/absolute/path"; onTextChanged: { page._ocCwd = text; if (!page._loadingDraft) page._draftDirty = true; } }
                            PC3.ToolButton { icon.name: "folder"; onClicked: folderDialog.open() }
                        }
                    }
                }

                Rectangle {
                    visible: page._mode === "pi"
                    Layout.fillWidth: true
                    implicitHeight: piColumn.implicitHeight + 24
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.045)
                    ColumnLayout { id: piColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout { Layout.fillWidth: true
                            PC3.Label { text: "Pi Agent"; font.bold: true; Layout.fillWidth: true }
                            PC3.ToolButton { icon.name: "view-refresh"; enabled: !page._busy; onClicked: page._refreshPi(); QQC2.ToolTip.visible: hovered; QQC2.ToolTip.text: "Refresh Pi providers and models" }
                        }
                        QQC2.Label { text: "Provider"; opacity: 0.7 }
                        QQC2.ComboBox {
                            id: piProviderCombo
                            Layout.fillWidth: true
                            model: page._piProviders
                            textRole: "text"
                            valueRole: "value"
                            currentIndex: {
                                for (var i = 0; i < model.length; i++) if (model[i].value === page._piProvider) return i;
                                return -1;
                            }
                            onActivated: {
                                page._piProvider = currentValue || currentText;
                                page._piModels = rootRef && rootRef.piProviderModelMap ? (rootRef.piProviderModelMap[page._piProvider] || []) : [];
                                page._piModel = page._piModels.length > 0 ? page._piModels[0] : "";
                                page._draftDirty = true;
                            }
                        }
                        QQC2.Label { text: "Model"; opacity: 0.7 }
                        QQC2.ComboBox {
                            id: piModelCombo
                            Layout.fillWidth: true
                            editable: true
                            model: page._piModels
                            editText: page._piModel
                            onActivated: { page._piModel = currentText; page._draftDirty = true; }
                            onEditTextChanged: { if (activeFocus) { page._piModel = editText; page._draftDirty = true; } }
                        }
                        PC3.Label { text: "Pi settings are applied to the Pi CLI when you press Apply."; wrapMode: Text.WordWrap; opacity: 0.62; Layout.fillWidth: true }
                    }
                }

                PC3.Label {
                    visible: page._status.length > 0
                    text: page._status
                    color: page._status.indexOf("failed") >= 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: memoryColumn.implicitHeight + 24
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.045)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    ColumnLayout { id: memoryColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout { Layout.fillWidth: true
                            PC3.Label { text: "Chat memory"; font.bold: true; Layout.fillWidth: true }
                            QQC2.CheckBox { id: memoryCheck; text: "On"; onCheckedChanged: { page._memoryEnabled = checked; if (!page._loadingDraft) page._draftDirty = true; } }
                        }
                        QQC2.TextArea { id: memoryArea; Layout.fillWidth: true; Layout.preferredHeight: 80; maximumLength: 100000; enabled: memoryCheck.checked; wrapMode: Text.WordWrap; placeholderText: "Notes retained for this chat"; onTextChanged: { page._memory = text; if (!page._loadingDraft) page._draftDirty = true; } }
                    }
                }

                Rectangle {
                    visible: page._mode !== "opencode"
                    Layout.fillWidth: true
                    implicitHeight: systemColumn.implicitHeight + 24
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.045)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    ColumnLayout { id: systemColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout { Layout.fillWidth: true
                            PC3.Label { text: "System instructions"; font.bold: true; Layout.fillWidth: true }
                            QQC2.CheckBox { id: systemCheck; text: "On"; onCheckedChanged: { page._systemEnabled = checked; if (!page._loadingDraft) page._draftDirty = true; } }
                        }
                        QQC2.TextArea { id: systemArea; Layout.fillWidth: true; Layout.preferredHeight: 96; maximumLength: 100000; enabled: systemCheck.checked; wrapMode: Text.WordWrap; placeholderText: "Instructions for this chat"; onTextChanged: { page._system = text; if (!page._loadingDraft) page._draftDirty = true; } }
                    }
                }

                RowLayout {
                    visible: page._mode !== "opencode"
                    Layout.fillWidth: true
                    PC3.Label { text: "Response length"; Layout.fillWidth: true }
                    QQC2.ComboBox { id: responseLengthCombo; model: ["Default", "Short", "Balanced", "Detailed", "Comprehensive"]; onActivated: if (!page._loadingDraft) page._draftDirty = true }
                }
                Item { implicitHeight: 10 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 66
            color: Kirigami.Theme.backgroundColor
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                PC3.Button { text: "Reset"; icon.name: "edit-undo"; onClicked: page._reset() }
                Item { Layout.fillWidth: true }
                PC3.Label { visible: page._draftDirty; text: "Unsaved"; opacity: 0.62 }
                PC3.Button { text: "Apply"; highlighted: true; enabled: !page._busy; onClicked: page._save() }
            }
        }
    }
}
