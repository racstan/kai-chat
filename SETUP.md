# KDE AI Chat - Setup & Usage Guide

A comprehensive guide to setting up and using each feature of the KDE AI Chat KDE Plasma widget.

## Table of Contents
1. [Installation](#installation)
2. [Initial Setup](#initial-setup)
3. [Provider Setup](#provider-setup)
4. [Features & Usage](#features--usage)
5. [Advanced Configuration](#advanced-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites
- KDE Plasma 6.0+
- Qt 6+
- `libsecret` (for secure API key storage)
- `notify-send` (for background notifications)

### Install Steps

#### Option A: Native 1-Click Desktop Installation (Recommended)
1. Right-click your desktop background or the panel and click **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. In the search box, search for **"KDE AI Chat"** (short for KDE AI Chat).
4. Click **Install**.

#### Option B: Manual Package Installation
If you downloaded the compiled `.plasmoid` file directly from the KDE Store:
1. Open a terminal in the folder containing the downloaded `.plasmoid` package.
2. Run the package registration command:
   ```bash
   kpackagetool6 --type Plasma/Applet --install org.kde.plasma.kdeaichat-v1.0.plasmoid
   ```
3. Restart your Plasma shell to apply the update:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```

4. **Verify installation:**
   - Right-click your panel/desktop, select **Add Widgets...**, search for **"KDE AI Chat"**, and drag it onto your panel or desktop.
   - Click the chat icon (💬) to open the popup.
   - Navigate to the **Settings** view (click the gear icon) to configure your first provider.

---

## Initial Setup

### Access Settings

1. **Open the KDE AI Chat widget** by clicking its panel icon
2. **Click the gear icon** in the top-right corner to open Settings
3. You'll see tabs for **General**, **Appearance**, and **Shortcuts**

### Configure Your First Provider

All 17 providers follow the same pattern:

1. **Select a Provider** from the dropdown in the **General** tab:
   - OpenAI, Anthropic, Gemini, Mistral, Grok (xAI), DeepSeek, MiniMax, Fireworks AI, NVIDIA NIM, Cloudflare Workers AI, Hugging Face, OpenRouter, Groq, LM Studio, Ollama, Local (OpenAI-compatible), LiteLLM Proxy

2. **Obtain Your API Key:**
   - See [Provider Setup](#provider-setup) for provider-specific instructions

3. **Enter the API Key:**
   - Paste your API key in the **API Key** field
   - When KWallet is available, the key is stored in KDE Wallet (encrypted); otherwise it remains in the local plaintext configuration fallback
   - Click **Refresh Models** to discover models and verify connection

4. **Configure API Endpoint (optional):**
   - Most providers use the default endpoint
   - For custom/self-hosted models, enter a different URL (e.g., `http://localhost:8000`)

5. **Select a Model:**
   - After setting the API key, click **Fetch Available Models**
   - Select your preferred model from the dropdown

6. **Set Temperature (optional):**
   - Adjust the temperature slider (0.0–2.0)
   - Lower values = more deterministic; higher = more creative

---

## Provider Setup

Follow the steps below for each provider you want to use.

### OpenAI

1. **Get API Key:**
   - Visit https://platform.openai.com/api-keys
   - Sign in or create an account
   - Click **+ Create new secret key**
   - Copy and paste into KDE AI Chat settings

2. **Model Selection:**
   - Click **Fetch Available Models** in settings
   - Select `gpt-4`, `gpt-3.5-turbo`, or similar

3. **Endpoint:**
   - Default: `https://api.openai.com/v1`
   - (Leave as-is unless using a proxy)

---

### Anthropic (Claude)

1. **Get API Key:**
   - Visit https://console.anthropic.com/
   - Navigate to **Account → API Keys**
   - Create a new key, copy it

2. **Model Selection:**
   - Common models: `claude-opus-4-1`, `claude-sonnet-4`, `claude-haiku`
   - Click **Fetch Available Models** to see all

3. **Endpoint:**
   - Default: `https://api.anthropic.com`

---

### Google Gemini

1. **Get API Key:**
   - Visit https://makersuite.google.com/app/apikey
   - Click **Create API Key**
   - Copy the key

2. **Model Selection:**
   - Common: `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash`
   - Use **Fetch Available Models** (may require additional setup)

3. **Endpoint:**
   - Default: `https://generativelanguage.googleapis.com/v1beta/openai/`

---

### Mistral AI

1. **Get API Key:**
   - Visit https://console.mistral.ai/api-keys/
   - Sign in, create a new API key

2. **Model Selection:**
   - Popular: `mistral-large`, `mistral-medium`, `mistral-small`
   - Fetch available models in settings

3. **Endpoint:**
   - Default: `https://api.mistral.ai/v1`

---

### Grok (X.AI)

1. **Get API Key:**
   - Visit https://console.x.ai/
   - Navigate to **API Keys** section
   - Create and copy your key

2. **Model Selection:**
   - Default: `grok-2`, `grok-2-vision-1212`
   - Fetch to see latest options

3. **Endpoint:**
   - Default: `https://api.x.ai/v1`

---

### DeepSeek

1. **Get API Key:**
   - Visit https://platform.deepseek.com/api_keys
   - Create a new key

2. **Model Selection:**
   - Popular: `deepseek-chat`, `deepseek-coder`

3. **Endpoint:**
   - Default: `https://api.deepseek.com`

---

### NVIDIA

1. **Get API Key:**
   - Visit https://build.nvidia.com/
   - Create a free account
   - Generate an API key

2. **Model Selection:**
   - Access NVIDIA's hosted models (Llama 2, Nemotron, etc.)

3. **Endpoint:**
   - Default: `https://integrate.api.nvidia.com/v1`

---

### Cerebras

1. **Get API Key:**
   - Visit https://cloud.cerebras.ai/
   - Create account and API key

2. **Model Selection:**
   - Primary: `llama-3.1-70b`

3. **Endpoint:**
   - Default: `https://api.cerebras.ai/v1`

---

### Cloudflare

1. **Get API Key:**
   - Visit https://dash.cloudflare.com/
   - Navigate to **AI** section
   - Create API token

2. **Model Selection:**
   - Access Cloudflare's model catalog

3. **Endpoint:**
   - Default: `https://api.cloudflare.com/client/v4/accounts/{account-id}/ai/run/`

---

### HuggingFace

1. **Get API Key:**
   - Visit https://huggingface.co/settings/tokens
   - Create a **Fine-grained access token**

2. **Model Selection:**
   - Popular: `mistralai/Mistral-7B`, `meta-llama/Llama-2-70b`
   - Use Inference API endpoint

3. **Endpoint:**
   - Default: `https://api-inference.huggingface.co/models/`

---

### OpenRouter

1. **Get API Key:**
   - Visit https://openrouter.ai/keys
   - Create an API key

2. **Model Selection:**
   - Access 200+ models from different providers
   - Popular: `openai/gpt-4`, `anthropic/claude-opus`, etc.

3. **Endpoint:**
   - Default: `https://openrouter.ai/api/v1`

---

### LiteLLM Proxy

1. **Install LiteLLM:**
   - `pip install litellm`
   - Or use the [LiteLLM Proxy docs](https://docs.litellm.ai/docs/proxy/quick_start) for a full config-file-based setup

2. **Start the proxy:**
   ```bash
   litellm --model gpt-4o-mini
   # or with a config file:
   litellm --config /path/to/config.yaml
   ```

3. **Configure the widget:**
   - Select **LiteLLM Proxy** from the provider dropdown
   - Set endpoint to `http://localhost:4000/v1` (default)
   - API key is **optional** — leave blank for keyless proxy setups
   - Click **Refresh Models** to discover available models

4. **Endpoint:**
   - Default: `http://localhost:4000/v1`
   - Adjust if you've configured a different port or remote host

---

### Local Models

1. **Setup Requirements:**
   - Run a local LLM server (e.g., Ollama, LM Studio, vLLM)
   - Ensure it's accessible on your local network

2. **Model Selection:**
   - Ollama: `ollama pull mistral` then use `mistral`
   - LM Studio: Use the model name configured in LM Studio
   - vLLM: Configure your model in vLLM startup

3. **Endpoint:**
   - Example (Ollama): `http://localhost:11434/v1`
   - Example (LM Studio): `http://localhost:1234/v1`
   - Example (vLLM): `http://localhost:8000/v1`

4. **API Key:**
   - Starting with **Version 1.1**, local providers (Ollama, LM Studio, and Local OpenAI-compatible) are configured as **keyless**. You do not need to enter any dummy tokens or API keys to use them!

---

## Features & Usage

### 1. Basic Chat

**How to use:**
1. Type your message in the input field at the bottom
2. Press **Enter** to send (or click **Send**)
3. The AI response appears in the chat above

**Tips:**
- Press **Shift+Enter** to create a new line without sending
- Use markdown in your messages (it's supported)
- The chat supports **markdown rendering** for responses (bold, links, code blocks, etc.)

---

### 2. Streaming Responses

**What it does:**
- Responses appear **token-by-token** in real-time instead of waiting for the full response
- The widget shows a **pulsing animation** while streaming

**How to use:**
- Just send a message normally; streaming happens automatically
- Click **Stop** button to interrupt the response mid-stream
- The response is saved to conversation history after completion

**Provider Support:**
- All 17 providers support streaming
- If a provider rejects streaming requests, open Settings → **Other** and enable
  **Disable response streaming (use full JSON responses)**.

---

### 3. Conversation Sessions

**What it does:**
- Each chat session is saved to disk at `~/.local/share/plasmoids/org.kde.plasma.kdeaichat/conversations/`
- Sessions persist after the widget closes or Plasma restarts

**How to use:**
1. **View Sessions:**
   - Look for the **Sessions menu** in the top-left of the chat (folder icon or label)
   - Click to see list of recent sessions

2. **Create New Session:**
   - Click **New Chat** button (or use the menu)
   - Existing chat is automatically saved before starting a new one

3. **Load Previous Session:**
   - Click a session name from the sessions list
   - Previous messages reload

4. **Session Data:**
   - Stored as JSON files: `conversations/{sessionId}.json`
   - Each session contains all messages, timestamps, and metadata

---

### 4. Clipboard Integration

**What it does:**
- Inject text from your clipboard directly into the chat
- Use selected text from any application

**How to use:**
1. **Paste Clipboard:**
   - Click the **Clipboard icon** (📋) in the input toolbar
   - Current clipboard content is inserted

2. **Use Selected Text:**
   - Highlight text in any application
   - Click the **Selection icon** (🔍) in KDE AI Chat
   - Selected text is inserted into the chat

3. **Tips:**
   - Great for code snippets: copy code → click clipboard icon → ask question
   - Fast way to include context from other apps

---

### 5. Response Actions

**Copy Response:**
- Click **Copy** button on any assistant message
- Full response is copied to clipboard

**Regenerate Response:**
- Click **Regenerate** button
- Resends the last user message and gets a fresh AI response

**Delete Message:**
- Click **Delete** button on any message
- Removes that message from the conversation

**Copy Code Block:**
- For responses with multiple code blocks, there are individual **Copy code N** buttons
- Click to copy specific code block to clipboard

---

### 6. File Attachment Support (via CLI)

**What it does:**
- If using CLI bridges (OpenCode, Aider, Claude Code), you can reference file attachments

**How to use:**
1. **For Code CLI Bridges:**
   - Include file references in your message (e.g., "Review `/path/to/file.py`")
   - Send to AI Chat first to get analysis
   - Click **Send to coding CLI** button (terminal icon)

2. **Available Bridges:**
   - **OpenCode** (beta)
   - **Aider** (AGPL-licensed, MIT-compatible)
   - **Claude Code** (requires local setup)

---

### 7. Compact State Indicator

**What it does:**
- The panel icon shows the widget's current state with visual feedback

**States:**
- **Idle** (💬): Ready for input
- **Streaming** (animated pulse): Response is arriving in real-time
- **Done** (✓): Response complete
- **Error** (❌): Something went wrong

**How to interpret:**
- Pulsing animation = actively streaming
- Static icon = idle or error
- Hover over icon to see tooltip with current state

---

### 8. KWallet & Plain Config Storage

**What it does:**
- API keys are securely synced to your **KDE Wallet (KWallet)** via DBus if active, or fall back to standard persistent plain-text configuration saved in your user home config directory.

**How to use:**
1. Open Settings → enter your credentials for any provider.
2. The widget automatically trims the keys and syncs them to KWallet (if available) or saves them directly in `~/.config/kdeaichatrc`.
3. Changes are auto-saved in the background immediately.

**Manual KWallet inspection:**
```bash
# Open KWallet Manager from terminal
kwalletmanager5

# Or query keys via DBus
qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets
```

---

### 9. Background Notifications

**What it does:**
- When a response completes, a desktop notification is sent (if enabled)
- You don't need to keep the widget open to see it

**How to enable:**
1. Open Settings → **General** tab
2. Enable **"Send desktop notifications for background completions"**
3. Notifications will appear in your system notification panel

**What the notification shows:**
- "KDE AI Chat: Response received"
- First 100 characters of the response
- Click to bring the widget to foreground

---

### 10. Global Keyboard Shortcut

**What it does:**
- Configure a keyboard shortcut to activate the KDE AI Chat widget from anywhere

**How to set up:**
1. Open **System Settings** → **Shortcuts** (or KDE's shortcut manager)
2. Search for "KDE AI Chat"
3. Assign a keyboard shortcut (e.g., `Meta+Shift+K`)
4. Press the shortcut from any app to open KDE AI Chat

**Alternative setup in widget settings:**
- Go to Settings → **Shortcuts** tab
- Shows notes on global hotkey configuration

---

## Advanced Configuration

### Custom API Endpoints

**Why:**
- Use a proxy, VPN, or self-hosted service
- Route requests through a custom gateway

**How:**
1. Go to Settings → **General**
2. In the **API Endpoint** field, enter your custom URL
3. Example: `http://localhost:8000/v1`
4. Click **Refresh Models** to query models and verify connection

---

### Widget Icon, Non-streaming Responses, and MCP Tools

These three options are in Settings → **Other**, under
**Widget Icon & Appearance** and **Response Streaming & MCP Server Tools**:

- **Widget Icon:** click **Choose Image…** to pick any image file (PNG, JPG,
  SVG, WEBP, or animated GIF) — the image is shown in the panel and updates
  live. **Reset** restores the default icon, or use the presets for KDE icon
  names.
- **Disable response streaming:** sends a complete JSON request instead of an
  SSE stream for OpenAI-compatible providers. This is useful for providers that
  return HTTP 400 when `stream: true` is requested.
- **Enable Model Context Protocol (MCP) server & web search tools:** opt in to
  the built-in web search tool. The optional **MCP servers** field accepts a JSON
  array, for example:

  ```json
   [{"id":"filesystem","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/tmp"],"tools":[]}]
  ```

   Click **Discover tools** after adding a server. The widget performs the
   standard MCP `initialize` and `tools/list` handshake and fills tool schemas
   automatically. MCP tool calls are handled automatically and are kept out of
   the visible chat transcript.

---

### Temperature Control

**What it does:**
- Controls response randomness/creativity

**Scale:**
- **0.0**: Most deterministic (same response every time)
- **1.0**: Balanced
- **2.0**: Most creative (varied, sometimes hallucinating)

**How to set:**
1. Go to Settings → **General**
2. Adjust the **Temperature** slider
3. Higher for creative writing, lower for code/facts

---

### Session Management

**View saved sessions:**
```bash
ls ~/.local/share/plasmoids/org.kde.plasma.kdeaichat/conversations/
```

**Inspect a session:**
```bash
cat ~/.local/share/plasmoids/org.kde.plasma.kdeaichat/conversations/{sessionId}.json | jq .
```

**Delete a session:**
```bash
rm ~/.local/share/plasmoids/org.kde.plasma.kdeaichat/conversations/{sessionId}.json
```

---

### Theme Customization

**What it does:**
- Widget colors and spacing automatically match your KDE Plasma theme

**How to change:**
1. Go to **System Settings** → **Appearance** → **Colors** or **Application Style**
2. Choose your theme
3. KDE AI Chat will automatically update colors/spacing

**Supported themes:**
- Any KDE Plasma 6 theme (dark, light, custom)
- High contrast themes are supported

---

## Troubleshooting

### "Provider configuration is missing"
**Problem:** Settings show a warning about missing configuration.

**Solution:**
1. Open Settings (gear icon)
2. Select a provider from the dropdown
3. Enter API Key and click **Refresh Models** to load active models.

---

### API Key Not Working
**Problem:** Model fetching fails or responses show auth errors.

**Solution:**
1. Verify the API key is correct (copy/paste from provider website)
2. Ensure the **Provider** dropdown matches your API key source
3. Check if the API key has expired or been revoked (regenerate if needed)
4. For paid services, ensure you have active credits/billing

---

### Streaming Not Working
**Problem:** Responses arrive all at once instead of token-by-token.

**Solution:**
1. This is normal for some providers (e.g., if the provider doesn't support streaming)
2. Check that streaming is enabled in the provider's settings
3. Try switching providers to verify feature works

---

### KWallet Errors
**Problem:** "Could not retrieve API key from KWallet" or keys not loading on startup.

**Solution:**
1. Ensure `kwalletd6` is running:
   ```bash
   systemctl --user status plasma-kwalletd.service
   # or start it:
   systemctl --user start plasma-kwalletd.service
   ```

2. Open KWallet Manager and check that the `KaiChat` folder exists and contains your keys:
   ```bash
   kwalletmanager5
   ```

3. If KWallet is not available on your system, the widget falls back to plaintext keys in the standard local configuration file. Use KWallet when at-rest secret protection is required.

4. Re-enter your API key in Settings to verify and trigger synchronization.

---

### Conversation Sessions Not Loading
**Problem:** Previous chats are missing or won't load.

**Solution:**
1. Check that sessions exist:
   ```bash
   ls -la ~/.local/share/plasmoids/org.kde.plasma.kdeaichat/conversations/
   ```

2. If directory is empty, sessions may not be saved. Ensure **conversation persistence** is working:
   - Send a test message
   - Wait for response
   - Check if session file is created

3. If files exist but don't load, restart the widget:
   - Right-click widget → **Configure** → close
   - Or restart Plasma Shell: `kquitapp6 plasmashell && kstart6 plasmashell`

---

### High CPU Usage
**Problem:** Widget is using too much CPU (especially during streaming).

**Solution:**
1. Disable background notifications (Settings → **General** → uncheck notification toggle)
2. Close Settings while not configuring
3. Reduce number of conversation sessions (delete old ones)
4. Restart the widget if it seems stuck

---

### Rate Limiting
**Problem:** Responses show rate limit errors after a few messages.

**Solution:**
1. Verify your API plan/credits with the provider
2. Wait before sending more messages
3. Consider upgrading your API plan if you're a heavy user

---

## Tips & Best Practices

1. **Use Clear Context:**
   - Prepend system instructions to your first message
   - Reference previous messages by number

2. **Temperature Tuning:**
   - Code generation: 0.3–0.7
   - Brainstorming: 1.0–1.5
   - Analysis: 0.3–0.5

3. **Multi-Provider Workflow:**
   - Use OpenAI for complex reasoning
   - Switch to Mistral for fast, cheap responses
   - Use Grok for current events (real-time knowledge)

4. **Keyboard Shortcuts:**
   - Set up a global hotkey for instant access
   - Great for quick questions during work

5. **Code Review:**
   - Paste code blocks and ask for review
   - Use regenerate to get multiple solutions

---

## Support & Feedback

- **GitHub Issues:** https://github.com/racstan/KDE-AI-Chat/issues
- **Feature Requests:** Open an issue with the `feature` label
- **Bug Reports:** Include widget version and error messages

---

## License

KDE AI Chat is licensed under the MIT License. See `LICENSE` file for details.
