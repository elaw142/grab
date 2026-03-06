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
- A residential proxy (required for YouTube on server IPs)

### Running

```bash
git clone https://github.com/elaw142/Grab.git
cd Grab
# Add your cookies.txt to the project root
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
yt-dlp --cookies cookies.txt --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Re-export cookies from your browser and replace `cookies.txt` on the server when they expire.

## Deployment

Pushes to `main` automatically deploy via GitHub Actions. The workflow SSHs into the server, pulls the latest code, and rebuilds the container.
