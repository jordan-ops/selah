#!/usr/bin/env python3
"""selah-dl - Selah webapp video downloader.

Two modes:
  (no args)          native-messaging stdio: the Chromium extension sends a
                     {url, title} JSON message; we acknowledge, then spawn
                     ourselves detached so the download survives Chromium
                     closing the pipe.
  --run URL TITLE    worker: yt-dlp into the Videos folder, with a
                     "Download started" and a "Download complete/failed"
                     notification via notify-send (picked up by the shell's
                     notification server).

Env:
  SELAH_DL_OUT       override output dir (used by the self-test only);
                     default ~/Videos.
"""

import fcntl
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import time

APP = "Selah"
VIDEOS_DIR = os.environ.get("SELAH_DL_OUT") or os.path.expanduser("~/Videos")
STATE_DIR = os.path.expanduser("~/.local/state/selah-video-dl")


def notify(title, body, icon="video-x-generic"):
    """Fire a desktop notification; never let notification trouble kill the job."""
    ns = shutil.which("notify-send")
    if not ns:
        return
    try:
        subprocess.run(
            [ns, "-a", APP, "-i", icon, "--", title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    except Exception:
        pass


def read_message():
    hdr = sys.stdin.buffer.read(4)
    if len(hdr) < 4:
        return None
    (n,) = struct.unpack("<I", hdr)
    if n > 4 * 1024 * 1024:
        return None
    raw = sys.stdin.buffer.read(n)
    if len(raw) != n:
        return None
    return json.loads(raw.decode("utf-8", "replace"))


def reply(obj):
    raw = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(raw)) + raw)
    sys.stdout.buffer.flush()


def serve():
    try:
        msg = read_message()
    except Exception:
        msg = None
    if not msg:
        return 1

    url = str(msg.get("url", "")).strip()
    title = " ".join(str(msg.get("title", "video")).split())[:200] or "video"
    if not url.startswith(("http://", "https://")):
        reply({"ok": False, "error": "not an http(s) url"})
        return 0

    os.makedirs(STATE_DIR, exist_ok=True)
    logfile = open(
        os.path.join(STATE_DIR, "spawn-%d.log" % int(time.time())), "ab"
    )
    try:
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "--run", url, title],
            stdin=subprocess.DEVNULL,
            stdout=logfile,
            stderr=logfile,
            start_new_session=True,  # survive the browser exiting
        )
    finally:
        logfile.close()

    reply({"ok": True})
    return 0


def run(url, title):
    os.makedirs(VIDEOS_DIR, exist_ok=True)
    os.makedirs(STATE_DIR, exist_ok=True)

    # One download per URL: if a job for this URL is already running, say so
    # instead of racing two yt-dlps over the same output file.
    lock_path = os.path.join(
        STATE_DIR, "dl-%s.lock" % hashlib.md5(url.encode()).hexdigest()[:16]
    )
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        notify("Already downloading", title, "dialog-information")
        return 0

    ytdlp = shutil.which("yt-dlp") or "yt-dlp"
    template = os.path.join(VIDEOS_DIR, "%(title).120B [%(id)s].%(ext)s")
    cmd = [
        ytdlp,
        "--no-playlist",
        "--quiet",
        "--no-warnings",
        "--print",
        "after_move:filepath",
        "-o",
        template,
        "-f",
        "bv*+ba/b" if shutil.which("ffmpeg") else "b",  # merged if ffmpeg, else single file
        "--",
        url,
    ]

    notify("Download started", title)
    started = time.time()
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, errors="replace"
        )
    except Exception as e:  # yt-dlp missing/not executable
        notify("Download failed", "%s\n%s" % (title, e), "dialog-error")
        return 1

    if proc.returncode == 0:
        lines = [l for l in proc.stdout.splitlines() if l.strip()]
        name = os.path.basename(lines[-1]) if lines else "video"
        notify(
            "Download complete",
            "%s\n%s  (%ds)" % (title, name, int(time.time() - started)),
            "folder-download",
        )
        return 0

    tail_src = (proc.stderr or proc.stdout or "").strip()
    tail = "\n".join(tail_src.splitlines()[-2:])[:300] or "no error output"
    notify("Download failed", "%s\n%s" % (title, tail), "dialog-error")
    return proc.returncode or 1


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "--run":
        return run(sys.argv[2], sys.argv[3])
    return serve()


if __name__ == "__main__":
    sys.exit(main())
