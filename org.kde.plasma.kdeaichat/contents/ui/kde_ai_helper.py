#!/usr/bin/env python3
"""kde_ai_helper — IPC helper invoked by the plasmoid via QProcess.

Each ``cmd_*`` function implements one RPC command. The QML side
sends ``<command> <base64-payload>`` and reads the result on stdout.

This module intentionally has zero third-party dependencies (stdlib
only) so it can run inside the plasmoid install without an extra
virtualenv.
"""
import sys
import os
import json
import base64
import shutil
import subprocess
import shlex
import configparser
import fcntl
import re
import secrets
import tempfile
import time
import selectors
import signal
from contextlib import contextmanager
from typing import Any, Callable, Dict, List, Tuple


_MAX_FILE_BYTES = 50 * 1024 * 1024
_MAX_MCP_OUTPUT_BYTES = 2 * 1024 * 1024
_MAX_SCHEDULE_STORE_BYTES = 5 * 1024 * 1024
_MAX_CONFIG_BYTES = 5 * 1024 * 1024


def _as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return default


def _safe_path(value: Any, *, allow_empty: bool = False) -> str:
    """Return a normalized absolute user path or raise ``ValueError``.

    The QML side validates paths before putting them into an IPC command, but
    this helper is also callable directly and is the last trust boundary for
    filesystem operations.  Spaces and normal Unicode filenames are allowed;
    control characters and traversal components are not.
    """
    if value is None:
        if allow_empty:
            return ""
        raise ValueError("path is required")
    raw = str(value)
    if raw == "":
        if allow_empty:
            return ""
        raise ValueError("path is required")
    if len(raw) > 4096 or any(ch in raw for ch in ("\x00", "\n", "\r")):
        raise ValueError("invalid path")
    expanded = os.path.expanduser(raw)
    if not os.path.isabs(expanded):
        raise ValueError("path must be absolute")
    if any(part == ".." for part in expanded.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    normalized = os.path.normpath(expanded)
    if any(part == ".." for part in normalized.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    return normalized


def _atomic_write_text(path: str, content: str, mode: int = 0o600) -> None:
    """Atomically write a private text file and preserve its permissions."""
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=folder or None)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        os.chmod(path, mode)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _atomic_write_json(path: str, data: Any) -> None:
    _atomic_write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def _voice_token_path() -> str:
    return os.path.expanduser("~/.local/share/kdeaichat/voice-http-token")


def ensure_voice_http_token(path: str = "") -> str:
    """Create/read the per-user token used by the local voice HTTP daemons."""
    token_path = _safe_path(path or _voice_token_path())
    folder = os.path.dirname(token_path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    try: os.chmod(folder, 0o700)
    except OSError: pass
    lock_path = token_path + ".lock"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            with open(token_path, "r", encoding="ascii") as f:
                token = f.read().strip()
            if len(token) >= 32 and re.fullmatch(r"[A-Za-z0-9_-]+", token):
                os.chmod(token_path, 0o600)
                return token
        except (OSError, UnicodeError):
            pass

        token = secrets.token_urlsafe(32)
        fd, temporary = tempfile.mkstemp(prefix="." + os.path.basename(token_path) + ".", dir=folder)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="ascii") as f:
                f.write(token + "\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(temporary, token_path)
            os.chmod(token_path, 0o600)
        except Exception:
            try: os.close(fd)
            except OSError: pass
            try: os.unlink(temporary)
            except OSError: pass
            raise
        return token
    finally:
        try: fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally: os.close(lock_fd)


def _systemd_quote(value: str) -> str:
    """Quote one systemd unit value without allowing unit-file injection."""
    text = str(value)
    if not text or len(text) > 4096 or any(ord(ch) < 0x20 or ch == "\x7f" for ch in text):
        raise ValueError("unsafe path for systemd service")
    # systemd accepts C-style escapes in quoted values. Escape all syntax
    # characters instead of rejecting valid paths containing spaces or parens.
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


@contextmanager
def _schedule_store_lock():
    """Serialize helper mutations with the background scheduler daemon."""
    lock_path = _schedules_path() + ".lock"
    folder = os.path.dirname(lock_path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
        try: os.chmod(folder, 0o700)
        except OSError: pass
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _schedules_path() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/schedules.json')


def _pending_dir() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/pending')


def _results_dir() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/results')


def _load_schedules() -> Dict[str, Any]:
    """Load the schedule store, tolerating legacy list-formatted files.

    Returns a dict with at least ``"version"`` and ``"schedules"`` keys.
    On missing file, returns an empty default. On parse failure, returns
    the empty default as well (the caller's write will overwrite).
    """
    sp = _schedules_path()
    if os.path.exists(sp):
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                raise ValueError("schedule store is too large")
            with open(sp) as f:
                data: Any = json.load(f)
        except ValueError:
            raise
        except Exception:
            data = None
    else:
        data = None
    if isinstance(data, list):
        return {"version": 1, "schedules": data}
    if isinstance(data, dict):
        schedules = data.get("schedules", [])
        history = data.get("history", [])
        data["schedules"] = schedules if isinstance(schedules, list) else []
        data["history"] = history if isinstance(history, list) else []
        return data
    return {"version": 1, "schedules": []}


def cmd_toggle_schedule(payload: Dict[str, Any]) -> None:
    """Enable/disable a schedule by id, clearing ``nextRunAt`` on enable."""
    with _schedule_store_lock():
        data = _load_schedules()
        sched_id = str(payload.get("schedId", ""))
        enabled = _as_bool(payload.get("enabled", False), False)
        for s in data.get("schedules", []):
            if isinstance(s, dict) and s.get("id") == sched_id:
                s["enabled"] = enabled
                if enabled:
                    s["nextRunAt"] = ""
        _atomic_write_json(_schedules_path(), data)


def cmd_update_schedule_history_status(payload: Dict[str, Any]) -> None:
    """Patch the most recent history entry for a schedule with a status."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    with _schedule_store_lock():
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                return
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        history: List[Dict[str, Any]] = data.setdefault("history", [])
        sched_id = str(payload.get("schedId", ""))
        status = str(payload.get("status", ""))[:256]
        for entry in reversed(history):
            if isinstance(entry, dict) and entry.get("scheduleId") == sched_id:
                entry["status"] = status
                break
        _atomic_write_json(sp, data)


def cmd_migrate_history(payload: Dict[str, Any]) -> None:
    """Move (or copy) a history file to a new path, returning its content."""
    old_p: str = _safe_path(payload.get("oldFullPath", ""), allow_empty=True)
    new_p: str = _safe_path(payload.get("newFullPath", ""), allow_empty=True)
    current_b64: str = str(payload.get("currentB64", ""))
    res: Dict[str, Any] = {"status": "ok", "action": "none"}
    try:
        if not new_p:
            if old_p and os.path.exists(old_p):
                if os.path.getsize(old_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                res["action"] = "load"
                with open(old_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
        else:
            folder = os.path.dirname(new_p)
            if folder:
                os.makedirs(folder, mode=0o700, exist_ok=True)
            if os.path.exists(new_p):
                if os.path.getsize(new_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                res["action"] = "load"
                with open(new_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
            elif old_p and os.path.exists(old_p):
                if os.path.getsize(old_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                shutil.copy2(old_p, new_p)
                res["action"] = "copied"
            else:
                data_bytes = base64.b64decode(current_b64, validate=True)
                if len(data_bytes) > _MAX_FILE_BYTES:
                    raise ValueError("history export is too large")
                data = data_bytes.decode("utf-8")
                _atomic_write_text(new_p, data)
                res["action"] = "exported"
    except Exception as e:
        res["status"] = "error"
        res["message"] = str(e)
    print(base64.b64encode(json.dumps(res).encode("utf-8")).decode("utf-8"))


def cmd_write_history(payload: Dict[str, Any]) -> None:
    """Decode a base64 payload to a UTF-8 text file at ``fullPath``."""
    path = _safe_path(payload.get("fullPath", ""))
    data = base64.b64decode(str(payload.get("b64Str", "")), validate=True)
    if len(data) > _MAX_FILE_BYTES:
        raise ValueError("history export is too large")
    _atomic_write_text(path, data.decode("utf-8"))
    print("OK")


def cmd_read_history(payload: Dict[str, Any]) -> None:
    """Read a JSON file and print its contents to stdout."""
    path = _safe_path(payload.get("fullPath", ""), allow_empty=True)
    if not path or not os.path.exists(path):
        print("[]")
        return
    try:
        if os.path.getsize(path) > _MAX_FILE_BYTES:
            print("[]")
            return
        with open(path, "r", encoding="utf-8") as f:
            print(f.read(_MAX_FILE_BYTES + 1))
    except Exception:
        print("[]")


def cmd_delete_session_schedules(payload: Dict[str, Any]) -> None:
    """Remove every schedule whose ``chatId`` matches ``sessionId``."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    with _schedule_store_lock():
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                return
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        scheds: List[Dict[str, Any]] = data.get("schedules", [])
        session_id = str(payload.get("sessionId", ""))
        data["schedules"] = [s for s in scheds if isinstance(s, dict) and s.get("chatId") != session_id]
        _atomic_write_json(sp, data)


def cmd_poll_pending_triggers(payload: Dict[str, Any]) -> None:
    """Drain the pending trigger directory and return its contents.

    Each file in the pending directory is read, parsed, and removed.
    Schedules are also returned for the QML side to keep its list in
    sync with the persisted store.
    """
    res: List[Dict[str, Any]] = []
    pd = _pending_dir()
    if os.path.exists(pd):
        for f in sorted(os.listdir(pd))[:50]:
            if f.endswith(".json"):
                p = os.path.join(pd, f)
                try:
                    if os.path.getsize(p) > 512 * 1024:
                        raise ValueError("pending trigger is too large")
                    with open(p) as pf:
                        item = json.load(pf)
                    if isinstance(item, dict) and len(str(item.get("message", ""))) <= 200000:
                        res.append(item)
                except (OSError, ValueError, json.JSONDecodeError):
                    pass
                finally:
                    try: os.remove(p)
                    except OSError: pass
    scheds: List[Dict[str, Any]] = []
    try:
        with _schedule_store_lock():
            scheds = _load_schedules().get("schedules", [])
    except Exception:
        pass
    print(json.dumps({"pending": res, "schedules": scheds}))


def cmd_delete_schedule(payload: Dict[str, Any]) -> None:
    """Remove a single schedule by id."""
    with _schedule_store_lock():
        data = _load_schedules()
        sched_id = str(payload.get("schedId", ""))
        data["schedules"] = [s for s in data.get("schedules", []) if isinstance(s, dict) and s.get("id") != sched_id]
        _atomic_write_json(_schedules_path(), data)


def cmd_add_schedule(payload: Dict[str, Any]) -> None:
    """Append a new schedule entry to the store."""
    entry = payload.get("entry")
    if not isinstance(entry, dict):
        raise ValueError("schedule entry must be an object")
    with _schedule_store_lock():
        data = _load_schedules()
        data.setdefault("schedules", []).append(entry)
        _atomic_write_json(_schedules_path(), data)


def _load_config(path: str) -> configparser.ConfigParser:
    """Load a configparser file, preserving key case."""
    config = configparser.ConfigParser()
    config.optionxform = str
    if os.path.exists(path):
        if os.path.getsize(path) > _MAX_CONFIG_BYTES:
            raise ValueError("config file is too large")
        config.read(path)
    return config


def cmd_sync_config_keys(payload: Dict[str, Any]) -> None:
    """Merge ``payload["keys"]`` into the ``[General]`` section of a config file."""
    path = _safe_path(payload.get("configPath", ""))
    data: Dict[str, Any] = payload.get("keys", {})
    if not isinstance(data, dict):
        raise ValueError("keys must be an object")
    config = _load_config(path)
    if "General" not in config:
        config["General"] = {}
    for k, v in data.items():
        if not isinstance(k, str) or "\n" in k or "\r" in k:
            raise ValueError("invalid config key")
        config["General"][k] = str(v)
    from io import StringIO
    serialized = StringIO()
    config.write(serialized)
    _atomic_write_text(path, serialized.getvalue(), mode=0o600)


def cmd_clear_config_keys(payload: Dict[str, Any]) -> None:
    """Remove ``payload["keys"]`` from the ``[General]`` section."""
    path = _safe_path(payload.get("configPath", ""))
    keys: List[str] = payload.get("keys", [])
    if not isinstance(keys, list):
        raise ValueError("keys must be a list")
    config = _load_config(path)
    if "General" in config:
        for k in keys:
            if not isinstance(k, str) or "\n" in k or "\r" in k:
                raise ValueError("invalid config key")
            config["General"].pop(k, None)
        from io import StringIO
        serialized = StringIO()
        config.write(serialized)
        _atomic_write_text(path, serialized.getvalue(), mode=0o600)


def cmd_load_config_keys(payload: Dict[str, Any]) -> None:
    """Dump the ``[General]`` section as a JSON object to stdout."""
    path: str = _safe_path(payload.get("configPath", "~/.config/kdeaichatrc"))
    config = _load_config(path)
    res: Dict[str, str] = dict(config["General"]) if "General" in config else {}
    print(json.dumps(res))


def cmd_setup_scheduler_service(payload: Dict[str, Any]) -> None:
    """Install the scheduler service file, daemon, and schedules store.

    Copies the helper script to the user's bin directory, ensures the
    schedules store exists with restrictive permissions, and writes the
    systemd user unit. Reports whether the unit ended up enabled.
    """
    src = _safe_path(payload.get("srcPath", ""))
    dest = _safe_path(payload.get("destPath", ""))
    os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
    os.makedirs(_results_dir(), mode=0o700, exist_ok=True)
    try: os.chmod(os.path.dirname(dest), 0o700); os.chmod(_results_dir(), 0o700)
    except OSError: pass
    if os.path.exists(src):
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
    sp = _schedules_path()
    with _schedule_store_lock():
        if not os.path.exists(sp):
            _atomic_write_json(sp, {"version": 1, "schedules": []})
    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)
    sfile = sdir + "/kde-ai-scheduler.service"
    service_content = str(payload.get("serviceContent", ""))
    if not service_content or "\x00" in service_content or len(service_content) > 32768:
        raise ValueError("invalid scheduler service content")
    _atomic_write_text(sfile, service_content, mode=0o600)
    os.system("systemctl --user daemon-reload")
    if os.system("systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1") == 0:
        print("AUTO_ENABLED")
    else:
        print("AUTO_DISABLED")


def cmd_setup_venv_services(payload: Dict[str, Any]) -> None:
    """Install the voice services for STT and TTS systemd user units."""
    requested_venv = _safe_path(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    venv_py = requested_venv
    if not os.path.exists(venv_py) and venv_py.endswith("/bin/python3"):
        alternate = venv_py[:-len("python3")] + "python"
        if os.path.exists(alternate):
            venv_py = alternate
    if not os.path.exists(venv_py):
        venv_py = shutil.which("python3") or "/usr/bin/python3"
    venv_py = _safe_path(venv_py)

    helper_dir = os.path.dirname(os.path.abspath(__file__))
    voice_helper = _safe_path(os.path.join(helper_dir, "voice", "voice_helper.py"))
    token_path = _safe_path(_voice_token_path())
    ensure_voice_http_token(token_path)

    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)

    espeak_env = ""
    espeak_path = payload.get("espeakPath", "")
    if espeak_path:
        # A custom executable/directory is optional. Refuse unsafe unit-file
        # input rather than attempting to interpret relative paths or control
        # characters.
        raw_espeak = _safe_path(espeak_path)
        dir_path = raw_espeak if os.path.isdir(raw_espeak) else os.path.dirname(raw_espeak)
        if dir_path:
            env_path = f"PATH={dir_path}:{os.path.expanduser('~/.local/bin')}:/usr/local/bin:/usr/bin:/bin"
            espeak_env = "\nEnvironment=" + _systemd_quote(env_path)
            espeak_env += "\nEnvironment=" + _systemd_quote(f"PHONEMIZER_ESPEAK_PATH={dir_path}")

    venv_arg = _systemd_quote(venv_py)
    helper_arg = _systemd_quote(voice_helper)
    token_arg = _systemd_quote(token_path)

    def write_voice_unit(path: str, server_flag: str) -> None:
        content = f"""[Unit]
Description=KDE AI Chat {server_flag.upper().lstrip('-') } Daemon
After=network.target

[Service]
Type=simple
ExecStart={venv_arg} {helper_arg} {server_flag} --token-file {token_arg}
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1{espeak_env}

[Install]
WantedBy=default.target
"""
        _atomic_write_text(path, content, mode=0o600)

    write_voice_unit(os.path.join(sdir, "kde-ai-stt.service"), "--stt-server")
    write_voice_unit(os.path.join(sdir, "kde-ai-tts.service"), "--tts-server")

    os.system("systemctl --user daemon-reload")
    voice_enabled = _as_bool(payload.get("voiceEnabled", True), True)
    voice_tts_enabled = _as_bool(payload.get("voiceTtsEnabled", True), True)
    if voice_enabled:
        os.system("systemctl --user enable --now kde-ai-stt.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-stt.service 2>/dev/null")

    if voice_enabled and voice_tts_enabled:
        os.system("systemctl --user enable --now kde-ai-tts.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-tts.service 2>/dev/null")
    print("VOICE_SERVICES_SETUP_OK")

def cmd_delete_venv_setup(payload: Dict[str, Any]) -> None:
    """Disable/stop voice systemd services and delete the venv & downloaded models."""
    # Stop & disable services
    os.system("systemctl --user stop kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user stop kde-ai-tts.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-tts.service 2>/dev/null")
    
    # Remove the HTTP capability token as part of voice teardown.
    for token_file in (_voice_token_path(), _voice_token_path() + ".lock"):
        try:
            os.remove(token_file)
        except OSError:
            pass

    # Remove service files
    sdir = os.path.expanduser("~/.config/systemd/user")
    for sfile in ("kde-ai-stt.service", "kde-ai-tts.service"):
        p = os.path.join(sdir, sfile)
        if os.path.exists(p):
            try:
                os.remove(p)
            except Exception:
                pass
    os.system("systemctl --user daemon-reload")
    
    # Remove venv only when it is an explicitly selected absolute path with
    # the expected virtualenv layout. Never recursively remove an arbitrary
    # user-supplied directory.
    try:
        venv_py = _safe_path(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    except ValueError:
        venv_py = ""
    venv_dir = venv_py[:-12] if venv_py.endswith("/bin/python3") else ""
    if venv_dir and os.path.exists(venv_dir) and venv_dir != "/usr" and len(venv_dir) > 5:
        try:
            shutil.rmtree(venv_dir)
        except Exception:
            pass
            
    # Remove default models folder
    models_dir = os.path.expanduser("~/.cache/kdeaichat/models")
    if os.path.exists(models_dir):
        try:
            shutil.rmtree(models_dir)
        except Exception:
            pass
            
    # Remove default huggingface cache faster-whisper/kokoro entries
    hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
    if os.path.isdir(hf_cache):
        try:
            for entry in os.listdir(hf_cache):
                if "faster-whisper" in entry or "kokoro" in entry:
                    p = os.path.join(hf_cache, entry)
                    if os.path.isdir(p):
                        try:
                            shutil.rmtree(p)
                        except Exception:
                            pass
        except Exception:
            pass
                        
    print("DELETE_SETUP_OK")


def cmd_save_all_schedules(payload: Dict[str, Any]) -> None:
    """Persist a full schedules payload (replaces the existing file atomically)."""
    if not isinstance(payload, dict):
        raise ValueError("schedule payload must be an object")
    if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > 1500000:
        raise ValueError("schedule payload is too large")
    p = os.path.expanduser("~/.local/share/kdeaichat")
    os.makedirs(p, mode=0o700, exist_ok=True)
    try: os.chmod(p, 0o700)
    except OSError: pass
    target = os.path.join(p, "schedules.json")
    try:
        with _schedule_store_lock():
            try:
                disk = _load_schedules()
            except Exception:
                disk = {"version": 1, "schedules": [], "history": []}
            merged_history = []
            seen = set()
            for history in (disk.get("history", []), payload.get("history", [])):
                for entry in history if isinstance(history, list) else []:
                    if not isinstance(entry, dict):
                        continue
                    key = entry.get("id") or json.dumps(entry, sort_keys=True, ensure_ascii=False)
                    if key not in seen:
                        seen.add(key)
                        merged_history.append(entry)
            payload_to_write = dict(payload)
            payload_to_write["schedules"] = [s for s in payload.get("schedules", []) if isinstance(s, dict)][:1000]
            payload_to_write["history"] = merged_history[-1000:]
            if not isinstance(payload_to_write.get("settings"), dict):
                payload_to_write["settings"] = disk.get("settings", {}) if isinstance(disk.get("settings", {}), dict) else {}
            _atomic_write_json(target, payload_to_write)
        print("SCHED_SAVE_OK")
    except Exception as e:
        sys.stderr.write(f"Error saving schedules: {e}\n")
        print("SCHED_SAVE_ERROR")


def _process_memory_kb(name: str, env_filter: str = None) -> int:
    """Sum RSS (in KiB) for every process whose command line matches ``name``."""
    r = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
    pids = r.stdout.strip().split()
    total = 0
    for pid in pids:
        try:
            if env_filter:
                try:
                    with open(f"/proc/{pid}/environ", "rb") as f:
                        env_data = f.read()
                    if env_filter.encode("utf-8") not in env_data:
                        continue
                except Exception:
                    continue

            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
        except Exception:
            pass
    return total


def cmd_get_memory_usage(payload: Dict[str, Any]) -> None:
    """Return RSS totals (KiB) for the opencode, stt, tts, and scheduler processes."""
    import urllib.request
    
    stt_vram = 0
    token = _read_existing_voice_token()
    headers = {"X-KDE-AI-Chat-Token": token} if token else {}

    try:
        req = urllib.request.Request("http://127.0.0.1:9015/status", headers=headers)
        with urllib.request.urlopen(req, timeout=1.0) as response:
            d = json.loads(response.read())
        stt_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    tts_vram = 0
    try:
        req = urllib.request.Request("http://127.0.0.1:9016/status", headers=headers)
        with urllib.request.urlopen(req, timeout=1.0) as response:
            d = json.loads(response.read())
        tts_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    # For STT/TTS, check both persistent server processes and one-shot command processes
    stt_mem = _process_memory_kb("voice_helper.py.*--stt-server")
    if stt_mem == 0:
        stt_mem = _process_memory_kb("voice_helper.py.*start_stt")
    tts_mem = _process_memory_kb("voice_helper.py.*--tts-server")
    if tts_mem == 0:
        tts_mem = _process_memory_kb("voice_helper.py.*cmd.*tts")
        
    # Track the opencode serve instance (server). We don't need env_filter because any opencode serve process on the machine is the one we connect to.
    opencode_mem = _process_memory_kb("opencode serve")
    
    d: Dict[str, int] = {
        "opencode": opencode_mem,
        "stt": stt_mem,
        "tts": tts_mem,
        "stt_vram": stt_vram,
        "tts_vram": tts_vram,
        "scheduler": _process_memory_kb("kde-ai-scheduler.py"),
    }
    print(json.dumps(d))


def cmd_export_chat(payload: Dict[str, Any]) -> None:
    """Decode a base64 chat export and write it to ``filePath`` as UTF-8."""
    path = _safe_path(payload.get("filePath", ""))
    data = base64.b64decode(str(payload.get("b64Content", "")), validate=True)
    if len(data) > _MAX_FILE_BYTES:
        raise ValueError("chat export is too large")
    _atomic_write_text(path, data.decode("utf-8"))
    print("OK")


def _read_existing_voice_token(path: str = "") -> str:
    """Read an existing voice token without creating one as a side effect."""
    token_path = _safe_path(path or _voice_token_path())
    try:
        with open(token_path, "r", encoding="ascii") as f:
            token = f.read().strip()
        return token if re.fullmatch(r"[A-Za-z0-9_-]{32,}", token) else ""
    except (OSError, UnicodeError, ValueError):
        return ""


def cmd_get_voice_token(payload: Dict[str, Any]) -> None:
    """Return the private token shared by the widget and voice daemons."""
    print(json.dumps({"type": "voice_token", "token": ensure_voice_http_token()}))


def _run_pi_process(argv: List[str], env: Dict[str, str], timeout: int) -> Tuple[int, bytes, bytes, bool]:
    """Run Pi while draining both pipes and retaining bounded output."""
    proc = subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        start_new_session=True,
    )
    limits = (10 * 1024 * 1024, 2 * 1024 * 1024)
    buffers = [bytearray(), bytearray()]
    selector = selectors.DefaultSelector()
    streams = [proc.stdout, proc.stderr]
    for index, stream in enumerate(streams):
        selector.register(stream, selectors.EVENT_READ, index)

    timed_out = False
    deadline = time.monotonic() + timeout
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except (OSError, ProcessLookupError):
                    proc.kill()
                break
            for key, _ in selector.select(min(remaining, 0.25)):
                stream = key.fileobj
                try:
                    chunk = os.read(stream.fileno(), 65536)
                except (OSError, ValueError):
                    chunk = b""
                if not chunk:
                    selector.unregister(stream)
                    stream.close()
                    continue
                index = key.data
                if len(buffers[index]) < limits[index]:
                    room = limits[index] - len(buffers[index])
                    buffers[index].extend(chunk[:room])
        if timed_out:
            try: proc.wait(timeout=2)
            except subprocess.TimeoutExpired: _terminate_process(proc)
        else:
            try:
                proc.wait(timeout=max(1, int(deadline - time.monotonic()) + 1))
            except subprocess.TimeoutExpired:
                timed_out = True
                _terminate_process(proc)
    finally:
        selector.close()
        for stream in streams:
            try: stream.close()
            except Exception: pass
    return (124 if timed_out else proc.returncode), bytes(buffers[0]), bytes(buffers[1]), timed_out


def cmd_run_pi(payload: Dict[str, Any]) -> None:
    """Run one Pi CLI request without putting user text in a shell command."""
    env = os.environ.copy()
    extra_path = [
        os.path.expanduser("~/.npm-global/bin"),
        os.path.expanduser("~/.local/bin"),
        os.path.expanduser("~/bin"),
    ]
    env["PATH"] = env.get("PATH", "") + os.pathsep + os.pathsep.join(extra_path)

    if payload.get("version"):
        argv = ["pi", "--version"]
    else:
        prompt = str(payload.get("prompt", ""))
        if not prompt:
            print(json.dumps({"type": "pi_result", "exitCode": 2, "stdout": "", "stderr": "Pi prompt is empty"}))
            return
        if len(prompt) > 100000 or "\x00" in prompt:
            raise ValueError("Pi prompt is too large or contains an invalid character")
        session_id = str(payload.get("sessionId", ""))
        if not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", session_id):
            raise ValueError("invalid Pi session id")
        argv = ["pi", "--session-id", session_id, "--mode", "text"]
        provider = str(payload.get("provider", "")).strip()
        model = str(payload.get("model", "")).strip()
        for option_name, option_value in (("provider", provider), ("model", model)):
            if option_value and (len(option_value) > 256 or option_value.startswith("-") or any(ord(ch) < 0x20 for ch in option_value)):
                raise ValueError("invalid Pi " + option_name)
        if provider:
            argv.extend(["--provider", provider])
        if model:
            argv.extend(["--model", model])
        argv.extend(["-p", prompt])

    try:
        try:
            requested_timeout = int(payload.get("timeout", 300))
        except (TypeError, ValueError):
            requested_timeout = 300
        timeout = max(15, min(300, requested_timeout))
        code, stdout_bytes, stderr_bytes, timed_out = _run_pi_process(argv, env, timeout)
        stdout = stdout_bytes.decode("utf-8", errors="replace")
        stderr = stderr_bytes.decode("utf-8", errors="replace")
        if timed_out:
            stderr = "Pi request timed out after " + str(timeout) + " seconds"
        print(json.dumps({"type": "pi_result", "exitCode": code, "stdout": stdout, "stderr": stderr}))
    except FileNotFoundError:
        print(json.dumps({"type": "pi_result", "exitCode": 127, "stdout": "", "stderr": "Pi CLI was not found in PATH"}))
    except Exception as exc:
        print(json.dumps({"type": "pi_result", "exitCode": 1, "stdout": "", "stderr": str(exc)}))


def cmd_mcp_web_search(payload: Dict[str, Any]) -> None:
    """Perform a web search using DuckDuckGo HTML search API and print JSON results."""
    import urllib.request
    import urllib.parse
    import re
    from html import unescape

    query = str(payload.get("query", "")).strip()[:2000]
    if not query:
        print(json.dumps({"status": "error", "message": "Empty search query", "results": []}))
        return

    results: List[Dict[str, str]] = []
    try:
        url = "https://html.duckduckgo.com/html/?q=" + urllib.parse.quote(query)
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        })
        with urllib.request.urlopen(req, timeout=10) as response:
            html = response.read().decode("utf-8", errors="ignore")

        raw_matches = re.findall(
            r'<a[^>]+class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
            html, re.DOTALL
        )
        if not raw_matches:
            raw_matches = re.findall(
                r'<a class="result__url"[^>]*href="([^"]+)"[^>]*>\s*(.*?)\s*</a>.*?<a class="result__snippet"[^>]*>(.*?)</a>',
                html, re.DOTALL
            )

        for link, title, snippet in raw_matches[:6]:
            clean_title = unescape(re.sub(r'<[^>]+>', '', title)).strip()
            clean_snippet = unescape(re.sub(r'<[^>]+>', '', snippet)).strip()
            link_match = re.search(r'uddg=([^&]+)', link)
            actual_url = urllib.parse.unquote(link_match.group(1)) if link_match else link
            if actual_url and clean_title:
                results.append({
                    "title": clean_title,
                    "snippet": clean_snippet,
                    "url": actual_url
                })
        print(json.dumps({"status": "ok", "query": query, "results": results}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e), "results": []}))


def _terminate_process(proc: subprocess.Popen) -> None:
    """Terminate a helper subprocess and its children when possible."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (OSError, ProcessLookupError):
        try: proc.kill()
        except Exception: pass
    try: proc.wait(timeout=2)
    except Exception: pass


def cmd_mcp_query(payload: Dict[str, Any]) -> None:
    """Run one MCP stdio request using the MCP initialize handshake."""
    command = payload.get("serverCommand", "")
    command_args = payload.get("serverArgs", [])
    method = payload.get("method", "tools/list")
    params = payload.get("params", {})

    if not command:
        print(json.dumps({"status": "error", "message": "No server command provided"}))
        return

    try:
        argv = shlex.split(command) if isinstance(command, str) else list(command or [])
        if isinstance(command_args, list):
            argv.extend(str(arg) for arg in command_args)
        if not argv:
            raise ValueError("Empty MCP server command")
        if len(argv) > 64 or sum(len(str(arg)) for arg in argv) > 8192:
            raise ValueError("MCP server command is too large")
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": payload.get("protocolVersion", "2025-06-18"),
                "capabilities": {}, "clientInfo": {"name": "KDE AI Chat", "version": "1.0"},
            }},
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            {"jsonrpc": "2.0", "id": 2, "method": method, "params": params},
        ]
        with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
            proc = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE,
                stdout=stdout_file,
                stderr=stderr_file,
                start_new_session=True,
            )
            try:
                proc.communicate(input="".join(json.dumps(m) + "\n" for m in messages).encode("utf-8"), timeout=15)
            except subprocess.TimeoutExpired:
                _terminate_process(proc)
                raise
            stdout_file.seek(0)
            stderr_file.seek(0)
            stdout_data = stdout_file.read(_MAX_MCP_OUTPUT_BYTES).decode("utf-8", errors="replace")
            stderr_data = stderr_file.read(_MAX_MCP_OUTPUT_BYTES).decode("utf-8", errors="replace")
        responses = []
        for line in stdout_data.splitlines():
            try:
                item = json.loads(line)
                if isinstance(item, dict): responses.append(item)
            except json.JSONDecodeError:
                pass
        result = next((item for item in reversed(responses) if item.get("id") == 2), None)
        print(json.dumps(result or (responses[-1] if responses else {"status": "error", "message": stderr_data.strip() or "MCP server returned no JSON response"})))
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "error", "message": "MCP server timed out after 15 seconds"}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))


def cmd_mcp_discover(payload: Dict[str, Any]) -> None:
    """Discover tools for configured servers using the standard MCP handshake."""
    results = []
    for server in payload.get("servers", []):
        if not isinstance(server, dict) or not server.get("command"):
            continue
        request = dict(server)
        request["method"] = "tools/list"
        # Capture the same command output without changing the public RPC shape.
        server_id = str(server.get("id") or server.get("name") or "server")[:128]
        try:
            argv = shlex.split(str(server.get("command", "")))
            argv.extend(str(arg) for arg in server.get("args", []) if isinstance(server.get("args", []), list))
        except (TypeError, ValueError) as exc:
            results.append({"id": server_id, "tools": [], "error": "Invalid command: " + str(exc)[:512]})
            continue
        if len(argv) > 64 or sum(len(str(arg)) for arg in argv) > 8192:
            results.append({"id": server_id, "tools": [], "error": "Command is too large"})
            continue
        try:
            messages = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "KDE AI Chat", "version": "1.0"}}},
                {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            ]
            with tempfile.TemporaryFile() as output_file, tempfile.TemporaryFile() as error_file:
                proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=output_file, stderr=error_file, start_new_session=True)
                try:
                    proc.communicate("".join(json.dumps(m) + "\n" for m in messages).encode("utf-8"), timeout=15)
                except subprocess.TimeoutExpired:
                    _terminate_process(proc)
                    raise
                output_file.seek(0)
                error_file.seek(0)
                output = output_file.read(_MAX_MCP_OUTPUT_BYTES).decode("utf-8", errors="replace")
                error = error_file.read(_MAX_MCP_OUTPUT_BYTES).decode("utf-8", errors="replace")
            response = None
            for line in reversed(output.splitlines()):
                try:
                    item = json.loads(line)
                    if isinstance(item, dict) and item.get("id") == 2:
                        response = item; break
                except json.JSONDecodeError:
                    pass
            result_obj = (response or {}).get("result") or {}
            raw_tools = result_obj.get("tools", []) if isinstance(result_obj, dict) else []
            safe_tools = []
            for raw_tool in (raw_tools[:100] if isinstance(raw_tools, list) else []):
                if not isinstance(raw_tool, dict) or not raw_tool.get("name"):
                    continue
                safe_tool = {
                    "name": str(raw_tool.get("name"))[:128],
                    "description": str(raw_tool.get("description", ""))[:2000],
                }
                schema = raw_tool.get("inputSchema", raw_tool.get("parameters"))
                if isinstance(schema, dict):
                    try:
                        if len(json.dumps(schema, ensure_ascii=False)) <= 20000:
                            safe_tool["inputSchema"] = schema
                    except (TypeError, ValueError):
                        pass
                safe_tools.append(safe_tool)
                if len(json.dumps(safe_tools, ensure_ascii=False)) > 100000:
                    safe_tools.pop()
                    break
            server_id = str(server.get("id") or server.get("name") or "server")[:128]
            results.append({"id": server_id, "tools": safe_tools, "error": "" if response else error.strip()[:2000] or "No tools/list response"})
        except subprocess.TimeoutExpired:
            results.append({"id": server.get("id") or server.get("name") or "server", "tools": [], "error": "Timed out"})
        except Exception as exc:
            results.append({"id": server.get("id") or server.get("name") or "server", "tools": [], "error": str(exc)})
    print(json.dumps({"servers": results}))


def _watchdog_dir() -> str:
    return os.path.expanduser("~/.local/share/kdeaichat")


def _watchdog_paths(payload: Dict[str, Any]) -> Dict[str, str]:
    try:
        folder = _safe_path(payload.get("directory") or _watchdog_dir())
    except ValueError:
        folder = _safe_path(_watchdog_dir())
    return {
        "directory": folder,
        "heartbeat": os.path.join(folder, "plasmashell-heartbeat"),
        "pid": os.path.join(folder, "plasmashell-watchdog.pid"),
        "last_restart": os.path.join(folder, "plasmashell-watchdog.last-restart"),
    }


def _pid_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def _write_heartbeat(path: str) -> None:
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path, "a", encoding="utf-8"):
        os.chmod(path, 0o600)
        os.utime(path, None)


def _watchdog_monitor(payload: Dict[str, Any], paths: Dict[str, str]) -> None:
    try: requested_timeout = int(payload.get("timeout", 45))
    except (TypeError, ValueError): requested_timeout = 45
    try: requested_cooldown = int(payload.get("restartCooldown", 180))
    except (TypeError, ValueError): requested_cooldown = 180
    timeout = max(15, min(3600, requested_timeout))
    cooldown = max(timeout, min(86400, requested_cooldown))
    monitor_pid = os.getpid()
    with open(paths["pid"], "w", encoding="utf-8") as pid_file:
        os.chmod(paths["pid"], 0o600)
        pid_file.write(str(monitor_pid))

    try:
        while True:
            try:
                heartbeat_age = time.time() - os.path.getmtime(paths["heartbeat"])
            except OSError:
                heartbeat_age = timeout + 1

            if heartbeat_age > timeout:
                try:
                    last_restart = os.path.getmtime(paths["last_restart"])
                except OSError:
                    last_restart = 0

                if time.time() - last_restart >= cooldown:
                    try:
                        subprocess.run(
                            ["systemctl", "--user", "restart", "plasma-plasmashell.service"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=30,
                            check=False,
                        )
                    finally:
                        _write_heartbeat(paths["heartbeat"])
                        with open(paths["last_restart"], "w", encoding="utf-8") as marker:
                            os.chmod(paths["last_restart"], 0o600)
                            marker.write(str(time.time()))
            time.sleep(min(5, max(1, timeout // 3)))
    finally:
        try:
            with open(paths["pid"], encoding="utf-8") as pid_file:
                if pid_file.read().strip() == str(monitor_pid):
                    os.unlink(paths["pid"])
        except OSError:
            pass


def cmd_plasmashell_watchdog(payload: Dict[str, Any]) -> None:
    """Start, stop, or heartbeat an external PlasmaShell recovery monitor."""
    action = payload.get("action", "heartbeat")
    paths = _watchdog_paths(payload)
    os.makedirs(paths["directory"], mode=0o700, exist_ok=True)

    if action == "heartbeat":
        _write_heartbeat(paths["heartbeat"])
        print(json.dumps({"status": "ok", "action": action}))
        return

    if action == "stop":
        try:
            with open(paths["pid"], encoding="utf-8") as pid_file:
                pid = int(pid_file.read().strip())
            if _pid_is_alive(pid):
                os.kill(pid, 15)
        except (OSError, ValueError):
            pass
        try:
            os.unlink(paths["pid"])
        except OSError:
            pass
        print(json.dumps({"status": "ok", "action": action}))
        return

    if action == "monitor":
        _watchdog_monitor(payload, paths)
        return
    if action != "start":
        raise ValueError("Unknown watchdog action: " + str(action))

    try:
        with open(paths["pid"], encoding="utf-8") as pid_file:
            existing_pid = int(pid_file.read().strip())
        if _pid_is_alive(existing_pid):
            print(json.dumps({"status": "already-running", "pid": existing_pid}))
            return
    except (OSError, ValueError):
        pass

    _write_heartbeat(paths["heartbeat"])
    monitor_payload = dict(payload)
    monitor_payload["action"] = "monitor"
    encoded = base64.b64encode(json.dumps(monitor_payload).encode("utf-8")).decode("ascii")
    child = subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "plasmashell_watchdog", encoded],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    with open(paths["pid"], "w", encoding="utf-8") as pid_file:
        os.chmod(paths["pid"], 0o600)
        pid_file.write(str(child.pid))
    print(json.dumps({"status": "started", "pid": child.pid}))


def cmd_get_pi_models(payload: Dict[str, Any]) -> None:
    try:
        # We source ~/.profile or similar if needed, or rely on pi in PATH or global install
        # Pi is a globally installed CLI agent
        env = os.environ.copy()
        env["PATH"] = env.get("PATH", "") + ":" + os.path.expanduser("~/.npm-global/bin") + ":" + os.path.expanduser("~/.local/bin") + ":" + os.path.expanduser("~/bin")
        
        proc = subprocess.run(
            ["pi", "--list-models"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            env=env
        )
        providers_dict = {}
        lines = proc.stdout.splitlines()[1:]
        for line in lines:
            parts = line.split()
            if len(parts) >= 2:
                prov = parts[0]
                model = parts[1]
                if prov not in providers_dict:
                    providers_dict[prov] = []
                providers_dict[prov].append(model)
        
        providers_list = []
        for prov, models in providers_dict.items():
            providers_list.append({"id": prov, "models": models})
        print(json.dumps({"providers": providers_list}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))


def _decode_payload(raw: str) -> Dict[str, Any]:
    """Decode the base64+JSON payload passed as ``argv[2]``.

    Returns an empty dict on missing/empty input, exits the process on
    a parse error after printing a diagnostic.
    """
    if not raw:
        return {}
    try:
        raw_bytes = raw.encode("ascii") if isinstance(raw, str) else raw
        decoded: Any = json.loads(base64.b64decode(raw_bytes, validate=True).decode("utf-8"))
        if isinstance(decoded, dict):
            return decoded
        return {}
    except Exception as e:
        print(f"Error parsing payload: {e}")
        sys.exit(1)


def main() -> None:
    """Dispatch to the named ``cmd_*`` function with the decoded payload."""
    if len(sys.argv) < 2:
        print("Usage: kde_ai_helper.py <command> [b64payload]")
        sys.exit(1)

    command = sys.argv[1]
    payload = _decode_payload(sys.argv[2]) if len(sys.argv) > 2 else {}

    commands: Dict[str, Callable[[Dict[str, Any]], None]] = {
        "toggle_schedule": cmd_toggle_schedule,
        "update_schedule_history_status": cmd_update_schedule_history_status,
        "migrate_history": cmd_migrate_history,
        "write_history": cmd_write_history,
        "read_history": cmd_read_history,
        "delete_session_schedules": cmd_delete_session_schedules,
        "poll_pending_triggers": cmd_poll_pending_triggers,
        "delete_schedule": cmd_delete_schedule,
        "add_schedule": cmd_add_schedule,
        "sync_config_keys": cmd_sync_config_keys,
        "clear_config_keys": cmd_clear_config_keys,
        "load_config_keys": cmd_load_config_keys,
        "setup_scheduler_service": cmd_setup_scheduler_service,
        "setup_venv_services": cmd_setup_venv_services,
        "setup_voice_services": cmd_setup_venv_services,
        "delete_venv_setup": cmd_delete_venv_setup,
        "delete_voice_setup": cmd_delete_venv_setup,
        "save_all_schedules": cmd_save_all_schedules,
        "get_memory_usage": cmd_get_memory_usage,
        "export_chat": cmd_export_chat,
        "get_voice_token": cmd_get_voice_token,
        "run_pi": cmd_run_pi,
        "mcp_web_search": cmd_mcp_web_search,
        "mcp_query": cmd_mcp_query,
        "mcp_discover": cmd_mcp_discover,
        "plasmashell_watchdog": cmd_plasmashell_watchdog,
        "get_pi_models": cmd_get_pi_models,
    }

    if command not in commands:
        print(f"Unknown command: {command}")
        sys.exit(1)

    try:
        # Each schedule mutator acquires the shared lock around its complete
        # read/modify/write operation. Keeping locking inside the commands
        # avoids nested flock calls when the helper is invoked directly.
        commands[command](payload)
    except Exception as e:
        print(f"Error executing {command}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
