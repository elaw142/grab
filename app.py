from flask import Flask, request, jsonify, send_file, render_template
import os
import uuid
import threading
import time
import subprocess
import glob
import shutil
from urllib.parse import urlparse

app = Flask(__name__)

DOWNLOAD_DIR = "/tmp/grab"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

YTDLP_BIN = os.environ.get("YTDLP_BIN", "/usr/local/bin/yt-dlp")
COOKIES_FILE = os.environ.get("COOKIES_FILE", "/app/cookies.txt")
INSTAGRAM_COOKIES_FILE = os.environ.get("INSTAGRAM_COOKIES_FILE", "/app/instagram-cookies.txt")
JS_RUNTIME = os.environ.get("YTDLP_JS_RUNTIME", "deno:/usr/local/bin/deno")
YTDLP_PROXY = os.environ.get("YTDLP_PROXY")
DIRECT_PROXY_VALUES = {"", "none", "direct", "off", "false", "0"}


def hostname_matches(url, domain):
    hostname = (urlparse(url).hostname or "").lower().rstrip(".")
    return hostname == domain or hostname.endswith(f".{domain}")


def is_youtube_url(url):
    return hostname_matches(url, "youtube.com") or hostname_matches(url, "youtu.be")


def get_cookies_file(url):
    if hostname_matches(url, "instagram.com") and os.path.exists(INSTAGRAM_COOKIES_FILE):
        return INSTAGRAM_COOKIES_FILE
    if is_youtube_url(url) and os.path.exists(COOKIES_FILE):
        return COOKIES_FILE
    return None

jobs = {}

FORMATS = ["mp3", "wav", "flac", "m4a", "ogg"]


def make_cookies_copy(cookies_file=None):
    if not cookies_file or not os.path.exists(cookies_file):
        return None

    cookies_copy = os.path.join(DOWNLOAD_DIR, f"cookies-{uuid.uuid4()}.txt")
    shutil.copyfile(cookies_file, cookies_copy)
    os.chmod(cookies_copy, 0o600)
    return cookies_copy


def build_ytdlp_cmd(*args, cookies_file=None):
    cmd = [YTDLP_BIN]

    if cookies_file:
        cmd.extend(["--cookies", cookies_file])
    if JS_RUNTIME:
        cmd.extend(["--js-runtimes", JS_RUNTIME])
    if YTDLP_PROXY is not None:
        proxy = YTDLP_PROXY.strip()
        cmd.extend(["--proxy", "" if proxy.lower() in DIRECT_PROXY_VALUES else proxy])

    cmd.extend(args)
    return cmd


def last_stderr_line(result):
    lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
    return lines[-1] if lines else "Download failed"


def cleanup_file(path, delay=300):
    def delete():
        time.sleep(delay)
        if os.path.exists(path):
            os.remove(path)
    threading.Thread(target=delete, daemon=True).start()


def do_download(job_id, url, fmt):
    job = jobs[job_id]
    output_path = os.path.join(DOWNLOAD_DIR, job_id)
    cookies_copy = None

    try:
        cookies_copy = make_cookies_copy(get_cookies_file(url))

        # Public YouTube videos are more reliable without account cookies, and
        # yt-dlp recommends only using account cookies for restricted content.
        # Other authenticated sites try their site-specific cookies first.
        cookie_attempts = [None]
        if cookies_copy:
            cookie_attempts = ([None, cookies_copy]
                               if is_youtube_url(url)
                               else [cookies_copy, None])

        result = None
        successful_cookies = None
        for attempt_cookies in cookie_attempts:
            result = subprocess.run(build_ytdlp_cmd(
                "-f", "bestaudio/best",
                "-x", "--audio-format", fmt,
                "-o", output_path + ".%(ext)s",
                "--no-playlist",
                url,
                cookies_file=attempt_cookies
            ), capture_output=True, text=True)

            if result.returncode == 0:
                successful_cookies = attempt_cookies
                break

            for partial_path in glob.glob(output_path + ".*"):
                if os.path.isfile(partial_path):
                    os.remove(partial_path)

        if result is None or result.returncode != 0:
            job["status"] = "error"
            job["error"] = last_stderr_line(result)
            return

        title_result = subprocess.run(build_ytdlp_cmd(
            "--get-title",
            "--no-playlist",
            url,
            cookies_file=successful_cookies
        ), capture_output=True, text=True)
        title = title_result.stdout.strip() or "audio"

        files = glob.glob(output_path + f".{fmt}")
        if not files:
            files = glob.glob(output_path + ".*")

        final_path = files[0] if files else None
        if not final_path:
            job["status"] = "error"
            job["error"] = "Output file not found"
            return

        job["status"] = "done"
        job["path"] = final_path
        job["title"] = title
        job["fmt"] = fmt
        cleanup_file(final_path)

    except Exception as e:
        job["status"] = "error"
        job["error"] = str(e)
    finally:
        if cookies_copy and cookies_copy != COOKIES_FILE and os.path.exists(cookies_copy):
            os.remove(cookies_copy)


@app.route("/")
def index():
    return render_template("index.html", formats=FORMATS)


@app.route("/api/download", methods=["POST"])
def download():
    data = request.json
    url = data.get("url", "").strip()
    fmt = data.get("format", "mp3").lower()

    if not url:
        return jsonify({"error": "No URL provided"}), 400
    if fmt not in FORMATS:
        return jsonify({"error": "Invalid format"}), 400

    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "processing"}

    thread = threading.Thread(
        target=do_download, args=(job_id, url, fmt), daemon=True)
    thread.start()

    return jsonify({"job_id": job_id})


@app.route("/api/status/<job_id>")
def status(job_id):
    job = jobs.get(job_id)
    if not job:
        return jsonify({"error": "Job not found"}), 404
    if job["status"] == "done":
        return jsonify({"status": "done", "title": job["title"], "format": job["fmt"]})
    if job["status"] == "error":
        return jsonify({"status": "error", "error": job["error"]})
    return jsonify({"status": "processing"})


@app.route("/api/file/<job_id>")
def get_file(job_id):
    job = jobs.get(job_id)
    if not job or job["status"] != "done":
        return jsonify({"error": "File not ready"}), 404
    return send_file(
        job["path"],
        as_attachment=True,
        download_name=f"{job['title']}.{job['fmt']}"
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5008, debug=False)
