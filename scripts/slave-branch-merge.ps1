# scripts/slave-branch-merge.ps1
# 一键合并 gitcode/slave/* 分支的新代码 commits 到 master，并清理已合并分支
# 用法: pwsh scripts/slave-branch-merge.ps1
# 流程: fetch → 扫描哪些分支有 src/scripts/cmd/moon.pkg 改动 → 逐个 cherry-pick → 清冲突标记 → build → push → 删已合并分支
# 黑名单(TASK-002): src/ops/moon.pkg 与 src/ops/rhop*.mbt 命中即撤出索引（HEAD 有的还原、没有的删），逐条点名
# 自检: powershell -NoProfile -File scripts/slave-branch-merge.ps1 -SelfTest（沙箱在 %TEMP%，零副作用；rc 0/1/2）

param(
  [switch]$DryRun,  # 只扫描不执行
  [switch]$SelfTest  # 只跑零副作用自检（TASK-002 黑名单），不做任何合并动作
)

$ErrorActionPreference = "Stop"

# ---- TASK-002 cherry-pick 黑名单（poison 面）----
# 主机实测（docs/tasks/backlog/TASK-002-cherry-pick-blacklist.yaml）：旧 slave commit 里
# src/ops/moon.pkg 自带冲突标记（pick 进来就是 moon build 的 [3002] lexing error），
# rhop_poll.mbt 与 HEAD 的 rhop_native.mbt 重复定义 ⇒ 两个形状一旦 cherry-pick 必崩。
# 本脚本因此带一张跳过名单：命中即从索引撤出、HEAD 里有的还原、HEAD 里没有的直接删，
# **每条都点名**，不做静默丢弃。
$script:SkipPaths = @(
  '^src/ops/moon\.pkg$',
  '^src/ops/rhop.*\.mbt$'
)
$script:PoisonNames = @('src/ops/rhop_poll.mbt')

function Invoke-Git {
  # 原生 git 调用一律走这里：$ErrorActionPreference=Stop 下，原生命令的 stderr 经 2>&1 会变成
  # 终止错误（BUG-109 那一族），所以临时降 EAP 再取回 rc。返回 @{rc; out}。
  param([string[]]$GitArgs)
  $savedEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = ''
  $rc = -1
  try {
    $collected = & git @GitArgs 2>&1
    $rc = $LASTEXITCODE
    $out = ($collected | Out-String)
  } finally {
    $ErrorActionPreference = $savedEap
  }
  return @{ rc = $rc; out = $out }
}

function Test-SkipPath {
  # 纯函数：路径命中黑名单吗。git 输出恒为正斜杠；反斜杠一并收，防人手传 Windows 形状的路径。
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $norm = $Path.Replace('\', '/').TrimStart('/')
  foreach ($pat in $script:SkipPaths) {
    if ($norm -match $pat) { return $true }
  }
  return $false
}

function Select-PoisonNames {
  # 盘上兜底只点名真 poison，**不收 rhop_native.mbt**——那是 HEAD 的干净实现，永远在盘上，
  # 把它当 poison 会打出一条假警报（"build 必崩"），把合入者引去删对的函数。
  param([string[]]$Paths)
  $hits = @()
  foreach ($one in $Paths) {
    $norm = $one.Replace('\', '/').TrimStart('/')
    if ($script:PoisonNames -contains $norm) { $hits += $norm }
  }
  return $hits
}

function Select-SkipPaths {
  param([string[]]$Paths)
  $hits = @()
  foreach ($one in $Paths) {
    if (Test-SkipPath $one) { $hits += $one }
  }
  return $hits
}

function Clear-SkipPaths {
  # 撤出索引 + 还原/删除。git reset -q -- <path> 会连 unmerged 三态一起清（冲突条目），
  # 所以 pick 冲突现场也能用；HEAD 里存在的还原成 HEAD 版本，不存在的（poison 新增件）删文件。
  param([string[]]$Paths, [string]$Why = 'cherry-pick')
  $handled = @()
  foreach ($path in (Select-SkipPaths $Paths)) {
    $reset = Invoke-Git @('reset', '-q', '--', $path)
    if ($reset.rc -ne 0) {
      Write-Host "      !! 撤出索引失败 $path (rc=$($reset.rc)) —— 手工处理" -ForegroundColor Red
      $handled += [pscustomobject]@{ Path = $path; Action = 'reset 失败'; Failed = $true }
      continue
    }
    $inHead = Invoke-Git @('cat-file', '-e', "HEAD:$path")
    if ($inHead.rc -eq 0) {
      Invoke-Git @('checkout', '--', $path) | Out-Null
      $action = '还原 HEAD 版本'
    } else {
      if (Test-Path -LiteralPath $path) { Remove-Item -Force -LiteralPath $path }
      $action = '删除（HEAD 里没有这个文件）'
    }
    if ($script:PoisonNames -contains $path) {
      Write-Host "      poison: $path ⇒ $action（与 rhop_native.mbt 重复定义，$Why）" -ForegroundColor Red
    } else {
      Write-Host "      黑名单: $path ⇒ $action（$Why）" -ForegroundColor DarkYellow
    }
    $handled += [pscustomobject]@{ Path = $path; Action = $action; Failed = $false }
  }
  return $handled
}

function Invoke-Cell {
  param([string]$Name, [bool]$Ok, [string]$Note)
  if ($Ok) {
    $script:selfPass = $script:selfPass + 1
    Write-Host "  ok  $Name" -ForegroundColor Green
  } else {
    $script:selfFail = $script:selfFail + 1
    Write-Host "  FAIL $Name — $Note" -ForegroundColor Red
  }
}

function Run-SelfTest {
  # 零副作用自检：P* 是纯函数格，G* 在 %TEMP% 里建一次性 git 沙箱跑**真 cherry-pick 冲突形状**，
  # 绝不碰调用方仓库。rc：0 全过 / 1 有失败 / 2 尺子自己跑不动（git 或沙箱不可用）——
  # 异常绝不冒用 1 那一档（BUG-369 退出码契约家族口径）。
  $script:selfPass = 0
  $script:selfFail = 0

  Invoke-Cell 'P1 moon.pkg 命中' (Test-SkipPath 'src/ops/moon.pkg') '黑名单读不到 src/ops/moon.pkg'
  Invoke-Cell 'P2 rhop_poll.mbt 命中' (Test-SkipPath 'src/ops/rhop_poll.mbt') 'poison 文件没进黑名单'
  Invoke-Cell 'P3 rhop* 族形命中' (Test-SkipPath 'src/ops/rhop_native.mbt') '族形没生效'
  Invoke-Cell 'P4 反斜杠形状命中' (Test-SkipPath 'src\ops\rhop_poll.mbt') 'Windows 形状的路径漏判'
  Invoke-Cell 'P5 非名单不误伤' (-not (Test-SkipPath 'src/server/server.mbt')) '普通源文件被误判成 poison'
  Invoke-Cell 'P6 锚点钉住尾部' (-not (Test-SkipPath 'src/ops/moon.pkg.bak')) '尾部多出的字符也算命中'
  Invoke-Cell 'P7 空串不误伤' (-not (Test-SkipPath '')) '空路径被判成命中'
  Invoke-Cell 'P8 Select-SkipPaths 只挑名单内的' ((Select-SkipPaths @('src/ops/moon.pkg', 'src/store/a.mbt', 'src/ops/rhop_x.mbt')).Count -eq 2) '挑选结果数量不对'
  Invoke-Cell 'P9 族形不含非 mbt' (-not (Test-SkipPath 'src/ops/rhop_notes.txt')) 'txt 也被 rhop* 族收进名单'
  Invoke-Cell 'P10 兜底点名 poison' (@(Select-PoisonNames @('src/ops/rhop_poll.mbt')).Count -eq 1) '盘上兜底抓不到 poison'
  Invoke-Cell 'P11 兜底不误伤 rhop_native' (@(Select-PoisonNames @('src/ops/rhop_native.mbt', 'src/store/a.mbt')).Count -eq 0) 'HEAD 的干净实现被当成 poison'

  $probe = Invoke-Git @('--version')
  if ($probe.rc -ne 0) {
    Write-Host "  SELFTEST REFUSED（git 不可用：rc=$($probe.rc)）" -ForegroundColor Red
    return 2
  }

  $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('slave-merge-selftest-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  $inSandbox = $false
  try {
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    Push-Location $sandbox
    $inSandbox = $true
    $null = New-Item -ItemType Directory -Path 'src/ops' -Force
    $null = New-Item -ItemType Directory -Path 'src/store' -Force
    Set-Content -Path 'src/ops/moon.pkg' -Value 'import "pkg/moonbitlang/core"' -Encoding ASCII
    Set-Content -Path 'src/store/a.mbt' -Value 'pub fn a() {}' -Encoding ASCII
    (Invoke-Git @('init', '-q')).rc | Out-Null
    (Invoke-Git @('config', 'user.email', 'selftest@local')).rc | Out-Null
    (Invoke-Git @('config', 'user.name', 'selftest')).rc | Out-Null
    (Invoke-Git @('add', '-A')).rc | Out-Null
    (Invoke-Git @('commit', '-qm', 'base')).rc | Out-Null
    if ((Invoke-Git @('rev-parse', '--verify', 'HEAD')).rc -ne 0) {
      Write-Host '  SELFTEST REFUSED（沙箱 base commit 建不起来）' -ForegroundColor Red
      return 2
    }

    # 分叉：先记下 base 与 trunk 分支名（git 的默认初始分支名不保证是 master，不能写死）。
    # trunk 侧改 moon.pkg；poison 侧**从 base 分叉**（不是从 trunk 之后），把它写成带冲突标记的样子
    # + 新增 rhop_poll.mbt + 改 a.mbt ⇒ cherry-pick 回来才是真冲突形状。
    $trunkBranch = (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).out.Trim()
    $baseSha = (Invoke-Git @('rev-parse', 'HEAD')).out.Trim()
    Set-Content -Path 'src/ops/moon.pkg' -Value 'import "pkg/moonbitlang/core"  # trunk 侧改动' -Encoding ASCII
    (Invoke-Git @('commit', '-qam', 'trunk')).rc | Out-Null
    (Invoke-Git @('checkout', '-qb', 'poison', $baseSha)).rc | Out-Null
    Set-Content -Path 'src/ops/moon.pkg' -Value '<<<<<<< HEAD' -Encoding ASCII
    Add-Content -Path 'src/ops/moon.pkg' -Value 'import "pkg/moonbitlang/core"  # trunk 侧改动' -Encoding ASCII
    Add-Content -Path 'src/ops/moon.pkg' -Value '=======' -Encoding ASCII
    Add-Content -Path 'src/ops/moon.pkg' -Value 'import "pkg/moonbitlang/core"  # poison 侧改动' -Encoding ASCII
    Add-Content -Path 'src/ops/moon.pkg' -Value '>>>>>>> poison' -Encoding ASCII
    Set-Content -Path 'src/ops/rhop_poll.mbt' -Value 'pub fn rhop_poll() {}' -Encoding ASCII
    Set-Content -Path 'src/store/a.mbt' -Value 'pub fn a() { println("changed") }' -Encoding ASCII
    (Invoke-Git @('add', '-A')).rc | Out-Null
    (Invoke-Git @('commit', '-qm', 'poison commit')).rc | Out-Null
    $poisonSha = (Invoke-Git @('rev-parse', 'HEAD')).out.Trim()
    (Invoke-Git @('checkout', '-q', $trunkBranch)).rc | Out-Null
    $pick = Invoke-Git @('cherry-pick', '--no-commit', $poisonSha)
    Invoke-Cell 'G0 沙箱真造出 cherry-pick 冲突' ($pick.rc -ne 0) "预期冲突，实际 rc=$($pick.rc)：$($pick.out)"
    Invoke-Cell 'G0b 冲突确实落在 moon.pkg 上' ((Invoke-Git @('ls-files', '-u')).out.Contains('src/ops/moon.pkg')) 'unmerged 里没有 moon.pkg，沙箱形状不对'

    $handled = @(Clear-SkipPaths @('src/ops/moon.pkg', 'src/ops/rhop_poll.mbt', 'src/store/a.mbt') -Why 'selftest')
    Invoke-Cell 'G1 两条黑名单各处置一次' ($handled.Count -eq 2) "实际处置 $($handled.Count) 条"
    Invoke-Cell 'G2 poison 已从盘上删除' (-not (Test-Path 'src/ops/rhop_poll.mbt')) '文件还在盘上'
    Invoke-Cell 'G3 poison 不在索引里' ((Invoke-Git @('ls-files', '--', 'src/ops/rhop_poll.mbt')).out.Trim() -eq '') '索引里仍有它'
    Invoke-Cell 'G4 moon.pkg 无 unmerged 残留' ((Invoke-Git @('ls-files', '-u')).out.Trim() -eq '') "仍有 unmerged：$((Invoke-Git @('ls-files', '-u')).out.Trim())"
    $pkgNow = Get-Content 'src/ops/moon.pkg' -Raw
    Invoke-Cell 'G5 moon.pkg 回到 trunk 版本' ($pkgNow.Contains('trunk') -and -not $pkgNow.Contains('<<<<<<<')) "内容=$($pkgNow.Trim())"
    Invoke-Cell 'G6 非名单文件的改动没被撤' ((Invoke-Git @('diff', '--cached', '--name-only')).out.Contains('src/store/a.mbt')) 'a.mbt 被误撤了'
    Invoke-Cell 'G7 Clear 对非名单路径无事发生' (@(Clear-SkipPaths @('src/store/a.mbt') -Why 'selftest').Count -eq 0) '非名单文件被处置了'
    Pop-Location
    $inSandbox = $false
  } catch {
    Write-Host "  SELFTEST REFUSED（沙箱异常：$($_.Exception.Message)）" -ForegroundColor Red
    return 2
  } finally {
    if ($inSandbox) { try { Pop-Location } catch { } }
    if (Test-Path $sandbox) {
      try { Remove-Item -Recurse -Force $sandbox } catch { }
    }
  }

  Write-Host ''
  Write-Host "SELFTEST 通过 $script:selfPass / 失败 $script:selfFail"
  if ($script:selfFail -gt 0) { return 1 }
  return 0
}

Write-Host "=== FIST-Mbt Slave Branch Merger ===" -ForegroundColor Cyan
Write-Host ""

if ($SelfTest) {
  Write-Host "[SELFTEST] slave-branch-merge.ps1 黑名单自检（沙箱建在 %TEMP%，不碰本仓）" -ForegroundColor Cyan
  exit (Run-SelfTest)
}

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
$poisonSkipped = @()

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
    if ($LASTEXITCODE -ne 0) {
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
    
    # TASK-002：pick 进来的 poison 面（src/ops/moon.pkg 冲突标记 / rhop*.mbt 重复定义）先撤掉再提交
    $hits = @(Select-SkipPaths $files)
    if ($hits.Count -gt 0) {
      $cleared = @(Clear-SkipPaths $hits -Why "pick $shortHash")
      foreach ($h in $cleared) { $poisonSkipped += $h }
    }

    git commit -m "$msg (from $shortHash)" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $pickCount++ }
  }
}

Write-Host "`n  Picked: $pickCount commits, Skipped (no code): $skipCount" -ForegroundColor Green
Write-Host "  黑名单处置: $($poisonSkipped.Count) 个文件（TASK-002，逐条已点名，不静默丢）" -ForegroundColor DarkYellow

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

# 5.5 盘上 poison 兜底普查（pick 之外还可能被 checkout/copy 带进来，这里点名）
$onDiskPoison = @()
if (Test-Path 'src/ops') {
  $onDiskMbt = @(Get-ChildItem -Path 'src/ops' -Filter '*.mbt' -File -ErrorAction SilentlyContinue |
      ForEach-Object { 'src/ops/' + $_.Name })
  $onDiskPoison = @(Select-PoisonNames $onDiskMbt)
}
if ($onDiskPoison.Count -gt 0) {
  foreach ($f in $onDiskPoison) { Write-Host "  !! 盘上还留着 $f —— 与 rhop_native.mbt 重复定义，build 必崩" -ForegroundColor Red }
  $cleared = @(Clear-SkipPaths $onDiskPoison -Why '盘上残留')
  foreach ($h in $cleared) { $poisonSkipped += $h }
}

# 6. Build 验证
Write-Host "`n[6/6] Build 验证..." -ForegroundColor Yellow
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
