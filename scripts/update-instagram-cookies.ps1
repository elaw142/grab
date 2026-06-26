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

function Test-InstagramCookieDomain {
    param([string]$Domain)

    (Get-CookieDomain -Domain $Domain) -match '(^|\.)instagram\.com$'
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

function Copy-InstagramCookies {
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
        if ($fields.Length -ge 7 -and (Test-InstagramCookieDomain -Domain $fields[0])) {
            $cookieLines += $line
        }
    }

    @(
        "# Netscape HTTP Cookie File"
        "# This file was filtered by grab/scripts/update-instagram-cookies.ps1"
        ""
    ) + $cookieLines | Set-Content -LiteralPath $Destination -Encoding ascii
}

function Assert-InstagramAuthCookies {
    param([string]$Path)

    $cookieNames = @(Get-CookieNames -Path $Path | Sort-Object -Unique)
    $domains = @(Get-CookieDomains -Path $Path | Sort-Object -Unique)
    $hasSessionId = $cookieNames -contains "sessionid"
    $hasUserId = $cookieNames -contains "ds_user_id"

    if (!$hasSessionId -or !$hasUserId) {
        $present = if ($cookieNames.Count) { $cookieNames -join ", " } else { "none" }
        $presentDomains = if ($domains.Count) { $domains -join ", " } else { "none" }
        throw "Cookie file does not look like a signed-in Instagram export. Make sure the browser/profile is logged into Instagram, then export again. Domains: $presentDomains. Cookie names: $present"
    }
}

$cookieFileProvided = $PSBoundParameters.ContainsKey("CookieFile") -and $CookieFile
$browserProvided = $PSBoundParameters.ContainsKey("Browser")
$useBrowserExport = $Browser -and (!$cookieFileProvided -or $browserProvided)
$deleteCookieFile = $false

if ($useBrowserExport) {
    if (!$CookieFile) {
        $CookieFile = Join-Path ([IO.Path]::GetTempPath()) "grab-instagram-cookies-$([guid]::NewGuid()).txt"
        $deleteCookieFile = $true
    }

    Invoke-YtDlp @(
        "--cookies-from-browser", $Browser,
        "--cookies", $CookieFile,
        "--ignore-no-formats-error",
        "--skip-download",
        "--no-playlist",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    )

    $browserCookie = Get-Item -LiteralPath $CookieFile -ErrorAction SilentlyContinue
    if (!$browserCookie -or $browserCookie.Length -lt 100) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
        throw "Browser cookie export did not produce a usable cookies file."
    }
}

if (!(Test-Path -LiteralPath $CookieFile)) {
    throw "Cookie file not found: $CookieFile. To export directly from your browser, run .\scripts\update-instagram-cookies.ps1 -Browser firefox"
}

$uploadCookieFile = New-TemporaryFile
Copy-InstagramCookies -Source $CookieFile -Destination $uploadCookieFile
Assert-InstagramAuthCookies -Path $uploadCookieFile

if ($ValidateOnly) {
    Write-Host "Cookie validation passed. Nothing uploaded because -ValidateOnly was set."
    Remove-Item -LiteralPath $uploadCookieFile -Force -ErrorAction SilentlyContinue
    if ($deleteCookieFile) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
    }
    return
}

try {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($uploadCookieFile))
    gh secret set INSTAGRAM_COOKIES_B64 --repo $Repo --body $b64
    gh workflow run $Workflow --repo $Repo

    Write-Host "Updated INSTAGRAM_COOKIES_B64 and triggered $Workflow for $Repo."
}
finally {
    Remove-Item -LiteralPath $uploadCookieFile -Force -ErrorAction SilentlyContinue
    if ($deleteCookieFile) {
        Remove-Item -LiteralPath $CookieFile -Force -ErrorAction SilentlyContinue
    }
}
