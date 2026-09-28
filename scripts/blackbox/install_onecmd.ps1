#!/usr/bin/env pwsh
<#
scripts/blackbox/install_onecmd.ps1 —— irm 一条命令安装入口（v2 Release Assets 版）

用户跑（首选，2026-09-28 实测公网可达且返回正文即脚本）：
  iex ((irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
# BUG-113：这里为什么不写 `irm … | iex` 而是先 TrimStart —— 本文件含中文，按 check_ps_encoding
# 必须带 UTF-8 BOM；`irm` 把 BOM 留成首字符 U+FEFF，`iex` 就不再把 `param()` 当首语句，
# 报「At line:22 char:22 赋值表达式的左侧无效」。用 `powershell -File` 走磁盘没这问题
# （两条调用面不同形）⇒ 回归入口：scripts/blackbox/e2e_irm_line.py 跑**字面文档线**。
备用（GitCode 镜像，同一份内容）：
  irm https://gitcode.com/VictorTop/Fist-Mbt/-/raw/master/scripts/blackbox/install_onecmd.ps1 | iex

分支名用 master 不是 main：GitHub 默认分支是 master，raw/main 那条实测取不到东西。
GitCode 侧实测三种形状（/-/raw/、/raw/、raw. 子域）匿名 GET 都返回 **HTTP 200 + HTML 页**，
所以它只能当备用，且必须过下面那道"正文形状"检查（200 不等于拿到文件）。

下载源（自动按序 fallback）：
  1. GitCode Release Assets 直链
  2. GitHub Release Assets 直链
#>

param(
  # 版本号唯一真源 = moon.mod（发布资产名也从它生成）。写死默认值的后果实测过：
  # 默认值偏一个字 ⇒ 用户跑不带参数的 `irm … | iex` 永远指向发布链不会产出的资产名（两条源都 404）。
  [string]$Version = "",
  [switch]$Force,
  # 离线/内网/发布前自证：给了本地 zip 就跳过下载（不发 Release 也能装）
  [string]$LocalZip = "",
  # 镜像入口：给一个 base（内网镜像 / 本机 http.server）就只从它下面按**与公网同形的路径**取
  # moon.mod 与资产 —— 这样"下载这一步"在没有公网 Release 时也能被真跑一遍，而不是只能靠 -LocalZip 绕行。
  [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   FIST-Mbt Installer  v$Version" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

function Test-Cmd($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

$needPython = $true
$pyCmd = if (Test-Cmd "python") { "python" } elseif (Test-Cmd "py") { "py -3" } else { "" }

if (-not (Test-Cmd "node")) { Write-Host "❌ 需要 Node.js >=24 (winget install OpenJS.NodeJS.LTS)" -ForegroundColor Red; exit 1 }
$nv = (node -v)
$nm = [int]($nv -replace '^v', '' -split '\.')[0]
if ($nm -lt 24) { Write-Host "❌ Node.js $nv 过低，需要 >=24" -ForegroundColor Red; exit 1 }
Write-Host "✅ node $nv" -ForegroundColor Green

if (-not $pyCmd) { Write-Host "⚠️ python 未找到，ESM patch 将跳过" -ForegroundColor Yellow; $needPython = $false }
else { Write-Host "✅ python ($pyCmd)" -ForegroundColor Green }

# 版本号没显式给就现取：从 moon.mod（与发布链同源的那批 raw 地址）解析，解析不到就显式失败——
# 绝不静默退回某个"猜出来的版本号"，那正是 `irm | iex` 装不上的根因。
$rawUrls = @(
  "https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/moon.mod",
  "https://gitcode.com/VictorTop/Fist-Mbt/-/raw/master/moon.mod"
)
$versionSource = ""
if ($BaseUrl -ne "") { $rawUrls = @(($BaseUrl.TrimEnd('/') + "/moon.mod")) }
if ($Version -eq "") {
  if ($LocalZip -ne "" -and (Split-Path -Leaf $LocalZip) -match '^fist-mbt-js-v(.+)\.zip$') {
    $Version = $matches[1]; $versionSource = "本地 zip 文件名"
  } else {
    foreach ($r in $rawUrls) {
      try {
        $mm = (Invoke-WebRequest -Uri $r -UseBasicParsing -TimeoutSec 20).Content
        # 有的源（本机 http.server、内网镜像）把 .mod 标成 application/octet-stream ⇒ PS 交回来的是
        # byte[] 而不是 string，直接 -match 会静默不中，用户只看到"解析不到版本"。先按 UTF-8 归一。
        if ($mm -isnot [string]) { $mm = [Text.Encoding]::UTF8.GetString($mm) }
        # BUG-107：状态码 200 不代表拿到了文件。GitCode 匿名 raw 直链实测返回一整个 HTML 页，
        # 而 HTML 里没有 `version = "…"` ⇒ 旧代码会安静地跳到下一个源，用户看不到"这源给的是网页"。
        if ($mm -match '^\s*<(!DOCTYPE|html)') {
          Write-Host "  · $r 返回 HTML 页而不是文件（该源不可用作 raw 直链）" -ForegroundColor DarkGray
          continue
        }
        if ($mm -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $Version = $matches[1]; $versionSource = $r; break }
        Write-Host "  · $r 的正文里没有可解析的 version 行" -ForegroundColor DarkGray
      } catch {
        Write-Host "  · 取不到 $r ：$($_.Exception.Message)" -ForegroundColor DarkGray
      }
    }
  }
}
if ($Version -eq "") {
  Write-Host "❌ 无法从 moon.mod 解析版本号（候选源见上）。显式指定：& <脚本> -Version 0.3.0" -ForegroundColor Red
  exit 1
}
Write-Host "  目标版本 v$Version（来源：$versionSource）" -ForegroundColor DarkGray

$zipName = "fist-mbt-js-v$Version.zip"
$urls = @(
  "https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v$Version/$zipName",
  "https://github.com/vicTop-cw/FIST-Mbt/releases/download/v$Version/$zipName"
)
if ($BaseUrl -ne "") { $urls = @(($BaseUrl.TrimEnd('/') + "/-/releases/download/v$Version/$zipName")) }
if ($BaseUrl -ne "" -and $LocalZip -ne "") {
  # 两个"跳过公网"的口子同时给，日志里就说不清装的是哪一份东西 ⇒ 当场拒，不做"取第一个"的猜
  Write-Host "❌ -BaseUrl 与 -LocalZip 不能同时给（前者走镜像下载，后者跳过下载）" -ForegroundColor Red
  exit 1
}

$dest = Join-Path $env:LOCALAPPDATA "FIST-Mbt"
$bin  = Join-Path $env:USERPROFILE ".local\bin"
$temp = Join-Path $env:TEMP ("fist-install-" + [guid]::NewGuid().ToString("N"))

Write-Host ""
Write-Host "📥 下载 $zipName ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $temp -Force | Out-Null

$zipPath = Join-Path $temp $zipName
$downloaded = $false
if ($LocalZip -ne "") {
  if (-not (Test-Path $LocalZip)) {
    Write-Host "❌  -LocalZip 指向的文件不存在: $LocalZip" -ForegroundColor Red
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
  }
  $li = Get-Item $LocalZip
  Copy-Item $li.FullName $zipPath -Force
  Write-Host ("  ✅ 用本地 zip（跳过下载）: " + $li.FullName + " (" + [math]::Round($li.Length/1KB,1) + " KB)") -ForegroundColor Green
  $downloaded = $true
}
foreach ($u in $(if ($downloaded) { @() } else { $urls })) {
  Write-Host "  尝试: $u" -ForegroundColor DarkGray
  try {
    Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
    # BUG-107：光看大小会被"200 + 一整页 HTML"糊过去（备用源的真实形状就是网页）。
    # zip 的前两字节必须是 PK —— 这一条判据不看状态码，只看拿到的东西是什么。
    $magic = [IO.File]::ReadAllBytes($zipPath)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
      Write-Host "  · 该源给的不是 zip（前两字节 $([BitConverter]::ToString($magic))，多半是 HTML 页）" -ForegroundColor DarkGray
      Remove-Item $zipPath -Force; continue
    }
    if ((Get-Item $zipPath).Length -gt 10KB) {
      Write-Host "  ✅ 下载成功 ($([math]::Round((Get-Item $zipPath).Length/1KB,1)) KB)" -ForegroundColor Green
      $downloaded = $true; break
    } else { Remove-Item $zipPath -Force }
  } catch {
    # 吞掉异常就等于让用户分不清「资产没发布(404)」和「我这里断网」，两者处方完全不同
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { "n/a" }
    Write-Host ("  ⚠️ 失败 HTTP " + $code + " (" + $_.Exception.GetType().Name + ") ... 换源") -ForegroundColor Yellow
  }
}
if (-not $downloaded) {
  Write-Host "❌ 下载全部失败（每个源的状态见上）。三种可能：Release 未发布 / 资产名不是 $zipName / 本机连不上外网" -ForegroundColor Red
  foreach ($u in $urls) { Write-Host "    - $u" -ForegroundColor DarkGray }
  Write-Host "  离线安装：& <脚本路径> -Version $Version -LocalZip $env:USERPROFILE\Downloads\$zipName" -ForegroundColor DarkGray
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
}

Write-Host ""
Write-Host "📦 解压 ..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $temp -Force
$jsMain = Get-ChildItem -Path $temp -Filter "fist-mbt.js" -Recurse -File | Select-Object -First 1
if (-not $jsMain) { Write-Host "❌ zip 里没找到 fist-mbt.js" -ForegroundColor Red; Remove-Item -Recurse -Force $temp; exit 1 }
$pyPatch = Get-ChildItem -Path $temp -Filter "patch_esm_main.py" -Recurse -File | Select-Object -First 1
Write-Host "  ✅ fist-mbt.js ($([math]::Round($jsMain.Length/1024,1)) KB)" -ForegroundColor Green

Write-Host ""
Write-Host "📦 安装到 $dest ..." -ForegroundColor Yellow
if (Test-Path $dest) { if ($Force) { Remove-Item -Recurse -Force $dest } else { Write-Host "  ⚠️ 已存在，加 -Force 覆盖" -ForegroundColor Yellow } }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item $jsMain.FullName          "$dest\fist-mbt.js"          -Force
if ($pyPatch) { Copy-Item $pyPatch.FullName "$dest\patch_esm_main.py" -Force }
'{"type":"module"}' | Set-Content "$dest\package.json" -Encoding ASCII

if ($needPython -and $pyPatch) {
  Write-Host "🔧 注入 ESM createRequire shim ..." -ForegroundColor Yellow
  Invoke-Expression "$pyCmd `"$dest\patch_esm_main.py`" `"$dest\fist-mbt.js`" 2>&1 | Select-Object -Last 1" | Out-Null
}

Write-Host ""
Write-Host "🔧 创建 shim + PATH ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $bin -Force | Out-Null
# 注释一律纯 ASCII：这下面用 -Encoding ASCII 写盘，非 ASCII 字符会被替换成 '?'
# （实测旧版那行 REM 落盘成 "shim ? v0.3.0"），而 shim 内容本身不参与执行，别放中文。
$shimCmd = "@echo off`r`nREM FIST-Mbt shim (v" + $Version + ")`r`nnode `"$dest\fist-mbt.js`" %*`r`n"
Set-Content -Path "$bin\fist.cmd"     -Value $shimCmd -Encoding ASCII
Set-Content -Path "$bin\fist-mbt.cmd" -Value $shimCmd -Encoding ASCII
# BUG-105：POSIX shell（Git Bash / MSYS / Cygwin / agent harness 的 bash 工具）不按 PATHEXT
# 解析命令名 ⇒ 只写 .cmd 的话，装完在同一台机器的 bash 里 `fist` 直接 command not found。
# 再写一份无扩展名 shim；换行必须是 LF——CRLF 的 shebang 会让 sh 报 "bad interpreter"。
$shimSh = '#!/bin/sh' + "`n" + 'exec node "' + $dest + '\fist-mbt.js" "$@"' + "`n"
Set-Content -Path "$bin\fist"     -Value $shimSh -Encoding ASCII -NoNewline
Set-Content -Path "$bin\fist-mbt" -Value $shimSh -Encoding ASCII -NoNewline
# 硬门：四件齐才算装上。少一件就是"文档说装好了、命令却找不到"的那类坑，绝不静默放过。
$shimMissing = @()
foreach ($f in @("fist.cmd", "fist-mbt.cmd", "fist", "fist-mbt")) {
  if (-not (Test-Path (Join-Path $bin $f))) { $shimMissing += $f }
}
if ($shimMissing.Count -gt 0) {
  Write-Host "❌ shim 未全部写出：$($shimMissing -join ', ')（期望 .cmd + 无扩展名 POSIX 两份）" -ForegroundColor Red
  exit 1
}

$pathUser = [Environment]::GetEnvironmentVariable("PATH", "User")
$pathChanged = $false
if ($pathUser -notlike "*$bin*") {
  [Environment]::SetEnvironmentVariable("PATH", "$bin;$pathUser", "User")
  $env:PATH = "$bin;$env:PATH"; $pathChanged = $true
}

Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "🏥 自检..." -ForegroundColor Yellow
# BUG-109：脚本顶部是 $ErrorActionPreference="Stop"，而原生命令只要往 stderr 打一个字，
# 经 2>&1 就被包成终止错误（NativeCommandError）。node:sqlite 每次启动都打
# ExperimentalWarning: SQLite is an experimental feature ⇒ 旧写法里那两个 try 必然进
# catch（空 catch 把错吞掉），下一行 "✅ fist-mbt.js 可执行" 却无条件打印——绿是假的；
# 更糟的是 `& fist version` 的 catch 把"命令跑通了"报成"当前会话 PATH 未刷新"，
# 把用户支到一个不存在的原因上。正解：调用期临时降 EAP、stderr 单独丢（只要 stdout 回执），
# 并把「命令名解析不到」和「解析到了却无回执」分成两条不同诊断。
function Invoke-FistNative {
  param($Exe, [string[]]$ExeArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { $out = (& $Exe @ExeArgs 2>$null | Out-String) } finally { $ErrorActionPreference = $prevEap }
  return $out.Trim()
}
$jsVer = Invoke-FistNative -Exe "node" -ExeArgs @("$dest\fist-mbt.js", "version")
if ($jsVer) {
  Write-Host "  ✅ $jsVer" -ForegroundColor Green
  Write-Host "  ✅ fist-mbt.js 可执行" -ForegroundColor Green
} else {
  Write-Host "  ❌ 产物跑不出版本（node 不在 PATH 或产物损坏）：node `"$dest\fist-mbt.js`" version 无 stdout 回执" -ForegroundColor Red
  exit 1
}
$shimCmd = Get-Command fist -ErrorAction SilentlyContinue
if ($shimCmd) {
  $vv = Invoke-FistNative -Exe $shimCmd.Source -ExeArgs @("version")
  if ($vv) { Write-Host "  ✅ fist (PATH) → $vv" -ForegroundColor Green }
  else {
    Write-Host "  ❌ fist 解析到 $($shimCmd.Source)，但跑起来没有回执" -ForegroundColor Red
    exit 1
  }
} else {
  Write-Host "  ⚠️ 当前会话 PATH 未刷新（新开终端即可）" -ForegroundColor Yellow
}
# 无扩展名那份只能由 POSIX shell 验到：这里核字节（shebang 必须是首行且行尾不是 CRLF），
# 因为 CRLF 的 `#!/bin/sh` 在 Git Bash 里报的是 "bad interpreter"——装完当场看不出来。
$shBytes = [IO.File]::ReadAllBytes((Join-Path $bin "fist"))
$shHead = [Text.Encoding]::ASCII.GetString($shBytes[0..8])
if ($shHead -eq "#!/bin/sh" -and ($shBytes -notcontains 13)) {
  Write-Host "  ✅ fist (POSIX shim, LF) 供 Git Bash / MSYS 使用" -ForegroundColor Green
} else {
  Write-Host "  ❌ POSIX shim 头不对或含 CR（bash 下会报 bad interpreter）" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅ FIST-Mbt v$Version 安装完成！" -ForegroundColor Green
Write-Host "║   新开终端:  fist help" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
if ($pathChanged) { Write-Host "💡 已把 $bin 追加到用户级 PATH" -ForegroundColor DarkGray }

