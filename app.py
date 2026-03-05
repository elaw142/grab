from flask import Flask, request, jsonify, send_file, render_template
import yt_dlp
import os
import uuid
import threading
import time

app = Flask(__name__)

DOWNLOAD_DIR = "/tmp/grab"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

jobs = {}

FORMATS = ["mp3", "wav", "flac", "m4a", "ogg"]


def cleanup_file(path, delay=300):
    def delete():
        time.sleep(delay)
        if os.path.exists(path):
            os.remove(path)
    threading.Thread(target=delete, daemon=True).start()


def do_download(job_id, url, fmt):
    job = jobs[job_id]
    output_path = os.path.join(DOWNLOAD_DIR, job_id)

    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": output_path + ".%(ext)s",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": fmt,
        }],
        "quiet": True,
        "no_warnings": True,
        "cookiefile": "/app/cookies.txt",
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            title = info.get("title", "audio")

        final_path = output_path + f".{fmt}"
        job["status"] = "done"
        job["path"] = final_path
        job["title"] = title
        job["fmt"] = fmt
        cleanup_file(final_path)
    except Exception as e:
        job["status"] = "error"
        job["error"] = str(e)


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
