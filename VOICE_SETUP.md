# KDE AI Chat Voice Setup (Beta Feature)

Welcome to the Voice Tools (Speech-to-Text and Text-to-Speech) setup guide! Voice mode allows you to talk to the AI and have it read responses out loud using fully local, private AI models. 

> **⚠️ IMPORTANT DISCLAIMER (BETA FEATURE):**  
> Voice Tools are highly experimental. Running local AI models is complex, and the automatic setup downloads multiple machine-learning frameworks (like PyTorch and CUDA) in the background. **This can consume a HUGE amount of disk space (upwards of 4-6 GB) and can take a very long time to download**, depending on your internet speed. Please be extremely patient when clicking "Repair Engine" and wait for it to finish.

Since running local AI models is complex, the widget automates as much of the process as possible. Follow this step-by-step guide to get started.

## Step-by-Step Setup Guide

### Step 1: Install System Requirements
Before configuring the widget, you need a system-level text-to-speech dependency (`espeak-ng`) and basic build tools. Open your terminal and install them based on your Linux distribution:

- **Ubuntu / Debian**: `sudo apt install python3-venv python3-dev espeak-ng portaudio19-dev`
- **Fedora**: `sudo dnf install python3-devel espeak-ng portaudio-devel`
- **Arch Linux**: `sudo pacman -S python espeak-ng portaudio`
- **openSUSE**: `sudo zypper install python3-devel espeak-ng portaudio-devel`

### Step 2: Enable Voice Tools
1. Open the KDE AI Chat widget settings.
2. Navigate to the **Voice** tab.
3. Check the box for **Enable Voice Tools (Beta)**.

### Step 3: Set up the Python Engine
The widget uses a dedicated Python virtual environment to run the AI voice models without interfering with your system Python packages.
1. In the Voice settings tab, look at the **Status** section.
2. If it says the engine is missing or damaged, click the **Repair Engine** button.
3. The widget runs the setup in the background to download and install the required Python packages (`faster-whisper`, `kokoro-onnx`, etc.). This may take a few minutes depending on your internet speed.
4. Once completed, the status should update to show that the environment is ready.

### Step 4: Configure GPU Acceleration (NVIDIA Only)
If you have an NVIDIA graphics card, you can significantly speed up voice processing:
1. Check the **GPU Usage (CUDA)** box in the settings.
2. If the status says **GPU libraries: Missing**, click the **Repair Engine** button again.
3. The system will download the GPU-enabled versions of PyTorch (which are heavy, around 3GB). This will take some time.
4. Once completed, the status will show **GPU libraries: Installed**, and your voice processing will be faster. CPU mode remains supported when GPU acceleration is disabled or unavailable.

*Note: AMD and Intel GPU acceleration is not currently configured. CPU mode works on systems without NVIDIA CUDA; leave this option unchecked there.*

### Step 5: Download the AI Models
You don't need to manually hunt for models!
1. Leave the **STT folder** and **TTS folder** paths completely empty.
2. Click the **Check** button to verify the environment.
3. Close the settings window.
4. The system will automatically download the standard models (`faster-whisper-small` and `kokoro-82m`) in the background the **first time** you use them. 
   *(Note: Your first voice prompt or read-aloud might take an extra minute or two while the models download to your cache).*

---

## Using Voice Mode

- **Record Voice (STT)**: Click the microphone icon next to the chat input to start speaking. Click it again to stop and transcribe.
- **Read Aloud (TTS)**: Click the speaker icon on any assistant message to have the AI read it out loud. 
- **Stop Reading**: If you want to stop the AI from reading, you can click the **Stop button (■)** that appears in the status bar at the bottom of the chat while audio is playing.
- **Auto-TTS**: If you want the AI to automatically read every new response, you can enable "Auto-TTS" in the settings.

The optional STT/TTS daemons listen only on loopback and require a per-user token. The widget creates the token with mode `0600`; do not copy or share the token file.

## Troubleshooting

- **"Engine is damaged" or "Repair Engine" keeps showing up:** Try deleting your virtual environment folder completely by running `rm -rf ~/.local/share/kdeaichat/venv` in your terminal, and then clicking **Repair Engine** again.
- **Microphone not found:** Check your system's PulseAudio or PipeWire settings to ensure a default microphone is selected and unmuted.
- **Continuous Spinning Icon:** If the widget gets stuck on "Starting up...", it usually means a dependency is missing. Double-check that `espeak-ng` is installed.
- **Restarting the daemon**: The TTS/STT servers run in the background. If they ever glitch, simply unchecking and re-checking **Enable Voice Tools (Beta)** in the settings will cleanly restart them.

