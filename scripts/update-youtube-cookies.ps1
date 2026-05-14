param(
    [string]$CookieFile = "$env:USERPROFILE\Downloads\www.youtube.com_cookies (1).txt",
    [string]$Repo = "elaw142/grab",
    [string]$Workflow = "deploy.yml",
    [string]$Browser = ""
)

$ErrorActionPreference = "Stop"

function Invoke-YtDlp {
    param([string[]]$Arguments)

    if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
        & yt-dlp @Arguments
    }
    else {
        & python -m yt_dlp @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp failed with exit code $LASTEXITCODE"
    }
}

if ($Browser) {
    $browserCookieFile = Join-Path ([IO.Path]::GetTempPath()) "grab-youtube-cookies-$([guid]::NewGuid()).txt"

    Invoke-YtDlp @(
        "--cookies-from-browser", $Browser,
        "--cookies", $browserCookieFile,
        "--skip-download",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    )

    $browserCookie = Get-Item -LiteralPath $browserCookieFile -ErrorAction SilentlyContinue
    if (!$browserCookie -or $browserCookie.Length -lt 100) {
        Remove-Item -LiteralPath $browserCookieFile -Force -ErrorAction SilentlyContinue
        throw "Browser cookie export did not produce a usable cookies file."
    }

    Move-Item -LiteralPath $browserCookieFile -Destination $CookieFile -Force
}

if (!(Test-Path -LiteralPath $CookieFile)) {
    throw "Cookie file not found: $CookieFile"
}

$tempFile = New-TemporaryFile

try {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($CookieFile)) |
        Set-Content -LiteralPath $tempFile -NoNewline -Encoding ascii

    Get-Content -Raw -LiteralPath $tempFile |
        gh secret set YOUTUBE_COOKIES_B64 --repo $Repo
    gh workflow run $Workflow --repo $Repo

    Write-Host "Updated YOUTUBE_COOKIES_B64 and triggered $Workflow for $Repo."
}
finally {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
}
