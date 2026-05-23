param(
    [string]$CookieFile = "",
    [string]$Repo = "elaw142/grab",
    [string]$Workflow = "deploy.yml",
    [string]$Browser = "firefox",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

function Invoke-YtDlp {
    param([string[]]$Arguments)

    $result = Invoke-YtDlpCapture -Arguments $Arguments
    $result.Output | ForEach-Object { Write-Output $_ }

    if ($result.ExitCode -ne 0) {
        throw "yt-dlp failed with exit code $($result.ExitCode)"
    }
}

function Invoke-YtDlpCapture {
    param([string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
            $output = & yt-dlp @Arguments 2>&1
        }
        else {
            $output = & python -m yt_dlp @Arguments 2>&1
        }

        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { $_.ToString() })
    }
}

function Test-CookieDataLine {
    param([string]$Line)

    $Line.Trim() -and (!$Line.StartsWith("#") -or $Line.StartsWith("#HttpOnly_"))
}

function Get-CookieDomain {
    param([string]$Domain)

    $Domain -replace '^#HttpOnly_', ''
}

function Get-CookieNames {
    param([string]$Path)

    foreach ($line in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))) {
        if (!(Test-CookieDataLine -Line $line)) {
            continue
        }

        $fields = $line.Split([char]9)
        if ($fields.Length -ge 7) {
            $fields[5]
        }
    }
}

function Test-YoutubeCookieDomain {
    param([string]$Domain)

    (Get-CookieDomain -Domain $Domain) -match '(^|\.)youtube\.com$'
}

function Get-CookieDomains {
    param([string]$Path)

    foreach ($line in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))) {
        if (!(Test-CookieDataLine -Line $line)) {
            continue
        }

        $fields = $line.Split([char]9)
        if ($fields.Length -ge 7) {
            Get-CookieDomain -Domain $fields[0]
        }
    }
}

function Copy-YoutubeCookies {
    param(
        [string]$Source,
        [string]$Destination
    )

    $cookieLines = @()
    foreach ($line in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Source))) {
        if (!(Test-CookieDataLine -Line $line)) {
            continue
        }

        $fields = $line.Split([char]9)
        if ($fields.Length -ge 7 -and (Test-YoutubeCookieDomain -Domain $fields[0])) {
            $cookieLines += $line
        }
    }

    @(
        "# Netscape HTTP Cookie File"
        "# This file was filtered by grab/scripts/update-youtube-cookies.ps1"
        ""
    ) + $cookieLines | Set-Content -LiteralPath $Destination -Encoding ascii
}

function Assert-YoutubeAuthCookies {
    param([string]$Path)

    $cookieNames = @(Get-CookieNames -Path $Path | Sort-Object -Unique)
    $domains = @(Get-CookieDomains -Path $Path | Sort-Object -Unique)
    $hasLoginInfo = $cookieNames -contains "LOGIN_INFO"
    $hasSessionCookie = @($cookieNames | Where-Object {
            $_ -in @("SID", "__Secure-1PSID", "__Secure-3PSID")
        }).Count -gt 0
    $hasApiCookie = @($cookieNames | Where-Object {
            $_ -in @("SAPISID", "APISID", "__Secure-1PAPISID", "__Secure-3PAPISID")
        }).Count -gt 0

    if (!$hasLoginInfo -or !$hasSessionCookie -or !$hasApiCookie) {
        $present = if ($cookieNames.Count) { $cookieNames -join ", " } else { "none" }
        $presentDomains = if ($domains.Count) { $domains -join ", " } else { "none" }
        throw "Cookie file does not look like a signed-in YouTube export. Make sure the browser/profile is logged into YouTube, then export again. Domains: $presentDomains. Cookie names: $present"
    }
}

function Assert-YoutubeAcceptsCookies {
    param([string]$Path)

    $validationCookieFile = New-TemporaryFile

    try {
        Copy-Item -LiteralPath $Path -Destination $validationCookieFile -Force
        $result = Invoke-YtDlpCapture -Arguments @(
            "--cookies", $validationCookieFile,
            "--ignore-no-formats-error",
            "--skip-download",
            "--no-playlist",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        $output = $result.Output -join "`n"
        if ($output -match "provided YouTube account cookies are no longer valid" -or
            $output -match "Sign in to confirm") {
            $result.Output | ForEach-Object { Write-Output $_ }
            throw "YouTube rejected these cookies. Re-export from a browser profile that is freshly signed into YouTube, then try again."
        }

        if ($result.ExitCode -ne 0) {
            $result.Output | ForEach-Object { Write-Output $_ }
            throw "yt-dlp could not validate these cookies. Check the output above, then try again."
        }
    }
    finally {
        Remove-Item -LiteralPath $validationCookieFile -Force -ErrorAction SilentlyContinue
    }
}

$cookieFileProvided = $PSBoundParameters.ContainsKey("CookieFile") -and $CookieFile
$browserProvided = $PSBoundParameters.ContainsKey("Browser")
$useBrowserExport = $Browser -and (!$cookieFileProvided -or $browserProvided)
$deleteCookieFile = $false

if ($useBrowserExport) {
    if (!$CookieFile) {
        $CookieFile = Join-Path ([IO.Path]::GetTempPath()) "grab-youtube-cookies-$([guid]::NewGuid()).txt"
        $deleteCookieFile = $true
    }

    Invoke-YtDlp @(
        "--cookies-from-browser", $Browser,
        "--cookies", $CookieFile,
        "--skip-download",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    )

    $browserCookie = Get-Item -LiteralPath $CookieFile -ErrorAction SilentlyContinue
    if (!$browserCookie -or $browserCookie.Length -lt 100) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
        throw "Browser cookie export did not produce a usable cookies file."
    }
}

if (!(Test-Path -LiteralPath $CookieFile)) {
    throw "Cookie file not found: $CookieFile. To export directly from your browser, run .\scripts\update-youtube-cookies.ps1 -Browser firefox"
}

$uploadCookieFile = New-TemporaryFile
Copy-YoutubeCookies -Source $CookieFile -Destination $uploadCookieFile
Assert-YoutubeAuthCookies -Path $uploadCookieFile
Assert-YoutubeAcceptsCookies -Path $uploadCookieFile

if ($ValidateOnly) {
    Write-Host "Cookie validation passed. Nothing uploaded because -ValidateOnly was set."
    Remove-Item -LiteralPath $uploadCookieFile -Force -ErrorAction SilentlyContinue
    if ($deleteCookieFile) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
    }
    return
}

$tempFile = New-TemporaryFile

try {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($uploadCookieFile)) |
        Set-Content -LiteralPath $tempFile -NoNewline -Encoding ascii

    Get-Content -Raw -LiteralPath $tempFile |
        gh secret set YOUTUBE_COOKIES_B64 --repo $Repo
    gh workflow run $Workflow --repo $Repo

    Write-Host "Updated YOUTUBE_COOKIES_B64 and triggered $Workflow for $Repo."
}
finally {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $uploadCookieFile -Force -ErrorAction SilentlyContinue
    if ($deleteCookieFile) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
    }
}
