FROM denoland/deno:bin-2.5.6 AS deno

FROM python:3.11-slim

COPY --from=deno /deno /usr/local/bin/deno

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1 \
    YTDLP_JS_RUNTIME=deno:/usr/local/bin/deno

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5008/', timeout=3)"

CMD ["python", "app.py"]
