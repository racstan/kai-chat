import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import "ProviderService.js" as ProviderService
import "Security.js" as Sec

KCM.SimpleKCM {
    id: page

    //* Ctrl+scroll zoom for the settings form (0.75–1.5).
    property real configZoom: 1
    property alias cfg_appearanceMode: appearanceModeCombo.currentIndex
    readonly property bool kwalletModeActive: true
    property alias cfg_provider: providerBox.currentValue
    property alias cfg_baseUrl: baseUrlField.text
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_model: modelField.text
    property alias cfg_anthropicApiKey: anthropicApiKeyField.text
    property alias cfg_anthropicModel: anthropicModelField.text
    property alias cfg_groqBaseUrl: groqBaseUrlField.text
    property alias cfg_groqApiKey: groqApiKeyField.text
    property alias cfg_groqModel: groqModelField.text
    property alias cfg_deepSeekBaseUrl: deepSeekBaseUrlField.text
    property alias cfg_deepSeekApiKey: deepSeekApiKeyField.text
    property alias cfg_deepSeekModel: deepSeekModelField.text
    property alias cfg_miniMaxBaseUrl: miniMaxBaseUrlField.text
    property alias cfg_miniMaxApiKey: miniMaxApiKeyField.text
    property alias cfg_miniMaxModel: miniMaxModelField.text
    property alias cfg_fireworksBaseUrl: fireworksBaseUrlField.text
    property alias cfg_fireworksApiKey: fireworksApiKeyField.text
    property alias cfg_fireworksModel: fireworksModelField.text
    property alias cfg_googleBaseUrl: googleBaseUrlField.text
    property alias cfg_googleApiKey: googleApiKeyField.text
    property alias cfg_googleModel: googleModelField.text
    property alias cfg_openRouterBaseUrl: openRouterBaseUrlField.text
    property alias cfg_openRouterApiKey: openRouterApiKeyField.text
    property alias cfg_openRouterModel: openRouterModelField.text
    property alias cfg_mistralBaseUrl: mistralBaseUrlField.text
    property alias cfg_mistralApiKey: mistralApiKeyField.text
    property alias cfg_mistralModel: mistralModelField.text
    property alias cfg_cloudflareBaseUrl: cloudflareBaseUrlField.text
    property alias cfg_cloudflareApiKey: cloudflareApiKeyField.text
    property alias cfg_cloudflareModel: cloudflareModelField.text
    property alias cfg_nvidiaBaseUrl: nvidiaBaseUrlField.text
    property alias cfg_nvidiaApiKey: nvidiaApiKeyField.text
    property alias cfg_nvidiaModel: nvidiaModelField.text
    property alias cfg_huggingFaceBaseUrl: huggingFaceBaseUrlField.text
    property alias cfg_huggingFaceApiKey: huggingFaceApiKeyField.text
    property alias cfg_huggingFaceModel: huggingFaceModelField.text
    property alias cfg_xaiBaseUrl: xaiBaseUrlField.text
    property alias cfg_xaiApiKey: xaiApiKeyField.text
    property alias cfg_xaiModel: xaiModelField.text
    property alias cfg_lmStudioBaseUrl: lmStudioBaseUrlField.text
    property alias cfg_lmStudioModel: lmStudioModelField.text
    property alias cfg_localBaseUrl: localBaseUrlField.text
    property alias cfg_localModel: localModelField.text
    property alias cfg_ollamaBaseUrl: ollamaBaseUrlField.text
    property alias cfg_ollamaModel: ollamaModelField.text
    property alias cfg_litellmBaseUrl: litellmBaseUrlField.text
    property alias cfg_litellmApiKey: litellmApiKeyField.text
    property alias cfg_litellmModel: litellmModelField.text
    property alias cfg_maritacaBaseUrl: maritacaBaseUrlField.text
    property alias cfg_maritacaApiKey: maritacaApiKeyField.text
    property alias cfg_maritacaModel: maritacaModelField.text
    property alias cfg_perplexityBaseUrl: perplexityBaseUrlField.text
    property alias cfg_perplexityApiKey: perplexityApiKeyField.text
    property alias cfg_perplexityModel: perplexityModelField.text
    property alias cfg_useOpenCode: openCodeToggle.checked
    property alias cfg_usePi: piToggle.checked
    property alias cfg_playNotificationSound: playSoundToggle.checked
    property alias cfg_requestTimeout: requestTimeoutSpinBox.value
    property alias cfg_openCodeUrl: openCodeUrlField.text
    property alias cfg_openCodeModel: openCodeModelValueField.text
    property alias cfg_openCodeProvider: openCodeProviderValueField.text
    property alias cfg_openCodeStartCommand: openCodeStartCommandField.text
    property alias cfg_openCodeStopCommand: openCodeStopCommandField.text
    property alias cfg_piProvider: piProviderValueField.text
    property alias cfg_piModel: piModelValueField.text
    property string cfg_customProvidersJson: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customProvidersJson || "[]") : "[]"
    property string discoveryStatus: ""
    property var pendingOps: ({
    })
    // Guard to prevent premature writes during KCM initialization (cfg_ aliases
    // are populated after the combo's onCurrentIndexChanged fires).
    property bool pageReady: false
    property bool keyringBusy: false
    property string keyringStatus: ""
    property var availableWalletNames: []
    property bool openCodeBusy: utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#opencode-") >= 0;
    }).length > 0
    property var providerModelCandidates: []
    property int providerRefreshGeneration: 0
    property bool providerRefreshBusy: false
    property var openCodeProviderCandidates: []
    property var openCodeProviderModelMap: ({
    })
    property var openCodeModelCandidates: []
    property string openCodeModelSearch: ""
    property var piProviderCandidates: []
    property var piProviderModelMap: ({
    })
    property var piModelCandidates: []
    property string piModelSearch: ""
    property string _cachedSchedulesJson: ""
    property bool memRefreshing: false
    property int memOpenCode: 0
    property int memStt: 0
    property int memTts: 0
    property string providerModelSearch: ""
    property string editingCustomProviderId: ""
    readonly property string walletFolderName: "KaiChat"
    readonly property string walletAppId: "org.kde.plasma.kdeaichat"
    readonly property bool hasPlasmoidConfig: typeof plasmoid !== 'undefined' && plasmoid !== null && plasmoid.configuration !== undefined

    function updateFilteredProviderModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            filteredProviderModels = providerModelCandidates;
        } else {
            var filtered = [];
            for (var i = 0; i < providerModelCandidates.length; i++) {
                if (providerModelCandidates[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(providerModelCandidates[i]);

            }
            filteredProviderModels = filtered;
        }
    }

    function updateFilteredOpenCodeModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            filteredOpenCodeModels = openCodeModelCandidates;
        } else {
            var filtered = [];
            for (var i = 0; i < openCodeModelCandidates.length; i++) {
                if (openCodeModelCandidates[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(openCodeModelCandidates[i]);

            }
            filteredOpenCodeModels = filtered;
        }
    }

    function updateFilteredPiModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            piModelCandidates = piProviderModelMap[piProviderValueField.text] || [];
        } else {
            var all = piProviderModelMap[piProviderValueField.text] || [];
            var filtered = [];
            for (var i = 0; i < all.length; i++) {
                if (all[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(all[i]);
            }
            piModelCandidates = filtered;
        }
    }

    function syncPiProviderSelection(providerId, preferredModel) {
        var selectedProvider = providerId || "";
        var candidateModels = piProviderModelMap[selectedProvider] || [];
        var chosenModel = preferredModel || piModelValueField.text || "";
        if (candidateModels.indexOf(chosenModel) < 0)
            chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";
        piProviderValueField.text = selectedProvider;
        piModelCandidates = candidateModels;
        piModelSearch = "";
        updateFilteredPiModels("");
        piModelValueField.text = chosenModel;
    }

    function _buildProviderBoxModel() {
        var list = [
            {"value": "openai", "text": "OpenAI"},
            {"value": "anthropic", "text": "Anthropic"},
            {"value": "groq", "text": "Groq"},
            {"value": "deepseek", "text": "DeepSeek"},
            {"value": "minimax", "text": "MiniMax"},
            {"value": "fireworks", "text": "Fireworks AI"},
            {"value": "google", "text": "Google Gemini"},
            {"value": "openrouter", "text": "OpenRouter"},
            {"value": "mistral", "text": "Mistral"},
            {"value": "cloudflare", "text": "Cloudflare Workers AI"},
            {"value": "nvidia", "text": "NVIDIA NIM"},
            {"value": "huggingface", "text": "Hugging Face Router"},
            {"value": "xai", "text": "xAI (Grok)"},
            {"value": "lmstudio", "text": "LM Studio"},
            {"value": "local", "text": "Local (OpenAI-compatible)"},
            {"value": "ollama", "text": "Ollama"},
            {"value": "litellm", "text": "LiteLLM Proxy"},
            {"value": "maritaca", "text": "Maritaca"},
            {"value": "perplexity", "text": "Perplexity"}
        ];
        var customs = [];
        try { customs = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch(e) {}
        for (var i = 0; i < customs.length; i++) {
            list.push({ "value": customs[i].id, "text": "[Custom] " + customs[i].name });
        }
        return list;
    }

    // ── Custom provider helpers (two-step multi-provider UX) ────────────
    function isCustomProviderId(id) {
        return String(id || "").indexOf("custom_") === 0;
    }
    function customProviderById(id) {
        var list = [];
        try { list = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch(e) { return null; }
        for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i];
        return null;
    }
    function setCustomProviderProperty(id, key, value, persistConfig) {
        var list = [];
        try { list = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch(e) { list = []; }
        var changed = false;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id) { list[i][key] = value; changed = true; break; }
        }
        if (!changed) return;
        var json = JSON.stringify(list);
        page.cfg_customProvidersJson = json;
        if (persistConfig !== false && plasmoid && plasmoid.configuration)
            plasmoid.configuration.customProvidersJson = json;
        // keep dropdown in sync without losing selection
        var cur = providerBox.currentValue;
        providerBox.model = page._buildProviderBoxModel();
        for (var j = 0; j < providerBox.model.length; j++) if (providerBox.model[j].value === cur) { providerBox.currentIndex = j; break; }
    }
    function customProviderDefaultBaseUrl(providerType) {
        // Provide sensible defaults for quick-add
        if (providerType === "anthropic") return "https://api.anthropic.com/v1";
        return "https://api.openai.com/v1";
    }

    function effectiveWalletName() {
        return "kdewallet";
    }

    function detectWallets() {
        // Native DBus operations are the source of truth. Keep this small
        // compatibility hook for old status callbacks.
        keyringStatus = "KWallet status refreshed.";
    }

    function walletCall(member, args, resolve, reject) {
        var reply;
        try {
            reply = DBus.SessionBus.asyncCall({
                service: "org.kde.kwalletd6",
                path: "/modules/kwalletd6",
                iface: "org.kde.KWallet",
                member: member,
                arguments: args
            });
        } catch (e) {
            if (reject) reject(String(e));
            else {
                keyringBusy = false;
                keyringStatus = "KWallet is unavailable: " + e;
            }
            return;
        }
        reply.finished.connect(function() {
            if (reply.isError) {
                if (reject) reject(reply.error);
                else {
                    keyringBusy = false;
                    keyringStatus = "KWallet error while calling " + member + ".";
                    console.warn("KDE AI Chat: wallet DBus error:", member, reply.error);
                }
            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && typeof val === 'object' && val.hasOwnProperty("value")) val = val.value;
                if (resolve) resolve(val);
            }
        });
    }

    function setActiveProviderModelValue(value) {
        var p = providerBox.currentValue || "openai";
        if (isCustomProviderId(p)) { setCustomProviderProperty(p, "model", value || ""); return; }
        currentProviderConfig().modelField.text = value || "";
    }

    function activeProviderModelValue() {
        var p = providerBox.currentValue || "openai";
        if (isCustomProviderId(p)) { var c = customProviderById(p); return c ? (c.model || "") : ""; }
        return currentProviderConfig().modelField.text || "";
    }

    // Shell script builders removed in favor of native DBus calls.

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''");
    }

    function quoteForShell(s) {
        return "'" + shellEscape(s) + "'";
    }

    function getHelperPath() {
        var urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        if (path.endsWith("/contents/ui/kde_ai_helper.py"))
            return path;
        return "";
    }

    function copyToClipboard(textValue) {
        var text = textValue || "";
        var arg = Sec.rawShellSnippetQuote(text);
        var cmd = "if command -v wl-copy >/dev/null 2>&1; then printf '%s' " + arg + " | wl-copy; "
            + "elif command -v xclip >/dev/null 2>&1; then printf '%s' " + arg + " | xclip -selection clipboard; "
            + "else echo 'Clipboard tool missing: install wl-clipboard or xclip' 1>&2; exit 1; fi";
        utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #clipboard-copy-" + Date.now());
    }

    function providerEnabled(providerId) {
        return !openCodeToggle.checked && !piToggle.checked && providerBox.currentValue === providerId;
    }

    function providerNeedsApiKey(providerId) {
        if (isCustomProviderId(providerId)) {
            var cp = customProviderById(providerId);
            if (!cp) return true;
            // mirrors ProviderService custom allowEmptyKey logic
            if (cp.allowEmptyKey === true) return false;
            if (cp.type === "anthropic") return true;
            // openai-compat custom: require key unless it's a localhost url
            var url = String(cp.baseUrl || "").toLowerCase();
            if (url.indexOf("localhost") >= 0 || url.indexOf("127.0.0.1") >= 0) return false;
            return true;
        }
        return providerId !== "local" && providerId !== "lmstudio" && providerId !== "ollama" && providerId !== "litellm";
    }

    function providerHasConfiguredKey(providerId) {
        if (isCustomProviderId(providerId)) {
            var cp2 = customProviderById(providerId);
            if (!cp2) return false;
            if (cp2.allowEmptyKey === true) return true;
            var u = String(cp2.baseUrl || "").toLowerCase();
            if (u.indexOf("localhost") >= 0 || u.indexOf("127.0.0.1") >= 0) return true;
            return (cp2.apiKey || "").trim() !== "";
        }
        if (providerId === "anthropic")
            return (anthropicApiKeyField.text || "").trim() !== "";

        if (providerId === "groq")
            return (groqApiKeyField.text || "").trim() !== "";

        if (providerId === "deepseek")
            return (deepSeekApiKeyField.text || "").trim() !== "";

        if (providerId === "minimax")
            return (miniMaxApiKeyField.text || "").trim() !== "";

        if (providerId === "fireworks")
            return (fireworksApiKeyField.text || "").trim() !== "";

        if (providerId === "google")
            return (googleApiKeyField.text || "").trim() !== "";

        if (providerId === "openrouter")
            return (openRouterApiKeyField.text || "").trim() !== "";

        if (providerId === "mistral")
            return (mistralApiKeyField.text || "").trim() !== "";

        if (providerId === "cloudflare")
            return (cloudflareApiKeyField.text || "").trim() !== "";

        if (providerId === "nvidia")
            return (nvidiaApiKeyField.text || "").trim() !== "";

        if (providerId === "huggingface")
            return (huggingFaceApiKeyField.text || "").trim() !== "";

        if (providerId === "xai")
            return (xaiApiKeyField.text || "").trim() !== "";

        if (providerId === "litellm")
            return (litellmApiKeyField.text || "").trim() !== "";

        if (providerId === "maritaca")
            return (maritacaApiKeyField.text || "").trim() !== "";

        if (providerId === "perplexity")
            return (perplexityApiKeyField.text || "").trim() !== "";

        if (providerId === "openai")
            return (apiKeyField.text || "").trim() !== "";

        return true;
    }

    function refreshIfActiveProvider(providerId) {
        if (providerBox.currentValue === providerId)
            refreshCurrentProviderModels();

    }

    function providerModelVisible(providerId) {
        return providerEnabled(providerId) && (!providerNeedsApiKey(providerId) || providerHasConfiguredKey(providerId));
    }

    function providerNeedsKeyHintVisible(providerId) {
        return providerEnabled(providerId) && providerNeedsApiKey(providerId) && !providerHasConfiguredKey(providerId);
    }

    function currentProviderDisplayName() {
        return providerBox.currentText || "Provider";
    }

    function currentProviderConfig() {
        var p = providerBox.currentValue || "openai";
        if (p === "anthropic")
            return {
                "id": p,
                "type": "anthropic",
                "baseUrl": "https://api.anthropic.com/v1",
                "apiKey": anthropicApiKeyField.text,
                "modelField": anthropicModelField
            };

        if (p === "local")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": localBaseUrlField.text,
                "apiKey": "",
                "modelField": localModelField
            };

        if (p === "groq")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": groqBaseUrlField.text,
                "apiKey": groqApiKeyField.text,
                "modelField": groqModelField
            };

        if (p === "deepseek")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": deepSeekBaseUrlField.text,
                "apiKey": deepSeekApiKeyField.text,
                "modelField": deepSeekModelField
            };

        if (p === "minimax")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": miniMaxBaseUrlField.text,
                "apiKey": miniMaxApiKeyField.text,
                "modelField": miniMaxModelField
            };

        if (p === "fireworks")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": fireworksBaseUrlField.text,
                "apiKey": fireworksApiKeyField.text,
                "modelField": fireworksModelField
            };

        if (p === "google")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": googleBaseUrlField.text,
                "apiKey": googleApiKeyField.text,
                "modelField": googleModelField
            };

        if (p === "openrouter")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": openRouterBaseUrlField.text,
                "apiKey": openRouterApiKeyField.text,
                "modelField": openRouterModelField
            };

        if (p === "mistral")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": mistralBaseUrlField.text,
                "apiKey": mistralApiKeyField.text,
                "modelField": mistralModelField
            };

        if (p === "cloudflare")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": cloudflareBaseUrlField.text,
                "apiKey": cloudflareApiKeyField.text,
                "modelField": cloudflareModelField
            };

        if (p === "nvidia")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": nvidiaBaseUrlField.text,
                "apiKey": nvidiaApiKeyField.text,
                "modelField": nvidiaModelField
            };

        if (p === "huggingface")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": huggingFaceBaseUrlField.text,
                "apiKey": huggingFaceApiKeyField.text,
                "modelField": huggingFaceModelField
            };

        if (p === "xai")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": xaiBaseUrlField.text,
                "apiKey": xaiApiKeyField.text,
                "modelField": xaiModelField
            };

        if (p === "lmstudio")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": lmStudioBaseUrlField.text,
                "apiKey": "",
                "modelField": lmStudioModelField
            };

        if (p === "ollama")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": ollamaBaseUrlField.text,
                "apiKey": "",
                "modelField": ollamaModelField
            };

        if (p === "litellm")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": litellmBaseUrlField.text,
                "apiKey": litellmApiKeyField.text,
                "modelField": litellmModelField
            };

        if (p === "maritaca")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": maritacaBaseUrlField.text,
                "apiKey": maritacaApiKeyField.text,
                "modelField": maritacaModelField
            };

        if (p === "perplexity")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": perplexityBaseUrlField.text,
                "apiKey": perplexityApiKeyField.text,
                "modelField": perplexityModelField
            };

        if (isCustomProviderId(p)) {
            var cp0 = customProviderById(p);
            if (cp0) {
                // modelField is virtual — writes go through setCustomProviderProperty
                var dummy = { text: cp0.model || "" };
                return {
                    "id": p,
                    "type": cp0.type || "openai-compat",
                    "baseUrl": cp0.baseUrl || "",
                    "apiKey": cp0.apiKey || "",
                    "modelField": dummy
                };
            }
        }

        return {
            "id": "openai",
            "type": "openai-compat",
            "baseUrl": baseUrlField.text,
            "apiKey": apiKeyField.text,
            "modelField": modelField
        };
    }

    function makeOpenAiModelsUrl(baseUrl) {
        return (baseUrl || "").replace(/\/$/, "") + "/models";
    }

    function parseModelIds(responseObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i]);
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id);
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name);
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var j = 0; j < responseObj.data.length; j++) {
                if (responseObj.data[j] && responseObj.data[j].id)
                    pushId(responseObj.data[j].id);
                else if (responseObj.data[j] && responseObj.data[j].name)
                    pushId(responseObj.data[j].name);
            }
        } else if (responseObj && Array.isArray(responseObj.models)) {
            for (var k = 0; k < responseObj.models.length; k++) {
                if (typeof responseObj.models[k] === "string")
                    pushId(responseObj.models[k]);
                else if (responseObj.models[k] && responseObj.models[k].id)
                    pushId(responseObj.models[k].id);
                else if (responseObj.models[k] && responseObj.models[k].name)
                    pushId(responseObj.models[k].name);
            }
        }
        return ids;
    }

    function parseProviderIds(responseObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i]);
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id);
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name);
                else if (responseObj[i] && responseObj[i].provider)
                    pushId(responseObj[i].provider);
            }
        } else if (responseObj && Array.isArray(responseObj.providers)) {
            for (var j = 0; j < responseObj.providers.length; j++) {
                if (typeof responseObj.providers[j] === "string")
                    pushId(responseObj.providers[j]);
                else if (responseObj.providers[j] && responseObj.providers[j].id)
                    pushId(responseObj.providers[j].id);
                else if (responseObj.providers[j] && responseObj.providers[j].name)
                    pushId(responseObj.providers[j].name);
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var k = 0; k < responseObj.data.length; k++) {
                if (responseObj.data[k] && responseObj.data[k].provider)
                    pushId(responseObj.data[k].provider);

            }
        }
        return ids;
    }

    function requestJson(url, headers, onSuccess, onError) {
        var safeUrl = Sec.validateHttpUrl(url);
        if (!safeUrl) {
            onError("Request blocked: only HTTP(S) provider URLs are allowed.");
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", safeUrl, true);
        xhr.timeout = 15000;
        xhr.ontimeout = function() {
            onError("Request to " + url + " timed out after 15 seconds.");
        };
        for (var h in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, h) && headers[h])
                xhr.setRequestHeader(h, headers[h]);

        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    onSuccess(JSON.parse(xhr.responseText));
                } catch (e) {
                    onError("Invalid JSON from " + url);
                }
            } else {
                onError("HTTP " + xhr.status + " from " + url);
            }
        };
        xhr.onerror = function() {
            onError("Network error while requesting " + url);
        };
        try {
            xhr.send();
        } catch (e) {
            onError("Unable to start request: " + e);
        }
        return xhr;
    }

    function refreshCurrentProviderModels() {
        var requestGeneration = ++providerRefreshGeneration;
        providerRefreshBusy = true;
        var cfg = currentProviderConfig();
        var headers = {
        };
        if (providerNeedsApiKey(cfg.id) && (!cfg.apiKey || cfg.apiKey.trim() === "")) {
            providerRefreshBusy = false;
            providerModelCandidates = [];
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = "API key is missing for " + currentProviderDisplayName() + ". Add key first, then refresh models.";
            return ;
        }
        if (cfg.apiKey)
            headers["Authorization"] = "Bearer " + cfg.apiKey;

        function failed(err) {
            if (requestGeneration !== providerRefreshGeneration)
                return;
            providerRefreshBusy = false;
            providerModelCandidates = [];
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = err;
        }
        function succeeded(obj) {
            if (requestGeneration !== providerRefreshGeneration)
                return;
            providerRefreshBusy = false;
            var ids = parseModelIds(obj);
            providerModelCandidates = ids;
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
        }

        if (cfg.type === "anthropic") {
            headers["x-api-key"] = cfg.apiKey;
            headers["anthropic-version"] = "2023-06-01";
            requestJson(makeOpenAiModelsUrl(cfg.baseUrl || "https://api.anthropic.com/v1"), headers, succeeded, failed);
            return ;
        }
        requestJson(makeOpenAiModelsUrl(cfg.baseUrl), headers, succeeded, failed);
    }

    function applyDetectedModelToActiveProvider(modelId) {
        var p = providerBox.currentValue || "openai";
        if (isCustomProviderId(p)) {
            setCustomProviderProperty(p, "model", modelId || "");
            return;
        }
        var cfg = currentProviderConfig();
        cfg.modelField.text = modelId || "";
    }

    function activeOpenCodeProvider() {
        return openCodeProviderValueField.text || "";
    }

    function setOpenCodeProviderValue(v) {
        openCodeProviderValueField.text = v || "";
    }

    function setOpenCodeModelValue(v) {
        openCodeModelValueField.text = v || "";
    }

    function openCodeServerRoot(baseUrl) {
        var value = (baseUrl || "").replace(/\/$/, "");
        if (value.slice(-3) === "/v1")
            return value.slice(0, -3);

        return value;
    }

    function parseOpenCodeProviderModels(providerObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (!providerObj || !providerObj.models)
            return ids;

        if (Array.isArray(providerObj.models)) {
            for (var i = 0; i < providerObj.models.length; i++) {
                if (typeof providerObj.models[i] === "string")
                    pushId(providerObj.models[i]);
                else if (providerObj.models[i] && providerObj.models[i].id)
                    pushId(providerObj.models[i].id);
            }
            return ids;
        }
        for (var modelId in providerObj.models) {
            if (!Object.prototype.hasOwnProperty.call(providerObj.models, modelId))
                continue;

            pushId(providerObj.models[modelId].id || modelId);
        }
        return ids;
    }

    function syncOpenCodeProviderSelection(providerId, preferredModel) {
        var selectedProvider = providerId || "";
        var candidateModels = openCodeProviderModelMap[selectedProvider] || [];
        var chosenModel = preferredModel || openCodeModelValueField.text || "";
        if (candidateModels.indexOf(chosenModel) < 0)
            chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";

        setOpenCodeProviderValue(selectedProvider);
        openCodeModelCandidates = candidateModels;
        openCodeModelSearch = "";
        updateFilteredOpenCodeModels("");
        setOpenCodeModelValue(chosenModel);
        if (openCodeProvidersCombo) {
            var pidx = openCodeProviderCandidates.indexOf(selectedProvider);
            if (pidx >= 0)
                openCodeProvidersCombo.currentIndex = pidx;

        }
        if (openCodeModelsCombo) {
            var midx = candidateModels.indexOf(chosenModel);
            if (midx >= 0)
                openCodeModelsCombo.currentIndex = midx;

        }
    }

    function refreshOpenCodeDiscovery() {
        probeOpenCodeProviders(openCodeUrlField.text);
    }

    function refreshPiDiscovery() {
        discoveryStatus = "Checking Pi Agent models...";
        var cmd = "python3 " + quoteForShell(getHelperPath()) + " get_pi_models";
        var uid = "pi_models_" + Date.now();
        utilityDs.connectSource(cmd + " #" + uid);
    }

    function probeOpenCodeProviders(baseUrl) {
        var url = openCodeServerRoot(baseUrl) + "/config/providers";
        discoveryStatus = "Checking OpenCode server...";
        requestJson(url, {
        }, function(obj) {
            if (!openCodeToggle.checked) return;
            var providers = (obj && obj.providers) || [];
            var ids = [];
            var defaults = (obj && obj.default) || {
            };
            var modelsByProvider = {
            };
            for (var i = 0; i < providers.length; i++) {
                var provider = providers[i];
                var providerId = provider && provider.id ? provider.id : (provider && provider.name ? provider.name : "");
                if (!providerId)
                    continue;

                if (ids.indexOf(providerId) < 0)
                    ids.push(providerId);

                modelsByProvider[providerId] = parseOpenCodeProviderModels(provider);
            }
            openCodeProviderCandidates = ids;
            openCodeProviderModelMap = modelsByProvider;
            if (ids.length === 0) {
                openCodeModelCandidates = [];
                openCodeModelSearch = "";
                updateFilteredOpenCodeModels("");
                setOpenCodeProviderValue("");
                setOpenCodeModelValue("");
                discoveryStatus = "OpenCode server is reachable, but it returned no configured providers.";
                return ;
            }
            var selectedProvider = activeOpenCodeProvider();
            if (ids.indexOf(selectedProvider) < 0)
                selectedProvider = ids[0];

            var rememberedModel = openCodeModelValueField.text || "";
            var fallbackModel = defaults[selectedProvider] || "";
            syncOpenCodeProviderSelection(selectedProvider, rememberedModel || fallbackModel);
            discoveryStatus = "OpenCode server reachable. Loaded " + ids.length + " providers from /config/providers.";
        }, function(err) {
            if (!openCodeToggle.checked) return;
            openCodeProviderCandidates = [];
            openCodeProviderModelMap = ({
            });
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            setOpenCodeProviderValue("");
            setOpenCodeModelValue("");
            discoveryStatus = "OpenCode server check failed: " + err;
        });
    }

    function probeOpenCodeModels(baseUrl, providerId) {
        var selectedProvider = providerId || activeOpenCodeProvider();
        if (!selectedProvider) {
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            if (openCodeToggle.checked) {
                discoveryStatus = "Select an OpenCode provider first.";
            }
            return ;
        }
        syncOpenCodeProviderSelection(selectedProvider, openCodeModelValueField.text);
        if (openCodeToggle.checked) {
            discoveryStatus = openCodeModelCandidates.length > 0 ? ("Loaded " + openCodeModelCandidates.length + " models for OpenCode provider " + selectedProvider + ".") : ("OpenCode provider " + selectedProvider + " has no models listed by /config/providers.");
        }
    }

    function kwalletStore(targetId, value, isBulk) {
        if (!value || value.trim() === "")
            return;

        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("createFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function() {
                            walletCall("writePassword", [new DBus.int32(handle), walletFolderName, keyName, value, walletAppId], function() {
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                if (!isBulk) keyringStatus = "Saved key for " + targetId + " to KWallet.";
                            });
                        });
                    } else {
                        walletCall("writePassword", [new DBus.int32(handle), walletFolderName, keyName, value, walletAppId], function() {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            if (!isBulk) keyringStatus = "Saved key for " + targetId + " to KWallet.";
                        });
                    }
                });
            });
        });
    }

    function notifyWalletChanged() {
        if (hasPlasmoidConfig && plasmoid.configuration.walletKeysRevision !== undefined)
            plasmoid.configuration.walletKeysRevision = (Number(plasmoid.configuration.walletKeysRevision) || 0) + 1;
    }

    function clearPlaintextApiKey(targetId) {
        if (!hasPlasmoidConfig)
            return;
        var configKey = ProviderService.getApiKeyConfigKey(targetId);
        if (configKey && plasmoid.configuration[configKey] !== undefined)
            plasmoid.configuration[configKey] = "";
        if (isCustomProviderId(targetId)) {
            var list = [];
            try { list = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch (e) { list = []; }
            var changed = false;
            for (var i = 0; i < list.length; i++) {
                if (list[i] && list[i].id === targetId && list[i].apiKey) {
                    list[i].apiKey = "";
                    changed = true;
                    break;
                }
            }
            if (changed) {
                var json = JSON.stringify(list);
                page.cfg_customProvidersJson = json;
                plasmoid.configuration.customProvidersJson = json;
            }
        }
        notifyWalletChanged();
    }

    function clearPlaintextApiKeys() {
        var ids = keyTargetIds();
        for (var i = 0; i < ids.length; i++)
            clearPlaintextApiKey(ids[i]);
    }

    function saveKey(targetId, value) {
        var val = (value || "").trim();
        if (val === "") {
            kwalletRemove(targetId);
            return;
        }
        kwalletStore(targetId, val, false);
    }

    function kwalletRemove(targetId) {
        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        keyringBusy = true;
        walletCall("wallets", [], function(wallets) {
            if (!wallets || wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                        keyringBusy = false;
                        return;
                    }
                    walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function(hasEntry) {
                        if (hasEntry)
                            walletCall("removeEntry", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function() {
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                clearPlaintextApiKey(targetId);
                                keyringStatus = "Removed key for " + targetId + " from KWallet.";
                            });
                        else {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                        }
                    });
                });
            });
        });
    }

    function kwalletLoad(targetId, isBulk) {
        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                        keyringBusy = false;
                        return;
                    }
                    walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function(hasEntry) {
                        if (hasEntry) {
                            walletCall("readPassword", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function(secret) {
                                applyLoadedKey(targetId, secret);
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                if (!isBulk) keyringStatus = "Loaded key for " + targetId + " from KWallet.";
                            });
                        } else {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            if (!isBulk) keyringStatus = "No saved key for " + targetId + " in KWallet.";
                        }
                    });
                });
            });
        });
    }

    function applyLoadedKey(targetId, secretValue) {
        var normalized = (secretValue || "").trim();
        var lower = normalized.toLowerCase();
        if (normalized === "" || normalized.indexOf("__KAI_") === 0)
            return ;

        var before = apiKeyForTarget(targetId);
        if (targetId === "openai")
            apiKeyField.text = normalized;
        else if (targetId === "anthropic")
            anthropicApiKeyField.text = normalized;
        else if (targetId === "groq")
            groqApiKeyField.text = normalized;
        else if (targetId === "deepseek")
            deepSeekApiKeyField.text = normalized;
        else if (targetId === "minimax")
            miniMaxApiKeyField.text = normalized;
        else if (targetId === "fireworks")
            fireworksApiKeyField.text = normalized;
        else if (targetId === "google")
            googleApiKeyField.text = normalized;
        else if (targetId === "openrouter")
            openRouterApiKeyField.text = normalized;
        else if (targetId === "mistral")
            mistralApiKeyField.text = normalized;
        else if (targetId === "cloudflare")
            cloudflareApiKeyField.text = normalized;
        else if (targetId === "nvidia")
            nvidiaApiKeyField.text = normalized;
        else if (targetId === "huggingface")
            huggingFaceApiKeyField.text = normalized;
        else if (targetId === "xai")
            xaiApiKeyField.text = normalized;
        else if (targetId === "litellm")
            litellmApiKeyField.text = normalized;
        else if (targetId === "maritaca")
            maritacaApiKeyField.text = normalized;
        else if (targetId === "perplexity")
            perplexityApiKeyField.text = normalized;
        else if (isCustomProviderId(targetId))
            setCustomProviderProperty(targetId, "apiKey", normalized, false);
        var after = apiKeyForTarget(targetId);
        if (before !== after && providerBox.currentValue === targetId)
            refreshCurrentProviderModels();

    }

    function keyTargetIds() {
        var ids = ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm", "maritaca", "perplexity"];
        var customs = [];
        try { customs = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch (e) { customs = []; }
        for (var i = 0; i < customs.length; i++) {
            var id = customs[i] && String(customs[i].id || "");
            if (/^custom_[A-Za-z0-9._:-]{1,100}$/.test(id) && ids.indexOf(id) < 0)
                ids.push(id);
        }
        return ids;
    }

    function apiKeyForTarget(targetId) {
        if (targetId === "openai")
            return apiKeyField.text;

        if (targetId === "anthropic")
            return anthropicApiKeyField.text;

        if (targetId === "groq")
            return groqApiKeyField.text;

        if (targetId === "deepseek")
            return deepSeekApiKeyField.text;

        if (targetId === "minimax")
            return miniMaxApiKeyField.text;

        if (targetId === "fireworks")
            return fireworksApiKeyField.text;

        if (targetId === "google")
            return googleApiKeyField.text;

        if (targetId === "openrouter")
            return openRouterApiKeyField.text;

        if (targetId === "mistral")
            return mistralApiKeyField.text;

        if (targetId === "cloudflare")
            return cloudflareApiKeyField.text;

        if (targetId === "nvidia")
            return nvidiaApiKeyField.text;

        if (targetId === "huggingface")
            return huggingFaceApiKeyField.text;

        if (targetId === "xai")
            return xaiApiKeyField.text;

        if (targetId === "litellm")
            return litellmApiKeyField.text;

        if (targetId === "maritaca")
            return maritacaApiKeyField.text;

        if (targetId === "perplexity")
            return perplexityApiKeyField.text;

        if (isCustomProviderId(targetId)) {
            var custom = customProviderById(targetId);
            return custom ? (custom.apiKey || "") : "";
        }
        return "";
    }

    function kwalletLoadAll() {
        var walletName = effectiveWalletName();
        keyringStatus = "Refreshing API keys from KWallet...";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                        keyringBusy = false;
                        keyringStatus = "KWallet storage not initialized yet.";
                        return;
                    }
                    var targets = keyTargetIds();
                    var idx = 0;
                    function readNext() {
                        if (idx >= targets.length) {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            keyringStatus = "Loaded API keys from KWallet.";
                            return;
                        }
                        var targetId = targets[idx++];
                        var key = "kai-chat-" + targetId + "-api-key";
                        walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, key, walletAppId], function(hasEntry) {
                            if (hasEntry) {
                                walletCall("readPassword", [new DBus.int32(handle), walletFolderName, key, walletAppId], function(secret) {
                                    applyLoadedKey(targetId, secret);
                                    readNext();
                                });
                            } else {
                                readNext();
                            }
                        });
                    }
                    readNext();
                });
            });
        });
    }

    function kwalletStoreAll() {
        var walletName = effectiveWalletName();
        var targetsToSave = [];
        var ids = keyTargetIds();
        for (var i = 0; i < ids.length; i++) {
            var value = (apiKeyForTarget(ids[i]) || "").trim();
            // Include empty fields so keys removed in Settings are also
            // removed from KWallet rather than silently lingering.
            targetsToSave.push({id: ids[i], val: value});
        }
        
        if (targetsToSave.length === 0) {
            keyringStatus = "No API keys to sync.";
            return;
        }

        keyringBusy = true;
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    var proceedToSave = function() {
                        var idx = 0;
                        function saveNext() {
                            if (idx >= targetsToSave.length) {
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                clearPlaintextApiKeys();
                                keyringStatus = "Synced " + targetsToSave.length + " API keys to KWallet.";
                                return;
                            }
                            var t = targetsToSave[idx++];
                            var key = "kai-chat-" + t.id + "-api-key";
                            var member = t.val === "" ? "removeEntry" : "writePassword";
                            var args = t.val === ""
                                ? [new DBus.int32(handle), walletFolderName, key, walletAppId]
                                : [new DBus.int32(handle), walletFolderName, key, t.val, walletAppId];
                            walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, key, walletAppId], function(hasEntry) {
                                if (t.val === "" && !hasEntry) { saveNext(); return; }
                                walletCall(member, args, function() { saveNext(); });
                            });
                        }
                        saveNext();
                    };

                    if (!hasFolder) {
                        walletCall("createFolder", [new DBus.int32(handle), walletFolderName, walletAppId], proceedToSave);
                    } else {
                        proceedToSave();
                    }
                });
            });
        });
    }

    function loadPlaintextApiKeyFallbacks() {
        if (!hasPlasmoidConfig)
            return;
        var fields = {
            "openai": apiKeyField,
            "anthropic": anthropicApiKeyField,
            "groq": groqApiKeyField,
            "deepseek": deepSeekApiKeyField,
            "minimax": miniMaxApiKeyField,
            "fireworks": fireworksApiKeyField,
            "google": googleApiKeyField,
            "openrouter": openRouterApiKeyField,
            "mistral": mistralApiKeyField,
            "cloudflare": cloudflareApiKeyField,
            "nvidia": nvidiaApiKeyField,
            "huggingface": huggingFaceApiKeyField,
            "xai": xaiApiKeyField,
            "litellm": litellmApiKeyField,
            "maritaca": maritacaApiKeyField,
            "perplexity": perplexityApiKeyField
        };
        var ids = Object.keys(fields);
        for (var i = 0; i < ids.length; i++) {
            var configKey = ProviderService.getApiKeyConfigKey(ids[i]);
            if (configKey && !fields[ids[i]].text)
                fields[ids[i]].text = String(plasmoid.configuration[configKey] || "");
        }
    }

    function clearAllApiKeyFields() {
        apiKeyField.text = "";
        anthropicApiKeyField.text = "";
        groqApiKeyField.text = "";
        deepSeekApiKeyField.text = "";
        miniMaxApiKeyField.text = "";
        fireworksApiKeyField.text = "";
        googleApiKeyField.text = "";
        openRouterApiKeyField.text = "";
        mistralApiKeyField.text = "";
        cloudflareApiKeyField.text = "";
        nvidiaApiKeyField.text = "";
        huggingFaceApiKeyField.text = "";
        xaiApiKeyField.text = "";
        litellmApiKeyField.text = "";
        maritacaApiKeyField.text = "";
        perplexityApiKeyField.text = "";
    }



    function saveGeneralSettingsOnly() {
        if (!hasPlasmoidConfig) {
            return;
        }
        // App name saved via ConfigOther.qml
        plasmoid.configuration.appearanceMode = appearanceModeCombo.currentIndex;

        plasmoid.configuration.provider = providerBox.currentValue;
        plasmoid.configuration.baseUrl = baseUrlField.text;
        plasmoid.configuration.model = modelField.text;
        plasmoid.configuration.anthropicModel = anthropicModelField.text;
        plasmoid.configuration.groqBaseUrl = groqBaseUrlField.text;
        plasmoid.configuration.groqModel = groqModelField.text;
        plasmoid.configuration.deepSeekBaseUrl = deepSeekBaseUrlField.text;
        plasmoid.configuration.deepSeekModel = deepSeekModelField.text;
        plasmoid.configuration.miniMaxBaseUrl = miniMaxBaseUrlField.text;
        plasmoid.configuration.miniMaxModel = miniMaxModelField.text;
        plasmoid.configuration.fireworksBaseUrl = fireworksBaseUrlField.text;
        plasmoid.configuration.fireworksModel = fireworksModelField.text;
        plasmoid.configuration.googleBaseUrl = googleBaseUrlField.text;
        plasmoid.configuration.googleModel = googleModelField.text;
        plasmoid.configuration.openRouterBaseUrl = openRouterBaseUrlField.text;
        plasmoid.configuration.openRouterModel = openRouterModelField.text;
        plasmoid.configuration.mistralBaseUrl = mistralBaseUrlField.text;
        plasmoid.configuration.mistralModel = mistralModelField.text;
        plasmoid.configuration.cloudflareBaseUrl = cloudflareBaseUrlField.text;
        plasmoid.configuration.cloudflareModel = cloudflareModelField.text;
        plasmoid.configuration.nvidiaBaseUrl = nvidiaBaseUrlField.text;
        plasmoid.configuration.nvidiaModel = nvidiaModelField.text;
        plasmoid.configuration.huggingFaceBaseUrl = huggingFaceBaseUrlField.text;
        plasmoid.configuration.huggingFaceModel = huggingFaceModelField.text;
        plasmoid.configuration.xaiBaseUrl = xaiBaseUrlField.text;
        plasmoid.configuration.xaiModel = xaiModelField.text;
        plasmoid.configuration.lmStudioBaseUrl = lmStudioBaseUrlField.text;
        plasmoid.configuration.lmStudioModel = lmStudioModelField.text;
        plasmoid.configuration.localBaseUrl = localBaseUrlField.text;
        plasmoid.configuration.localModel = localModelField.text;
        plasmoid.configuration.ollamaBaseUrl = ollamaBaseUrlField.text;
        plasmoid.configuration.ollamaModel = ollamaModelField.text;
        plasmoid.configuration.litellmBaseUrl = litellmBaseUrlField.text;
        plasmoid.configuration.litellmModel = litellmModelField.text;
        plasmoid.configuration.maritacaBaseUrl = maritacaBaseUrlField.text;
        plasmoid.configuration.maritacaModel = maritacaModelField.text;
        plasmoid.configuration.perplexityBaseUrl = perplexityBaseUrlField.text;
        plasmoid.configuration.perplexityModel = perplexityModelField.text;
        plasmoid.configuration.useOpenCode = openCodeToggle.checked;
        plasmoid.configuration.usePi = piToggle.checked;
        plasmoid.configuration.playNotificationSound = playSoundToggle.checked;
        plasmoid.configuration.requestTimeout = requestTimeoutToggle.checked ? requestTimeoutSpinBox.value : 0;
        plasmoid.configuration.openCodeUrl = openCodeUrlField.text;
        plasmoid.configuration.openCodeProvider = openCodeProviderValueField.text;
        plasmoid.configuration.openCodeModel = openCodeModelValueField.text;
        plasmoid.configuration.piProvider = piProviderValueField.text;
        plasmoid.configuration.piModel = piModelValueField.text;
        plasmoid.configuration.openCodeStartCommand = openCodeStartCommandField.text;
        plasmoid.configuration.openCodeStopCommand = openCodeStopCommandField.text;
    }

    function cancelKeyringOps() {
        var running = keyringDs.connectedSources;
        for (var i = 0; i < running.length; i++) keyringDs.disconnectSource(running[i])
        var utilityRunning = utilityDs.connectedSources;
        for (var j = 0; j < utilityRunning.length; j++) {
            if (utilityRunning[j].indexOf("#kwallet-") >= 0)
                utilityDs.disconnectSource(utilityRunning[j]);

        }
        pendingOps = ({
        });
    }

    function resetToDefaults() {
        // App name reset handled in reset helper
        providerBox.currentIndex = 0;
        baseUrlField.text = "https://api.openai.com/v1";
        apiKeyField.text = "";
        modelField.text = "";
        anthropicApiKeyField.text = "";
        anthropicModelField.text = "";
        groqBaseUrlField.text = "https://api.groq.com/openai/v1";
        groqApiKeyField.text = "";
        groqModelField.text = "";
        deepSeekBaseUrlField.text = "https://api.deepseek.com";
        deepSeekApiKeyField.text = "";
        deepSeekModelField.text = "";
        miniMaxBaseUrlField.text = "https://api.minimax.io/v1";
        miniMaxApiKeyField.text = "";
        miniMaxModelField.text = "";
        fireworksBaseUrlField.text = "https://api.fireworks.ai/inference/v1";
        fireworksApiKeyField.text = "";
        fireworksModelField.text = "";
        googleBaseUrlField.text = "https://generativelanguage.googleapis.com/v1beta/openai/";
        googleApiKeyField.text = "";
        googleModelField.text = "";
        openRouterBaseUrlField.text = "https://openrouter.ai/api/v1";
        openRouterApiKeyField.text = "";
        openRouterModelField.text = "";
        mistralBaseUrlField.text = "https://api.mistral.ai/v1";
        mistralApiKeyField.text = "";
        mistralModelField.text = "";
        cloudflareBaseUrlField.text = "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1";
        cloudflareApiKeyField.text = "";
        cloudflareModelField.text = "";
        nvidiaBaseUrlField.text = "https://integrate.api.nvidia.com/v1";
        nvidiaApiKeyField.text = "";
        nvidiaModelField.text = "";
        huggingFaceBaseUrlField.text = "https://router.huggingface.co/v1";
        huggingFaceApiKeyField.text = "";
        huggingFaceModelField.text = "";
        xaiBaseUrlField.text = "https://api.x.ai/v1";
        xaiApiKeyField.text = "";
        xaiModelField.text = "";
        lmStudioBaseUrlField.text = "http://localhost:1234/v1";
        lmStudioModelField.text = "";
        localBaseUrlField.text = "http://localhost:11434/v1";
        localModelField.text = "";
        ollamaBaseUrlField.text = "http://localhost:11434/v1";
        ollamaModelField.text = "";
        litellmBaseUrlField.text = "http://localhost:4000/v1";
        litellmApiKeyField.text = "";
        litellmModelField.text = "";
        maritacaBaseUrlField.text = "https://chat.maritaca.ai/api";
        maritacaApiKeyField.text = "";
        maritacaModelField.text = "";
        perplexityBaseUrlField.text = "https://api.perplexity.ai/router/v1";
        perplexityApiKeyField.text = "";
        perplexityModelField.text = "";
        openCodeToggle.checked = false;
        piToggle.checked = false;
        openCodeUrlField.text = "http://127.0.0.1:4096/v1";
        openCodeProviderValueField.text = "";
        openCodeModelValueField.text = "";
        piProviderValueField.text = "";
        piModelValueField.text = "";
        openCodeStartCommandField.text = "env KDE_AI_CHAT_WIDGET=1 nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.";
        openCodeStopCommandField.text = "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stop command launched. || echo No OpenCode process matched.";
        providerModelCandidates = [];
        openCodeProviderCandidates = [];
        openCodeModelCandidates = [];
        openCodeProviderModelMap = ({
        });
        piProviderCandidates = [];
        piModelCandidates = [];
        piProviderModelMap = ({
        });
        requestTimeoutToggle.checked = true;
        requestTimeoutSpinBox.value = 60;
        discoveryStatus = "Settings reset to defaults.";
    }

    horizontalScrollBarPolicy: configZoom > 1.01 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
    Component.onCompleted: {
        if (plasmoid.configuration.appearanceMode === 3 || plasmoid.configuration.appearanceMode > 2)
            plasmoid.configuration.appearanceMode = 0;

        if (openCodeToggle.checked)
            refreshOpenCodeDiscovery();
        else if (piToggle.checked)
            refreshPiDiscovery();
        else
            Qt.callLater(function() { refreshCurrentProviderModels(); });

        // Refresh memory usage
        var cmd = "python3 " + quoteForShell(getHelperPath()) + " get_memory_usage";
        utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());

        // Show a legacy plaintext value while KWallet is being queried, then
        // replace it with the wallet value when available.
        loadPlaintextApiKeyFallbacks();
        // Load secrets from KWallet after the form has initialized. The
        // ordinary KConfig values remain only as a migration fallback; the
        // live widget prefers its in-memory wallet copy.
        pageReady = true;
        Qt.callLater(page.kwalletLoadAll);
    }
    Component.onDestruction: {
        saveGeneralSettingsOnly();
        // Sync the current fields to KWallet before closing.
        kwalletStoreAll();
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: function(event) {
            var step = event.angleDelta.y / 800;
            page.configZoom = Math.max(0.75, Math.min(1.5, page.configZoom + step));
            event.accepted = true;
        }
    }

    P5Support.DataSource {
        id: keyringDs
        engine: "executable"
        connectedSources: []
    }

    P5Support.DataSource {
        id: utilityDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim();
            var err = (data["stderr"] || "").trim();
            if (sourceName.indexOf("kwallet-wallet-list") >= 0) {
                if (out.indexOf("__NO_QDBUS__") >= 0) {
                    availableWalletNames = [];
                    keyringStatus = "qdbus6 / qdbus is missing! KWallet requires Qt DBus tools. Please install 'qt6-tools' (or 'qttools' depending on your Linux distribution) to enable secure KWallet credentials storage.";
                    disconnectSource(sourceName);
                    return;
                }
                availableWalletNames = out === "" ? [] : out.split(/\n+/).filter(function(name) {
                    return name.trim() !== "";
                });
                maybeAdoptDetectedWalletName();
                if (availableWalletNames.length === 0)
                    keyringStatus = "No wallets detected yet. Create one or open KWallet first.";
                else
                    Qt.callLater(page.kwalletLoadAll);
            } else if (sourceName.indexOf("kwallet-refresh-all") >= 0) {
                console.log("KWallet refresh response received (stdout/stderr lengths):", out.length, err.length);
                if (out.indexOf("__KAI_BULK__:") < 0) {
                    return ;
                }
                if (out === "__KAI_BULK__:NO_WALLET") {
                    keyringStatus = "Configured wallet not found. Pick a detected wallet and retry.";
                } else if (out === "__KAI_BULK__:OPEN_FAILED") {
                    keyringStatus = "KWallet did not open the selected wallet.";
                } else if (out === "__KAI_BULK__:NO_FOLDER") {
                    keyringStatus = "Wallet opened, but KDE AI Chat storage is not initialized yet.";
                } else {
                    var lines = out === "" ? [] : out.split(/\n+/);
                    var loaded = 0;
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("__KAI_SECRET__:") !== 0)
                            continue;

                        var rest = lines[i].slice("__KAI_SECRET__:".length);
                        var sep = rest.indexOf(":");
                        if (sep <= 0)
                            continue;

                        var targetId = rest.slice(0, sep);
                        var secretValue = rest.slice(sep + 1);
                        applyLoadedKey(targetId, secretValue);
                        if ((secretValue || "").trim() !== "")
                            loaded++;

                    }
                    keyringStatus = "KWallet refresh finished. Loaded " + loaded + " key(s).";
                }
            } else if (sourceName.indexOf("kwallet-create") >= 0) {
                if (out === "__KAI_INIT__:READY")
                    keyringStatus = "Wallet connection is ready for KDE AI Chat storage.";
                else if (out === "__KAI_INIT__:CREATED")
                    keyringStatus = "KDE AI Chat storage folder was created in the wallet.";
                else if (out === "__KAI_INIT__:OPEN_FAILED")
                    keyringStatus = "KWallet did not open the selected wallet. If the wallet does not exist, KDE should prompt to create it.";
                else
                    keyringStatus = out !== "" ? out : (err !== "" ? err : "Wallet initialization finished.");
                Qt.callLater(page.detectWallets);
            } else if (sourceName.indexOf("kwallet-status-check") >= 0) {
                if (out.indexOf("__KAI_STATUS__:NO_WALLET:") === 0) {
                    var walletList = out.slice("__KAI_STATUS__:NO_WALLET:".length).replace(/\n/g, ", ");
                    keyringStatus = walletList !== "" ? ("Configured wallet not found. Available wallets: " + walletList) : "Configured wallet not found.";
                } else if (out === "__KAI_STATUS__:OPEN_FAILED")
                    keyringStatus = "KWallet could not open the selected wallet.";
                else if (out === "__KAI_STATUS__:NO_FOLDER")
                    keyringStatus = "Wallet is open, but KDE AI Chat storage is not initialized yet. Click Create wallet.";
                else if (out === "__KAI_STATUS__:READY")
                    keyringStatus = "Wallet ready for KDE AI Chat.";
                else
                    keyringStatus = out !== "" ? out : (err !== "" ? err : "Wallet check finished.");
            } else if (sourceName.indexOf("mem-usage-") >= 0) {
                page.memRefreshing = false;
                if (out !== "") {
                    try {
                        var memData = JSON.parse(out);
                        page.memOpenCode = memData.opencode || 0;
                        page.memStt = memData.stt || 0;
                        page.memTts = memData.tts || 0;
                    } catch (e) {
                        console.warn("Failed to parse memory data:", e);
                    }
                }
            } else if (sourceName.indexOf("#pi_models_") >= 0) {
                try {
                    var msg = JSON.parse(out);
                    if (msg.providers && Array.isArray(msg.providers)) {
                        var providers = msg.providers;
                        var ids = [];
                        var modelsByProvider = {};
                        for (var i = 0; i < providers.length; i++) {
                            var provider = providers[i];
                            var providerId = provider && provider.id ? provider.id : "";
                            if (!providerId) continue;
                            if (ids.indexOf(providerId) < 0) ids.push(providerId);
                            var mods = [];
                            if (provider.models && Array.isArray(provider.models)) {
                                mods = provider.models;
                            }
                            modelsByProvider[providerId] = mods;
                        }
                        piProviderCandidates = ids;
                        piProviderModelMap = modelsByProvider;
                        if (ids.length === 0) {
                            piModelCandidates = [];
                            piModelSearch = "";
                            updateFilteredPiModels("");
                            piProviderValueField.text = "";
                            piModelValueField.text = "";
                            discoveryStatus = "Pi agent returned no models.";
                        } else {
                            var selectedProvider = piProviderValueField.text || "";
                            if (ids.indexOf(selectedProvider) < 0)
                                selectedProvider = ids[0];
                            var rememberedModel = piModelValueField.text || "";
                            syncPiProviderSelection(selectedProvider, rememberedModel);
                            discoveryStatus = "Pi models loaded successfully.";
                        }
                    } else if (msg.status === "error" || msg.error) {
                        discoveryStatus = "Helper error: " + (msg.message || msg.error);
                    }
                } catch(e) {
                    discoveryStatus = "Error parsing Pi models: " + out;
                }
            } else {
                discoveryStatus = out !== "" ? out : (err !== "" ? err : "Command finished.");
            }
            disconnectSource(sourceName);
        }
    }

    Kirigami.FormLayout {
        id: formLayout
        width: page.width || 500
        wideMode: false
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 36

        ColumnLayout {
                Kirigami.FormData.label: "Appearance:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: appearanceModeCombo

                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    model: ["Follow system", "Light mode", "Dark mode"]
                }

                Rectangle {
                    visible: showInteractiveGuidesToggle.checked
                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    implicitHeight: appearanceGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: appearanceGuideLayout
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
                            text: "<b>Appearance Modes:</b><br>" +
                                  "Light mode and Dark mode pin the widget to a bright or dark UI.<br>" +
                                  "<b>Follow system</b> uses your Plasma colors and updates with the desktop theme.<br><br>" +
                                  "<i>Note: These themes apply only to the chat widget popup, not this settings page.</i>"
                        }
                    }
                }

            }

            QQC2.CheckBox {
                id: playSoundToggle

                Kirigami.FormData.label: "Notification sound:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Play sound when AI finishes a response"
            }

            RowLayout {
                id: requestTimeoutLayout
                Kirigami.FormData.label: "Request timeout:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.CheckBox {
                    id: requestTimeoutToggle
                    text: "Enable timeout"
                    checked: hasPlasmoidConfig ? (plasmoid.configuration.requestTimeout > 0) : true
                    onCheckedChanged: {
                        if (hasPlasmoidConfig && !checked) {
                            plasmoid.configuration.requestTimeout = 0;
                        } else if (hasPlasmoidConfig && checked && requestTimeoutSpinBox.value === 0) {
                            requestTimeoutSpinBox.value = 60;
                        }
                    }
                }

                QQC2.SpinBox {
                    id: requestTimeoutSpinBox
                    visible: requestTimeoutToggle.checked
                    from: 1
                    to: 600
                    stepSize: 5
                    editable: true
                    value: hasPlasmoidConfig && plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout : 60
                }
                QQC2.Label {
                    visible: requestTimeoutToggle.checked
                    text: "seconds"
                }
            }

            QQC2.CheckBox {
                id: showInteractiveGuidesToggle

                Kirigami.FormData.label: i18n("Interactive Guides:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                checked: hasPlasmoidConfig ? (plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true) : true
                text: checked ? i18n("Guides visible — showing setup instructions") : i18n("Guides hidden")
                onToggled: {
                    if (hasPlasmoidConfig) {
                        plasmoid.configuration.showInteractiveGuides = checked;
                    }
                }
            }

            Rectangle {
                visible: showInteractiveGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: generalGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                border.width: 1

                RowLayout {
                    id: generalGuideLayout
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
                        text: "<b>General Setup Guide</b><br><br>" +
                              "<b>Cloud Providers:</b> Select a provider (like OpenAI or Anthropic), enter your API key, and press <b>Save</b>. Then click <b>Refresh</b> to load available models.<br><br>" +
                              "<b>Local Providers:</b> Services like Ollama or LM Studio operate completely offline and do not require API keys.<br><br>" +
                              "<b>OpenCode Mode:</b> Use this only when you are connecting to your personal OpenCode local server."
                    }
                }
            }

            QQC2.CheckBox {
                id: openCodeToggle

                Kirigami.FormData.label: "OpenCode mode:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enable OpenCode mode"
                onCheckedChanged: {
                    discoveryStatus = "";
                    if (checked) {
                        piToggle.checked = false;
                        if (pageReady)
                            refreshOpenCodeDiscovery();
                    }
                }
            }

            QQC2.CheckBox {
                id: piToggle

                Kirigami.FormData.label: "Pi mode:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enable Pi CLI Agent"
                onCheckedChanged: {
                    if (checked) {
                        openCodeToggle.checked = false;
                        refreshPiDiscovery();
                    }
                }
            }

            Kirigami.Separator {
                visible: !openCodeToggle.checked && !piToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Provider"
            }

            QQC2.ComboBox {
                id: providerBox

                visible: !openCodeToggle.checked && !piToggle.checked
                Kirigami.FormData.label: "Default provider:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                textRole: "text"
                valueRole: "value"
                model: page._buildProviderBoxModel()
                onActivated: {
                    providerModelCandidates = [];
                    discoveryStatus = "";
                    if (pageReady)
                        Qt.callLater(function() { refreshCurrentProviderModels(); });
                }
            }

            QQC2.Button {
                visible: !openCodeToggle.checked && !piToggle.checked
                Kirigami.FormData.label: "Model discovery:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Refresh models for active provider"
                 enabled: !providerRefreshBusy && (!providerNeedsApiKey(providerBox.currentValue || "openai") || providerHasConfiguredKey(providerBox.currentValue || "openai"))
                onClicked: refreshCurrentProviderModels()
            }

            QQC2.BusyIndicator {
                 visible: !openCodeToggle.checked && !piToggle.checked && (openCodeBusy || providerRefreshBusy)
                running: visible
                Kirigami.FormData.label: "Loading:"
            }

            QQC2.ComboBox {
                id: providerModelsCombo

                function syncText() {
                    var val = activeProviderModelValue();
                    var idx = providerModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: !openCodeToggle.checked && !piToggle.checked && providerModelVisible(providerBox.currentValue || "openai")
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: providerModelCandidates
                Component.onCompleted: {
                    syncText();
                }
                onModelChanged: {
                    syncText();
                }
                onEditTextChanged: {
                    if (activeFocus)
                        applyDetectedModelToActiveProvider(editText);

                }
                onActivated: {
                    applyDetectedModelToActiveProvider(currentText);
                    editText = currentText;
                }
            }

            QQC2.Label {
                visible: discoveryStatus !== ""
                Kirigami.FormData.label: "Status:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: discoveryStatus
                wrapMode: Text.Wrap
                opacity: 0.8
            }

            Kirigami.Separator {
                visible: openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "OpenCode"
            }

            QQC2.TextField {
                id: openCodeUrlField

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode URL:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://127.0.0.1:4096/v1"
            }

            Flow {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode server:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: "Start server"
                    enabled: !openCodeBusy
                    onClicked: {
                        discoveryStatus = "Running OpenCode start command...";
                        var cmd = "sh -lc '" + shellEscape(openCodeStartCommandField.text || "env KDE_AI_CHAT_WIDGET=1 nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.") + "'";
                        utilityDs.connectSource(cmd + " #opencode-start");
                    }
                }

                QQC2.Button {
                    text: "Check server"
                    enabled: !openCodeBusy
                    onClicked: probeOpenCodeProviders(openCodeUrlField.text)
                }

                QQC2.Button {
                    text: "Refresh"
                    enabled: !openCodeBusy
                    onClicked: refreshOpenCodeDiscovery()
                }

                QQC2.Button {
                    text: "Kill server"
                    enabled: !openCodeBusy
                    onClicked: {
                        discoveryStatus = "Running OpenCode stop command...";
                        var cmd = "sh -lc '" + shellEscape(openCodeStopCommandField.text || "pkill -f opencode") + "'";
                        utilityDs.connectSource(cmd + " #opencode-stop");
                    }
                }

            }

            QQC2.BusyIndicator {
                visible: openCodeToggle.checked && openCodeBusy
                running: visible
                Kirigami.FormData.label: "Loading:"
            }

            QQC2.ComboBox {
                id: openCodeProvidersCombo

                visible: openCodeToggle.checked && openCodeProviderCandidates.length > 0
                Kirigami.FormData.label: "Providers:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: openCodeProviderCandidates
                onActivated: {
                    setOpenCodeProviderValue(currentText);
                    probeOpenCodeModels(openCodeUrlField.text, currentText);
                }
            }

            QQC2.Button {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode models:"
                text: "Refresh models"
                onClicked: probeOpenCodeModels(openCodeUrlField.text, activeOpenCodeProvider())
            }

            QQC2.ComboBox {
                id: openCodeModelsCombo

                function syncText() {
                    var val = openCodeModelValueField.text || "";
                    var idx = openCodeModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: openCodeModelCandidates
                Component.onCompleted: {
                    syncText();
                }
                onModelChanged: {
                    syncText();
                }
                onEditTextChanged: {
                    if (activeFocus)
                        setOpenCodeModelValue(editText);

                }
                onActivated: {
                    setOpenCodeModelValue(currentText);
                    editText = currentText;
                }
            }

            QQC2.TextField {
                visible: openCodeToggle.checked && (false)
                Kirigami.FormData.label: filteredOpenCodeModels.length > 0 ? "Custom model:" : "OpenCode model (optional):"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Enter your OpenCode model id"
                text: openCodeModelValueField.text
                onTextChanged: {
                    openCodeModelSearch = text;
                    updateFilteredOpenCodeModels(text);
                    setOpenCodeModelValue(text);
                }
            }

            QQC2.TextField {
                id: openCodeStartCommandField

                visible: false
            }

            QQC2.TextField {
                id: openCodeStopCommandField

                visible: false
                text: plasmoid.configuration.openCodeStopCommand || ""
            }

            Kirigami.Separator {
                visible: piToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Pi Agent Details"
            }

            QQC2.ComboBox {
                id: piProvidersCombo

                visible: piToggle.checked && piProviderCandidates.length > 0
                Kirigami.FormData.label: "Providers:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: piProviderCandidates
                onActivated: {
                    piProviderValueField.text = currentText;
                    syncPiProviderSelection(currentText, "");
                }
            }

            QQC2.Button {
                visible: piToggle.checked
                Kirigami.FormData.label: "Pi models:"
                text: "Refresh models"
                onClicked: refreshPiDiscovery()
            }

            QQC2.ComboBox {
                id: piModelsCombo

                function syncText() {
                    var val = piModelValueField.text || "";
                    var idx = piModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: piToggle.checked
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: piModelCandidates
                Component.onCompleted: syncText()
                onModelChanged: syncText()
                onEditTextChanged: {
                    if (activeFocus)
                        piModelValueField.text = editText;
                }
                onActivated: {
                    piModelValueField.text = currentText;
                }
                onAccepted: {
                    piModelValueField.text = editText;
                }
            }

            QQC2.TextField {
                id: piProviderValueField
                visible: false
                text: plasmoid.configuration.piProvider || ""
            }

            QQC2.TextField {
                id: piModelValueField
                visible: false
                text: plasmoid.configuration.piModel || ""
            }


            QQC2.TextField {
                id: openCodeProviderValueField

                visible: false
                text: plasmoid.configuration.openCodeProvider || ""
            }

            QQC2.TextField {
                id: openCodeModelValueField

                visible: false
                text: plasmoid.configuration.openCodeModel || ""
            }

            QQC2.TextField {
                id: walletNameField

                visible: false
                text: "kdeaichatwallet"
            }

            QQC2.Label {
                visible: !openCodeToggle.checked && !piToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                text: keyringBusy ? i18n("KWallet is handling API keys…") : (keyringStatus || i18n("API keys are stored in KWallet when it is available; existing KConfig values remain a compatibility fallback."))
                opacity: 0.72
            }

            QQC2.TextField {
                id: baseUrlField

                Kirigami.FormData.label: "OpenAI URL:"
                visible: page.providerEnabled("openai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.openai.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "OpenAI key:"
                visible: page.providerEnabled("openai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: apiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - apiKeyShowHide.implicitWidth - parent.spacing
                    echoMode: apiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("openai", text);
                        page.refreshIfActiveProvider("openai");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: openaiSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("openai", apiKeyField.text);
                        page.refreshIfActiveProvider("openai");
                        saved = true;
                        openaiSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: apiKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openai")
                Kirigami.FormData.label: "OpenAI model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the OpenAI API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: modelField

                Kirigami.FormData.label: "OpenAI model:"
                visible: page.providerModelVisible("openai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
                text: activeProviderModelValue()
                onTextChanged: setActiveProviderModelValue(text)
            }

            RowLayout {
                Kirigami.FormData.label: "Anthropic key:"
                visible: page.providerEnabled("anthropic")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: anthropicApiKeyField

                    Layout.fillWidth: true
                    echoMode: anthropicKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("anthropic", text);
                        page.refreshIfActiveProvider("anthropic");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: anthropicSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("anthropic", anthropicApiKeyField.text);
                        page.refreshIfActiveProvider("anthropic");
                        saved = true;
                        anthropicSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: anthropicKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("anthropic")
                Kirigami.FormData.label: "Anthropic model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Anthropic API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: anthropicModelField

                Kirigami.FormData.label: "Anthropic model:"
                visible: page.providerModelVisible("anthropic") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: groqBaseUrlField

                Kirigami.FormData.label: "Groq URL:"
                visible: page.providerEnabled("groq")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.groq.com/openai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Groq key:"
                visible: page.providerEnabled("groq")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: groqApiKeyField

                    Layout.fillWidth: true
                    echoMode: groqKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("groq", text);
                        page.refreshIfActiveProvider("groq");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: groqSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("groq", groqApiKeyField.text);
                        page.refreshIfActiveProvider("groq");
                        saved = true;
                        groqSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: groqKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("groq")
                Kirigami.FormData.label: "Groq model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Groq API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: groqModelField

                Kirigami.FormData.label: "Groq model:"
                visible: page.providerModelVisible("groq") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: deepSeekBaseUrlField

                Kirigami.FormData.label: "DeepSeek URL:"
                visible: page.providerEnabled("deepseek")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.deepseek.com"
            }

            RowLayout {
                Kirigami.FormData.label: "DeepSeek key:"
                visible: page.providerEnabled("deepseek")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: deepSeekApiKeyField

                    Layout.fillWidth: true
                    echoMode: deepSeekKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("deepseek", text);
                        page.refreshIfActiveProvider("deepseek");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: deepseekSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("deepseek", deepseekApiKeyField.text);
                        page.refreshIfActiveProvider("deepseek");
                        saved = true;
                        deepseekSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: deepSeekKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("deepseek")
                Kirigami.FormData.label: "DeepSeek model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the DeepSeek API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: deepSeekModelField

                Kirigami.FormData.label: "DeepSeek model:"
                visible: page.providerModelVisible("deepseek") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: miniMaxBaseUrlField

                Kirigami.FormData.label: "MiniMax URL:"
                visible: page.providerEnabled("minimax")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.minimax.io/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "MiniMax key:"
                visible: page.providerEnabled("minimax")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: miniMaxApiKeyField

                    Layout.fillWidth: true
                    echoMode: miniMaxKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("minimax", text);
                        page.refreshIfActiveProvider("minimax");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: minimaxSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("minimax", minimaxApiKeyField.text);
                        page.refreshIfActiveProvider("minimax");
                        saved = true;
                        minimaxSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: miniMaxKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("minimax")
                Kirigami.FormData.label: "MiniMax model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the MiniMax API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: miniMaxModelField

                Kirigami.FormData.label: "MiniMax model:"
                visible: page.providerModelVisible("minimax") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "MiniMax-M2.7"
            }

            QQC2.TextField {
                id: fireworksBaseUrlField

                Kirigami.FormData.label: "Fireworks URL:"
                visible: page.providerEnabled("fireworks")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.fireworks.ai/inference/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Fireworks key:"
                visible: page.providerEnabled("fireworks")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: fireworksApiKeyField

                    Layout.fillWidth: true
                    echoMode: fireworksKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("fireworks", text);
                        page.refreshIfActiveProvider("fireworks");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: fireworksSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("fireworks", fireworksApiKeyField.text);
                        page.refreshIfActiveProvider("fireworks");
                        saved = true;
                        fireworksSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: fireworksKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("fireworks")
                Kirigami.FormData.label: "Fireworks model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Fireworks API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: fireworksModelField

                Kirigami.FormData.label: "Fireworks model:"
                visible: page.providerModelVisible("fireworks") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: googleBaseUrlField

                Kirigami.FormData.label: "Google URL:"
                visible: page.providerEnabled("google")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://generativelanguage.googleapis.com/v1beta/openai/"
            }

            RowLayout {
                Kirigami.FormData.label: "Google key:"
                visible: page.providerEnabled("google")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: googleApiKeyField

                    Layout.fillWidth: true
                    echoMode: googleKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("google", text);
                        page.refreshIfActiveProvider("google");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: googleSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("google", googleApiKeyField.text);
                        page.refreshIfActiveProvider("google");
                        saved = true;
                        googleSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: googleKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("google")
                Kirigami.FormData.label: "Google model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Gemini API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: googleModelField

                Kirigami.FormData.label: "Google model:"
                visible: page.providerModelVisible("google") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gemini-3-flash-preview"
            }

            QQC2.TextField {
                id: openRouterBaseUrlField

                Kirigami.FormData.label: "OpenRouter URL:"
                visible: page.providerEnabled("openrouter")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://openrouter.ai/api/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "OpenRouter key:"
                visible: page.providerEnabled("openrouter")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: openRouterApiKeyField

                    Layout.fillWidth: true
                    echoMode: openRouterKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("openrouter", text);
                        page.refreshIfActiveProvider("openrouter");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: openrouterSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("openrouter", openrouterApiKeyField.text);
                        page.refreshIfActiveProvider("openrouter");
                        saved = true;
                        openrouterSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: openRouterKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openrouter")
                Kirigami.FormData.label: "OpenRouter model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the OpenRouter API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: openRouterModelField

                Kirigami.FormData.label: "OpenRouter model:"
                visible: page.providerModelVisible("openrouter") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: mistralBaseUrlField

                Kirigami.FormData.label: "Mistral URL:"
                visible: page.providerEnabled("mistral")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.mistral.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Mistral key:"
                visible: page.providerEnabled("mistral")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: mistralApiKeyField

                    Layout.fillWidth: true
                    echoMode: mistralKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("mistral", text);
                        page.refreshIfActiveProvider("mistral");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: mistralSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("mistral", mistralApiKeyField.text);
                        page.refreshIfActiveProvider("mistral");
                        saved = true;
                        mistralSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: mistralKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("mistral")
                Kirigami.FormData.label: "Mistral model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Mistral API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: mistralModelField

                Kirigami.FormData.label: "Mistral model:"
                visible: page.providerModelVisible("mistral") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Fetch models to choose one"
            }

            QQC2.TextField {
                id: cloudflareBaseUrlField

                Kirigami.FormData.label: "Cloudflare URL:"
                visible: page.providerEnabled("cloudflare")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Cloudflare key:"
                visible: page.providerEnabled("cloudflare")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: cloudflareApiKeyField

                    Layout.fillWidth: true
                    echoMode: cloudflareKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("cloudflare", text);
                        page.refreshIfActiveProvider("cloudflare");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: cloudflareSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("cloudflare", cloudflareApiKeyField.text);
                        page.refreshIfActiveProvider("cloudflare");
                        saved = true;
                        cloudflareSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: cloudflareKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("cloudflare")
                Kirigami.FormData.label: "Cloudflare model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Cloudflare API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: cloudflareModelField

                Kirigami.FormData.label: "Cloudflare model:"
                visible: page.providerModelVisible("cloudflare") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: nvidiaBaseUrlField

                Kirigami.FormData.label: "NVIDIA NIM URL:"
                visible: page.providerEnabled("nvidia")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://integrate.api.nvidia.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "NVIDIA NIM key:"
                visible: page.providerEnabled("nvidia")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: nvidiaApiKeyField

                    Layout.fillWidth: true
                    echoMode: nvidiaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("nvidia", text);
                        page.refreshIfActiveProvider("nvidia");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: nvidiaSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("nvidia", nvidiaApiKeyField.text);
                        page.refreshIfActiveProvider("nvidia");
                        saved = true;
                        nvidiaSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: nvidiaKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("nvidia")
                Kirigami.FormData.label: "NVIDIA NIM model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the NVIDIA NIM API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: nvidiaModelField

                Kirigami.FormData.label: "NVIDIA NIM model:"
                visible: page.providerModelVisible("nvidia") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: huggingFaceBaseUrlField

                Kirigami.FormData.label: "HF URL:"
                visible: page.providerEnabled("huggingface")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://router.huggingface.co/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "HF token:"
                visible: page.providerEnabled("huggingface")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: huggingFaceApiKeyField

                    Layout.fillWidth: true
                    echoMode: huggingFaceKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("huggingface", text);
                        page.refreshIfActiveProvider("huggingface");
                    }
                }

                QQC2.Button {
                    id: huggingFaceKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("huggingface")
                Kirigami.FormData.label: "HF model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Hugging Face token first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: huggingFaceModelField

                Kirigami.FormData.label: "HF model:"
                visible: page.providerModelVisible("huggingface") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: xaiBaseUrlField

                Kirigami.FormData.label: "xAI URL:"
                visible: page.providerEnabled("xai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.x.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "xAI key:"
                visible: page.providerEnabled("xai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: xaiApiKeyField

                    Layout.fillWidth: true
                    echoMode: xaiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("xai", text);
                        page.refreshIfActiveProvider("xai");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: xaiSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("xai", xaiApiKeyField.text);
                        page.refreshIfActiveProvider("xai");
                        saved = true;
                        xaiSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: xaiKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("xai")
                Kirigami.FormData.label: "xAI model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the xAI API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: xaiModelField

                Kirigami.FormData.label: "xAI model:"
                visible: page.providerModelVisible("xai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "grok-2-latest"
            }

            QQC2.TextField {
                id: lmStudioBaseUrlField

                Kirigami.FormData.label: "LM Studio URL:"
                visible: page.providerEnabled("lmstudio")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:1234/v1"
            }

            QQC2.TextField {
                id: lmStudioModelField

                Kirigami.FormData.label: "LM Studio model:"
                visible: page.providerModelVisible("lmstudio") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Load a model in LM Studio, then refresh models"
            }

            QQC2.TextField {
                id: localBaseUrlField

                Kirigami.FormData.label: "Local URL:"
                visible: page.providerEnabled("local")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: localModelField

                Kirigami.FormData.label: "Local model:"
                visible: page.providerModelVisible("local") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: ollamaBaseUrlField

                Kirigami.FormData.label: "Ollama URL:"
                visible: page.providerEnabled("ollama")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: ollamaModelField

                Kirigami.FormData.label: "Ollama model:"
                visible: page.providerModelVisible("ollama") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: litellmBaseUrlField

                Kirigami.FormData.label: "LiteLLM URL:"
                visible: page.providerEnabled("litellm")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:4000/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "LiteLLM key:"
                visible: page.providerEnabled("litellm")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: litellmApiKeyField

                    Layout.fillWidth: true
                    echoMode: litellmKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("litellm", text);
                        page.refreshIfActiveProvider("litellm");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: litellmSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("litellm", litellmApiKeyField.text);
                        page.refreshIfActiveProvider("litellm");
                        saved = true;
                        litellmSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: litellmKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("litellm")
                Kirigami.FormData.label: "LiteLLM model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the LiteLLM API key first if required, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: litellmModelField

                Kirigami.FormData.label: "LiteLLM model:"
                visible: page.providerModelVisible("litellm") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Refresh models to choose one"
            }

            QQC2.TextField {
                id: maritacaBaseUrlField
                Kirigami.FormData.label: "Maritaca URL:"
                visible: page.providerEnabled("maritaca")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://chat.maritaca.ai/api"
            }

            RowLayout {
                Kirigami.FormData.label: "Maritaca key:"
                visible: page.providerEnabled("maritaca")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: maritacaApiKeyField
                    Layout.fillWidth: true
                    echoMode: maritacaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("maritaca", text);
                        page.refreshIfActiveProvider("maritaca");
                    }
                }
                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    onClicked: {
                        page.saveKey("maritaca", maritacaApiKeyField.text);
                        page.refreshIfActiveProvider("maritaca");
                        saved = true;
                        maritacaSaveTimer.start();
                    }
                    Timer {
                        id: maritacaSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                }
                QQC2.Button {
                    id: maritacaKeyShowHide
                    checkable: true
                    text: checked ? "Hide" : "Show"
                }
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("maritaca")
                Kirigami.FormData.label: "Maritaca model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Maritaca API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: maritacaModelField
                Kirigami.FormData.label: "Maritaca model:"
                visible: page.providerModelVisible("maritaca") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Fetch models to choose one"
            }

            QQC2.TextField {
                id: perplexityBaseUrlField
                Kirigami.FormData.label: "Perplexity URL:"
                visible: page.providerEnabled("perplexity")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.perplexity.ai/router/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Perplexity key:"
                visible: page.providerEnabled("perplexity")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: perplexityApiKeyField
                    Layout.fillWidth: true
                    echoMode: perplexityKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("perplexity", text);
                        page.refreshIfActiveProvider("perplexity");
                    }
                }
                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    onClicked: {
                        page.saveKey("perplexity", perplexityApiKeyField.text);
                        page.refreshIfActiveProvider("perplexity");
                        saved = true;
                        perplexitySaveTimer.start();
                    }
                    Timer {
                        id: perplexitySaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                }
                QQC2.Button {
                    id: perplexityKeyShowHide
                    checkable: true
                    text: checked ? "Hide" : "Show"
                }
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("perplexity")
                Kirigami.FormData.label: "Perplexity model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter a Perplexity API key, then refresh models or type a Gateway model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: perplexityModelField
                Kirigami.FormData.label: "Perplexity model:"
                visible: page.providerModelVisible("perplexity") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Fetch models to choose one"
            }

        // ── Other Providers ──────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Other Providers")
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: customProvLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            border.width: 1
            radius: 6

            ColumnLayout {
                id: customProvLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: i18n("Configure multiple custom AI provider endpoints simultaneously:")
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    opacity: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: newCpName
                        placeholderText: "Provider Name (e.g. Enterprise LLM)"
                        Layout.fillWidth: true
                    }

                    QQC2.ComboBox {
                        id: newCpType
                        model: ["openai-compat", "anthropic"]
                        Layout.preferredWidth: 130
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: newCpUrl
                        placeholderText: "Base URL (e.g. https://api.myllm.com/v1)"
                        Layout.fillWidth: true
                    }

                    QQC2.TextField {
                        id: newCpKey
                        placeholderText: "API Key (optional)"
                        echoMode: QQC2.TextField.Password
                        Layout.preferredWidth: 150
                    }

                    QQC2.TextField {
                        id: newCpModel
                        placeholderText: "Model ID"
                        Layout.preferredWidth: 120
                    }

                     QQC2.Button {
                         text: page.editingCustomProviderId ? i18n("Save Provider") : i18n("Add Provider")
                         icon.name: "list-add"
                         enabled: newCpName.text.trim().length > 0 && Sec.validateHttpUrl(newCpUrl.text.trim()) !== ""
                         onClicked: {
                             var list = [];
                             try { list = JSON.parse(page.cfg_customProvidersJson || "[]"); } catch (e) { list = []; }
                             var requestedId = String(page.editingCustomProviderId || "");
                             var entry = {
                                 "id": /^custom_[A-Za-z0-9._:-]{1,100}$/.test(requestedId) ? requestedId : ("custom_" + Date.now()),
                                 "name": newCpName.text.trim(),
                                 "type": newCpType.currentText,
                                 "baseUrl": newCpUrl.text.trim(),
                                 "apiKey": newCpKey.text.trim(),
                                 "model": newCpModel.text.trim()
                             };
                             var replaced = false;
                             for (var n = 0; n < list.length; n++) {
                                 if (list[n] && list[n].id === entry.id) { list[n] = entry; replaced = true; break; }
                             }
                             if (!replaced) list.push(entry);
                             var oldVal = providerBox.currentValue;
                             page.cfg_customProvidersJson = JSON.stringify(list);
                            if (plasmoid && plasmoid.configuration) {
                                plasmoid.configuration.customProvidersJson = JSON.stringify(list);
                            }
                            if (entry.apiKey)
                                page.kwalletStore(entry.id, entry.apiKey, false);
                            else
                                page.kwalletRemove(entry.id);
                            providerBox.model = page._buildProviderBoxModel();
                            for (var j = 0; j < providerBox.model.length; j++) {
                                if (providerBox.model[j].value === oldVal) {
                                    providerBox.currentIndex = j; break;
                                }
                            }
                            newCpName.text = "";
                             newCpUrl.text = "";
                             newCpKey.text = "";
                             newCpModel.text = "";
                             page.editingCustomProviderId = "";
                         }
                     }
                     QQC2.Button {
                         visible: page.editingCustomProviderId !== ""
                         text: i18n("Cancel")
                         onClicked: {
                             page.editingCustomProviderId = "";
                             newCpName.text = ""; newCpUrl.text = ""; newCpKey.text = ""; newCpModel.text = "";
                         }
                     }
                }

                ListView {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(180, count * 50)
                    clip: true
                    model: {
                        try { return JSON.parse(page.cfg_customProvidersJson || "[]"); }
                        catch(e) { return []; }
                    }
                    delegate: Rectangle {
                        width: parent.width
                        implicitHeight: 44
                        color: index % 2 === 0 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02) : Qt.rgba(0,0,0,0)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            Kirigami.Icon {
                                source: "network-server"
                                implicitWidth: 18
                                implicitHeight: 18
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                QQC2.Label {
                                    text: modelData.name + " (" + modelData.type + ")"
                                    font.bold: true
                                }
                                QQC2.Label {
                                    text: modelData.baseUrl + (modelData.model ? (" | model: " + modelData.model) : "")
                                    font.pointSize: 8
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                }
                            }

                             QQC2.ToolButton {
                                 icon.name: "document-edit"
                                 QQC2.ToolTip.text: i18n("Edit provider")
                                 onClicked: {
                                     page.editingCustomProviderId = modelData.id || "";
                                     newCpName.text = modelData.name || "";
                                     newCpType.currentIndex = newCpType.model.indexOf(modelData.type || "openai-compat");
                                     if (newCpType.currentIndex < 0) newCpType.currentIndex = 0;
                                     newCpUrl.text = modelData.baseUrl || "";
                                     newCpKey.text = modelData.apiKey || "";
                                     newCpModel.text = modelData.model || "";
                                 }
                             }

                             QQC2.ToolButton {
                                 icon.name: "edit-delete"
                                onClicked: {
                                    var oldVal = providerBox.currentValue;
                                    var list = JSON.parse(page.cfg_customProvidersJson || "[]");
                                    var removedId = list[index] && list[index].id ? String(list[index].id) : "";
                                    list.splice(index, 1);
                                    page.cfg_customProvidersJson = JSON.stringify(list);
                                    if (plasmoid && plasmoid.configuration) {
                                        plasmoid.configuration.customProvidersJson = JSON.stringify(list);
                                    }
                                    if (removedId)
                                        page.kwalletRemove(removedId);
                                    providerBox.model = page._buildProviderBoxModel();
                                    for (var j = 0; j < providerBox.model.length; j++) {
                                        if (providerBox.model[j].value === oldVal) {
                                            providerBox.currentIndex = j; break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Advanced"
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                text: "Settings are persisted automatically by KDE when you press Apply or OK."
                opacity: 0.8
            }

            QQC2.Button {
                Kirigami.FormData.label: "Reset settings:"
                text: "Reset to defaults"
                onClicked: page.resetToDefaults()
            }

        }
    }
