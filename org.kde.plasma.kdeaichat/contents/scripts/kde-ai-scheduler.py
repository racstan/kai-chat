#!/usr/bin/env python3
"""
kde-ai-scheduler.py — KDE AI Chat Scheduling Daemon (Simplified Message Injector)
================================================================================
Runs as a systemd user service. Reads ~/.local/share/kdeaichat/schedules.json,
and when a cron rule is due, writes a pending trigger JSON file to:
~/.local/share/kdeaichat/pending/sched-{id}-{timestamp}.json

This is picked up by the KDE AI Chat front-end widget, which injects it
directly into the active chat session.

Reload schedules without restart: kill -HUP <pid>
"""

import argparse
import fcntl
import json
import logging
import os
import re
import signal
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timedelta

parser = argparse.ArgumentParser(
    description="KDE AI Chat scheduling daemon — reads schedule files and triggers pending jobs via cron rules."
)
parser.add_argument("--debug", action="store_true", help="Enable debug-level logging")
parser.add_argument("--dry-run", action="store_true", help="Simulate without creating trigger files")
args, _ = parser.parse_known_args()

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.DEBUG if args.debug else logging.INFO,
)
log = logging.getLogger(__name__)

# ── Paths ──────────────────────────────────────────────────────────────────────
HOME = os.path.expanduser("~")
DATA_DIR = os.path.join(HOME, ".local", "share", "kdeaichat")
SCHEDULES_FILE = os.path.join(DATA_DIR, "schedules.json")
LOCK_FILE = os.path.join(DATA_DIR, "scheduler.lock")
LOCK_FD = None

# Tick interval in seconds
TICK_SECONDS = 5
MAX_SCHEDULE_STORE_BYTES = 5 * 1024 * 1024
MAX_SCHEDULES = 1000
MAX_HISTORY_ENTRIES = 1000

# ── Globals ────────────────────────────────────────────────────────────────────
schedules = []
history = []
execute_missed_schedules = False
history_limit = 100
settings_dict = {}
reload_requested = False
_schedules_mtime: float = 0.0


# ── Signal handlers ────────────────────────────────────────────────────────────
def handle_sighup(signum, frame):
    global reload_requested
    reload_requested = True
    log.info("SIGHUP received — will reload schedules.json on next tick")


def handle_sigterm(signum, frame):
    log.info("SIGTERM received — shutting down gracefully")
    cleanup()
    sys.exit(0)


signal.signal(signal.SIGHUP, handle_sighup)
signal.signal(signal.SIGTERM, handle_sigterm)


# ── Filesystem helpers ─────────────────────────────────────────────────────────
def ensure_dirs():
    for directory in (DATA_DIR, os.path.join(DATA_DIR, "pending")):
        os.makedirs(directory, mode=0o700, exist_ok=True)
        try: os.chmod(directory, 0o700)
        except OSError: pass


@contextmanager
def data_lock():
    """Coordinate schedule-store writes with the plasmoid helper."""
    path = SCHEDULES_FILE + ".lock"
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _safe_int(value, default, minimum=None):
    try:
        result = int(value)
    except (TypeError, ValueError):
        result = default
    if minimum is not None:
        result = max(minimum, result)
    return result


def _as_bool(value, default=False):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return default


def write_lock():
    global LOCK_FD
    fd = None
    try:
        fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        os.fchmod(fd, 0o600)
        # Acquire the inode lock before truncating or writing the PID. This
        # prevents a second startup from clobbering an active daemon's lock.
        fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.ftruncate(fd, 0)
        os.write(fd, str(os.getpid()).encode())
        LOCK_FD = fd
    except (OSError, IOError) as e:
        if fd is not None:
            try: os.close(fd)
            except OSError: pass
        log.error("Lock file %s: %s — another instance may be running", LOCK_FILE, e)
        sys.exit(1)


def _lock_pid_is_alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def cleanup():
    global LOCK_FD
    if LOCK_FD is not None:
        # Unlink while the descriptor is still locked, then release it. A new
        # daemon can create a fresh inode without an old cleanup removing it.
        try: os.unlink(LOCK_FILE)
        except OSError: pass
        try: os.close(LOCK_FD)
        except OSError: pass
        LOCK_FD = None
    else:
        # Also clean up an abandoned stale PID file, but never unlink a lock
        # that appears to belong to a live daemon we do not own.
        try:
            with open(LOCK_FILE, encoding="ascii") as f:
                pid = int(f.read().strip())
            if not _lock_pid_is_alive(pid):
                os.unlink(LOCK_FILE)
        except (OSError, ValueError):
            pass


# ── Schedules I/O ──────────────────────────────────────────────────────────────
def load_schedules():
    global history, execute_missed_schedules, history_limit, settings_dict
    if not os.path.exists(SCHEDULES_FILE):
        log.debug(f"Schedules file not found: {SCHEDULES_FILE}")
        history, execute_missed_schedules, history_limit, settings_dict = [], False, 100, {}
        return []
    try:
        with data_lock():
            if os.path.getsize(SCHEDULES_FILE) > MAX_SCHEDULE_STORE_BYTES:
                raise ValueError("schedule store is too large")
            with open(SCHEDULES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        if isinstance(data, list):
            items, history, settings_dict = data, [], {}
        elif isinstance(data, dict):
            items = data.get("schedules", [])
            history = data.get("history", [])
            settings_dict = data.get("settings", {})
            if not isinstance(settings_dict, dict): settings_dict = {}
        else:
            items, history, settings_dict = [], [], {}
        items = [s for s in items if isinstance(s, dict)][:MAX_SCHEDULES] if isinstance(items, list) else []
        history = [h for h in history if isinstance(h, dict)] if isinstance(history, list) else []
        execute_missed_schedules = _as_bool(settings_dict.get("executeMissedSchedules", False))
        history_limit = min(MAX_HISTORY_ENTRIES, _safe_int(settings_dict.get("historyLimit", 100), 100, 1))
        history = history[-history_limit:]
        log.info(f"Loaded {len(items)} schedule(s) (executeMissed={execute_missed_schedules}, historyLimit={history_limit}) and {len(history)} history entry(s) from {SCHEDULES_FILE}")
        return items
    except (json.JSONDecodeError, OSError, ValueError) as e:
        log.error("Failed to load schedules: %s", e)
        history, execute_missed_schedules, history_limit, settings_dict = [], False, 100, {}
        return []


def save_schedules(items, modified_sids=None):
    global history, settings_dict
    if modified_sids is None:
        modified_sids = set()
    try:
        with data_lock():
            try:
                with open(SCHEDULES_FILE, "r", encoding="utf-8") as f:
                    disk_data = json.load(f)
            except Exception:
                disk_data = {"version": 1, "schedules": [], "history": [], "settings": {}}
            if not isinstance(disk_data, dict):
                disk_data = {"version": 1, "schedules": [], "history": [], "settings": {}}
            disk_schedules = disk_data.get("schedules", [])
            if not isinstance(disk_schedules, list): disk_schedules = []
            disk_schedules = [s for s in disk_schedules if isinstance(s, dict)]
            if not modified_sids:
                disk_schedules = [s for s in items if isinstance(s, dict)]
            else:
                disk_map = {s.get("id"): s for s in disk_schedules if s.get("id") is not None}
                for s in items:
                    if not isinstance(s, dict): continue
                    sid = s.get("id")
                    if sid in modified_sids and sid in disk_map:
                        disk_map[sid] = s
                disk_schedules = list(disk_map.values())
            # Merge history/settings read from disk so helper/UI writes made
            # while the daemon was running are not silently overwritten.
            merged_history = []
            seen_history = set()
            for entry in list(disk_data.get("history", []) or []) + list(history or []):
                if not isinstance(entry, dict): continue
                key = entry.get("id") or json.dumps(entry, sort_keys=True, ensure_ascii=False)
                if key not in seen_history:
                    seen_history.add(key); merged_history.append(entry)
            merged_history = merged_history[-max(1, history_limit):]
            disk_settings = disk_data.get("settings", {})
            if not isinstance(disk_settings, dict): disk_settings = {}
            if not disk_settings and settings_dict:
                disk_settings = dict(settings_dict)
            payload = {"version": 1, "schedules": disk_schedules, "history": merged_history, "settings": disk_settings}
            serialized = json.dumps(payload, indent=2, ensure_ascii=False)
            if len(serialized.encode("utf-8")) > MAX_SCHEDULE_STORE_BYTES:
                raise ValueError("schedule store would exceed the size limit")
            tmp = SCHEDULES_FILE + f".tmp-{os.getpid()}"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(serialized)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, SCHEDULES_FILE)
            os.chmod(SCHEDULES_FILE, 0o600)
            history = merged_history
            settings_dict = disk_settings
        log.debug("Schedules and history saved")
    except (OSError, ValueError) as e:
        log.error("Failed to save schedules: %s", e)


# ── Cron parser ────────────────────────────────────────────────────────────────
WEEKDAY_NAMES = {
    "sun": 0, "mon": 1, "tue": 2, "wed": 3,
    "thu": 4, "fri": 5, "sat": 6,
}


def parse_cron_field(field_str, min_val, max_val):
    if not isinstance(field_str, str) or not field_str.strip():
        raise ValueError("invalid cron field")
    field_str = field_str.strip().lower()
    for name, num in WEEKDAY_NAMES.items():
        field_str = field_str.replace(name, str(num))

    result = set()

    for part in field_str.split(","):
        part = part.strip()
        step = 1
        if "/" in part:
            part, step_str = part.split("/", 1)
            step = int(step_str)
            if step <= 0:
                raise ValueError("cron step must be positive")

        if part == "*":
            start, end = min_val, max_val
        elif "-" in part:
            start_str, end_str = part.split("-", 1)
            start, end = int(start_str), int(end_str)
        else:
            val = int(part)
            if val < min_val or val > max_val:
                raise ValueError("cron value out of range")
            result.add(val)
            continue

        if start < min_val or end > max_val or start > end:
            raise ValueError("cron range out of range")
        for v in range(start, end + 1, step):
            result.add(v)

    return sorted(result)


def cron_matches(cron_expr, dt):
    if not isinstance(cron_expr, str):
        return False
    parts = cron_expr.strip().split()
    if len(parts) != 5:
        return False
    try:
        minutes = parse_cron_field(parts[0], 0, 59)
        hours = parse_cron_field(parts[1], 0, 23)
        mdays = parse_cron_field(parts[2], 1, 31)
        months = parse_cron_field(parts[3], 1, 12)
        wdays = parse_cron_field(parts[4], 0, 6)
    except (TypeError, ValueError, IndexError):
        return False

    py_wd = dt.weekday()
    cron_wd = (py_wd + 1) % 7

    dom_star = parts[2].strip() == "*"
    dow_star = parts[4].strip() == "*"

    if dom_star and dow_star:
        day_match = True
    elif dom_star:
        day_match = cron_wd in wdays
    elif dow_star:
        day_match = dt.day in mdays
    else:
        day_match = (dt.day in mdays) or (cron_wd in wdays)

    return (
        dt.minute in minutes
        and dt.hour in hours
        and day_match
        and dt.month in months
    )


# ── Schedule runner ────────────────────────────────────────────────────────────
def run_schedule(s):
    if not isinstance(s, dict):
        log.warning("Skipping malformed schedule entry")
        return "error"
    sid = str(s.get("id", "unknown"))
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", sid):
        log.warning("[%s] Skipping — invalid schedule id", sid[:64])
        return "error"
    name = str(s.get("name", "Unnamed"))[:256]
    chat_id = str(s.get("chatId", ""))
    if chat_id and not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", chat_id):
        log.warning("[%s] Skipping — invalid chat id", name)
        return "error"
    message = str(s.get("message", "")).strip()
    if len(message) > 200000:
        log.warning("[%s] Skipping — message is too large", name)
        return "error"
    should_notify = _as_bool(s.get("notify", True), True)

    if not chat_id or not message:
        log.warning("[%s] Skipping — missing chatId or message", name)
        return "error"

    log.info(f"[{name}] Triggering schedule message injection to chat {chat_id}")
    
    pending_dir = os.path.join(DATA_DIR, "pending")
    ts = int(time.time() * 1000)
    filename = f"sched-{sid}-{ts}.json"
    path = os.path.join(pending_dir, filename)

    payload = {
        "id": sid,
        "chatId": chat_id,
        "message": message,
        "notify": should_notify,
        "name": name,
        "timestamp": ts
    }

    if args.dry_run:
        log.info("[%s] DRY-RUN: would write trigger to %s", name, path)
        return "success"  # pretend it worked

    temporary = ""
    try:
        temporary = path + f".tmp-{os.getpid()}"
        with open(temporary, "w", encoding="utf-8") as f:
            os.chmod(temporary, 0o600)
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
        log.info(f"[{name}] Wrote pending trigger file successfully: {path}")
        return "success"
    except Exception as e:
        try:
            if os.path.exists(temporary):
                os.remove(temporary)
        except OSError:
            pass
        log.error("[%s] Failed to write pending trigger: %s", name, e)
        return "error"


# ── Main loop ──────────────────────────────────────────────────────────────────
def is_start_date_passed(s, now):
    if not isinstance(s, dict):
        return False
    start_date_str = s.get("startDate")
    if not start_date_str:
        return True
    try:
        clean_str = str(start_date_str)
        if clean_str.endswith("Z"):
            clean_str = clean_str[:-1] + "+00:00"
        
        # Parse ISO format string with timezone offset (e.g. +00:00)
        start_dt = datetime.fromisoformat(clean_str)
        if start_dt.tzinfo is not None:
            # Timezone-aware comparison
            from datetime import timezone
            now_utc = datetime.now(timezone.utc)
            return now_utc >= start_dt
        else:
            # Naive comparison fallback
            return now >= start_dt
    except Exception as e:
        log.warning("Error parsing startDate '%s': %s", start_date_str, e)
    return True


def update_schedule_timestamps(items, sid, now_iso, status, next_iso):
    updated = []
    for s in items:
        if not isinstance(s, dict):
            continue
        if s.get("id") == sid:
            s = dict(s)
            s["lastRunAt"] = now_iso
            s["lastRunStatus"] = status
            s["nextRunAt"] = next_iso
            s.pop("triggerNow", None)
        updated.append(s)
    return updated


def next_run_iso(cron_expr, start_date_str=None):
    """Compute next cron fire time. Pre-parses fields once to avoid per-iteration overhead."""
    if not isinstance(cron_expr, str):
        return ""
    parts = cron_expr.strip().split()
    if len(parts) != 5:
        return ""
    try:
        minutes_set = set(parse_cron_field(parts[0], 0, 59))
        hours_set   = set(parse_cron_field(parts[1], 0, 23))
        mdays_set   = set(parse_cron_field(parts[2], 1, 31))
        months_set  = set(parse_cron_field(parts[3], 1, 12))
        wdays_set   = set(parse_cron_field(parts[4], 0, 6))
    except (ValueError, IndexError):
        return ""

    dom_star = parts[2].strip() == "*"
    dow_star = parts[4].strip() == "*"

    # Parse start_date if present
    start_dt = None
    if start_date_str:
        try:
            clean_str = str(start_date_str)
            if clean_str.endswith("Z"):
                clean_str = clean_str[:-1] + "+00:00"
            parsed_dt = datetime.fromisoformat(clean_str)
            if parsed_dt.tzinfo is not None:
                parsed_dt = parsed_dt.astimezone().replace(tzinfo=None) # convert to local naive
            start_dt = parsed_dt
        except Exception as e:
            log.warning("Error parsing start_date_str in next_run_iso: %s", e)

    now = datetime.now().replace(second=0, microsecond=0)
    if start_dt and start_dt > now:
        # Start search exactly at start_dt because it hasn't run yet
        candidate = start_dt.replace(second=0, microsecond=0)
    else:
        # Start search from next minute
        candidate = now + timedelta(minutes=1)

    # Max search: 1 year of minutes
    for _ in range(527040):
        py_wd   = candidate.weekday()
        cron_wd = (py_wd + 1) % 7

        if dom_star and dow_star:
            day_ok = True
        elif dom_star:
            day_ok = cron_wd in wdays_set
        elif dow_star:
            day_ok = candidate.day in mdays_set
        else:
            day_ok = (candidate.day in mdays_set) or (cron_wd in wdays_set)

        if (candidate.minute in minutes_set
                and candidate.hour in hours_set
                and day_ok
                and candidate.month in months_set):
            return candidate.isoformat(timespec="seconds")

        candidate += timedelta(minutes=1)
    return ""


def refresh_next_runs(items):
    global execute_missed_schedules
    modified_sids = set()
    now = datetime.now()
    for s in items:
        if not isinstance(s, dict):
            continue
        if _as_bool(s.get("enabled"), False) and not _as_bool(s.get("archived", False), False):
            cron = str(s.get("cron", "") or "").strip()
            if cron:
                next_run_str = s.get("nextRunAt", "")
                should_recalc = False
                should_trigger_missed = False
                if not next_run_str:
                    should_recalc = True
                else:
                    try:
                        clean_next = str(next_run_str)
                        if clean_next.endswith("Z"):
                            clean_next = clean_next[:-1]
                        if "." in clean_next:
                            clean_next = clean_next.split(".")[0]
                        next_dt = datetime.fromisoformat(clean_next)
                        if next_dt < now - timedelta(seconds=5):
                            if execute_missed_schedules:
                                should_trigger_missed = True
                            else:
                                should_recalc = True
                    except Exception:
                        should_recalc = True
                
                if should_trigger_missed:
                    old_next = s.get("nextRunAt", "")
                    s["triggerNow"] = True
                    s["nextRunAt"] = next_run_iso(cron, s.get("startDate"))
                    log.info(f"[{s.get('name', 'Unnamed')}] Missed run detected! Executing missed schedule (old run: {old_next}, next scheduled: {s['nextRunAt']})")
                    modified_sids.add(s.get("id"))
                elif should_recalc:
                    old_next = s.get("nextRunAt", "")
                    s["nextRunAt"] = next_run_iso(cron, s.get("startDate"))
                    log.info(f"[{s.get('name', 'Unnamed')}] Recalculated next run time from {old_next} to {s['nextRunAt']} (past run bypassed)")
                    modified_sids.add(s.get("id"))
    return modified_sids


def _schedules_file_changed() -> bool:
    """Return True if schedules.json has been modified since we last loaded it."""
    global _schedules_mtime
    try:
        mtime = os.path.getmtime(SCHEDULES_FILE)
        if mtime != _schedules_mtime:
            _schedules_mtime = mtime
            return True
    except OSError:
        pass
    return False


def main():
    global schedules, reload_requested, history, _schedules_mtime

    log.info("KDE AI Chat Scheduler daemon starting up")
    ensure_dirs()
    write_lock()

    schedules = load_schedules()
    # Record mtime immediately after loading so we don't double-reload on startup
    try:
        _schedules_mtime = os.path.getmtime(SCHEDULES_FILE)
    except OSError:
        pass

    mod_sids = refresh_next_runs(schedules)
    if mod_sids:
        save_schedules(schedules, mod_sids)
        try:
            _schedules_mtime = os.path.getmtime(SCHEDULES_FILE)
        except OSError:
            pass

    log.info(f"Tick interval: {TICK_SECONDS}s — monitoring {len(schedules)} schedule(s)")

    while True:
        # Reload when explicitly signalled (SIGHUP) OR when the file changed on disk
        if reload_requested or _schedules_file_changed():
            reload_requested = False
            schedules = load_schedules()
            mod_sids = refresh_next_runs(schedules)
            if mod_sids:
                save_schedules(schedules, mod_sids)
                try:
                    _schedules_mtime = os.path.getmtime(SCHEDULES_FILE)
                except OSError:
                    pass
            log.info(f"Schedules reloaded — {len(schedules)} schedule(s) active")

        now = datetime.now()
        now_iso = now.isoformat(timespec="seconds")
        modified_sids = set()

        for s in schedules:
            if not isinstance(s, dict) or _as_bool(s.get("archived", False), False):
                continue
            
            sid = str(s.get("id", ""))
            if not sid:
                continue
            
            # Migration for old tasks that were finished but not archived correctly by previous versions
            if not _as_bool(s.get("enabled", True), True):
                disable_task = False
                if s.get("taskType") == "single":
                    disable_task = True
                elif _as_bool(s.get("limitEnabled", False)) and _safe_int(s.get("runCount", 0), 0, 0) >= _safe_int(s.get("limitCount", 5), 5, 1):
                    disable_task = True
                
                if disable_task:
                    s["archived"] = True
                    s["nextRunAt"] = ""
                    modified_sids.add(sid)
                continue

            cron = str(s.get("cron", "") or "").strip()
            trigger_now = _as_bool(s.get("triggerNow", False))
            task_type = str(s.get("taskType", "repeat") or "repeat")

            # Start date filter
            start_passed = is_start_date_passed(s, now)
            if not start_passed and not trigger_now:
                continue

            # Limit checking
            if task_type == "repeat" and _as_bool(s.get("limitEnabled", False)):
                run_count = _safe_int(s.get("runCount", 0), 0, 0)
                limit_count = _safe_int(s.get("limitCount", 5), 5, 1)
                if run_count >= limit_count:
                    s["enabled"] = False
                    modified_sids.add(sid)
                    continue

            should_run = trigger_now
            if not should_run:
                if task_type == "single":
                    should_run = not s.get("lastRunAt")
                elif cron:
                    # Prevent multiple runs within the same minute
                    last_run = str(s.get("lastRunAt", "") or "")
                    if last_run and last_run.startswith(now_iso[:16]):
                        should_run = False
                    else:
                        should_run = cron_matches(cron, now)

            if should_run:
                status = run_schedule(s)

                # Append to history
                try:
                    entry = {
                        "id": f"h-{int(time.time() * 1000)}",
                        "scheduleId": sid,
                        "scheduleName": s.get("name", "Unnamed"),
                        "chatId": s.get("chatId", ""),
                        "chatName": s.get("chatName", "Chat"),
                        "message": s.get("message", ""),
                        "timestamp": now_iso,
                        "status": status or "success"
                    }
                    history.append(entry)
                    if len(history) > history_limit:
                        history = history[-history_limit:]
                except Exception as ex:
                    log.error("Failed to append to history: %s", ex)

                # Update run counts and limits
                new_count = _safe_int(s.get("runCount", 0), 0, 0) + 1
                s["runCount"] = new_count

                disable_task = False
                if task_type == "single":
                    disable_task = True
                elif _as_bool(s.get("limitEnabled", False)) and new_count >= _safe_int(s.get("limitCount", 5), 5, 1):
                    disable_task = True

                next_iso = ""
                if not disable_task and cron:
                    next_iso = next_run_iso(cron, s.get("startDate"))

                schedules = update_schedule_timestamps(
                    schedules, sid, now_iso, status or "success", next_iso
                )

                # Archive task when done (single-run or limit reached)
                if disable_task:
                    for item in schedules:
                        if item.get("id") == sid:
                            item["enabled"] = False
                            item["nextRunAt"] = ""
                            item["archived"] = True  # move to archived so UI shows in History

                modified_sids.add(sid)

        if modified_sids:
            save_schedules(schedules, modified_sids)
            # Update mtime so we don't self-reload our own write
            try:
                _schedules_mtime = os.path.getmtime(SCHEDULES_FILE)
            except OSError:
                pass

        time.sleep(TICK_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Interrupted — shutting down")
        cleanup()
        sys.exit(0)
    except Exception as e:
        log.error("Fatal error: %s", e)
        cleanup()
        sys.exit(1)
