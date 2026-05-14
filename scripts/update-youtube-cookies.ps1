param(
    [string]$CookieFile = "$env:USERPROFILE\Downloads\www.youtube.com_cookies (1).txt",
    [string]$Repo = "elaw142/grab",
    [string]$Workflow = "deploy.yml",
    [string]$Browser = ""
)

$ErrorActionPreference = "Stop"

if ($Browser) {
    yt-dlp --cookies-from-browser $Browser --cookies $CookieFile --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
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
