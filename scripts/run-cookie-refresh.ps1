param(
    [Parameter(Mandatory)][ValidateSet("youtube", "instagram")][string]$Site,
    [string]$Browser = "firefox"
)

$grabDir = Join-Path $env:LOCALAPPDATA "Grab"
$log = Join-Path $grabDir "cookie-refresh-$Site.log"
$topicFile = Join-Path $grabDir "ntfy-topic.txt"
$script = Join-Path $PSScriptRoot "update-$Site-cookies.ps1"

New-Item -ItemType Directory -Force $grabDir | Out-Null

$failed = $false
try {
    & $script -Browser $Browser *> $log
    if (!$?) { $failed = $true }
}
catch {
    $failed = $true
    "ERROR: $_" | Add-Content -LiteralPath $log
}

$reason = Get-Content -LiteralPath $log |
    Where-Object { $_ -match 'ERROR|does not look|rejected|HTTP \d{3}' -and $_ -notmatch 'yt-dlp version' } |
    Select-Object -First 1

# GitHub silently disables scheduled workflows after 60 days without repo activity.
$disabled = @(gh workflow list --repo elaw142/grab --all --json path,state 2>$null |
    ConvertFrom-Json | Where-Object { $_.state -ne 'active' } | ForEach-Object { Split-Path -Leaf $_.path })

"Finished $(Get-Date -Format s) failed=$failed disabled=$($disabled -join ',')" | Add-Content -LiteralPath $log

$messages = @()
if ($failed) {
    if (!$reason) { $reason = "See $log" }
    if ($reason.Length -gt 300) { $reason = $reason.Substring(0, 300) }
    $messages += "$Site cookie refresh failed: $reason"
}
if ($disabled) {
    $messages += "GitHub workflows disabled: $($disabled -join ', '). Run: gh workflow enable <name> --repo elaw142/grab"
}

if ($messages -and (Test-Path $topicFile)) {
    $topic = (Get-Content -Raw $topicFile).Trim()
    # Built from the code point so the emoji survives Windows PowerShell's ANSI script decoding.
    $warning = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $body = [Text.Encoding]::UTF8.GetBytes("$warning " + ($messages -join "`n$warning "))
    Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$topic" `
        -Headers @{ Title = "grab"; Priority = "high" } `
        -ContentType "text/plain; charset=utf-8" -Body $body | Out-Null
}

if ($failed) { exit 1 }
