# commit_bug335_lock.ps1
# Purpose: Auto-complete BUG-339 (commit-pairing) once the concurrent agent
#          commits server.mbt containing publish_parallel_route (BUG-335 fix).
# Usage:   pwsh scripts/commit_bug335_lock.ps1
# Rules:   - DO NOT commit server.mbt (concurrent agent owns it).
#          - Only commits src/server/bug335_ns_route_wbtest.mbt (our lock).
#          - Safe to run repeatedly; idempotent (exits 0 if lock already committed).
#          - Pure ASCII (BUG-88: .ps1 must be ASCII or UTF-8 BOM for PS5.1).

param(
    # SkipStep: skip fmt+test (use only for dry e2e validation in a worktree
    # without .mooncakes). Production use must NOT pass -SkipTest.
    [switch]$SkipTest
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$lockFile = "src/server/bug335_ns_route_wbtest.mbt"
$serverFile = "src/server/server.mbt"
$lockFull = Join-Path $repoRoot $lockFile
$serverFull = Join-Path $repoRoot $serverFile

Write-Output "[bug335-lock] repoRoot = $repoRoot"

# --- Step 0: check preconditions -------------------------------------------
if (-not (Test-Path $lockFull)) {
    Write-Output "[bug335-lock] SKIP: lock file not found ($lockFull)"
    exit 0
}

# Is the lock already committed in HEAD?
$headHasLock = git -C $repoRoot show "HEAD:$lockFile" 2>$null
if ($LASTEXITCODE -eq 0 -and $headHasLock) {
    Write-Output "[bug335-lock] DONE: lock already in HEAD, nothing to do."
    exit 0
}

# --- Step 1: wait for concurrent agent to commit publish_parallel_route ---
$headHits = 0
$headServer = git -C $repoRoot show "HEAD:$serverFile" 2>$null
$headHits = ($headServer | Select-String "publish_parallel_route").Count

if ($headHits -eq 0) {
    Write-Output "[bug335-lock] WAITING: concurrent agent has NOT committed server.mbt yet."
    Write-Output "[bug335-lock] HEAD currently lacks 'publish_parallel_route' (hits=0)."
    Write-Output "[bug335-lock] Re-run this script after the concurrent agent commits."
    Write-Output "[bug335-lock] Current HEAD: $(git -C $repoRoot log --oneline -1)"
    exit 0
}

Write-Output "[bug335-lock] OK: HEAD has 'publish_parallel_route' (hits=$headHits). Proceeding."

if (-not $SkipTest) {
    # --- Step 2: format the lock file -------------------------------------
    Push-Location $repoRoot
    try {
        Write-Output "[bug335-lock] Running moon fmt on $lockFile ..."
        moon fmt $lockFile 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "moon fmt failed with exit $LASTEXITCODE"
        }
        Write-Output "[bug335-lock] fmt OK."
    } finally {
        Pop-Location
    }

    # --- Step 3: run src/server tests (expect 342 -> 345) -----------------
    Push-Location $repoRoot
    try {
        Write-Output "[bug335-lock] Running moon test --target js src/server ..."
        $env:DSH_FULL_JOB = "x"
        # Remove FIST_DB_PATH if set, it breaks worktree test runs
        Remove-Item Env:FIST_DB_PATH -ErrorAction SilentlyContinue
        $testOut = moon test --target js src/server 2>&1
        $testLine = ($testOut | Select-String "Total tests").Line
        Write-Output "[bug335-lock] $testLine"
        if ($testLine -notmatch "failed: 0") {
            throw "src/server tests NOT all green: $testLine"
        }
        Write-Output "[bug335-lock] src/server all green."
    } finally {
        Pop-Location
    }
} else {
    Write-Output "[bug335-lock] SKIPPING fmt+test (-SkipTest set). Only guard+commit will run."
}

# --- Step 4: commit ONLY the lock file ------------------------------------
Push-Location $repoRoot
try {
    # Guard: stage only our lock file. IMPORTANT: check ONLY the lock file against
    # the index (concurrent agent may have staged OTHER files; whole-index check
    # would falsely abort). `git commit <pathspec>` is --only semantics, so it
    # commits ONLY the lock file and never the concurrent agent's staged files.
    git add -- "$lockFile"
    $stagedLock = git diff --cached --name-only -- "$lockFile"
    if ($stagedLock -notcontains $lockFile) {
        git reset --quiet
        throw "Refusing: $lockFile not staged. Aborting (no commit made)."
    }
    # Content guard: lock must still contain our 3 BUG-335 markers. Detects
    # accidental pollution (e.g. concurrent agent overwrote the file).
    $lockContent = Get-Content $lockFull -Raw
    $hasFn = ($lockContent -match "publish_parallel_route")
    $testCount = ([regex]::Matches($lockContent, 'test "BUG-335')).Count
    if (-not $hasFn -or $testCount -lt 3) {
        git reset --quiet
        throw "Refusing: lock content lost BUG-335 markers (publish_parallel_route=$hasFn, tests=$testCount). Aborting (no commit made)."
    }
    $msg = "test(r33): 补提 BUG-335 配套回归锁 bug335_ns_route_wbtest.mbt (3 条白盒锁: publish_parallel_route 隔离 ns 收 default / 非隔离走独立库 / default空ns 恒 default)"
    git commit --only -m $msg -- "$lockFile" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed with exit $LASTEXITCODE"
    }
    Write-Output "[bug335-lock] COMMITTED: $lockFile"
    Write-Output "[bug335-lock] New HEAD: $(git log --oneline -1)"
    Write-Output "[bug335-lock] BUG-339 (commit-pairing) is now resolved."
} finally {
    Pop-Location
}