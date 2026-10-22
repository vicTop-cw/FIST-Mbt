# scripts/slave-branch-merge.ps1
# 一键合并 gitcode/slave/* 分支的新代码 commits 到 master，并清理已合并分支
# 用法: pwsh scripts/slave-branch-merge.ps1
# 流程: fetch → 扫描哪些分支有 src/scripts/cmd/moon.pkg 改动 → 逐个 cherry-pick → 清冲突标记 → build → push → 删已合并分支

param(
  [switch]$DryRun,   # 只扫描不执行
  [switch]$SelfTest  # R100：只跑沙箱自证格，不合并、不 fetch、不 push
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

# ── R100：黑名单自证面（-SelfTest）──────────────────────────────────────
# 为什么要这一档：TASK-002 的黑名单是「把毒路径摘出跟踪面」的唯一执行面，入仓以来没有任何
# 一格能证明它摘得动。R97 实踩的代价是 `moon build` 当场 [3002] lexing error——也就是说
# 「黑名单失明」的发现成本是一整次构建崩溃，而不是一行 FAIL。尺子必须先证明自己会红。
# 本档在 %TEMP% 的沙箱 git 仓里跑：逐格造违例 → 调 Restore-Blacklisted → 断言盘面与索引。
# 绝不 cd 进真仓、绝不读改任何跟踪文件、绝不起网络。沙箱跑完即删。
# 退出码三档（本仓契约）：0 全绿 / 1 判据红 / 2 尺子无法自证（git 缺失或沙箱建不起来，绝不冒用 1）。
# M1/M2 是变异台：把名单改瞎 ⇒ 对应格必须转红，否则说明 C1/C3 的断言是幻影。

function Invoke-STGit {
  # 原生命令一律走这里：EAP 在函数作用域内降到 Continue——Stop 下 git 的 stderr 会变成终止错误
  # （BUG-109 那一格），那样「git 打了句警告」就能被读成「判据红」。断言只看盘面，不看异常。
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $ErrorActionPreference = "Continue"
  $out = & git @GitArgs 2>&1
  $rc = $LASTEXITCODE
  $text = ($out | Out-String)
  return [pscustomobject]@{ Rc = $rc; Out = $text }
}

function Write-STFile {
  param([string]$Rel, [string]$Text)
  $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $Rel))
  $dir = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
  [System.IO.File]::WriteAllText($full, $Text)
}

function Read-STFile {
  param([string]$Rel)
  $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $Rel))
  if (-not (Test-Path $full)) { return $null }
  return [System.IO.File]::ReadAllText($full)
}

function Reset-STSandbox {
  # 每格开跑前清回种子态：格与格之间不得互相喂状态，否则后一格的绿是前一格的遗产。
  $null = Invoke-STGit 'reset' '-q' '--hard' 'HEAD'
  $null = Invoke-STGit 'clean' '-fdq'
}

function New-STSandbox {
  $ErrorActionPreference = "Continue"
  $tmp = $env:TEMP
  if (-not $tmp) { return $null }
  try {
    $root = Join-Path $tmp ('fist-merge-st-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    if (Test-Path $root) { return $null }
    $null = New-Item -ItemType Directory -Path $root
  } catch {
    return $null
  }
  if ((Invoke-STGit '-C' $root 'init' '-q').Rc -ne 0) { return $null }
  # 沙箱自带身份与 EOL 策略：既不依赖全局 git 配置，也不让 autocrlf 把断言变成运气测试。
  $null = Invoke-STGit '-C' $root 'config' 'user.name' 'selftest'
  $null = Invoke-STGit '-C' $root 'config' 'user.email' 'selftest@invalid.local'
  $null = Invoke-STGit '-C' $root 'config' 'core.autocrlf' 'false'
  $null = Invoke-STGit '-C' $root 'config' 'core.safecrlf' 'false'
  return $root
}

function Remove-STSandbox {
  param([string]$Root)
  $ErrorActionPreference = "Continue"
  if ($Root -and (Test-Path $Root)) { Remove-Item -Recurse -Force $Root }
}

function Set-STSeed {
  Write-STFile 'src/ops/moon.pkg' 'HEAD-MARKER'
  Write-STFile 'src/ops/rhop_native.mbt' 'HEAD-RHOP'
  Write-STFile 'src/ops/keep.mbt' 'HEAD-KEEP'
  $null = Invoke-STGit 'add' '-A'
  $null = Invoke-STGit 'commit' '-q' '-m' 'seed'
  if ((Invoke-STGit 'rev-parse' '--verify' 'HEAD').Rc -ne 0) { return $false }
  if ((Read-STFile 'src/ops/moon.pkg') -ne 'HEAD-MARKER') { return $false }
  return $true
}

function Invoke-STCell {
  param([string]$Name, [ScriptBlock]$Body)
  $ErrorActionPreference = "Continue"
  Reset-STSandbox
  $verdict = $null
  try {
    $verdict = & $Body
  } catch {
    $verdict = '抛出异常：' + $_.Exception.Message
  }
  if ($verdict -eq $true) {
    Write-Host ('  OK   ' + $Name) -ForegroundColor DarkGray
    return
  }
  Write-Host ('  FAIL ' + $Name + '  got=' + $verdict) -ForegroundColor Red
  $script:ST_FAILURES += $Name
}

function Invoke-MergeSelfTest {
  $script:ST_FAILURES = @()
  Write-Host '=== slave-branch-merge.ps1 -SelfTest（沙箱自证，不合并任何东西）===' -ForegroundColor Cyan

  if ((Invoke-STGit 'version').Rc -ne 0) {
    Write-Host 'SELFTEST BLOCKED: 本会话取不到 git，尺子无法自证' -ForegroundColor Red
    return 2
  }
  $root = New-STSandbox
  if (-not $root) {
    Write-Host 'SELFTEST BLOCKED: 沙箱仓建不起来（TEMP 不可写或 git init 失败）' -ForegroundColor Red
    return 2
  }

  $dir0 = (Get-Location).Path
  $seeded = $false
  try {
    Set-Location $root
    $seeded = Set-STSeed
    if (-not $seeded) {
      Write-Host 'SELFTEST BLOCKED: 沙箱种子提交建不起来' -ForegroundColor Red
      return 2
    }

    $cells = @(
      @('C1 exact-path-staged-reverts-to-head', {
          Write-STFile 'src/ops/moon.pkg' 'PICKED-DIRTY'
          $null = Invoke-STGit 'add' '-A'
          $t = Restore-Blacklisted 'selftest-C1'
          if ($t -lt 1) { return "touched=$t（该摘的没摘）" }
          if ((Read-STFile 'src/ops/moon.pkg') -ne 'HEAD-MARKER') { return '盘面未回到 HEAD 版本' }
          if ((Invoke-STGit 'diff' '--cached' '--name-only' 'src/ops/moon.pkg').Out.Trim() -ne '') { return '索引仍留脏' }
          return $true
        }),
      @('C2 new-poison-file-removed-from-disk-and-index', {
          Write-STFile 'src/ops/rhop_poll.mbt' 'function rhop_poll() {}'
          $null = Invoke-STGit 'add' '-A'
          $t = Restore-Blacklisted 'selftest-C2'
          if (Test-Path 'src/ops/rhop_poll.mbt') { return '盘上新文件未被删除' }
          if ((Invoke-STGit 'ls-files' 'src/ops/rhop_poll.mbt').Out.Trim() -ne '') { return '索引仍留该新增文件' }
          if ($t -lt 1) { return "touched=$t" }
          return $true
        }),
      @('C3 glob-only-new-file-removed', {
          Write-STFile 'src/ops/rhop_probe.mbt' 'function rhop_probe() {}'
          $null = Invoke-STGit 'add' '-A'
          $null = Restore-Blacklisted 'selftest-C3'
          if (Test-Path 'src/ops/rhop_probe.mbt') { return 'SKIP_GLOB 没覆盖到非精确名' }
          if ((Invoke-STGit 'ls-files' 'src/ops/rhop_probe.mbt').Out.Trim() -ne '') { return '索引仍留该新增文件' }
          return $true
        }),
      @('C4 glob-path-with-head-version-reverts', {
          Write-STFile 'src/ops/rhop_native.mbt' 'PICKED-RHOP-DIRTY'
          $null = Invoke-STGit 'add' '-A'
          $t = Restore-Blacklisted 'selftest-C4'
          if ((Read-STFile 'src/ops/rhop_native.mbt') -ne 'HEAD-RHOP') { return 'glob 命中且有 HEAD 版本时未回退' }
          if ($t -lt 1) { return "touched=$t" }
          return $true
        }),
      @('C5 unstaged-worktree-is-left-alone', {
          # 现状刻画格：函数只认索引面。生产路径成立是因为 cherry-pick --no-commit 的产物是暂存态；
          # 这条边界写进 README，不写成「已修复」。
          Write-STFile 'src/ops/moon.pkg' 'WORKTREE-WIP'
          $t = Restore-Blacklisted 'selftest-C5'
          if ($t -ne 0) { return "未暂存却被动手（touched=$t）——函数形状与本档声明不符" }
          if ((Read-STFile 'src/ops/moon.pkg') -ne 'WORKTREE-WIP') { return '未暂存的工作树被改写' }
          return $true
        }),
      @('M1 mutation-skiplist-blind-turns-red', {
          # 变异台：名单清空 ⇒ C1 那一格的动作必须失效。若仍回退，说明断言是幻影。
          Write-STFile 'src/ops/moon.pkg' 'PICKED-DIRTY'
          $null = Invoke-STGit 'add' '-A'
          $orig = $script:SKIP_EXACT
          try {
            $script:SKIP_EXACT = @()
            $t = Restore-Blacklisted 'mutant-M1'
            if ($t -ne 0) { return "变异台不咬人：名单已空却 touched=$t" }
            if ((Read-STFile 'src/ops/moon.pkg') -ne 'PICKED-DIRTY') { return '变异台不咬人：名单已空却仍回退了' }
          } finally {
            $script:SKIP_EXACT = $orig
          }
          return $true
        }),
      @('M2 mutation-glob-blind-turns-red', {
          Write-STFile 'src/ops/rhop_probe.mbt' 'function rhop_probe() {}'
          $null = Invoke-STGit 'add' '-A'
          $orig = $script:SKIP_GLOB
          try {
            $script:SKIP_GLOB = @('never-matching-pattern-*')
            $null = Restore-Blacklisted 'mutant-M2'
            if (-not (Test-Path 'src/ops/rhop_probe.mbt')) { return '变异台不咬人：glob 已改瞎却仍删了文件' }
            # 复原后同一违例必须立刻被摘掉——证明名单是承重的，不是装饰。
            $script:SKIP_GLOB = $orig
            $null = Restore-Blacklisted 'mutant-M2-restore'
            if (Test-Path 'src/ops/rhop_probe.mbt') { return '名单复原后没能摘掉' }
          } finally {
            $script:SKIP_GLOB = $orig
          }
          return $true
        }),
      @('S8 sandbox-sentinel-not-standing-in-repo', {
          $here = (Get-Location).Path
          if (-not $here.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return "不在沙箱内：$here" }
          if (Test-Path 'moon.mod') { return '当前目录有 moon.mod——可能站在真仓里' }
          if (Test-Path '.git') { return $true }
          return '沙箱不是 git 仓'
        })
    )

    foreach ($c in $cells) { Invoke-STCell $c[0] $c[1] }
  } catch {
    Write-Host ('SELFTEST BLOCKED: 沙箱阶段异常 ' + $_.Exception.Message) -ForegroundColor Red
    return 2
  } finally {
    Set-Location $dir0
    Remove-STSandbox $root
  }

  $n = $cells.Count
  if ($script:ST_FAILURES.Count -gt 0) {
    Write-Host ('SELFTEST FAIL: ' + $script:ST_FAILURES.Count + '/' + $n + ' 格红 → ' + ($script:ST_FAILURES -join ',')) -ForegroundColor Red
    return 1
  }
  Write-Host ('SELFTEST OK: ' + $n + ' 格全绿（黑名单 C1-C5 / 变异台 M1-M2 / 沙箱哨兵 S8），沙箱已删') -ForegroundColor Green
  return 0
}

$ErrorActionPreference = "Stop"

# R100：自证档必须在任何真实动作之前分叉出去——走到这里就绝不 fetch/cherry-pick/push。
if ($SelfTest) { exit (Invoke-MergeSelfTest) }

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
