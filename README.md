# grab

A minimal self-hosted web tool for downloading audio from YouTube and other supported sites.

## Features

- Paste a URL and download audio in your preferred format
- Supports MP3, WAV, FLAC, M4A, and OGG
- Files auto-delete after 5 minutes
- Clean, minimal interface

## Supported Sites

Any site supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp) — including YouTube, SoundCloud, Bandcamp, Vimeo, and hundreds more.

## Stack

- **Backend**: Python / Flask
- **Downloader**: yt-dlp
- **Audio conversion**: ffmpeg
- **Container**: Docker

## Setup

### Prerequisites

- Docker
- A `cookies.txt` file exported from your browser while logged into YouTube (Netscape format)
- A residential proxy for YouTube on server IPs, configured with `YTDLP_PROXY`

### Running

```bash
git clone https://github.com/elaw142/Grab.git
cd Grab
# Optional local-only file: add cookies.txt to the project root
# Optional: copy .env.example to .env and set YTDLP_PROXY
docker compose up -d --build
```

The app runs on port `5008` by default.

### Caddy (reverse proxy)

```
grab.yourdomain.com {
    reverse_proxy grab:5008
}
```

## Cookie Maintenance

YouTube cookies expire periodically. To check if your cookies are still valid:

```bash
cp cookies.txt /tmp/grab-cookies-test.txt
yt-dlp --cookies /tmp/grab-cookies-test.txt --js-runtimes node --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Re-export cookies from your browser and replace `cookies.txt` on the server when they expire.

You can also refresh cookies directly from your local browser profile and upload them through GitHub Actions without committing them:

```powershell
.\scripts\update-youtube-cookies.ps1
```

Firefox is currently the default and most reliable local browser source on Windows. To choose a browser explicitly:

```powershell
.\scripts\update-youtube-cookies.ps1 -Browser firefox
```

Chrome may fail with DPAPI/App-Bound cookie decryption errors. If you use a cookie export extension instead, export cookies while you are on `youtube.com`, not `grab.emlw.dev`, then pass the file:

```powershell
.\scripts\update-youtube-cookies.ps1 -CookieFile "$env:USERPROFILE\Downloads\www.youtube.com_cookies.txt"
```

The script rejects empty, wrong-domain, anonymous, or signed-out YouTube cookie exports that only contain visitor cookies such as `PREF`, `SOCS`, `YSC`, or `VISITOR_INFO1_LIVE`; use a browser profile that is signed into YouTube.
It also runs a local `yt-dlp` check and rejects exports that YouTube reports as rotated or invalid. Full-browser exports are filtered down to YouTube cookies before upload.
To test an export or browser profile without uploading anything, add `-ValidateOnly`.

`cookies.txt` is intentionally ignored by Git. Production deploys read the `YOUTUBE_COOKIES_B64` GitHub Actions secret and write `cookies.txt` on the server during deployment.

To refresh `yt-dlp` inside the Docker image, rebuild without cache:

```bash
docker compose build --no-cache grab
docker compose up -d
```

## Proxy Configuration

`yt-dlp` proxy settings are controlled by the `YTDLP_PROXY` environment variable.

```bash
YTDLP_PROXY=http://username:password@proxy.example.com:8080
```

Leave `YTDLP_PROXY` empty for a direct connection. If you see `407 Proxy Authentication Required`, the proxy server rejected the configured username, password, host, or port. Update `.env` with valid proxy credentials, then rebuild/restart the container:

```bash
docker compose up -d --build
```

## Deployment

Pushes to `main` automatically deploy via GitHub Actions. The workflow SSHs into the server, pulls the latest code, and rebuilds the container.
