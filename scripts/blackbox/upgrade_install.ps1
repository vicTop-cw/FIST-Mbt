# scripts/blackbox/upgrade_install.ps1 -- upgrade-time installer (tracked source of truth)
#
# Fetched and run by `fist upgrade` (cmd/cli/upgrade_js.mbt: fetch_installer -> run_installer).
# Same fetch discipline as scripts/blackbox/install_onecmd.ps1 (R6 PK magic / R12 retry only
# transport-layer errors / R7 no-false-green self-check), but this is the upgrade path:
# it installs into $LOCALAPPDATA\FIST-Mbt (where `fist upgrade` keeps read_local / backup /
# rollback state) and a -Force clean MUST preserve fist-mbt.js.bak-* backups
# (BUG-235: wiping them leaves rollback with nothing to restore).
#
# Zip sources (identical shape to the irm installer):
#   1. https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v$Version/fist-mbt-js-v$Version.zip
#   2. https://github.com/vicTop-cw/FIST-Mbt/releases/download/v$Version/fist-mbt-js-v$Version.zip
#   -BaseUrl mirrors use <BaseUrl>/-/releases/download/v$Version/fist-mbt-js-v$Version.zip
#
# Usage:
#   pwsh upgrade_install.ps1 -Version <x.y.z> [-BaseUrl <mirror>] [-Force] [-NoPath]

param(
  # R1: no hard-coded default version. `fist upgrade` always passes -Version resolved
  # from the latest release; an empty Version prints usage and exits 1.
  [string]$Version = "",
  [string]$BaseUrl = "",
  [switch]$Force,
  [switch]$NoPath
)

$ErrorActionPreference = "Stop"

# R7: native commands must be wrapped. Under EAP=Stop a native command's stderr
# becomes a terminating error once redirected (BUG-109), and the real fist-mbt.js
# prints ExperimentalWarning (node:sqlite) on every start. Lower EAP for the call
# and drop stderr; keep only the stdout receipt. No empty catch anywhere.
function Invoke-NativeQuiet {
  param([string]$Exe, [string[]]$ExeArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { $out = (& $Exe @ExeArgs 2>$null | Out-String) } finally { $ErrorActionPreference = $prevEap }
  return $out.Trim()
}

if ($Version -eq "") {
  Write-Host "ERROR: -Version is required (no hard-coded default, R1)." -ForegroundColor Red
  Write-Host "usage: pwsh upgrade_install.ps1 -Version <x.y.z> [-BaseUrl <mirror>] [-Force] [-NoPath]"
  exit 1
}

$InstallRoot = Join-Path $env:LOCALAPPDATA "FIST-Mbt"
$ZipName     = "fist-mbt-js-v$Version.zip"
$urls = @(
  "https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v$Version/$ZipName",
  "https://github.com/vicTop-cw/FIST-Mbt/releases/download/v$Version/$ZipName"
)
if ($BaseUrl -ne "") {
  $urls = @($BaseUrl.TrimEnd('/') + "/-/releases/download/v$Version/$ZipName")
}

Write-Host "=== FIST-Mbt upgrade install v$Version ===" -ForegroundColor Cyan
Write-Host "Target: $InstallRoot"

if ((Test-Path $InstallRoot) -and -not $Force) {
  Write-Host "Already installed at $InstallRoot. Use -Force to reinstall." -ForegroundColor Yellow
  exit 0
}

Write-Host "[1/4] Downloading $ZipName ..." -ForegroundColor Cyan
$Tmp = Join-Path $env:TEMP ("fist-upgrade-" + [guid]::NewGuid().ToString("N") + ".zip")
$downloaded = $false
foreach ($u in $urls) {
  Write-Host "  try: $u" -ForegroundColor DarkGray
  # R12: retry ONLY transport-layer failures (no HTTP response) with backoff (2s/4s).
  # 404/403 (have a response) and non-PK / HTML content are deterministic conclusions:
  # switch source immediately, no retry.
  for ($try = 1; $try -le 3; $try++) {
    $retry = $false
    try {
      Invoke-WebRequest -Uri $u -OutFile $Tmp -UseBasicParsing -TimeoutSec 60
      # R6: HTTP 200 does not mean we got the file. A real zip starts with PK (0x50 0x4B);
      # mirrors can answer 200 + a whole HTML page. Check shape, not status code.
      $bytes = [IO.File]::ReadAllBytes($Tmp)
      if ($bytes.Length -lt 2) {
        Write-Host "  . source returned an empty body (unusable)" -ForegroundColor DarkGray
        Remove-Item $Tmp -Force -ErrorAction SilentlyContinue
        break
      }
      $head = [Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min($bytes.Length, 256) - 1)])
      if ($head -match '^\s*<(!DOCTYPE|html)') {
        Write-Host "  . source returned an HTML page, not a file (source unusable)" -ForegroundColor DarkGray
        Remove-Item $Tmp -Force -ErrorAction SilentlyContinue
        break
      }
      if ($bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
        Write-Host ("  . not a zip (first two bytes " + [BitConverter]::ToString($bytes[0..1]) + ")") -ForegroundColor DarkGray
        Remove-Item $Tmp -Force -ErrorAction SilentlyContinue
        break
      }
      Write-Host ("  ok downloaded (" + [math]::Round($bytes.Length/1KB,1) + " KB)") -ForegroundColor Green
      $downloaded = $true
      break
    } catch {
      $resp = $_.Exception.Response
      $code = if ($resp) { [int]$resp.StatusCode } else { "n/a(transport)" }
      $why = ($_.Exception.Message -replace '\s+', ' ')
      Write-Host ("  ! attempt $try failed HTTP " + $code + " " + $why) -ForegroundColor Yellow
      if ($resp) { break }   # deterministic conclusion -> switch source
      if ($try -lt 3) { $retry = $true }
    }
    if ($retry) { Start-Sleep -Seconds (2 * $try) } else { break }
  }
  if ($downloaded) { break }
}
if (-not $downloaded) {
  Write-Host "ERROR: download failed from all sources (each status above)." -ForegroundColor Red
  Remove-Item $Tmp -Force -ErrorAction SilentlyContinue
  exit 1
}

Write-Host "[2/4] Installing to $InstallRoot ..." -ForegroundColor Cyan
if (Test-Path $InstallRoot) {
  # BUG-235: a -Force clean MUST keep fist-mbt.js.bak-* backups. `fist upgrade` writes
  # the pre-upgrade backup into $InstallRoot right before running this script; wiping
  # the whole directory would leave rollback with nothing to restore.
  Get-ChildItem -LiteralPath $InstallRoot -Force |
    Where-Object { $_.Name -notlike 'fist-mbt.js.bak-*' } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Expand-Archive -Path $Tmp -DestinationPath $InstallRoot -Force
Remove-Item $Tmp -Force -ErrorAction SilentlyContinue

# ESM shim (idempotent): only patch when the raw artifact does not run as-is.
# (Wrapped per R7: a bare `node ... 2>$null` under EAP=Stop would turn the
# ExperimentalWarning on stderr into a terminating error mid-install.)
$helpOut = Invoke-NativeQuiet -Exe "node" -ExeArgs @((Join-Path $InstallRoot "fist-mbt.js"), "help")
if (-not $helpOut) {
  Write-Host "[patch] ESM shim ..."
  $patchPy = Join-Path $InstallRoot "patch_esm_main.py"
  if (Test-Path $patchPy) {
    $null = Invoke-NativeQuiet -Exe "python" -ExeArgs @($patchPy, (Join-Path $InstallRoot "fist-mbt.js"))
  }
}

# R7: the self-check must not report a false green. Success is claimed ONLY on a
# real version receipt from `node fist-mbt.js version` (exit code alone is not a
# receipt), run with EAP temporarily lowered and stderr dropped (BUG-109 shape:
# under EAP=Stop, redirected native stderr becomes a terminating error, and the
# real artifact prints ExperimentalWarning on every start).
Write-Host "[3/4] Self-check: node fist-mbt.js version ..." -ForegroundColor Cyan
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $verOut = (& node (Join-Path $InstallRoot "fist-mbt.js") version 2>$null | Out-String).Trim()
} finally {
  $ErrorActionPreference = $prevEap
}
if ($LASTEXITCODE -ne 0 -or -not $verOut) {
  Write-Host "ERROR: self-check failed -- no real version receipt from fist-mbt.js. VERSION NOT written." -ForegroundColor Red
  exit 1
}
Write-Host "  ok self-check receipt: $verOut" -ForegroundColor Green

Write-Host "[4/4] Shim + PATH ..." -ForegroundColor Cyan
$cmdContent = "@echo off`r`nnode `"$InstallRoot\fist-mbt.js`" %*`r`n"
Set-Content -Path (Join-Path $InstallRoot "fist.cmd") -Value $cmdContent -Encoding ASCII

if (-not $NoPath) {
  $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($UserPath -notlike "*$InstallRoot*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallRoot", "User")
    $env:Path += ";$InstallRoot"
  }
}

# VERSION is written ONLY after the self-check passed (R7: no false green).
Set-Content -Path (Join-Path $InstallRoot "VERSION") -Value $Version -Encoding ASCII

Write-Host ""
Write-Host "=== Done! v$Version installed. VERSION = $Version ===" -ForegroundColor Green
