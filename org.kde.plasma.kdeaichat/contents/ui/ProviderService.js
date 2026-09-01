

/**
 * @typedef {Object} ProviderEntry
 * @property {string} type            `"openai-compat"` or `"anthropic"`.
 * @property {string} configKey       `plasmoid.configuration` key holding the API key (empty if none).
 * @property {string} modelKey        Configuration key holding the model name.
 * @property {string} [baseUrlKey]    Configuration key for a user-editable base URL.
 * @property {string} [defaultBaseUrl]  Fallback base URL if `baseUrlKey` is unset/empty.
 * @property {string} [defaultModel]  Default model name suggestion.
 * @property {boolean} [allowEmptyKey]  If true, requests work without an API key.
 * @property {boolean} [hasHeaders]   If true, the provider needs custom HTTP headers (e.g. OpenRouter).
 */

/**
 * @typedef {Object} ProviderConfig
 * @property {string} type            Wire protocol family.
 * @property {string} baseUrl         Resolved base URL.
 * @property {string} apiKey          Resolved (trimmed) API key.
 * @property {string} model           Resolved model name.
 * @property {?Object} headers        Optional extra HTTP headers.
 * @property {boolean} allowEmptyKey  Whether the provider tolerates empty key.
 */

let PROVIDER_CONFIGS = {
    "anthropic": {
        type: "anthropic",
        configKey: "anthropicApiKey",
        modelKey: "anthropicModel",
        defaultBaseUrl: "https://api.anthropic.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "openai": {
        type: "openai-compat",
        configKey: "apiKey",
        modelKey: "model",
        defaultBaseUrl: "https://api.openai.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "local": {
        type: "openai-compat",
        configKey: "",
        modelKey: "localModel",
        baseUrlKey: "localBaseUrl",
        defaultBaseUrl: "http://localhost:11434/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "ollama": {
        type: "openai-compat",
        configKey: "",
        modelKey: "ollamaModel",
        baseUrlKey: "ollamaBaseUrl",
        defaultBaseUrl: "http://localhost:11434/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "litellm": {
        type: "openai-compat",
        configKey: "litellmApiKey",
        modelKey: "litellmModel",
        baseUrlKey: "litellmBaseUrl",
        defaultBaseUrl: "http://localhost:4000/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "lmstudio": {
        type: "openai-compat",
        configKey: "",
        modelKey: "lmStudioModel",
        baseUrlKey: "lmStudioBaseUrl",
        defaultBaseUrl: "http://localhost:1234/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "groq": {
        type: "openai-compat",
        configKey: "groqApiKey",
        modelKey: "groqModel",
        baseUrlKey: "groqBaseUrl",
        defaultBaseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "deepseek": {
        type: "openai-compat",
        configKey: "deepSeekApiKey",
        modelKey: "deepSeekModel",
        baseUrlKey: "deepSeekBaseUrl",
        defaultBaseUrl: "https://api.deepseek.com",
        defaultModel: "",
        allowEmptyKey: false
    },
    "minimax": {
        type: "openai-compat",
        configKey: "miniMaxApiKey",
        modelKey: "miniMaxModel",
        baseUrlKey: "miniMaxBaseUrl",
        defaultBaseUrl: "https://api.minimax.io/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "fireworks": {
        type: "openai-compat",
        configKey: "fireworksApiKey",
        modelKey: "fireworksModel",
        baseUrlKey: "fireworksBaseUrl",
        defaultBaseUrl: "https://api.fireworks.ai/inference/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "google": {
        type: "openai-compat",
        configKey: "googleApiKey",
        modelKey: "googleModel",
        baseUrlKey: "googleBaseUrl",
        defaultBaseUrl: "https://generativelanguage.googleapis.com/v1beta/openai/",
        defaultModel: "",
        allowEmptyKey: false
    },
    "openrouter": {
        type: "openai-compat",
        configKey: "openRouterApiKey",
        modelKey: "openRouterModel",
        baseUrlKey: "openRouterBaseUrl",
        defaultBaseUrl: "https://openrouter.ai/api/v1",
        defaultModel: "",
        allowEmptyKey: false,
        hasHeaders: true
    },
    "mistral": {
        type: "openai-compat",
        configKey: "mistralApiKey",
        modelKey: "mistralModel",
        baseUrlKey: "mistralBaseUrl",
        defaultBaseUrl: "https://api.mistral.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "cloudflare": {
        type: "openai-compat",
        configKey: "cloudflareApiKey",
        modelKey: "cloudflareModel",
        baseUrlKey: "cloudflareBaseUrl",
        defaultBaseUrl: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "nvidia": {
        type: "openai-compat",
        configKey: "nvidiaApiKey",
        modelKey: "nvidiaModel",
        baseUrlKey: "nvidiaBaseUrl",
        defaultBaseUrl: "https://integrate.api.nvidia.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "huggingface": {
        type: "openai-compat",
        configKey: "huggingFaceApiKey",
        modelKey: "huggingFaceModel",
        baseUrlKey: "huggingFaceBaseUrl",
        defaultBaseUrl: "https://router.huggingface.co/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "xai": {
        type: "openai-compat",
        configKey: "xaiApiKey",
        modelKey: "xaiModel",
        baseUrlKey: "xaiBaseUrl",
        defaultBaseUrl: "https://api.x.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "qwen": {
        type: "openai-compat",
        configKey: "qwenApiKey",
        modelKey: "qwenModel",
        baseUrlKey: "qwenBaseUrl",
        defaultBaseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "moonshot": {
        type: "openai-compat",
        configKey: "moonshotApiKey",
        modelKey: "moonshotModel",
        baseUrlKey: "moonshotBaseUrl",
        defaultBaseUrl: "https://api.moonshot.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "mimo": {
        type: "openai-compat",
        configKey: "mimoApiKey",
        modelKey: "mimoModel",
        baseUrlKey: "mimoBaseUrl",
        defaultBaseUrl: "https://api.xiaomimimo.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "maritaca": {
        type: "openai-compat",
        configKey: "maritacaApiKey",
        modelKey: "maritacaModel",
        baseUrlKey: "maritacaBaseUrl",
        defaultBaseUrl: "https://chat.maritaca.ai/api",
        defaultModel: "",
        allowEmptyKey: false
    },
    "perplexity": {
        type: "openai-compat",
        configKey: "perplexityApiKey",
        modelKey: "perplexityModel",
        baseUrlKey: "perplexityBaseUrl",
        defaultBaseUrl: "https://api.perplexity.ai/router/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "pollinations": {
        type: "image-gen",
        configKey: "",
        modelKey: "pollinationsModel",
        baseUrlKey: "pollinationsBaseUrl",
        defaultBaseUrl: "https://image.pollinations.ai",
        defaultModel: "",
        allowEmptyKey: true
    },
    "huggingface-image": {
        type: "image-gen",
        configKey: "huggingfaceImageApiKey",
        modelKey: "huggingfaceImageModel",
        baseUrlKey: "huggingfaceImageBaseUrl",
        defaultBaseUrl: "https://api-inference.huggingface.co",
        defaultModel: "",
        allowEmptyKey: false
    },
    "together-image": {
        type: "image-gen",
        configKey: "togetherImageApiKey",
        modelKey: "togetherImageModel",
        baseUrlKey: "togetherImageBaseUrl",
        defaultBaseUrl: "https://api.together.xyz/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "openai-image": {
        type: "image-gen",
        configKey: "apiKey",
        modelKey: "openaiImageModel",
        baseUrlKey: "baseUrl",
        defaultBaseUrl: "https://api.openai.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "google-image": {
        type: "image-gen",
        configKey: "googleApiKey",
        modelKey: "googleImageModel",
        baseUrlKey: "googleImageBaseUrl",
        defaultBaseUrl: "https://generativelanguage.googleapis.com/v1beta",
        defaultModel: "",
        allowEmptyKey: false
    },
    "stability-image": {
        type: "image-gen",
        configKey: "stabilityApiKey",
        modelKey: "stabilityImageModel",
        baseUrlKey: "stabilityImageBaseUrl",
        defaultBaseUrl: "https://api.stability.ai",
        defaultModel: "",
        allowEmptyKey: false
    },
    "replicate-image": {
        type: "image-gen",
        configKey: "replicateApiKey",
        modelKey: "replicateImageModel",
        baseUrlKey: "replicateImageBaseUrl",
        defaultBaseUrl: "https://api.replicate.com",
        defaultModel: "",
        allowEmptyKey: false
    }
};

let DISPLAY_NAMES = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "groq": "Groq",
    "deepseek": "DeepSeek",
    "minimax": "MiniMax",
    "fireworks": "Fireworks",
    "google": "Google Gemini",
    "openrouter": "OpenRouter",
    "mistral": "Mistral",
    "cloudflare": "Cloudflare",
    "nvidia": "NVIDIA NIM",
    "huggingface": "Hugging Face",
    "xai": "xAI",
    "litellm": "LiteLLM Proxy",
    "lmstudio": "LM Studio",
    "local": "Local",
    "ollama": "Ollama",
    "qwen": "Qwen",
    "moonshot": "Moonshot",
    "mimo": "MiMo",
    "maritaca": "Maritaca",
    "perplexity": "Perplexity",
    "pollinations": "[Image] Pollinations.ai",
    "huggingface-image": "[Image] HuggingFace Image",
    "together-image": "[Image] Together AI",
    "openai-image": "[Image] OpenAI DALL-E",
    "google-image": "[Image] Google Imagen",
    "stability-image": "[Image] Stability AI",
    "replicate-image": "[Image] Replicate"
};

let API_KEY_CONFIG_MAP = {
    "openai": "apiKey",
    "anthropic": "anthropicApiKey",
    "groq": "groqApiKey",
    "deepseek": "deepSeekApiKey",
    "minimax": "miniMaxApiKey",
    "fireworks": "fireworksApiKey",
    "google": "googleApiKey",
    "openrouter": "openRouterApiKey",
    "mistral": "mistralApiKey",
    "cloudflare": "cloudflareApiKey",
    "nvidia": "nvidiaApiKey",
    "huggingface": "huggingFaceApiKey",
    "xai": "xaiApiKey",
    "litellm": "litellmApiKey",
    "qwen": "qwenApiKey",
    "moonshot": "moonshotApiKey",
    "mimo": "mimoApiKey",
    "maritaca": "maritacaApiKey",
    "perplexity": "perplexityApiKey",
    "huggingface-image": "huggingfaceImageApiKey",
    "together-image": "togetherImageApiKey",
    "openai-image": "apiKey",
    "google-image": "googleApiKey",
    "stability-image": "stabilityApiKey",
    "replicate-image": "replicateApiKey"
};

/**
 * ProviderService — data-driven provider configuration registry.
 *
 * Single source of truth for every supported LLM provider. All
 * previously hard-coded if/else chains in main.qml and
 * ConfigGeneral.qml delegate here so adding a new provider only
 * requires editing the `PROVIDER_CONFIGS` map below.
 *
 * @module ProviderService
 */

/**
 * Display name for a provider, falling back to the id and then to a
 * generic label.
 *
 * @param {string} providerId  Provider id (e.g. `"openai"`).
 * @returns {string} Human-readable name, or the id, or `"Selected provider"`.
 */
function parseCustomProviders(configuration) {
    if (!configuration || !configuration.customProvidersJson) return [];
    try {
        let raw = configuration.customProvidersJson;
        let list = (typeof raw === "string") ? JSON.parse(raw) : raw;
        return Array.isArray(list) ? list : [];
    } catch (e) {
        return [];
    }
}

/**
 * Display name for a provider, falling back to custom provider name, the id, and then to a
 * generic label.
 *
 * @param {string} providerId  Provider id (e.g. `"openai"` or `"custom_123"`).
 * @param {Object} [configuration] Optional configuration map.
 * @returns {string} Human-readable name.
 */
function getProviderDisplayName(providerId, configuration) {
    if (DISPLAY_NAMES[providerId]) return DISPLAY_NAMES[providerId];
    if (configuration) {
        let customs = parseCustomProviders(configuration);
        for (let i = 0; i < customs.length; i++) {
            if (customs[i] && customs[i].id === providerId && customs[i].name) {
                return "[Custom] " + customs[i].name;
            }
        }
    }
    return providerId || "Selected provider";
}

/**
 * Build a runtime provider config object by resolving all keys against
 * the user's `plasmoid.configuration` map. Returns a plain object the
 * request layer can consume directly.
 *
 * @param {string} providerId  Provider id.
 * @param {Object} configuration  The user's `plasmoid.configuration` map.
 * @returns {{type: string, baseUrl: string, apiKey: string, model: string, headers: ?Object, allowEmptyKey: boolean}}
 *   Runtime provider config.
 */
function getProviderConfig(providerId, configuration) {
    let entry = PROVIDER_CONFIGS[providerId];
    if (!entry) {
        let customs = parseCustomProviders(configuration);
        for (let i = 0; i < customs.length; i++) {
            let cp = customs[i];
            if (cp && cp.id === providerId) {
                return {
                    "type": cp.type || "openai-compat",
                    "baseUrl": (cp.baseUrl || "").trim(),
                    "apiKey": (cp.apiKey || "").trim(),
                    "model": (cp.model || "").trim(),
                    "headers": cp.headers || null,
                    "allowEmptyKey": cp.allowEmptyKey !== false
                };
            }
        }
        return {
            "type": "openai-compat",
            "baseUrl": (configuration.baseUrl || "https://api.openai.com/v1"),
            "apiKey": (configuration.apiKey || "").trim(),
            "model": configuration.model || "",
            "headers": null,
            "allowEmptyKey": false
        };
    }

    let apiKey = "";
    if (entry.configKey) {
        apiKey = (configuration[entry.configKey] || "").trim();
    }

    let model = configuration[entry.modelKey] || entry.defaultModel || "";
    let baseUrl = "";
    let baseUrlKey = entry.baseUrlKey || (providerId === "openai" ? "baseUrl" : null);
    baseUrl = (baseUrlKey ? configuration[baseUrlKey] : "") || entry.defaultBaseUrl || "";

    let headers = null;
    if (entry.hasHeaders && providerId === "openrouter") {
        headers = {};
        let referer = configuration.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat";
        let title = configuration.openRouterTitle || "KDE AI Chat";
        headers["HTTP-Referer"] = referer;
        headers["X-Title"] = title;
    }

    return {
        "type": entry.type,
        "baseUrl": baseUrl,
        "apiKey": apiKey,
        "model": model,
        "headers": headers,
        "allowEmptyKey": entry.allowEmptyKey
    };
}

/**
 * Look up the `plasmoid.configuration` key that holds a given
 * provider's API key.
 *
 * @param {string} targetId  Provider id.
 * @returns {?string} The configuration key, or `null` if the provider
 *   has no separate API key field (e.g. local providers).
 */
function getApiKeyConfigKey(targetId) {
    return API_KEY_CONFIG_MAP[targetId] || null;
}

/**
 * List all provider ids that have a dedicated API key configuration
 * field. Used by the KWallet bulk reader to know which entries to pull.
 *
 * @returns {string[]} Provider ids (e.g. `["openai", "anthropic", ...]`).
 */
function getApiKeyProviderIds() {
    return Object.keys(API_KEY_CONFIG_MAP);
}

/**
 * List all provider ids known to the registry, including custom remote providers.
 *
 * @param {Object} [configuration] Optional configuration map.
 * @returns {string[]} Provider ids.
 */
function getSupportedProviders(configuration) {
    let keys = Object.keys(PROVIDER_CONFIGS);
    if (configuration) {
        let customs = parseCustomProviders(configuration);
        for (let i = 0; i < customs.length; i++) {
            if (customs[i] && customs[i].id && keys.indexOf(customs[i].id) < 0) {
                keys.push(customs[i].id);
            }
        }
    }
    return keys;
}

/**
 * List all provider ids that have a valid configured API key (or don't require an API key).
 * Used by settings and chat header to only show usable providers in Normal mode.
 *
 * @param {Object} configuration User's plasmoid.configuration map.
 * @returns {string[]} Provider ids.
 */
function getConfiguredProviders(configuration) {
    let all = getSupportedProviders(configuration);
    if (!configuration) return all;
    let configured = [];
    for (let i = 0; i < all.length; i++) {
        let pId = all[i];
        let pConf = getProviderConfig(pId, configuration);
        if (pConf.allowEmptyKey || (pConf.apiKey && pConf.apiKey.length > 0)) {
            configured.push(pId);
        }
    }
    return configured.length > 0 ? configured : all;
}

/**
 * Parse model IDs from various provider API response structures.
 *
 * @param {Object} responseObj  Raw JSON object returned by the models endpoint.
 * @returns {string[]} List of unique model ID strings.
 */
function parseModelIds(responseObj) {
    var ids = [];
    function pushId(v) {
        if (!v) return;
        if (ids.indexOf(v) < 0) ids.push(v);
    }
    if (Array.isArray(responseObj)) {
        for (let i = 0; i < responseObj.length; i++) {
            if (typeof responseObj[i] === "string") pushId(responseObj[i]);
            else if (responseObj[i] && responseObj[i].id) pushId(responseObj[i].id);
            else if (responseObj[i] && responseObj[i].name) pushId(responseObj[i].name);
        }
    } else if (responseObj && Array.isArray(responseObj.data)) {
        for (let j = 0; j < responseObj.data.length; j++) {
            if (responseObj.data[j] && responseObj.data[j].id) pushId(responseObj.data[j].id);
            else if (responseObj.data[j] && responseObj.data[j].name) pushId(responseObj.data[j].name);
        }
    } else if (responseObj && Array.isArray(responseObj.models)) {
        for (let k = 0; k < responseObj.models.length; k++) {
            if (typeof responseObj.models[k] === "string") pushId(responseObj.models[k]);
            else if (responseObj.models[k] && responseObj.models[k].id) pushId(responseObj.models[k].id);
            else if (responseObj.models[k] && responseObj.models[k].name) pushId(responseObj.models[k].name);
        }
    }
    return ids;
}

/**
 * Fetch available model candidate IDs for a specific provider on-the-fly.
 *
 * @param {string} providerId  The provider ID (e.g. "openai", "anthropic", "groq", "ollama").
 * @param {Object} configuration  The user's plasmoid.configuration map.
 * @param {function(string[]):void} onSuccess  Callback invoked with array of model IDs.
 * @param {function(string):void} onError  Callback invoked with error message string.
 */
function isHttpUrlAllowed(url) {
    if (url === null || url === undefined) return false;
    let value = String(url).trim();
    if (!/^(?:http|https):\/\//i.test(value) || /[\u0000-\u001f\u007f]/.test(value)) return false;
    let authority = value.substring(value.indexOf("://") + 3).split(/[\/?#]/, 1)[0];
    return authority !== "" && !/[\s<>"'`]/.test(authority) && authority.indexOf("@") < 0;
}

function fetchModelsForProvider(providerId, configuration, onSuccess, onError) {
    let cfg = getProviderConfig(providerId, configuration);
    let apiKeyKey = getApiKeyConfigKey(providerId);
    if (apiKeyKey && (!cfg.apiKey || cfg.apiKey.trim() === "")) {
        if (onError) onError("API key missing for " + getProviderDisplayName(providerId));
        return;
    }

    let headers = {};
    if (cfg.apiKey) {
        headers["Authorization"] = "Bearer " + cfg.apiKey;
    }

    let url = "";
    if (cfg.type === "anthropic") {
        headers["x-api-key"] = cfg.apiKey;
        headers["anthropic-version"] = "2023-06-01";
        let base = (cfg.baseUrl || "https://api.anthropic.com/v1").replace(/\/$/, "");
        url = base.endsWith("/models") ? base : base + "/models";
    } else {
        let base = cfg.baseUrl || "";
        base = base.replace(/\/$/, "");
        if (base.endsWith("/chat/completions")) {
            url = base.substring(0, base.length - "/chat/completions".length) + "/models";
        } else {
            url = base + "/models";
        }
    }

    if (cfg.headers) {
        for (let k in cfg.headers) {
            if (cfg.headers.hasOwnProperty(k)) {
                headers[k] = cfg.headers[k];
            }
        }
    }

    if (!isHttpUrlAllowed(url)) {
        if (onError) onError("Request blocked: only HTTP(S) provider URLs are allowed.");
        return;
    }
    let xhr = new XMLHttpRequest();
    try {
        xhr.open("GET", url, true);
    } catch (e) {
        if (onError) onError("Invalid provider URL: " + e);
        return;
    }
    xhr.responseType = "text";
    xhr.timeout = 5000; // 5 second timeout — never hang plasmashell
    for (let h in headers) {
        if (headers[h]) xhr.setRequestHeader(h, headers[h]);
    }
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                if (xhr.responseText.length > 2000000)
                    throw new Error("model list response is too large");
                let parsed = JSON.parse(xhr.responseText);
                let ids = parseModelIds(parsed);
                if (onSuccess) onSuccess(ids);
            } catch (e) {
                if (onError) onError("Parse error: " + e.toString());
            }
        } else {
            if (onError) onError("HTTP " + xhr.status + " from " + url);
        }
    };
    xhr.ontimeout = function() {
        if (onError) onError("Timed out fetching models from " + url);
    };
    xhr.onerror = function() {
        if (onError) onError("Network error requesting " + url);
    };
    try { xhr.send(); } catch(e) {
        if (onError) onError("Send failed: " + e);
    }
}
