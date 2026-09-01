// ConfigGeneralLogic.js - Extracted logic for ConfigGeneral
//
// LINKAGE RELATIONSHIPS:
// - ConfigGeneralLogic.js: JavaScript file containing the business logic and helper functions for ConfigGeneral.qml.
// - Linked to ConfigGeneral.qml:
//   It is imported in ConfigGeneral.qml as ConfigGeneralLogic.
//   Functions inside this file accept the 'page' parameter, representing the ConfigGeneral instance, allowing access to its QML components and properties.

function debugLog() {
if (page.debugMode) {
let args = Array.prototype.slice.call(arguments);
console.log.apply(console, args);
}
}


function translate(text) {
return Translations.translate(text, page.cfg_language);
}


function updateFilteredProviderModels(searchText) {
let search = (searchText || "").toLowerCase();
if (search === "") {
page.filteredProviderModels = page.providerModelCandidates;
} else {
let filtered = [];
for (let i = 0; i < page.providerModelCandidates.length; i++) {
if (page.providerModelCandidates[i].toLowerCase().indexOf(search) >= 0)
filtered.push(page.providerModelCandidates[i]);
}
page.filteredProviderModels = filtered;
}
}


function updateFilteredOpenCodeModels(searchText) {
let search = (searchText || "").toLowerCase();
if (search === "") {
page.filteredOpenCodeModels = page.openCodeModelCandidates;
} else {
let filtered = [];
for (let i = 0; i < page.openCodeModelCandidates.length; i++) {
if (page.openCodeModelCandidates[i].toLowerCase().indexOf(search) >= 0)
filtered.push(page.openCodeModelCandidates[i]);
}
page.filteredOpenCodeModels = filtered;
}
}


function effectiveWalletName() {
let configuredName = (page.walletNameField.text || "").trim();
if (configuredName !== "")
return configuredName;
if (page.availableWalletNames.length > 0)
return page.availableWalletNames[0];
return "kdewallet";
}


function maybeAdoptDetectedWalletName() {
if (page.availableWalletNames.length === 0)
return ;
let configured = (page.walletNameField.text || "").trim();
if (configured === "") {
page.walletNameField.text = page.availableWalletNames[0];
return ;
}
for (let i = 0; i < page.availableWalletNames.length; i++) {
if (page.availableWalletNames[i].toLowerCase() === configured.toLowerCase()) {
page.walletNameField.text = page.availableWalletNames[i];
return ;
}
}
}


function detectWallets() {
page.utilityDs.connectSource("sh -c \"if ! command -v qdbus6 >/dev/null 2>&1 && ! command -v qdbus >/dev/null 2>&1; then echo '__NO_QDBUS__'; else qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null || qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null; fi\" #kwallet-wallet-list");
}


function setActiveProviderModelValue(value) {
    currentProviderConfig().modelField.text = value || "";
}


function activeProviderModelValue() {
    return currentProviderConfig().modelField.text || "";
}


function walletReadCommand(walletName, keyName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(page.walletFolderName);
let escapedKey = shellEscape(keyName);
let escapedAppId = shellEscape(page.walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_LOAD__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_LOAD__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_FOLDER\"; exit 0; fi; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_ENTRY\"; exit 0; fi; " + "secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_SECRET__:%s\" \"$secret\"'";
}


function walletWriteCommand(walletName, keyName, value, autoPrompt) {
if (autoPrompt === undefined) autoPrompt = true;
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(page.walletFolderName);
let escapedKey = shellEscape(keyName);
let escapedValue = shellEscape(value);
let escapedAppId = shellEscape(page.walletAppId);
let checkOpenScript = "";
if (!autoPrompt) {
checkOpenScript = "if ! $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.isOpen \"$wallet\" 2>/dev/null | grep -q true; then printf \"__KAI_STORE__:NOT_UNLOCKED\"; exit 0; fi; ";
}
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "value='\''" + escapedValue + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + checkOpenScript + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STORE__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" >/dev/null 2>&1; fi; " + "result=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.writePassword \"$handle\" \"$folder\" \"$key\" \"$value\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_STORE__:%s\" \"$result\"'";
}


function walletInitCommand(walletName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(page.walletFolderName);
let escapedAppId = shellEscape(page.walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_INIT__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_INIT__:READY\"; else created=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); if [ \"$created\" = true ]; then printf \"__KAI_INIT__:CREATED\"; else printf \"__KAI_INIT__:CREATE_FAILED\"; fi; fi; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1'";
}


function walletStatusCommand(walletName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(page.walletFolderName);
let escapedAppId = shellEscape(page.walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_STATUS__:NO_WALLET:%s\" \"$wallets\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STATUS__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_STATUS__:READY\"; else printf \"__KAI_STATUS__:NO_FOLDER\"; fi'";
}


function walletBulkReadCommand(walletName, autoPrompt) {
return WalletService.buildBulkReadCommand(walletName, ProviderService.getApiKeyProviderIds(), page.walletFolderName, page.walletAppId, autoPrompt);
}


function shellEscape(s) {
return Sec.sanitizeForShell(s || "").replace(/'/g, "'\\''");
}


function copyToClipboard(textValue) {
let text = textValue || "";
// Sanitize first so the value cannot be re-evaluated as shell
// grammar by the outer `sh -c` wrapper. See the same function
// in main.qml for the rationale.
let safe = Sec.sanitizeForShell(text);
let cmd = "sh -c 'if command -v wl-copy >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | xclip -selection clipboard; " + "else echo \"Clipboard tool missing: install wl-clipboard or xclip\" 1>&2; exit 1; fi'";
page.utilityDs.connectSource(cmd + " #clipboard-copy");
}


function providerEnabled(providerId) {
return !page.openCodeToggle.checked && page.providerBox.currentValue === providerId;
}


function providerNeedsApiKey(providerId) {
return providerId !== "local" && providerId !== "lmstudio" && providerId !== "ollama" && providerId !== "litellm" && providerId !== "pollinations";
}


function providerHasConfiguredKey(providerId) {
if (providerId === "anthropic")
return (page.anthropicApiKeyField.text || "").trim() !== "";
if (providerId === "groq")
return (page.groqApiKeyField.text || "").trim() !== "";
if (providerId === "deepseek")
return (page.deepSeekApiKeyField.text || "").trim() !== "";
if (providerId === "minimax")
return (page.miniMaxApiKeyField.text || "").trim() !== "";
if (providerId === "fireworks")
return (page.fireworksApiKeyField.text || "").trim() !== "";
if (providerId === "google")
return (page.googleApiKeyField.text || "").trim() !== "";
if (providerId === "openrouter")
return (page.openRouterApiKeyField.text || "").trim() !== "";
if (providerId === "mistral")
return (page.mistralApiKeyField.text || "").trim() !== "";
if (providerId === "cloudflare")
return (page.cloudflareApiKeyField.text || "").trim() !== "";
if (providerId === "nvidia")
return (page.nvidiaApiKeyField.text || "").trim() !== "";
if (providerId === "huggingface")
return (page.huggingFaceApiKeyField.text || "").trim() !== "";
if (providerId === "xai")
return (page.xaiApiKeyField.text || "").trim() !== "";
if (providerId === "litellm")
return (page.litellmApiKeyField.text || "").trim() !== "";
if (providerId === "qwen")
return (page.qwenApiKeyField.text || "").trim() !== "";
if (providerId === "moonshot")
return (page.moonshotApiKeyField.text || "").trim() !== "";
if (providerId === "mimo")
return (page.mimoApiKeyField.text || "").trim() !== "";
if (providerId === "maritaca")
return (page.maritacaApiKeyField.text || "").trim() !== "";
if (providerId === "openai")
return (page.apiKeyField.text || "").trim() !== "";
if (providerId === "openai-image")
return (page.apiKeyField.text || "").trim() !== "";
if (providerId === "google-image")
return (page.googleApiKeyField.text || "").trim() !== "";
if (providerId === "huggingface-image")
return (page.huggingfaceImageApiKeyField.text || "").trim() !== "";
if (providerId === "together-image")
return (page.togetherImageApiKeyField.text || "").trim() !== "";
if (providerId === "stability-image")
return (page.stabilityApiKeyField.text || "").trim() !== "";
if (providerId === "replicate-image")
return (page.replicateApiKeyField.text || "").trim() !== "";
return true;
}


function refreshIfActiveProvider(providerId) {
if (page.providerBox.currentValue === providerId)
refreshCurrentProviderModels();
}


function providerModelVisible(providerId) {
return providerEnabled(providerId) && (!providerNeedsApiKey(providerId) || providerHasConfiguredKey(providerId));
}


function providerNeedsKeyHintVisible(providerId) {
return providerEnabled(providerId) && providerNeedsApiKey(providerId) && !providerHasConfiguredKey(providerId);
}


function currentProviderDisplayName() {
return page.providerBox.currentText || "Provider";
}


function currentProviderConfig() {
    let p = page.providerBox.currentValue || "openai";
    if (p === "anthropic")
        return {
            "id": p,
            "type": "anthropic",
            "baseUrl": "https://api.anthropic.com/v1",
            "apiKey": page.anthropicApiKeyField.text,
            "modelField": page.anthropicModelField
        };
    if (p === "local")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.localBaseUrlField.text,
            "apiKey": "",
            "modelField": page.localModelField
        };
    if (p === "groq")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.groqBaseUrlField.text,
            "apiKey": page.groqApiKeyField.text,
            "modelField": page.groqModelField
        };
    if (p === "deepseek")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.deepSeekBaseUrlField.text,
            "apiKey": page.deepSeekApiKeyField.text,
            "modelField": page.deepSeekModelField
        };
    if (p === "minimax")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.miniMaxBaseUrlField.text,
            "apiKey": page.miniMaxApiKeyField.text,
            "modelField": page.miniMaxModelField
        };
    if (p === "fireworks")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.fireworksBaseUrlField.text,
            "apiKey": page.fireworksApiKeyField.text,
            "modelField": page.fireworksModelField
        };
    if (p === "google")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.googleBaseUrlField.text,
            "apiKey": page.googleApiKeyField.text,
            "modelField": page.googleModelField
        };
    if (p === "openrouter")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.openRouterBaseUrlField.text,
            "apiKey": page.openRouterApiKeyField.text,
            "modelField": page.openRouterModelField
        };
    if (p === "mistral")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.mistralBaseUrlField.text,
            "apiKey": page.mistralApiKeyField.text,
            "modelField": page.mistralModelField
        };
    if (p === "cloudflare")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.cloudflareBaseUrlField.text,
            "apiKey": page.cloudflareApiKeyField.text,
            "modelField": page.cloudflareModelField
        };
    if (p === "nvidia")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.nvidiaBaseUrlField.text,
            "apiKey": page.nvidiaApiKeyField.text,
            "modelField": page.nvidiaModelField
        };
    if (p === "huggingface")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.huggingFaceBaseUrlField.text,
            "apiKey": page.huggingFaceApiKeyField.text,
            "modelField": page.huggingFaceModelField
        };
    if (p === "xai")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.xaiBaseUrlField.text,
            "apiKey": page.xaiApiKeyField.text,
            "modelField": page.xaiModelField
        };
    if (p === "lmstudio")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.lmStudioBaseUrlField.text,
            "apiKey": "",
            "modelField": page.lmStudioModelField
        };
    if (p === "ollama")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.ollamaBaseUrlField.text,
            "apiKey": "",
            "modelField": page.ollamaModelField
        };
    if (p === "litellm")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.litellmBaseUrlField.text,
            "apiKey": page.litellmApiKeyField.text,
            "modelField": page.litellmModelField
        };
    if (p === "qwen")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.qwenBaseUrlField.text,
            "apiKey": page.qwenApiKeyField.text,
            "modelField": page.qwenModelField
        };
    if (p === "moonshot")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.moonshotBaseUrlField.text,
            "apiKey": page.moonshotApiKeyField.text,
            "modelField": page.moonshotModelField
        };
    if (p === "mimo")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.mimoBaseUrlField.text,
            "apiKey": page.mimoApiKeyField.text,
            "modelField": page.mimoModelField
        };
    if (p === "maritaca")
        return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": page.maritacaBaseUrlField.text,
            "apiKey": page.maritacaApiKeyField.text,
            "modelField": page.maritacaModelField
        };
    if (p === "pollinations")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.pollinationsBaseUrlField.text,
            "apiKey": "",
            "modelField": page.pollinationsModelField
        };
    if (p === "huggingface-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.huggingfaceImageBaseUrlField.text,
            "apiKey": page.huggingfaceImageApiKeyField.text,
            "modelField": page.huggingfaceImageModelField
        };
    if (p === "together-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.togetherImageBaseUrlField.text,
            "apiKey": page.togetherImageApiKeyField.text,
            "modelField": page.togetherImageModelField
        };
    if (p === "openai-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.baseUrlField.text,
            "apiKey": page.apiKeyField.text,
            "modelField": page.openaiImageModelField
        };
    if (p === "google-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.googleImageBaseUrlField.text,
            "apiKey": page.googleApiKeyField.text,
            "modelField": page.googleImageModelField
        };
    if (p === "stability-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.stabilityImageBaseUrlField.text,
            "apiKey": page.stabilityApiKeyField.text,
            "modelField": page.stabilityImageModelField
        };
    if (p === "replicate-image")
        return {
            "id": p,
            "type": "image-gen",
            "baseUrl": page.replicateImageBaseUrlField.text,
            "apiKey": page.replicateApiKeyField.text,
            "modelField": page.replicateImageModelField
        };
    return {
        "id": "openai",
        "type": "openai-compat",
        "baseUrl": page.baseUrlField.text,
        "apiKey": page.apiKeyField.text,
        "modelField": page.modelField
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
let ids = [];
if (Array.isArray(responseObj)) {
for (let i = 0; i < responseObj.length; i++) {
if (typeof responseObj[i] === "string")
pushId(responseObj[i]);
else if (responseObj[i] && responseObj[i].id)
pushId(responseObj[i].id);
else if (responseObj[i] && responseObj[i].name)
pushId(responseObj[i].name);
}
} else if (responseObj && Array.isArray(responseObj.data)) {
for (let j = 0; j < responseObj.data.length; j++) {
if (responseObj.data[j] && responseObj.data[j].id)
pushId(responseObj.data[j].id);
else if (responseObj.data[j] && responseObj.data[j].name)
pushId(responseObj.data[j].name);
}
} else if (responseObj && Array.isArray(responseObj.models)) {
for (let k = 0; k < responseObj.models.length; k++) {
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


function requestJson(url, headers, onSuccess, onError) {
let xhr = new XMLHttpRequest();
xhr.open("GET", url, true);
xhr.responseType = "text";
for (let h in headers) {
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
console.error("JSON parse error:", e.toString(), "Response start:", (xhr.responseText || "").substring(0, 100));
onError("Invalid JSON: " + e.toString() + " (Len: " + (xhr.responseText || "").length + ") from " + url);
}
} else {
onError("HTTP " + xhr.status + " from " + url);
}
};
xhr.onerror = function() {
onError("Network error while requesting " + url);
};
xhr.send();
}


function refreshCurrentProviderModels() {
let cfg = currentProviderConfig();
let headers = {
};
if (providerNeedsApiKey(cfg.id) && (!cfg.apiKey || cfg.apiKey.trim() === "")) {
page.providerModelCandidates = [];
page.providerModelSearch = "";
updateFilteredProviderModels("");
page.discoveryStatus = "API key is missing for " + currentProviderDisplayName() + ". Add key first, then refresh models.";
return ;
}
if (cfg.apiKey)
headers["Authorization"] = "Bearer " + cfg.apiKey;
if (cfg.type === "anthropic") {
headers["x-api-key"] = cfg.apiKey;
headers["anthropic-version"] = "2023-06-01";
requestJson("https://api.anthropic.com/v1/models", headers, function(obj) {
let ids = parseModelIds(obj);
page.providerModelCandidates = ids;
page.providerModelSearch = "";
updateFilteredProviderModels("");
page.discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
}, function(err) {
page.providerModelCandidates = [];
page.providerModelSearch = "";
updateFilteredProviderModels("");
page.discoveryStatus = err;
});
return ;
}
requestJson(makeOpenAiModelsUrl(cfg.baseUrl), headers, function(obj) {
let ids = parseModelIds(obj);
page.providerModelCandidates = ids;
page.providerModelSearch = "";
updateFilteredProviderModels("");
page.discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
}, function(err) {
page.providerModelCandidates = [];
page.providerModelSearch = "";
updateFilteredProviderModels("");
page.discoveryStatus = err;
});
}


function applyDetectedModelToActiveProvider(modelId) {
    let cfg = currentProviderConfig();
    cfg.modelField.text = modelId || "";
}


function activeOpenCodeProvider() {
return page.openCodeProviderValueField.text || "";
}


function setOpenCodeProviderValue(v) {
page.openCodeProviderValueField.text = v || "";
}


function setOpenCodeModelValue(v) {
if (page) page.cfg_openCodeModel = v || "";
}


function openCodeServerRoot(baseUrl) {
let value = (baseUrl || "").replace(/\/$/, "");
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
let ids = [];
if (!providerObj || !providerObj.models)
return ids;
if (Array.isArray(providerObj.models)) {
for (let i = 0; i < providerObj.models.length; i++) {
if (typeof providerObj.models[i] === "string")
pushId(providerObj.models[i]);
else if (providerObj.models[i] && providerObj.models[i].id)
pushId(providerObj.models[i].id);
}
return ids;
}
for (let modelId in providerObj.models) {
if (!Object.prototype.hasOwnProperty.call(providerObj.models, modelId))
continue;
pushId(providerObj.models[modelId].id || modelId);
}
return ids;
}


function syncOpenCodeProviderSelection(providerId, preferredModel) {
let selectedProvider = providerId || "";
let candidateModels = page.openCodeProviderModelMap[selectedProvider] || [];
let chosenModel = preferredModel || (page ? page.cfg_openCodeModel : "") || "";
if (candidateModels.indexOf(chosenModel) < 0)
chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";
setOpenCodeProviderValue(selectedProvider);
page.openCodeModelCandidates = candidateModels;
page.openCodeModelSearch = "";
updateFilteredOpenCodeModels("");
setOpenCodeModelValue(chosenModel);
if (page && page.openCodeProviderBox) {
let pidx = page.openCodeProviderCandidates.indexOf(selectedProvider);
if (pidx >= 0)
page.openCodeProviderBox.currentIndex = pidx;
}
}


function sanitizeOpenCodeStartCommand(cmd) {
    let raw = (cmd || "").trim();
    if (raw === "") {
        return 'logf="${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"; (nohup opencode serve --port 4096 --hostname 127.0.0.1 >"$logf" 2>&1 < /dev/null &) && echo ok';
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
    if (raw.indexOf("nohup") >= 0 && raw.indexOf("(nohup") < 0) {
        let parts = raw.split(";");
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i].trim();
            if (part.indexOf("nohup") >= 0 && part.endsWith("&") && !part.startsWith("(")) {
                parts[i] = "(" + part + ")";
            }
        }
        raw = parts.join("; ");
    }
    return raw;
}


function refreshOpenCodeDiscovery() {
probeOpenCodeProviders((page ? page.cfg_openCodeUrl : ""));
}


function startOpenCodeServer() {
page.discoveryStatus = "Starting OpenCode server...";
let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
let startCmd = sanitizeOpenCodeStartCommand(page.openCodeStartCommandField.text);
let cmd = "sh -c " + Sec.rawShellSnippetQuote(envPrefix + startCmd);
page.utilityDs.connectSource(cmd + " #opencode-start-manual");
openCodeAutoStartTimer.restart();
}


function stopOpenCodeServer() {
page.discoveryStatus = "Stopping OpenCode server...";
let stopCmd = page.openCodeStopCommandField.text || "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stopped. || echo No OpenCode process matched.";
let cmd = "sh -c " + Sec.rawShellSnippetQuote(stopCmd);
page.utilityDs.connectSource(cmd + " #opencode-stop-manual");
page.discoveryStatus = "OpenCode server stopped.";
}


function startOpenCodeServerAutomatically() {
page.discoveryStatus = "Starting OpenCode server automatically...";
let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
let startCmd = sanitizeOpenCodeStartCommand(page.openCodeStartCommandField.text);
let cmd = "sh -c " + Sec.rawShellSnippetQuote(envPrefix + startCmd);
page.utilityDs.connectSource(cmd + " #opencode-autostart");
// After a short delay, attempt discovery again
openCodeAutoStartTimer.restart();
}


function checkAndAutoStartOpenCodeServer() {
let url = openCodeServerRoot(page ? page.cfg_openCodeUrl : "") + "/config/providers";
page.discoveryStatus = "Checking OpenCode server...";
requestJson(url, {
}, function(obj) {
// Server is already running — just do normal discovery
refreshOpenCodeDiscovery();
}, function(err) {
// Server not reachable — auto-start it
let autoStart = page && page.autoStartOpenCodeToggle ? page.autoStartOpenCodeToggle.checked : false;
if (autoStart)
startOpenCodeServerAutomatically();
else if (page)
page.discoveryStatus = "OpenCode server check failed: " + err + ". Click \"Start server\" or enable Auto-start.";
});
}


function probeOpenCodeProviders(baseUrl) {
let url = openCodeServerRoot(baseUrl) + "/config/providers";
page.discoveryStatus = "Checking OpenCode server...";
requestJson(url, {
}, function(obj) {
let providers = (obj && obj.providers) || [];
let ids = [];
let defaults = (obj && obj.default) || {
};
let modelsByProvider = {
};
for (let i = 0; i < providers.length; i++) {
let provider = providers[i];
let providerId = provider && provider.id ? provider.id : (provider && provider.name ? provider.name : "");
if (!providerId)
continue;
if (ids.indexOf(providerId) < 0)
ids.push(providerId);
modelsByProvider[providerId] = parseOpenCodeProviderModels(provider);
}
if (page) { page.openCodeProviderCandidates = ids; page.openCodeProviderModelMap = modelsByProvider; }
if (ids.length === 0) {
if (page) page.discoveryStatus = "OpenCode server is reachable, but it returned no configured providers.";
return ;
}
let selectedProvider = activeOpenCodeProvider();
if (ids.indexOf(selectedProvider) < 0)
selectedProvider = ids[0];
let rememberedModel = (page && page.openCodeModelValueField) ? ((page ? page.cfg_openCodeModel : "") || "") : "";
let fallbackModel = defaults[selectedProvider] || "";
syncOpenCodeProviderSelection(selectedProvider, rememberedModel || fallbackModel);
if (page) page.discoveryStatus = "OpenCode server reachable. Loaded " + ids.length + " providers from /config/providers.";
}, function(err) {
if (page) page.discoveryStatus = "OpenCode server check failed: " + err;
});
}


function probeOpenCodeModels(baseUrl, providerId) {
let selectedProvider = providerId || activeOpenCodeProvider();
if (!selectedProvider) {
page.openCodeModelCandidates = [];
page.openCodeModelSearch = "";
updateFilteredOpenCodeModels("");
page.discoveryStatus = "Select an OpenCode provider first.";
return ;
}
syncOpenCodeProviderSelection(selectedProvider, (page ? page.cfg_openCodeModel : ""));
page.discoveryStatus = page.openCodeModelCandidates.length > 0 ? ("Loaded " + page.openCodeModelCandidates.length + " models for OpenCode provider " + selectedProvider + ".") : ("OpenCode provider " + selectedProvider + " has no models listed by /config/providers.");
}


function refreshRunningOpenCodeSessions() {
let baseUrl = (page ? page.cfg_openCodeUrl : "");
let rootUrl = openCodeServerRoot(baseUrl);
let urlSessions = rootUrl + "/session";
let urlStatus = rootUrl + "/session/status";
page.openCodeSessionsStatus = translate("Loading active OpenCode sessions...");
requestJson(urlStatus, {}, function(statusMap) {
loadSessionsList(urlSessions, statusMap);
}, function(statusErr) {
console.warn("Failed to load session statuses (ignoring): " + statusErr);
loadSessionsList(urlSessions, null);
});
}


function loadSessionsList(urlSessions, statusMap) {
requestJson(urlSessions, {}, function(sessionsArray) {
if (Array.isArray(sessionsArray)) {
let list = [];
for (let i = 0; i < sessionsArray.length; i++) {
let s = sessionsArray[i];
if (s && s.id) {
// If statusMap is available, only include sessions loaded in memory (present in statusMap).
// If statusMap is not available (null fallback), include all sessions.
if (statusMap && !statusMap[s.id]) {
continue;
}
let statusObj = (statusMap && statusMap[s.id]) ? statusMap[s.id] : null;
s.statusType = (statusObj && statusObj.type) ? statusObj.type : "active";
list.push(s);
}
}
if (page) { page.runningOpenCodeSessions = list; page.openCodeSessionsStatus = translate("Found %1 active session(s).").arg(list.length); }
} else {
if (page) { page.runningOpenCodeSessions = []; page.openCodeSessionsStatus = translate("Invalid response format from OpenCode server."); }
}
}, function(err) {
if (page) { page.runningOpenCodeSessions = []; page.openCodeSessionsStatus = translate("Failed to load sessions: %1").arg(err); }
});
}


function killRunningOpenCodeSession(sessionId) {
let baseUrl = (page ? page.cfg_openCodeUrl : "");
// Refuse any session id that does not match the expected
// character set. This blocks path traversal (`../`) and query
// string injection (`?evil=…`).
let safeSessionId = Sec.validateSessionId(sessionId);
if (safeSessionId === "") {
page.openCodeSessionsStatus = translate("Refusing to delete session: invalid id.");
return;
}
let url = openCodeServerRoot(baseUrl) + "/session/" + safeSessionId;
page.openCodeSessionsStatus = translate("Killing session %1...").arg(safeSessionId);
let xhr = new XMLHttpRequest();
xhr.open("DELETE", url, true);
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
if (page) page.openCodeSessionsStatus = translate("Session %1 successfully killed.").arg(sessionId);
refreshRunningOpenCodeSessions();
} else {
if (page) page.openCodeSessionsStatus = translate("Failed to kill session: HTTP %1").arg(xhr.status);
}
};
xhr.onerror = function() {
if (page) page.openCodeSessionsStatus = translate("Failed to kill session: Network error.");
};
xhr.send();
}


function kwalletStore(targetId, value, isBulk) {
if (!value || value.trim() === "")
return ;
if (!isBulk)
cancelKeyringOps();
let walletName = effectiveWalletName();
let keyName = "kai-chat-" + targetId + "-api-key";
let cmd = walletWriteCommand(walletName, keyName, value);
let ops = page.pendingOps;
ops[cmd] = {
"mode": "store",
"target": targetId,
"bulk": !!isBulk
};
page.pendingOps = ops;
page.keyringDs.connectSource(cmd);
}


function saveKey(targetId, value) {
let val = (value || "").trim();
if (page.cfg_keyStorageMode === 1)
syncKeysToDisk();
else if (page.cfg_keyStorageMode === 2)
kwalletStore(targetId, val, false);
}


function kwalletLoad(targetId, isBulk) {
if (!isBulk)
cancelKeyringOps();
let walletName = effectiveWalletName();
let keyName = "kai-chat-" + targetId + "-api-key";
let cmd = walletReadCommand(walletName, keyName);
let ops = page.pendingOps;
ops[cmd] = {
"mode": "load",
"target": targetId,
"bulk": !!isBulk
};
page.pendingOps = ops;
page.keyringDs.connectSource(cmd);
}


function applyLoadedKey(targetId, secretValue) {
let normalized = (secretValue || "").trim();
if (normalized === "")
return ;
// Reject only the structured KWallet error sentinels emitted by
// the shell helper. Do NOT reject arbitrary text containing the
// word "wallet" — legitimate API keys (e.g. `sk-wallet-abc123`)
// would otherwise be silently discarded.
if (/^__KAI_(?:LOAD|INIT|STATUS|BULK)__:/.test(normalized))
return ;
let before = apiKeyForTarget(targetId);
if (targetId === "openai")
page.apiKeyField.text = normalized;
else if (targetId === "anthropic")
page.anthropicApiKeyField.text = normalized;
else if (targetId === "groq")
page.groqApiKeyField.text = normalized;
else if (targetId === "deepseek")
page.deepSeekApiKeyField.text = normalized;
else if (targetId === "minimax")
page.miniMaxApiKeyField.text = normalized;
else if (targetId === "fireworks")
page.fireworksApiKeyField.text = normalized;
else if (targetId === "google")
page.googleApiKeyField.text = normalized;
else if (targetId === "openrouter")
page.openRouterApiKeyField.text = normalized;
else if (targetId === "mistral")
page.mistralApiKeyField.text = normalized;
else if (targetId === "cloudflare")
page.cloudflareApiKeyField.text = normalized;
else if (targetId === "nvidia")
page.nvidiaApiKeyField.text = normalized;
else if (targetId === "huggingface")
page.huggingFaceApiKeyField.text = normalized;
else if (targetId === "xai")
page.xaiApiKeyField.text = normalized;
else if (targetId === "litellm")
page.litellmApiKeyField.text = normalized;
else if (targetId === "qwen")
page.qwenApiKeyField.text = normalized;
else if (targetId === "moonshot")
page.moonshotApiKeyField.text = normalized;
else if (targetId === "mimo")
page.mimoApiKeyField.text = normalized;
else if (targetId === "maritaca")
page.maritacaApiKeyField.text = normalized;
else if (targetId === "huggingface-image")
page.huggingfaceImageApiKeyField.text = normalized;
else if (targetId === "together-image")
page.togetherImageApiKeyField.text = normalized;
let after = apiKeyForTarget(targetId);
if (before !== after && page.providerBox.currentValue === targetId)
refreshCurrentProviderModels();
}


function keyTargetIds() {
return ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm", "qwen", "moonshot", "mimo", "maritaca", "huggingface-image", "together-image"];
}


function apiKeyForTarget(targetId) {
if (targetId === "openai")
return page.apiKeyField.text;
if (targetId === "anthropic")
return page.anthropicApiKeyField.text;
if (targetId === "groq")
return page.groqApiKeyField.text;
if (targetId === "deepseek")
return page.deepSeekApiKeyField.text;
if (targetId === "minimax")
return page.miniMaxApiKeyField.text;
if (targetId === "fireworks")
return page.fireworksApiKeyField.text;
if (targetId === "google")
return page.googleApiKeyField.text;
if (targetId === "openrouter")
return page.openRouterApiKeyField.text;
if (targetId === "mistral")
return page.mistralApiKeyField.text;
if (targetId === "cloudflare")
return page.cloudflareApiKeyField.text;
if (targetId === "nvidia")
return page.nvidiaApiKeyField.text;
if (targetId === "huggingface")
return page.huggingFaceApiKeyField.text;
if (targetId === "xai")
return page.xaiApiKeyField.text;
if (targetId === "litellm")
return page.litellmApiKeyField.text;
if (targetId === "qwen")
return page.qwenApiKeyField.text;
if (targetId === "moonshot")
return page.moonshotApiKeyField.text;
if (targetId === "mimo")
return page.mimoApiKeyField.text;
if (targetId === "maritaca")
return page.maritacaApiKeyField.text;
if (targetId === "huggingface-image")
return page.huggingfaceImageApiKeyField.text;
if (targetId === "together-image")
return page.togetherImageApiKeyField.text;
return "";
}


function kwalletLoadAll(autoPrompt) {
if (autoPrompt === undefined) autoPrompt = true;
if (page.kwalletSyncPermanentlyFailed && !autoPrompt) {
    return;
}
cancelKeyringOps();
let walletName = effectiveWalletName();
debugLog("[KAI-DEBUG] kwalletLoadAll walletName:", walletName);
let cmd = walletBulkReadCommand(walletName, autoPrompt) + " #kwallet-refresh-all";
// Scrub the full pipeline (which includes the wallet/folder/appid
// single-quote variables) before logging, so debug-mode output
// does not contain the live wallet identifier.
debugLog("[KAI-DEBUG] kwalletLoadAll command:", Sec.scrubSecrets(cmd));
page.keyringStatus = "Refreshing API keys from KWallet...";
page.utilityDs.connectSource(cmd);
}


function kwalletStoreAll(autoPrompt) {
if (autoPrompt === undefined) autoPrompt = true;
if (page.kwalletSyncPermanentlyFailed && !autoPrompt) {
    return;
}
cancelKeyringOps();
let walletName = effectiveWalletName();
let ids = keyTargetIds();
let targetValueMap = {};
let count = 0;
for (let i = 0; i < ids.length; i++) {
    let value = (apiKeyForTarget(ids[i]) || "").trim();
    if (value === "")
        continue;
    targetValueMap[ids[i]] = value;
    count++;
}
if (count === 0) {
    page.keyringStatus = "No API keys to sync.";
    return;
}
let cmd = WalletService.buildBulkWriteCommand(walletName, page.walletFolderName, page.walletAppId, targetValueMap, autoPrompt) + " #kwallet-bulk-store";
let ops = page.pendingOps;
ops[cmd] = {
    "mode": "bulk_store",
    "target": "bulk",
    "bulk": true
};
page.pendingOps = ops;
page.keyringStatus = "Syncing API keys to KWallet...";
page.keyringDs.connectSource(cmd);
}


function clearAllApiKeyFields() {
page.apiKeyField.text = "";
page.anthropicApiKeyField.text = "";
page.groqApiKeyField.text = "";
page.deepSeekApiKeyField.text = "";
page.miniMaxApiKeyField.text = "";
page.fireworksApiKeyField.text = "";
page.googleApiKeyField.text = "";
page.openRouterApiKeyField.text = "";
page.mistralApiKeyField.text = "";
page.cloudflareApiKeyField.text = "";
page.nvidiaApiKeyField.text = "";
page.huggingFaceApiKeyField.text = "";
page.xaiApiKeyField.text = "";
page.litellmApiKeyField.text = "";
page.qwenApiKeyField.text = "";
page.moonshotApiKeyField.text = "";
page.mimoApiKeyField.text = "";
page.maritacaApiKeyField.text = "";
page.huggingfaceImageApiKeyField.text = "";
page.togetherImageApiKeyField.text = "";
}


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


function getHelperPath() {
// Resolve the helper path and refuse anything outside the
// package's `contents/ui/` directory. See the same function in
// main.qml for the rationale.
let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
if (urlStr.indexOf("file://") === 0)
urlStr = urlStr.substring(7);
let path = decodeURIComponent(urlStr);
if (path.indexOf("/contents/ui/") === -1)
return "";
return path;
}


function loadKeysFromPlainConfig() {
let payload = {
"configPath": page.configFilePath
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " load_config_keys " + Sec.rawShellSnippetQuote(b64Payload);
page.utilityDs.connectSource(cmd + " #plainconfig-load");
}


function applyPlainConfigKeys(keys) {
page.apiKeyField.text = keys["apiKey"] || "";
page.anthropicApiKeyField.text = keys["anthropicApiKey"] || "";
page.groqApiKeyField.text = keys["groqApiKey"] || "";
page.deepSeekApiKeyField.text = keys["deepSeekApiKey"] || "";
page.miniMaxApiKeyField.text = keys["miniMaxApiKey"] || "";
page.fireworksApiKeyField.text = keys["fireworksApiKey"] || "";
page.googleApiKeyField.text = keys["googleApiKey"] || "";
page.openRouterApiKeyField.text = keys["openRouterApiKey"] || "";
page.mistralApiKeyField.text = keys["mistralApiKey"] || "";
page.cloudflareApiKeyField.text = keys["cloudflareApiKey"] || "";
page.nvidiaApiKeyField.text = keys["nvidiaApiKey"] || "";
page.huggingFaceApiKeyField.text = keys["huggingFaceApiKey"] || "";
page.xaiApiKeyField.text = keys["xaiApiKey"] || "";
page.litellmApiKeyField.text = keys["litellmApiKey"] || "";
page.qwenApiKeyField.text = keys["qwenApiKey"] || "";
page.moonshotApiKeyField.text = keys["moonshotApiKey"] || "";
page.mimoApiKeyField.text = keys["mimoApiKey"] || "";
page.maritacaApiKeyField.text = keys["maritacaApiKey"] || "";
page.huggingfaceImageApiKeyField.text = keys["huggingfaceImageApiKey"] || "";
page.togetherImageApiKeyField.text = keys["togetherImageApiKey"] || "";
}


function writeKeysToDiskAndOpen() {
let keysPayload = {
"apiKey": page.apiKeyField.text,
"anthropicApiKey": page.anthropicApiKeyField.text,
"groqApiKey": page.groqApiKeyField.text,
"deepSeekApiKey": page.deepSeekApiKeyField.text,
"miniMaxApiKey": page.miniMaxApiKeyField.text,
"fireworksApiKey": page.fireworksApiKeyField.text,
"googleApiKey": page.googleApiKeyField.text,
"openRouterApiKey": page.openRouterApiKeyField.text,
"mistralApiKey": page.mistralApiKeyField.text,
"cloudflareApiKey": page.cloudflareApiKeyField.text,
"nvidiaApiKey": page.nvidiaApiKeyField.text,
"huggingFaceApiKey": page.huggingFaceApiKeyField.text,
"xaiApiKey": page.xaiApiKeyField.text,
"litellmApiKey": page.litellmApiKeyField.text,
"qwenApiKey": page.qwenApiKeyField.text,
"moonshotApiKey": page.moonshotApiKeyField.text,
"mimoApiKey": page.mimoApiKeyField.text,
"maritacaApiKey": page.maritacaApiKeyField.text,
"huggingfaceImageApiKey": page.huggingfaceImageApiKeyField.text,
"togetherImageApiKey": page.togetherImageApiKeyField.text,
"stabilityApiKey": page.stabilityApiKeyField.text,
"replicateApiKey": page.replicateApiKeyField.text
};
let payload = {
"configPath": page.configFilePath,
"keys": keysPayload
};
let b64Payload = base64Encode(JSON.stringify(payload));
let safeConfigPath = Sec.validateFilePath(page.configFilePath);
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " sync_config_keys " + Sec.rawShellSnippetQuote(b64Payload);
if (safeConfigPath !== "")
cmd += " && xdg-open " + Sec.quoteForShell(safeConfigPath);
page.utilityDs.connectSource(cmd + " #open-config");
}


function syncKeysToDisk() {
// Write current key fields to ~/.config/kdeaichatrc (plain-config extra copy).
// cfg_ aliases handle saving to the Plasma config automatically on OK/Apply.
let keysPayload = {
"apiKey": page.apiKeyField.text,
"anthropicApiKey": page.anthropicApiKeyField.text,
"groqApiKey": page.groqApiKeyField.text,
"deepSeekApiKey": page.deepSeekApiKeyField.text,
"miniMaxApiKey": page.miniMaxApiKeyField.text,
"fireworksApiKey": page.fireworksApiKeyField.text,
"googleApiKey": page.googleApiKeyField.text,
"openRouterApiKey": page.openRouterApiKeyField.text,
"mistralApiKey": page.mistralApiKeyField.text,
"cloudflareApiKey": page.cloudflareApiKeyField.text,
"nvidiaApiKey": page.nvidiaApiKeyField.text,
"huggingFaceApiKey": page.huggingFaceApiKeyField.text,
"xaiApiKey": page.xaiApiKeyField.text,
"litellmApiKey": page.litellmApiKeyField.text,
"qwenApiKey": page.qwenApiKeyField.text,
"moonshotApiKey": page.moonshotApiKeyField.text,
"mimoApiKey": page.mimoApiKeyField.text,
"maritacaApiKey": page.maritacaApiKeyField.text,
"huggingfaceImageApiKey": page.huggingfaceImageApiKeyField.text,
"togetherImageApiKey": page.togetherImageApiKeyField.text
};
let payload = {
"configPath": page.configFilePath,
"keys": keysPayload
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " sync_config_keys " + Sec.rawShellSnippetQuote(b64Payload);
page.utilityDs.connectSource(cmd + " #plainconfig-sync");
}


function clearKeysFromDisk() {
let payload = {
"configPath": page.configFilePath,
"keys": ['apiKey', 'anthropicApiKey', 'groqApiKey', 'deepSeekApiKey', 'miniMaxApiKey', 'fireworksApiKey', 'googleApiKey', 'openRouterApiKey', 'mistralApiKey', 'cloudflareApiKey', 'nvidiaApiKey', 'huggingFaceApiKey', 'xaiApiKey', 'litellmApiKey', 'qwenApiKey', 'moonshotApiKey', 'mimoApiKey', 'maritacaApiKey', 'huggingfaceImageApiKey', 'togetherImageApiKey', 'stabilityApiKey', 'replicateApiKey']
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " clear_config_keys " + Sec.rawShellSnippetQuote(b64Payload);
page.utilityDs.connectSource(cmd + " #plainconfig-clear");
plasmoid.configuration.apiKey = "";
plasmoid.configuration.anthropicApiKey = "";
plasmoid.configuration.groqApiKey = "";
plasmoid.configuration.deepSeekApiKey = "";
plasmoid.configuration.miniMaxApiKey = "";
plasmoid.configuration.fireworksApiKey = "";
plasmoid.configuration.googleApiKey = "";
plasmoid.configuration.openRouterApiKey = "";
plasmoid.configuration.mistralApiKey = "";
plasmoid.configuration.cloudflareApiKey = "";
plasmoid.configuration.nvidiaApiKey = "";
plasmoid.configuration.huggingFaceApiKey = "";
plasmoid.configuration.xaiApiKey = "";
plasmoid.configuration.litellmApiKey = "";
plasmoid.configuration.qwenApiKey = "";
plasmoid.configuration.moonshotApiKey = "";
plasmoid.configuration.mimoApiKey = "";
plasmoid.configuration.maritacaApiKey = "";
plasmoid.configuration.huggingfaceImageApiKey = "";
plasmoid.configuration.togetherImageApiKey = "";
plasmoid.configuration.stabilityApiKey = "";
plasmoid.configuration.replicateApiKey = "";
}


function saveGeneralSettingsOnly() {
plasmoid.configuration.appDisplayName = page.appDisplayNameField.text;
plasmoid.configuration.appearanceMode = page.appearanceModeCombo.currentIndex;
plasmoid.configuration.keyStorageMode = page.cfg_keyStorageMode;
plasmoid.configuration.provider = page.cfg_provider;
plasmoid.configuration.baseUrl = page.baseUrlField.text;
plasmoid.configuration.model = page.modelField.text;
plasmoid.configuration.anthropicModel = page.anthropicModelField.text;
plasmoid.configuration.groqBaseUrl = page.groqBaseUrlField.text;
plasmoid.configuration.groqModel = page.groqModelField.text;
plasmoid.configuration.deepSeekBaseUrl = page.deepSeekBaseUrlField.text;
plasmoid.configuration.deepSeekModel = page.deepSeekModelField.text;
plasmoid.configuration.miniMaxBaseUrl = page.miniMaxBaseUrlField.text;
plasmoid.configuration.miniMaxModel = page.miniMaxModelField.text;
plasmoid.configuration.fireworksBaseUrl = page.fireworksBaseUrlField.text;
plasmoid.configuration.fireworksModel = page.fireworksModelField.text;
plasmoid.configuration.googleBaseUrl = page.googleBaseUrlField.text;
plasmoid.configuration.googleModel = page.googleModelField.text;
plasmoid.configuration.openRouterBaseUrl = page.openRouterBaseUrlField.text;
plasmoid.configuration.openRouterModel = page.openRouterModelField.text;
plasmoid.configuration.mistralBaseUrl = page.mistralBaseUrlField.text;
plasmoid.configuration.mistralModel = page.mistralModelField.text;
plasmoid.configuration.cloudflareBaseUrl = page.cloudflareBaseUrlField.text;
plasmoid.configuration.cloudflareModel = page.cloudflareModelField.text;
plasmoid.configuration.nvidiaBaseUrl = page.nvidiaBaseUrlField.text;
plasmoid.configuration.nvidiaModel = page.nvidiaModelField.text;
plasmoid.configuration.huggingFaceBaseUrl = page.huggingFaceBaseUrlField.text;
plasmoid.configuration.huggingFaceModel = page.huggingFaceModelField.text;
plasmoid.configuration.xaiBaseUrl = page.xaiBaseUrlField.text;
plasmoid.configuration.xaiModel = page.xaiModelField.text;
plasmoid.configuration.lmStudioBaseUrl = page.lmStudioBaseUrlField.text;
plasmoid.configuration.lmStudioModel = page.lmStudioModelField.text;
plasmoid.configuration.localBaseUrl = page.localBaseUrlField.text;
plasmoid.configuration.localModel = page.localModelField.text;
plasmoid.configuration.ollamaBaseUrl = page.ollamaBaseUrlField.text;
plasmoid.configuration.ollamaModel = page.ollamaModelField.text;
plasmoid.configuration.litellmBaseUrl = page.litellmBaseUrlField.text;
plasmoid.configuration.litellmModel = page.litellmModelField.text;
plasmoid.configuration.qwenBaseUrl = page.qwenBaseUrlField.text;
plasmoid.configuration.qwenApiKey = page.qwenApiKeyField.text;
plasmoid.configuration.qwenModel = page.qwenModelField.text;
plasmoid.configuration.moonshotBaseUrl = page.moonshotBaseUrlField.text;
plasmoid.configuration.moonshotApiKey = page.moonshotApiKeyField.text;
plasmoid.configuration.moonshotModel = page.moonshotModelField.text;
plasmoid.configuration.mimoBaseUrl = page.mimoBaseUrlField.text;
plasmoid.configuration.mimoApiKey = page.mimoApiKeyField.text;
plasmoid.configuration.mimoModel = page.mimoModelField.text;
plasmoid.configuration.maritacaBaseUrl = page.maritacaBaseUrlField.text;
plasmoid.configuration.maritacaApiKey = page.maritacaApiKeyField.text;
plasmoid.configuration.maritacaModel = page.maritacaModelField.text;
plasmoid.configuration.pollinationsBaseUrl = page.pollinationsBaseUrlField.text;
plasmoid.configuration.pollinationsModel = page.pollinationsModelField.text;
plasmoid.configuration.huggingfaceImageBaseUrl = page.huggingfaceImageBaseUrlField.text;
plasmoid.configuration.huggingfaceImageApiKey = page.huggingfaceImageApiKeyField.text;
plasmoid.configuration.huggingfaceImageModel = page.huggingfaceImageModelField.text;
plasmoid.configuration.togetherImageBaseUrl = page.togetherImageBaseUrlField.text;
plasmoid.configuration.togetherImageApiKey = page.togetherImageApiKeyField.text;
plasmoid.configuration.togetherImageModel = page.togetherImageModelField.text;
plasmoid.configuration.openaiImageModel = page.openaiImageModelField.text;
plasmoid.configuration.googleImageBaseUrl = page.googleImageBaseUrlField.text;
plasmoid.configuration.googleImageModel = page.googleImageModelField.text;
plasmoid.configuration.stabilityImageBaseUrl = page.stabilityImageBaseUrlField.text;
plasmoid.configuration.stabilityApiKey = page.stabilityApiKeyField.text;
plasmoid.configuration.stabilityImageModel = page.stabilityImageModelField.text;
plasmoid.configuration.replicateImageBaseUrl = page.replicateImageBaseUrlField.text;
plasmoid.configuration.replicateApiKey = page.replicateApiKeyField.text;
plasmoid.configuration.replicateImageModel = page.replicateImageModelField.text;
plasmoid.configuration.language = page.cfg_language || "";
plasmoid.configuration.showInteractiveGuides = page.showGuidesToggle.checked;
plasmoid.configuration.autoStartOpenCodeServer = page.autoStartOpenCodeToggle.checked;
plasmoid.configuration.useOpenCode = page.openCodeToggle.checked;
plasmoid.configuration.usePi = page.piToggle.checked;
plasmoid.configuration.playNotificationSound = page.playSoundToggle.checked;
plasmoid.configuration.openCodeUrl = (page ? page.cfg_openCodeUrl : "");
plasmoid.configuration.openCodeModel = (page ? page.cfg_openCodeModel : "");
plasmoid.configuration.openCodeProvider = page.openCodeProviderValueField.text;
plasmoid.configuration.openCodeStartCommand = page.openCodeStartCommandField.text;
plasmoid.configuration.openCodeStopCommand = page.openCodeStopCommandField.text;
plasmoid.configuration.openCodeAutoKill = page.openCodeAutoKillToggle.checked;
plasmoid.configuration.openCodeAutoKillMinutes = page.openCodeAutoKillMinutesSpin.value;
plasmoid.configuration.kwalletName = page.walletNameField.text;
plasmoid.configuration.systemPrompt = page.systemPromptArea.text;
plasmoid.configuration.memoryEnabled = page.memoryEnabledToggle.checked;
plasmoid.configuration.userMemory = page.userMemoryArea.text;
plasmoid.configuration.globalContextEnabled = page.globalContextEnabledToggle.checked;
plasmoid.configuration.globalContextLimit = page.globalContextLimitSpin.value;
plasmoid.configuration.globalContextAutoCompact = page.globalContextAutoCompactToggle.checked;
plasmoid.configuration.globalContextCompactThreshold = page.globalContextCompactThresholdSpin.value;
}


function cancelKeyringOps() {
let running = page.keyringDs.connectedSources;
for (let i = 0; i < running.length; i++) page.keyringDs.disconnectSource(running[i])
let utilityRunning = page.utilityDs.connectedSources;
for (let j = 0; j < utilityRunning.length; j++) {
if (utilityRunning[j].indexOf("#kwallet-") >= 0)
page.utilityDs.disconnectSource(utilityRunning[j]);
}
page.pendingOps = ({
});
}


function resetToDefaults() {
page.appDisplayNameField.text = "KDE AI Chat";
page.providerBox.currentIndex = 0;
page.baseUrlField.text = "https://api.openai.com/v1";
page.apiKeyField.text = "";
page.modelField.text = "";
page.anthropicApiKeyField.text = "";
page.anthropicModelField.text = "";
page.groqBaseUrlField.text = "https://api.groq.com/openai/v1";
page.groqApiKeyField.text = "";
page.groqModelField.text = "";
page.deepSeekBaseUrlField.text = "https://api.deepseek.com";
page.deepSeekApiKeyField.text = "";
page.deepSeekModelField.text = "";
page.miniMaxBaseUrlField.text = "https://api.minimax.io/v1";
page.miniMaxApiKeyField.text = "";
page.miniMaxModelField.text = "MiniMax-M2.7";
page.fireworksBaseUrlField.text = "https://api.fireworks.ai/inference/v1";
page.fireworksApiKeyField.text = "";
page.fireworksModelField.text = "";
page.googleBaseUrlField.text = "https://generativelanguage.googleapis.com/v1beta/openai/";
page.googleApiKeyField.text = "";
page.googleModelField.text = "gemini-3-flash-preview";
page.openRouterBaseUrlField.text = "https://openrouter.ai/api/v1";
page.openRouterApiKeyField.text = "";
page.openRouterModelField.text = "";
page.mistralBaseUrlField.text = "https://api.mistral.ai/v1";
page.mistralApiKeyField.text = "";
    page.mistralModelField.text = "";
page.cloudflareBaseUrlField.text = "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1";
page.cloudflareApiKeyField.text = "";
page.cloudflareModelField.text = "";
page.nvidiaBaseUrlField.text = "https://integrate.api.nvidia.com/v1";
page.nvidiaApiKeyField.text = "";
page.nvidiaModelField.text = "";
page.huggingFaceBaseUrlField.text = "https://router.huggingface.co/v1";
page.huggingFaceApiKeyField.text = "";
page.huggingFaceModelField.text = "";
page.xaiBaseUrlField.text = "https://api.x.ai/v1";
page.xaiApiKeyField.text = "";
page.xaiModelField.text = "grok-2-latest";
page.lmStudioBaseUrlField.text = "http://localhost:1234/v1";
page.lmStudioModelField.text = "";
page.localBaseUrlField.text = "http://localhost:11434/v1";
page.localModelField.text = "llama3.2";
page.ollamaBaseUrlField.text = "http://localhost:11434/v1";
page.ollamaModelField.text = "llama3.2";
page.litellmBaseUrlField.text = "http://localhost:4000/v1";
page.litellmApiKeyField.text = "";
page.litellmModelField.text = "";
page.qwenBaseUrlField.text = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
page.qwenApiKeyField.text = "";
page.qwenModelField.text = "qwen-max";
page.moonshotBaseUrlField.text = "https://api.moonshot.ai/v1";
page.moonshotApiKeyField.text = "";
page.moonshotModelField.text = "moonshot-v1-8k";
page.mimoBaseUrlField.text = "https://api.xiaomimimo.com/v1";
page.mimoApiKeyField.text = "";
page.mimoModelField.text = "mimo-v2-pro";
page.maritacaBaseUrlField.text = "https://chat.maritaca.ai/api";
page.maritacaApiKeyField.text = "";
    page.maritacaModelField.text = "";
languageCombo.currentIndex = 0;
page.showGuidesToggle.checked = true;
page.autoStartOpenCodeToggle.checked = false;
page.openCodeToggle.checked = false;
if (page) page.cfg_openCodeUrl = "http://127.0.0.1:4096/v1";
page.openCodeProviderValueField.text = "";
if (page) page.cfg_openCodeModel = "";
page.openCodeStartCommandField.text = "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; (nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 < /dev/null &) && echo OpenCode start command launched.";
page.openCodeStopCommandField.text = "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stop command launched. || echo No OpenCode process matched.";
page.openCodeAutoKillToggle.checked = true;
page.openCodeAutoKillMinutesSpin.value = 5;
page.walletNameField.text = page.availableWalletNames.length > 0 ? page.availableWalletNames[0] : "kdewallet";
page.systemPromptArea.text = "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
page.memoryEnabledToggle.checked = false;
page.userMemoryArea.text = "";
plasmoid.configuration.customHistoryPath = StandardPaths.writableLocation(StandardPaths.ConfigLocation);
page.globalContextEnabledToggle.checked = true;
page.globalContextLimitSpin.value = 1;
page.globalContextAutoCompactToggle.checked = false;
page.globalContextCompactThresholdSpin.value = 10;
page.providerModelCandidates = [];
page.openCodeProviderCandidates = [];
page.openCodeModelCandidates = [];
page.openCodeProviderModelMap = ({
});
page.discoveryStatus = "Settings reset to defaults.";
}


function schedAutoSetup() {
let srcPath = String(Qt.resolvedUrl("../scripts/kde-ai-scheduler.py")).replace("file://", "");
let serviceContent = "[Unit]\nDescription=KDE AI Chat Scheduler Daemon\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py\nRestart=on-failure\nRestartSec=30\nStandardOutput=journal\nStandardError=journal\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\n\n[Install]\nWantedBy=default.target\n";
let payload = {
"srcPath": srcPath,
"destPath": page.schedulerScriptPath,
"serviceContent": serviceContent
};
let payloadStr = JSON.stringify(payload);
// Audit 5.6: skip I/O when content is unchanged since last run.
if (payloadStr === page._lastSchedSetupPayload)
return;
page._lastSchedSetupPayload = payloadStr;
let b64Payload = base64Encode(payloadStr);
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " setup_scheduler_service " + Sec.rawShellSnippetQuote(b64Payload);
page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-auto-setup");
}


function pollSchedulerState() {
page.utilityDs.connectSource("sh -c 'pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED' #sched-poll-" + Date.now());
}


function schedLoadSchedules() {
let safePath = Sec.validateFilePath(page.schedulesFilePath);
if (safePath === "")
return;
let cmd = "cat " + Sec.quoteForShell(safePath) + " 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'";
page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-load");
}


function schedSaveSchedules(items) {
page.schedulerList = items;
page.schedSaveAll();
}


function getHistoryLimitValue() {
return 100;
}


function schedSaveAll() {
page.schedSaving = true;
let all = [];
// Add active
for (let i = 0; i < page.schedulerList.length; i++) {
let s = Object.assign({}, page.schedulerList[i]);
s.archived = false;
all.push(s);
}
// Add archived
for (let j = 0; j < page.schedulerArchivedList.length; j++) {
let sa = Object.assign({}, page.schedulerArchivedList[j]);
sa.archived = true;
all.push(sa);
}
let limit = page.getHistoryLimitValue();
let hist = page.schedulerHistory || [];
if (hist.length > limit) {
hist = hist.slice(hist.length - limit);
page.schedulerHistory = hist;
}
let payload = {
"version": 1,
"schedules": all,
"history": hist,
"settings": {
"executeMissedSchedules": !!page.executeMissedSchedulesToggle.checked,
"historyLimit": limit
}
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " save_all_schedules " + Sec.rawShellSnippetQuote(b64Payload);
page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-save");
}


function schedTriggerNow(index) {
let copy = page.schedulerList.slice();
if (index < 0 || index >= copy.length)
return ;
let s = JSON.parse(JSON.stringify(copy[index]));
s.triggerNow = true;
copy[index] = s;
page.schedulerList = copy;
page.schedSaveAll();
}


function schedMakeUuid() {
return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
let r = Math.random() * 16 | 0;
return (c === "x" ? r : (r & 3 | 8)).toString(16);
});
}


function openPrefilledScheduleDialog(pId, pName) {
if (!pId || pId === "")
return;
let now = new Date();
now.setMinutes(now.getMinutes() + 5);
page.scheduleDialog.draft = {
"id": page.schedMakeUuid(),
"name": "",
"enabled": true,
"chatId": pId,
"chatName": pName || "Chat",
"message": "",
"taskType": "single",
"startDate": now.toISOString(),
"schedType": "days",
"schedEvery": 1,
"schedTime": "09:00",
"schedDays": [1],
"schedDayOfMonth": 1,
"limitEnabled": false,
"limitCount": 5,
"notify": true,
"createdAt": new Date().toISOString()
};
page.scheduleDialog.editingIndex = -2;
page.scheduleDialog.open();
// Clear configuration values immediately so it doesn't pop up again next time!
if (typeof page.cfg_preselectedChatId !== "undefined") {
page.cfg_preselectedChatId = "";
page.cfg_preselectedChatName = "";
}
if (plasmoid.configuration && "preselectedChatId" in plasmoid.configuration) {
plasmoid.configuration.preselectedChatId = "";
plasmoid.configuration.preselectedChatName = "";
}
}


function schedDefaultBaseUrl(provider) {
let urls = {
"openai": "https://api.openai.com/v1",
"anthropic": "https://api.anthropic.com/v1",
"groq": "https://api.groq.com/openai/v1",
"google": "https://generativelanguage.googleapis.com/v1beta/openai/",
"deepseek": "https://api.deepseek.com",
"mistral": "https://api.mistral.ai/v1",
"openrouter": "https://openrouter.ai/api/v1",
"xai": "https://api.x.ai/v1",
"nvidia": "https://integrate.api.nvidia.com/v1",
"fireworks": "https://api.fireworks.ai/inference/v1",
"minimax": "https://api.minimax.io/v1",
"cloudflare": "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
"huggingface": "https://router.huggingface.co/v1",
"ollama": "http://localhost:11434/v1",
"lmstudio": "http://localhost:1234/v1",
"local": "http://localhost:11434/v1",
"litellm": "http://localhost:4000/v1",
"qwen": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
"moonshot": "https://api.moonshot.ai/v1",
"mimo": "https://api.xiaomimimo.com/v1",
"maritaca": "https://chat.maritaca.ai/api"
};
return urls[provider] || "https://api.openai.com/v1";
}


function schedHumanCron(expr) {
if (!expr)
return "No schedule";
let parts = expr.trim().split(/\s+/);
if (parts.length !== 5)
return expr;
let min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4];
if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
let h = parseInt(hr), ampm = h >= 12 ? "PM" : "AM", h12 = h % 12 || 12;
let dayStr = dow === "*" ? "every day" : dow === "1-5" ? "weekdays" : dow === "6,0" || dow === "0,6" ? "weekends" : "on selected days";
return "Daily at " + h12 + ":00 " + ampm + " " + dayStr;
}
if (hr.startsWith && hr.startsWith("*/"))
return "Every " + hr.slice(2) + " hours";
return expr;
}
