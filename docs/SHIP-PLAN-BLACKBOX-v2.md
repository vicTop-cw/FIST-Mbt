# FIST-Mbt 黑盒分发与一键安装计划（重述版）

日期：2026-09-28 ｜ 版本：v1.0 ｜ 状态：实施中
前序计划：已被误删（SHIP-PLAN-0930.md，未 commit 过），本文件为重述

---

## §0 用户原始需求（拍板口径）

> 1. **黑盒化**：目标项目不能修改 FIST-Mbt 源码。参考 stdio MCP server 模式（每个 AI 客户端 spawn 独立进程）。
> 2. **Windows irm 一条命令**：下载依赖、安装、注册 `fist-mbt` 命令。
> 3. **无窗口 app + 后台无感运行**：运行期间是本机"类服务器"的存在。
> 4. **Linux 同等实现**（用 WSL2 实测）。
> 5. **GitCode 主源**：一键安装默认走 GitCode（国内友好），GitHub 作为 fallback。

### 用户拍板的 4 个关键决策（2026-09-28）

| 疑问 | 决策 | 理由 |
|------|------|------|
| MCP 传输层 | **保持 stdio** | 标准 MCP 协议形态，AI 客户端原生 spawn 进程即"类服务器"，天然隔离 |
| 命令名 | **fist-mbt**（不改） | deliverable 70 条、CLI、install 脚本已统一，改名零收益 |
| irm 拉取源 | **GitCode 主源 + GitHub fallback** | 国内直连快；GitHub 有 rate limit 问题（403） |
| 无窗口方案 | **后台 hidden 启动脚本** | stdio 天然无窗口（AI spawn 本来就没窗口）；手动跑时加 hidden shim |

---

## §1 现状审计（2026-09-28 实量）

### 已就绪
| 组件 | 状态 | 证据 |
|------|------|------|
| moon test JS 后端 | **535/535 全绿** | `moon test --target js` 真跑 |
| 账本 BUG | **43 FIXED + 6 DUPLICATE/FALSE_POSITIVE，零 OPEN** | `memory/bugs.md` 逐条解析 |
| 构建脚本 | `scripts/blackbox/build_release.ps1` | 产出 JS + Native zip |
| Windows 安装脚本 | `scripts/blackbox/install.ps1`（~180 行） | GitHub→GitCode 双源、PATH 追加、doctor 自检 |
| Linux 安装脚本 | `scripts/blackbox/install.sh`（~250 行） | 含 `--install-service` 生成 systemd unit |
| CLI 入口 | `cmd/cli/main.mbt` | serve / version / demo / doctor 四子命令 |
| ESM shim | `scripts/patch_esm_main.py` + install 自动调 | moonc ≥0.10.14 输出 ESM，require shim 必打 |
| 产物形状 | `_release/js/fist-mbt.js` + `_release/native/fist-mbt.exe` | 压缩后 zip 上传 |

### 未就绪（Gap 清单）

| # | 缺口 | 影响 | 补法 |
|---|------|------|------|
| G1 | **从未发布过任何 GitCode/GitHub Release** | install.ps1 的 Download-Artifact 会 404 | 首次发布（版本号只在 `BACKLOG.md` 的发布条目里自述，此处不重复数号） |
| G2 | **缺少 irm 一条命令入口脚本** | 用户不知道执行什么 | 写 `install_onecmd.ps1`，即 irm 管道入口 |
| G3 | **GitCode Releases API 未接入** | 当前 install.ps1 里 GitCode 路径写的是 GitHub 格式，GitCode 不同 | 改 GitCode API：`/api/v4/projects/{id}/releases` |
| G4 | **后台 hidden shim 未创建** | 用户手动跑会有 console 窗口 | install.ps1 自动生成 `fist-mbt-background.cmd` |
| G5 | **WSL2 未实测** | Linux 安装脚本理论有、WSL2 实际未知 | 端到端验证 |
| G6 | **serve 子命令缺参数** | 现在只有 `fist-mbt.cmd serve`，没有 `--foreground/--bg` | CLI 加极简参数解析 |
| G7 | **CI 自动发布未接 GitCode** | GitHub Actions release.yml 只写了 GitHub | 加 GitCode upload step |
| G8 | **6 个单模式无法串联循环** | 现有 `PipelineMode` 是单次语义约束，没有编排层 | Phase 6 新增 `PipelineLoop` 编排层与配套 MCP 工具（`loop_create` / `loop_tick` / `loop_status`，2026-09-28 已交付；当前工具总数以 `server.mbt` 注册表为准，由 `check_tools_sync` 对表） |

---

## §2 分阶段实施计划

### Phase 0：GitCode Release 基础设施（1 次 commit）

**目标**：产出第一个 Release，让 irm 命令有东西可拉（版本号以 `BACKLOG.md` 发布条目为准）。

| 步骤 | 动作 | 文件 |
|------|------|------|
| 0.1 | 查 GitCode API | `GET https://gitcode.com/api/v4/projects/VictorTop%2FFist-Mbt/releases` |
| 0.2 | 手动跑 `build_release.ps1 -SkipNative` | 产出 `_release/js/fist-mbt.js` |
| 0.3 | 手动上传 zip 到 GitCode Releases | tag `v0.3.0-beta` |
| 0.4 | 验证 URL 可达 | `https://gitcode.com/VictorTop/Fist-Mbt/-/releases/v0.3.0-beta` |

**完成判据**：`Invoke-WebRequest https://gitcode.com/.../download/v0.3.0-beta/fist-mbt-js-v0.3.0-beta.zip` 返回 200。

---

### Phase 1：irm 一键安装脚本（2-3 次 commit）

**目标**：一条命令完成下载 + 安装 + 注册 + 自检。

#### 1.1 写 irm 入口脚本（新文件）

**文件**：`scripts/blackbox/install_onecmd.ps1`（~50 行，即 irm 管道入口）

```powershell
# irm 入口命令（用户跑的那一行）：
#   irm https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
# 或 GitHub fallback：
#   irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/main/scripts/blackbox/install_onecmd.ps1 | iex
```

做的事：
1. 绕过执行策略：`powershell -ExecutionPolicy Bypass -Command {...}`
2. 用 irm **下载** `install.ps1`（不是直接 exec，避免被调链上）
3. 调用 `install.ps1 -GitCodeOnly`（GitCode 主源参数，新增）
4. 自动 `fist-mbt.cmd doctor` 自检
5. 输出 shim 路径 + 版本号

#### 1.2 改 install.ps1（GitCode API 适配）

**文件**：`scripts/blackbox/install.ps1`

改动点：
- **GitCode Releases API**：不是 GitHub 的 `https://gitcode.com/VictorTop/Fist-Mbt/releases/download/v0.3.0/file.zip`，GitCode 用 `/api/v4/projects/{id}/releases/...` 或直接 URL 格式
- 实测 GitCode 直链下载格式（Phase 0 验证）
- 新增 `-GitCodeOnly` / `-GitHubOnly` / `-PreferGitCode` 参数
- 保留 GitHub 原路径作 fallback（GitHub rate limit 403 时自动切 GitCode）

**防踩坑**（来自 Experience 198278）：
- ❌ 不要用 `irm ... -o out.zip`（irm 不支持 `-o`）
- ✅ 用 `Invoke-WebRequest -Uri URL -OutFile PATH -UseBasicParsing`
- ✅ 下载与解压分两步（避免文件锁占用）

#### 1.3 端到端验证

```powershell
# 干净终端跑（沙箱外）
irm https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
# 预期：下载 → 安装 → shim → doctor OK → "✅ FIST-Mbt v0.3.0-beta 安装完成"
```

---

### Phase 2：后台 hidden shim（1 次 commit）

**目标**：手动跑 `fist-mbt.cmd serve` 时无 console 窗口。

**文件**：`scripts/blackbox/install.ps1`（尾部追加）

新增生成的 shim：`~/.local/bin/fist-mbt-background.cmd`

```batch
@echo off
REM FIST-Mbt 后台启动 shim — 无 console 窗口
REM 用 PowerShell hidden 启动 fist-mbt.cmd serve
powershell -WindowStyle Hidden -Command "& { & \"%USERPROFILE%\.local\bin\fist-mbt.cmd\" serve }"
```

install.ps1 自动创建此文件，权限：用户级（不是管理员）。

同时 CLI 加一个极简 `fist-mbt background` 子命令——等价于直接用 hidden 方式 spawn serve（内部调 `Start-Process -WindowStyle Hidden`）。

---

### Phase 3：Linux/WSL2 验证（端到端）

**目标**：WSL2 里一条命令装完 systemd unit 也 OK。

#### 3.1 WSL2 环境准备
```bash
# 确认 WSL2 版本（systemd 需要 WSLg 或新 kernel）
wsl --status
# 进入
wsl -d Ubuntu-24.04
```

#### 3.2 安装
```bash
# 方式 A：curl 一条（GitCode 主源）
curl -fsSL https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install.sh | bash -s -- --source https://gitcode.com/VictorTop/Fist-Mbt/-/releases/v0.3.0-beta/download

# 方式 B：本地传 install.sh + --source
./scripts/blackbox/install.sh --source ./
```

#### 3.3 systemd --user unit
```bash
./scripts/blackbox/install.sh --install-service
systemctl --user enable --now fist-mbt
systemctl --user status fist-mbt   # 预期 active (running)
```

#### 3.4 验证
```bash
fist-mbt version        # v0.3.0-beta
fist-mbt doctor         # 全 ✅
fist-mbt serve &        # 后台跑，无窗口
```

---

### Phase 4：CI 自动发布（1-2 次 commit）

**目标**：tag push → 自动 build → 自动 upload 到 GitCode（+ GitHub fallback）。

**文件**：`.github/workflows/release.yml`（已有，加 GitCode upload step）

新增 step：
```yaml
- name: Upload to GitCode Releases
  if: startsWith(github.ref, 'refs/tags/')
  run: |
    curl -s -X POST \
      -H "PRIVATE-TOKEN: ${{ secrets.GITCODE_TOKEN }}" \
      -F "file=@_release/js/fist-mbt.js" \
      "https://gitcode.com/api/v4/projects/VictorTop%2FFist-Mbt/releases/:tag/upload"
```

---

### Phase 5：验收（一次性）

| 验收项 | 方法 | 通过标准 |
|--------|------|----------|
| moon test 不退化 | `moon test --target js` | 535/535 |
| irm 命令可达 | 浏览器直接打开 GitCode URL | 200 + 脚本内容正确 |
| Windows 安装 | 干净 PowerShell 跑 irm 命令 | shim + PATH + doctor ✅ |
| Windows 后台 | `fist-mbt-background.cmd serve` | 无 console 窗口 + `Get-Process node` 可见 |
| WSL2 安装 | Ubuntu 24.04 bash 一条命令 | `fist-mbt doctor` 全 ✅ |
| GitCode Release | tag v0.3.0-beta push | GitCode releases 页面可见 |
| 执行策略绕过 | 受限执行策略机器跑 irm 命令 | 不被 ExecutionPolicy 拦截 |

---

## §3 风险与预案

| 风险 | 可能性 | 影响 | 预案 |
|------|--------|------|------|
| GitCode Releases API 路径格式猜错 | 中 | irm 命令 404 | Phase 0 先 GET 确认 API，再写脚本 |
| PowerShell 执行策略拦截 irm | 高 | 用户机器直接失败 | 入口脚本加 `-ExecutionPolicy Bypass`；同时提供 `powershell -Command` 完整命令备选 |
| 下载 zip 后文件锁占用 | 低 | Expand-Archive 报"正被另一进程使用" | 复制到 temp 新文件名再解压（Experience 198278 教训） |
| GitCode upload 权限 | 中 | CI 失败 | 本地先手动上传 v0.3.0-beta，再补 CI 自动化 |
| WSL2 systemd 不默认开 | 中 | `--install-service` 段被跳过 | install.sh 里加 systemd 可用性检测，无 systemd 时 fallback 到 nohup + 提示 |
| npm/node 未装 | 中 | `fist-mbt.js` 跑不起来 | install 脚本开头加 `Test-Node`，缺 Node 时提示 `winget install OpenJS.NodeJS.LTS` |

---

## §4 交付物清单（逐文件）

| 文件 | 动作 | Phase |
|------|------|-------|
| `docs/SHIP-PLAN-BLACKBOX-v2.md` | **新增**（本文件） | 0 |
| `scripts/blackbox/install_onecmd.ps1` | **新增**（irm 入口） | 1 |
| `scripts/blackbox/install.ps1` | **修改**（GitCode API + 参数） | 1 |
| `scripts/blackbox/install.sh` | **微调**（systemd 检测 + Node 检查） | 3 |
| `.github/workflows/release.yml` | **修改**（GitCode upload step） | 4 |
| `cmd/cli/main.mbt` | **修改**（background 子命令可选） | 2 |
| `src/ops/ops_loop.mbt` | **新增**（PipelineLoop 编排层） | 6 |
| `src/ops/ops_loop_wbtest.mbt` | **新增**（环流转白盒） | 6 |
| `src/server/server.mbt` | **修改**（注册 loop_create/tick/status） | 6 |
| `src/store/multi_store.mbt` | **修改**（loop 持久化） | 6 |
| `templates/pipeline_mode_loop.md` | **新增**（组合环元提示词） | 6 |

---

## §5 执行顺序（最短路径）

```
Phase 0 → Phase 1 (1.1+1.2+1.3) → Phase 3 (WSL2 并行) → Phase 2 → Phase 4 → Phase 5
   ↑ 先有东西可拉        ↑ 核心路径                ↑ Linux 端验证    ↑ 后台     ↑ CI 收尾     ↑ 全验
                                                                    ↑
                                                    Phase 6（组合环） ──┘  独立开发路径，Phase 1 跑通后即可并行
```

**最关键路径**：Phase 0（GitCode 有东西）→ Phase 1（irm 命令能跑通）。其他 phase 可在 irm 跑通后并行推进。

**Phase 6 组合环**：纯 MoonBit 代码，零外部依赖，零 store 新表需求（可先 JSONL 追加式持久化）。与 Phase 1-5 完全正交，Phase 1 跑通后即可独立开发，最终在 Phase 5 全验时一并纳入 moon test 验收。

---

## §6 Phase 6：组合环模式（PipelineLoop）

### 6.1 用户原始需求

> 自驱式编程功能再加个"组合环"的模式——组合若干个其他模式为一体的模式。
> 例如 `[推进 → 寻虫 → 修复]` 是个流程，结束后重头再来，直到达成最终目标或超额完成目标。
> 组合环可以重复，如 `[推进 → 寻虫 → 修复 → 推进]`。

### 6.2 设计原则

**不改现有 PipelineMode enum（6 个单模式保持不动）**——组合环是**编排层**，不是新单模式：

```
┌──────────────────────────────────────────────────────┐
│ PipelineLoop（新增编排层，管理循环与终止条件）          │
│   └─ steps: [advance, bugfind, fix_and_merge, ...]  │
│   └─ current_step_idx: Int                            │
│   └─ round_count: Int                                 │
│   └─ stop_condition: GoalReached | Exceeded | MaxRounds│
└──────────────────────────────────────────────────────┘
          ↓ 每一步 dispatch 到 ↓
┌──────────────────────────────────────────────────────┐
│ PipelineMode enum（6 个单模式，零改动）                 │
│   Advance | Polish | Verify | BugFind | FixAndMerge | Tidy │
└──────────────────────────────────────────────────────┘
```

### 6.3 核心数据结构（ops_loop.mbt）

```moonbit
///|
/// 组合环 = 若干单模式的有序序列 + 循环控制。
/// 不引入新 PipelineMode 值——每 step 就是 parse_mode() 能认的那 6 个。
pub struct PipelineLoop {
  name: String               // 环名，如 "fix-iterate"
  steps: Array[String]       // ["advance", "bugfind", "fix_and_merge"]
  current_idx: Int           // 当前推进到 steps[current_idx]
  round: Int                 // 已跑了几轮完整循环（用于 max_rounds 判定）
  max_rounds: Int            // 硬上限（防止死循环），默认 5
  stop_on_goal: Bool         // 达成 project_health=healthy 时停
  stop_on_exceeded: Bool     // 超额完成（如 test count 超 baseline 10%）时停
  created_at: Int64          // Unix 秒
  updated_at: Int64
}
```

### 6.4 新增 MCP 工具（3 个）

| 工具 | 签名 | 说明 |
|------|------|------|
| `loop_create` | `{name, steps:[str], max_rounds?, stop_on_goal?, stop_on_exceeded?}` | 定义组合环，返回 loop_id（内存 + store 持久化） |
| `loop_tick` | `{loop_id, project_dir}` | 推进一环：取当前 steps[idx] → 调 `pipeline_tick(mode=steps[idx])` → idx++ → 到末尾 idx=0 且 round++ → 检查终止条件 |
| `loop_status` | `{loop_id?}` | 查环状态：当前 step、已跑几轮、stop 判定、全部已跑历史 |

**与现有 pipeline_tick 的关系**：`loop_tick` 是**编排器**，内部调 `pipeline_tick(mode=xxx)` 执行单步。零侵入现有 pipeline 逻辑。

### 6.5 终止条件（三选一，优先级从上到下）

| 条件 | 判定 | 动作 |
|------|------|------|
| **max_rounds 硬上限** | `loop.round >= max_rounds` | 停，返回 `status=max_rounds_hit` |
| **goal 达成** | `project_health` 返回 `grade=healthy` 且 `blocked_tasks=0` | 停，返回 `status=goal_reached` |
| **超额完成** | 相比 loop 创建时的 baseline，`test_count ↑ 10%+` 或 `bug_count ↓ 50%+` | 停，返回 `status=exceeded` |

> 用户拍板"达成或超额完成都停"。max_rounds 是安全网（默认 5 轮）。

### 6.6 内置预设环（开箱即用）

| 环名 | steps | 适用场景 |
|------|-------|----------|
| `fix-iterate` | `[bugfind, fix_and_merge]` | 持续寻虫→修复循环，直到零 OPEN bug |
| `build-verify` | `[advance, verify, polish]` | 开发→验证→打磨循环，直到 API 完备 |
| `full-iterate` | `[advance, bugfind, fix_and_merge, verify]` | 四模式流水线迭代（round1→round2→...） |

预设环硬编码在 `ops_loop.mbt::preset_loop(name)` 里，零配置即用。

### 6.7 文件清单

| 文件 | 动作 | 说明 |
|------|------|------|
| `src/ops/ops_loop.mbt` | **新增** | PipelineLoop 结构 + loop_create/tick/status 纯计算逻辑 |
| `src/ops/ops_loop_wbtest.mbt` | **新增** | 白盒：环流转、终止条件、预设环 |
| `src/server/server.mbt` | **修改** | 注册 3 个新工具 + 更新 `mode_list` 返回组合环信息 |
| `src/store/multi_store.mbt` | **修改** | loop 持久化（复用现有 store，一张新表或 JSONL 追加） |
| `templates/pipeline_mode_loop.md` | **新增** | 组合环统一元提示词模板（四分支自决策） |

### 6.8 不做什么（守边界）

- ❌ 不改 `PipelineMode` enum（6 个单模式保持零改动）
- ❌ 不合并 pipeline_tick 与 loop_tick（编排层 vs 执行层清晰分离）
- ❌ 不引入新外部依赖（全纯计算 + 现有 store）
- ❌ 不自动触发环（必须显式 `loop_tick`，或由用户加 `loop_autotick=true` 参数）

### 6.9 验收

| 验收项 | 方法 | 通过标准 |
|--------|------|----------|
| 环流转 | `loop_create → loop_tick × 4 → loop_status` | steps[0→1→2→0], round 正确递增 |
| max_rounds 硬停 | `max_rounds=2`, `loop_tick × 6` | status=max_rounds_hit, 不再推进 |
| goal_reached | 环创建时 3 OPEN bug，loop 内 fix_and_merge 全修后 loop_tick | status=goal_reached |
| 预设环 | `preset_loop("fix-iterate")` | 返回 steps=["bugfind","fix_and_merge"] |
| 持久化 | loop_create → 进程重启 → loop_status | 状态完整保留 |
| moon test | `moon test --target js` | 535/535（新测用例追加 ≥10 条） |
