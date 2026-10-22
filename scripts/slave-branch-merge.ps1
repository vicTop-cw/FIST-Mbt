# scripts/slave-branch-merge.ps1
# 一键合并 gitcode/slave/* 分支的新代码 commits 到 master，并清理已合并分支
# 用法: pwsh scripts/slave-branch-merge.ps1
# 流程: fetch → 扫描哪些分支有 src/scripts/cmd/moon.pkg 改动 → 逐个 cherry-pick → 清冲突标记 → build → push → 删已合并分支

param(
  [switch]$DryRun  # 只扫描不执行
)

# ── TASK-002：cherry-pick 黑名单（实测教训）──────────────────────────────
# 旧 commit 里的 `src/ops/moon.pkg` 与 HEAD 版本不同且常自带冲突标记；cherry-pick e1b1a9d3 时
# 正是它把 `moon build` 打成 [3002] lexing error。`src/ops/rhop_poll.mbt` 更毒：HEAD 已有
# `rhop_native.mbt` 完整实现，旧 commit 再带一份同名函数 `rhop_poll` ⇒ 重复定义直接崩构建。
# 处置：这些路径在每次 cherry-pick 后**一律回退到 HEAD 版本**（不是"取 theirs"，是"根本不收"）；
# `rhop*.mbt` 若以新增文件形式出现 ⇒ 文件 + 索引一起删，并打印警告留痕。
$SKIP_EXACT = @('src/ops/moon.pkg', 'src/ops/rhop_poll.mbt')
$SKIP_GLOB  = @('src/ops/rhop*.mbt')

function Restore-Blacklisted {
  param([string]$why)
  $touched = 0
  foreach ($f in $SKIP_EXACT) {
    git cat-file -e "HEAD:$f" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $staged = git diff --cached --name-only -- $f 2>$null
    if ($staged) {
      git checkout HEAD -- $f 2>$null
      Write-Host "      🚫 黑名单回退 HEAD: $f" -ForegroundColor DarkYellow
      $touched++
    }
  }
  foreach ($pat in $SKIP_GLOB) {
    $hits = git diff --cached --name-only -- $pat 2>$null
    foreach ($h in $hits) {
      if (-not $h) { continue }
      git cat-file -e "HEAD:$h" 2>$null
      if ($LASTEXITCODE -ne 0) {
        if (Test-Path $h) { Remove-Item -Force $h }
        git rm --cached --ignore-unmatch $h 2>$null | Out-Null
        Write-Host "      🚫 黑名单删除（新引入）: $h" -ForegroundColor DarkYellow
        $touched++
      } else {
        git checkout HEAD -- $h 2>$null
        Write-Host "      🚫 黑名单回退 HEAD: $h" -ForegroundColor DarkYellow
        $touched++
      }
    }
  }
  return $touched
}

$ErrorActionPreference = "Stop"

Write-Host "=== FIST-Mbt Slave Branch Merger ===" -ForegroundColor Cyan
Write-Host ""

# 0. 备份当前 HEAD
$before = git rev-parse HEAD 2>$null
Write-Host "当前 HEAD: $before" -ForegroundColor Gray

# 1. Fetch
Write-Host "`n[1/6] Fetch 所有远端..." -ForegroundColor Yellow
git fetch --all --prune 2>&1 | Out-Null

# 2. 扫描 slave 分支
Write-Host "`n[2/6] 扫描 gitcode/slave/* 分支..." -ForegroundColor Yellow
$slaves = git branch -r 2>$null | Select-String 'gitcode/slave/' | ForEach-Object { $_.Line.Trim() }
Write-Host "  发现 $($slaves.Count) 个 slave 分支" -ForegroundColor Gray

# 3. 筛选：哪些有 src/scripts/cmd/moon.pkg 改动且不在 HEAD 里
Write-Host "`n[3/6] 筛选有代码改动的分支..." -ForegroundColor Yellow
$codeBranches = @()
$docBranches = @()

foreach ($slave in $slaves) {
  $unique = git rev-list "HEAD..$slave" 2>$null
  if (-not $unique -or ($unique | Measure-Object).Count -eq 0) {
    $docBranches += $slave  # 完全在 HEAD 里
    continue
  }
  
  $hasCode = $false
  foreach ($c in $unique) {
    $files = git diff-tree --no-commit-id --name-only -r $c 2>$null
    if ($files -match '^(src/|scripts/|cmd/|moon\.pkg$)') {
      $hasCode = $true; break
    }
  }
  
  if ($hasCode) { $codeBranches += $slave } else { $docBranches += $slave }
}

Write-Host "  有代码改动: $($codeBranches.Count) 个" -ForegroundColor Green
Write-Host "  纯流水账:   $($docBranches.Count) 个" -ForegroundColor Gray
foreach ($b in $codeBranches) { Write-Host "    🔴 $b" }
foreach ($b in $docBranches) { Write-Host "    ⚪ $b" }

if ($DryRun) {
  Write-Host "`n[DRY-RUN] 退出。使用 -NoDryRun 执行合并。" -ForegroundColor Cyan
  return
}

if ($codeBranches.Count -eq 0) {
  Write-Host "`n✅ 没有新代码需要合并。" -ForegroundColor Green
}

# 4. 逐个 pick
Write-Host "`n[4/6] Cherry-pick 代码 commits..." -ForegroundColor Yellow
$pickCount = 0
$skipCount = 0

foreach ($slave in $codeBranches) {
  Write-Host "`n  --- $slave ---" -ForegroundColor Magenta
  
  # 按时间顺序 pick unique commits
  $unique = git rev-list --reverse "HEAD..$slave" 2>$null
  foreach ($c in $unique) {
    $msg = git log -1 --format="%s" $c 2>$null
    $files = git diff-tree --no-commit-id --name-only -r $c 2>$null
    $hasCode = $files -match '^(src/|scripts/|cmd/|moon\.pkg$)'
    
    if (-not $hasCode) { $skipCount++; continue }
    
    $shortHash = $c.Substring(0,7)
    Write-Host "    Pick $shortHash : $msg" -ForegroundColor White
    
    git cherry-pick --no-commit $c 2>&1 | Out-Null
    $cpRc = $LASTEXITCODE
    # TASK-002：无论成败先摘掉黑名单路径（冲突状态下它们最脏）
    $null = Restore-Blacklisted "cherry-pick $shortHash"
    if ($cpRc -ne 0) {
      # 冲突：memory/reports/plugins/docs 取 theirs，其他留着
      $conflicts = git diff --name-only --diff-filter=U 2>$null
      foreach ($f in $conflicts) {
        if ($f -match '^(memory/|reports/|plugins/|docs/)') {
          git checkout --theirs $f 2>$null
          Write-Host "      theirs: $f" -ForegroundColor Gray
        }
      }
      git add -A 2>$null
    }
    
    # TASK-001③：commit 之前先跑冲突标记判据（live），红则**不许提交**——
    # 这正是 259b56a8 的形状：标记进跟踪面后，CI 只能是事后才可能知道。
    $markerOut = python scripts/blackbox/check_merge_markers.py 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "      ❌ 冲突标记判据红，拒绝提交本笔" -ForegroundColor Red
      Write-Host ($markerOut | Select-Object -Last 1)
      git reset --hard HEAD 2>&1 | Out-Null
      $skipCount++
      continue
    }
    git commit -m "$msg (from $shortHash)" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $pickCount++ }
  }
}

Write-Host "`n  Picked: $pickCount commits, Skipped (no code): $skipCount" -ForegroundColor Green

# 5. 循环清冲突标记（最多 10 轮）
Write-Host "`n[5/6] 清理残留冲突标记..." -ForegroundColor Yellow
for ($round = 1; $round -le 10; $round++) {
  $totalFixed = 0
  # 只扫 git 跟踪的 src/ + cmd/ 目录，跳过 _build/ temp/ 缓存
  $srcFiles = git ls-files 'src/**/*.mbt' 'cmd/**/*.mbt' 2>$null
  foreach ($path in $srcFiles) {
    if (-not (Test-Path $path)) { continue }
    $raw = [System.IO.File]::ReadAllText($path)
    if (-not $raw.Contains('<<<<<<<')) { continue }
    $lines = [System.IO.File]::ReadAllLines($path)
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0; $takeTheirs = $false
    foreach ($line in $lines) {
      if ($line.StartsWith('<<<<<<<')) { $depth++; if ($depth -eq 1) { $takeTheirs = $false }; continue }
      if ($line.StartsWith('=======') -and $depth -eq 1) { $takeTheirs = $true; continue }
      if ($line.StartsWith('>>>>>>>')) { $depth--; if ($depth -eq 0) { $takeTheirs = $false; $totalFixed++ }; continue }
      if ($takeTheirs -or $depth -eq 0) { $out.Add($line) }
    }
    [System.IO.File]::WriteAllLines($path, $out)
  }
  # 也扫 moon.pkg
  $pkgFiles = git ls-files '**/moon.pkg' 2>$null
  foreach ($path in $pkgFiles) {
    if (-not (Test-Path $path)) { continue }
    $raw = [System.IO.File]::ReadAllText($path)
    if (-not $raw.Contains('<<<<<<<')) { continue }
    $lines = [System.IO.File]::ReadAllLines($path)
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0; $takeTheirs = $false
    foreach ($line in $lines) {
      if ($line.StartsWith('<<<<<<<')) { $depth++; if ($depth -eq 1) { $takeTheirs = $false }; continue }
      if ($line.StartsWith('=======') -and $depth -eq 1) { $takeTheirs = $true; continue }
      if ($line.StartsWith('>>>>>>>')) { $depth--; if ($depth -eq 0) { $takeTheirs = $false; $totalFixed++ }; continue }
      if ($takeTheirs -or $depth -eq 0) { $out.Add($line) }
    }
    [System.IO.File]::WriteAllLines($path, $out)
  }
  if ($round -eq 1) { Write-Host "  Round $round : $totalFixed blocks" }
  if ($totalFixed -eq 0 -and $round -gt 1) { break }
}

# moon.pkg 也扫
Get-ChildItem -Path . -Filter 'moon.pkg' -Recurse | ForEach-Object {
  $path = $_.FullName
  $raw = [System.IO.File]::ReadAllText($path)
  if (-not $raw.Contains('<<<<<<<')) { return }
  Write-Host "  ⚠️ $path 还有冲突标记！手动处理" -ForegroundColor Red
}

# 6. Build 验证
Write-Host "`n[6/6] Build 验证..." -ForegroundColor Yellow
# TASK-001③：整批 pick 完先自证判据（--selftest）再 live 扫全跟踪面
$selfOut = python scripts/blackbox/check_merge_markers.py --selftest 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ❌ 冲突标记判据自检失败（尺子本身坏了，拒绝继续）" -ForegroundColor Red
  return
}
$allOut = python scripts/blackbox/check_merge_markers.py 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ❌ 跟踪面仍有冲突标记，停止（不许 build/push）" -ForegroundColor Red
  Write-Host ($allOut | Select-Object -Last 5)
  return
}
Write-Host "  ✅ 冲突标记判据：selftest + live 全绿" -ForegroundColor Green

moon fmt 2>&1 | Out-Null
$buildOut = moon build --target js src/server src/engine src/store src/router src/ops 2>&1
$hasError = $buildOut -match 'Error:' -and $buildOut -notmatch 'Finished.*0 errors'

if ($hasError) {
  Write-Host "  ❌ BUILD FAILED — 检查冲突标记是否全清" -ForegroundColor Red
  Write-Host $buildOut | Select-String 'Error:' -Context 0,4 | Select-Object -First 10
  Write-Host "  需要手动修复后再 push。脚本退出。" -ForegroundColor Red
  return
} else {
  Write-Host "  ✅ Build passed!" -ForegroundColor Green
}

# 7. Commit 冲突清理 + Push
Write-Host "`nCommit 冲突清理..." -ForegroundColor Yellow
git add -A 2>$null
$hasUncommitted = $true
try { git diff --cached --quiet 2>$null; if ($LASTEXITCODE -eq 0) { $hasUncommitted = $false } } catch { }
if ($hasUncommitted) {
  git commit -m "chore: 清理 slave branch merge 残留冲突标记" 2>&1 | Out-Null
}

Write-Host "Push 所有远端..." -ForegroundColor Yellow
git push gitcode HEAD:main HEAD:master 2>&1 | Select-Object -Last 2
git push origin HEAD:main HEAD:master 2>&1 | Select-Object -Last 2

# 8. 删除已完全包含的 slave 分支
Write-Host "`n清理已合并分支..." -ForegroundColor Yellow
git fetch --all --prune 2>&1 | Out-Null
$allSlaves = git branch -r 2>$null | Select-String 'gitcode/slave/' | ForEach-Object { $_.Line.Trim() }
$toDelete = @()
foreach ($slave in $allSlaves) {
  $slaveHead = git rev-parse $slave 2>$null
  $mb = git merge-base HEAD $slave 2>$null
  if ($mb -eq $slaveHead) {
    $toDelete += $slave
  } else {
    # 也按 message 匹配
    $headMsg = git log -1 --format="%s" $slave 2>$null
    $headMessages = git log --format="%s" HEAD 2>$null
    if ($headMessages -contains $headMsg) { $toDelete += $slave }
  }
}

Write-Host "  将删除 $($toDelete.Count) 个分支:" -ForegroundColor Gray
foreach ($b in $toDelete) { Write-Host "    🗑️ $b" }
foreach ($b in $toDelete) {
  $name = $b -replace '^gitcode/', ''
  git push gitcode --delete $name 2>&1 | Out-Null
}

git fetch --all --prune 2>&1 | Out-Null
$remaining = git branch -r 2>$null | Select-String 'gitcode/slave/' | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "`n========== 完成 ==========" -ForegroundColor Cyan
Write-Host "  HEAD: $(git rev-parse HEAD | Select-Object -First 8)"
Write-Host "  新 picked: $pickCount commits"
Write-Host "  剩余 slave 分支: $remaining"
Write-Host ""
