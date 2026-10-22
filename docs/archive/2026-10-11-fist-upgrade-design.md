# FIST-Mbt `--upgrade` 自动升级 · 设计方案

- **日期**：2026-10-11
- **状态**：**阶段 1（`--check` 只读）已实现并实测**；阶段 2（写盘）待指挥官批准后动工。终审 = 指挥官
- **驱动**：指挥官「fist-mbt 没有自动升级功能 --upgrade，设计一下」

---

## 1. 现状盘点（实机核实，非臆测）

| 面 | 现状 | 出处 |
|---|---|---|
| 子命令 | `enum Subcmd { Serve, Version, Demo, Doctor, Help, NoArgs, Unknown(String) }`，`parse_subcmd` 展开别名一次 | `cmd/cli/subcmd.mbt` |
| 分发 | `main.mbt` 按 `cmd` match 到 `run_serve/run_version/run_demo/run_doctor/run_help`；未知回 2 | `cmd/cli/main.mbt` |
| 版本源 | `moon.mod version="0.3.8"` → `@server.get_version()` → `project_version`；常驻白盒锁「`project_version`==moon.mod」（BUG-114） | `moon.mod` / `src/server/fist-mbt_wbtest.mbt` |
| 安装器 | `scripts/blackbox/install.ps1`（Windows）+ `install.sh`（POSIX）；GitHub→GitCode 双源下载 `fist-mbt-js-v<ver>.zip` / `fist-mbt-native-win-x64-v<ver>.zip`；解包取 `fist-mbt.js` 到 `$LOCALAPPDATA\FIST-Mbt\`；写 shim `~/.local/bin/fist-mbt.cmd`（native 优先、node 兜底）；追加 PATH | `scripts/blackbox/install.ps1` L77-201 |
| 升级安装器 | `scripts/blackbox/upgrade_install.ps1`（**tracked 真源**，含 `-BaseUrl`/`-Force`/`-NoPath`；BUG-E 由 `_release/js/install_onecmd.ps1` 收口为 tracked） | `check_upgrade_installer.py` G1 |
| `upgrade` | **全仓 0 处** | `grep -i upgrade` 全空 |
| 发布/安装硬化 | R5（无扩展 shim）/ R6（200≠文件，`PK` 魔数）/ R7（自检不假绿）/ R8-R14（release/install 双栈重试）已落地 | `check_release_asset_names.py` / `e2e_mirror_install.py` / `e2e_irm_line.py` 等 |
| **关键缺口** | 安装器**不写 `VERSION` 文件**到安装位；已装版本只能靠跑 `fist-mbt.js version` 反解 | `install.ps1` L155-201 |

**结论**：`--upgrade` 的缺口不是「下载/校验」（已有 R6/R12/R14 硬化），而是**「版本可发现 + 原子替换 + 回滚」三层从未存在**。设计围绕这三层展开，复用已有下载链。

---

## 2. 设计目标

1. **可发现**：任何时刻能确定「当前装的版本」与「远端最新版本」。
2. **可比较**：语义版本比较（`major.minor.patch`），`project_version` 与 `moon.mod` 不一致时**拒绝宣称**（BUG-114 锁）。
3. **原子替换**：下载→校验→解包→备份→换入，任一步失败不破坏现状。
4. **可回滚**：换入后自检新版本，失败自动还原备份。
5. **不假绿**（R7）：无网络/无凭据/无 node 时明确报错，**绝不说「已是最新」**。
6. **判据可自证**：纯逻辑（版本比较）+ 端到端（镜像仓库）两层判据。

---

## 3. 接入方式

**子命令（规范）** `fist-mbt upgrade [--check] [--channel <stable|pre>]`
**别名（按指挥官措辞）** `fist-mbt --upgrade`、`fist-mbt -U`

`cmd/cli/subcmd.mbt` 增：

```moonbit
enum Subcmd { Serve; Version; Upgrade; Demo; Doctor; Help; NoArgs; Unknown(String) }

fn parse_subcmd(sub : String) -> Subcmd {
  match sub {
    "serve" => Serve
    "version" | "--version" | "-V" => Version
    "upgrade" | "--upgrade" | "-U" => Upgrade
    "demo" => Demo
    "doctor" => Doctor
    "help" | "--help" | "-h" => Help
    "" => NoArgs
    other => Unknown(other)
  }
}
```

`main.mbt` 分发：`Upgrade => run_upgrade(args)`。旗参从 `args[3]` 读（与 `help` 读 topic 同模式）：`args[3] == "--check"` → 只检测不下载。

**白盒锁**：`subcmd_wbtest.mbt` 补 `assert_eq(parse_subcmd("upgrade"), Upgrade)` / `assert_eq(parse_subcmd("--upgrade"), Upgrade)` / `assert_eq(parse_subcmd("-U"), Upgrade)`。**未知子命令仍回 2**（BUG-106，别把 `--upgrade` 之外的 `--upgrade-xxx` 吞成 Upgrade）。

---

## 4. 核心流程（三阶段）

```
┌─ 阶段 A · 检测（--check 只走到这，rc=0 表示「跑完了」，不是「可升级」）
│  1. 读本地已装版本 L
│       ├─ 优先读 $InstallDir\VERSION（新安装器会写）
│       └─ 缺则跑 `node <jsBin> version` 解析 "FIST-Mbt vX.Y.Z"
│  2. 读远端最新 R
│       ├─ 主：GitHub API `releases/latest` → tag_name（去 v 前缀）
│       └─ 备：GitCode releases/latest
│  3. 比较 R vs L
│       ├─ R == L  → "已是最新 vL"，rc=0
│       ├─ R <  L  → "本地超前（dev 构建）"，rc=0 + 提示
│       └─ R >  L  → "可升级 vL → vR"，rc=0 + 列出变更摘要（可选）
│  若任何一步拿不到（无网络/API 拒绝/无 node）→ 明确报错 rc≠0，绝不回落"已是最新"
│
├─ 阶段 B · 取物
│  4. 下载 upgrade_install.ps1（tracked 真源 `scripts/blackbox/`，走 R12 双栈重试：只对传输层错误重试/换栈）
│  5. 调它：pwsh upgrade_install.ps1 -Version <R> [-BaseUrl ...] [-NoPath] [-Force]（不重复实现下载）
│
└─ 阶段 C · 验证 + 回滚
   6. 跑 `node <jsBin> version`，确认 == R
   7. == R  → 写 $InstallDir\VERSION=R，打印成功
   8. != R  → 从 $InstallDir\fist-mbt.js.bak-<L> 还原，报错 rc≠0
```

**关键：阶段 B 复用升级安装器，不重写下载/校验**——R5/R6/R7/R12 全部继承，避免「再写一遍下载器」引入新 bug 面。

---

## 5. 关键决策

### 5.1 已装版本从哪来？
**推荐**：安装器升级为**写 `VERSION` 文件**（`install.ps1`/`install.sh`/`upgrade_install.ps1` 在装完 `fist-mbt.js` 后 `Set-Content $InstallDir\VERSION $Version`，且都在自检真回执通过后才写——R7）。已有安装无此文件 → **回退**跑 `node fist-mbt.js version` 解析。
- 拒绝「grep fist-mbt.js 里的版本字符串」：产物被压缩，正则脆弱，且 `project_version` 可能滞后（正是 BUG-114 要防的）。

### 5.2 版本比较放哪？
**纯 MoonBit**，放 `cmd/cli/` 或 `src/upgrade/` 新模块，**零 IO**，可白盒单测：

```moonbit
/// 返回 1/0/-1：R 高于/等于/低于 L；解析失败返回 Err
fn cmp_version(r : String, l : String) -> Int
```
- 只比 `major.minor.patch` 三段；pre-release（`-alpha1` 之类）按「低于同号正式版」处理。
- 前置锁（BUG-114）：`run_upgrade` 首步读 `@server.get_version()`，若 `!= moon.mod` 的 `project_version`，**报「自身版本声明不可信，拒绝升级判断」**并 rc≠0。**宁可红，不可假绿**。

### 5.3 原子替换怎么做？
阶段 B 交给 `upgrade_install.ps1`，但 **阶段 C 前先备份**：
- `Copy-Item $InstallDir\fist-mbt.js → fist-mbt.js.bak-<L>`（同目录，同卷，rename 原子）。
- 换入用「下载到 temp → 解包 → Move-Item -Force」（Windows 同卷 Move 是 rename，原子）。
- **Windows 文件占用**：若 MCP server 正在跑，`Move-Item` 会失败（EXDEV/占用）。**检测到占用 → 提示「请先停止 fist-mbt serve 再 upgrade」**，rc≠0，不静默。

### 5.4 通道
`--channel stable`（默认）/ `--channel pre`。当前只读 `releases/latest`（= stable）；pre 通道留接口（读 `releases?per_page=1&prerelease=true`），**默认不启用**（零回归）。

### 5.5 前置依赖
- JS 版需 **node ≥24**（项目硬性要求，README 已写明）；不满足 → 明确报错。
- native 版升级：`--upgrade` 默认只升 JS 版（native 资产名平台相关 `fist-mbt-native-win-x64-*`），跨平台 native 升级本期不做（留接口）。

---

## 6. 判据与自证

### 6.1 纯逻辑白盒（`src/upgrade/upgrade_wbtest.mbt`）
| 用例 | 断言 |
|---|---|
| 0.3.8 > 0.3.7 | `cmp_version("0.3.8","0.3.7") == 1` |
| 0.3.8 == 0.3.8 | `== 0` |
| 0.3.8 < 0.10.0 | `== -1`（**十进位陷阱**：0.10 > 0.9，不能按浮点比） |
| "0.3.8-alpha1" < "0.3.8" | `== -1` |
| "abc" 解析失败 | `is_err` |

### 6.2 入口判据（扩 `cli_flag_probe.py`）
- `node fist-mbt.js upgrade --check` rc=0（**跑完**，不是可升级）
- `node fist-mbt.js upgrade`（无网络环境）rc≠0 且 stderr 明说「无法检测最新版本」
- `node fist-mbt.js upgrade --bogus` rc=2（用法错，BUG-106）
- **反向对照**：`upgrade --check` 在「本地=远端」时输出「已是最新」不误报

### 6.3 端到端镜像（扩 `e2e_mirror_install.py`，常驻判据）
镜像仓库（GitHub Pages 静态面，同 BUG-108 思路）里放 `v0.3.7` / `v0.3.9` 两版资产 + `releases/latest` 形状 JSON：
1. **升级成功**：装 v0.3.7 → `upgrade` → 变 v0.3.9，`$InstallDir\VERSION=="0.3.9"`，`fist-mbt.js.bak-0.3.7` 存在。
2. **已是最新不重装**：装 v0.3.9 → `upgrade --check` → 「已是最新」，**不下载**（判据抓「多一次下载」）。
3. **回滚**：镜像 asset 损坏（`PK` 魔数错误）→ `upgrade` 失败，`fist-mbt.js` 仍是 v0.3.7，备份未消费。
4. **无网络不假绿**：镜像不可达 → rc≠0，**绝不说「已是最新」**（R7 硬门）。
5. **VERSION 文件兼容**：装 v0.3.7 后**删掉** VERSION 文件 → `upgrade` 仍能靠 `node fist-mbt.js version` 反解出 v0.3.7（回退路径成立）。

### 6.4 一源四态
- 单真源：`moon.mod` 版本 + `install.ps1/install.sh/install_onecmd.ps1` 写 VERSION 行为。
- 四态（文档/CLI/插件/MCP）同步靠 `check_doc_surface.py` J4（注册表发布版本只在 BACKLOG 一处自述）+ J14（工具计数与 CLI 帮助分组和）。
- 若把 `upgrade` 做成 MCP 工具（`upgrade_check` / `upgrade_apply`），需同时入 `server.mbt` 注册表 + 描述 + 插件态（`gen_plugins.py`），并复跑 cl7。**本期建议只做 CLI**，MCP 面留作后续（MCP server 自己升级自己会「杀掉正在跑的进程」，语义别扭）。

---

## 7. 落地文件清单

| 文件 | 动作 |
|---|---|
| `cmd/cli/subcmd.mbt` | enum 加 `Upgrade`；`parse_subcmd` 加别名 |
| `cmd/cli/main.mbt` | 分发 `Upgrade => run_upgrade(args)`；新增 `run_upgrade` |
| `cmd/cli/upgrade_core.mbt`（新） | `cmp_version` 纯函数 + 检测/取物/验证/回滚编排（JS extern 走 net/fs） |
| `cmd/cli/subcmd_wbtest.mbt` | 补 `upgrade`/`--upgrade`/`-U` 解析锁 |
| `src/upgrade/upgrade_wbtest.mbt`（新） | 版本比较白盒锁（§6.1 表） |
| `cmd/cli/help_topics.mbt` | `help install` 补 upgrade 说明；`list_topics` 增 `upgrade` 条目 |
| `scripts/blackbox/install.ps1` / `install.sh` / `upgrade_install.ps1` | 装完后写 `$InstallDir\VERSION` |
| `scripts/blackbox/e2e_mirror_install.py` | 扩 §6.3 五格 |
| `scripts/cli_flag_probe.py` | 扩 §6.2 四格 |
| `scripts/README.md` | 登记 e2e_mirror_install 新增格子（`check_scripts_index` 依赖） |
| `docs/2026-10-11-fist-upgrade-design.md` | 本设计 |

**不碰**：`server.mbt`（除非做 MCP 工具，本期不做）、`src/store/`、`moon.mod`、并发 WIP 文件。

---

## 8. 失败路径与预案

| 场景 | 行为 |
|---|---|
| 无网络 / API 429 / 超时 | rc≠0 + 明说「无法检测」，**不说已是最新** |
| GitCode 也失败 | 同上（双源都失败=确定不可升级，非重试问题） |
| node <24 | rc≠0 + 明说版本要求 |
| `project_version != moon.mod` | rc≠0 + 明说「自身版本声明不可信」（BUG-114 锁） |
| 下载到 404 / HTML 页 / 非 `PK` | rc≠0（R6：HTTP 200 ≠ 拿到文件），不重试 |
| 传输层抖动（连接被重置） | 按 R12/R14 双栈重试 + 退避 |
| 换入时文件被占用（server 在跑） | rc≠0 + 提示先停 server |
| 换入后自检失败 | 还原 `.bak-<L>`，rc≠0 |
| 本地超前（dev 构建 0.3.9，远端 0.3.8） | rc=0 + 提示「本地超前，未动作」 |

**预案（不可逆边界）**：`--upgrade` 会**写文件、换二进制**——按 AGENTS.md「不可逆操作只给方案+预案，执行权留指挥官」。本设计只做设计，**实现须指挥官批准后**再动工；且先落地 `--check`（只读），`--check` 稳定后再开 `upgrade`（写盘）。

---

## 9. 分阶段实施建议

1. **阶段 1（只读，低风险）**：`fist-mbt upgrade --check`——检测+比较，不下载不写盘。落地即有价值（用户一眼知道「有 v0.3.9 可升」）。
2. **阶段 2（写盘）**：`fist-mbt upgrade` 真升级，复用 `upgrade_install.ps1` + 备份 + 自检 + 回滚。
3. **阶段 3（可选）**：`--channel pre`、MCP 工具面、native 跨平台升级。

**建议先做阶段 1**，它零写盘、零风险，且立刻让 `fist-mbt version` 之外的「有没有新版」这一问有答案。

---

## 10. 实施记录 · 阶段 1（`--check` 只读）已落地

**已实现（2026-10-11，本机实测）**：

- 新增 `cmd/cli/upgrade_core.mbt`（纯逻辑，双 target 通用）：
  - `parse_version` → `Option[(major, minor, patch, is_pre)]`（容忍 v 前缀 / pre-release / build 后缀；`is_pre` 区分 `-alpha1`）
  - `strip_suffix` / `has_pre_release` / `parse_num`（手写 digit 循环，核心无 `parse_int`）
  - `cmp_version(a,b) -> Result[Int,String]`：按 3 元组数值比较；pre-release 排同号正式版之下；解析失败回 `Err`（**绝不回 0 假绿**，R7）
  - `latest_tag(repo, timeout_ms)`：**只透传** `upgrade_fetch_latest`（后者已完成 `{ok,tag,error}` 解包，避免二次解析）
- 新增 `cmd/cli/upgrade_js.mbt`：`js_fetch_latest`（Node 原生 `fetch` + `AbortController` + `finally clearTimeout`，`releases/latest` → `tag_name` 去 v）+ `upgrade_fetch_latest`
- 新增 `cmd/cli/upgrade_native.mbt`：`upgrade_fetch_latest` stub 返 `Err`（native 无 fetch，绝不假绿）
- 新增 `cmd/cli/upgrade_wbtest.mbt`：upgrade-1（`0.10.0 > 0.9.0`，防浮点陷阱）/ upgrade-2（v 前缀 + pre-release + build）/ upgrade-3（不可解析 → Err）
- `cmd/cli/subcmd.mbt`：`Subcmd` 增 `Upgrade`；`parse_subcmd` 认 `upgrade`/`--upgrade`/`-U`
- `cmd/cli/main.mbt`：`run_upgrade(args)` 分发；rc 契约 0=跑完 / 2=用法错（BUG-106）/ 3=拿不到远端或不可比较
- `cmd/cli/moon.pkg`：增 `moonbitlang/core/json` 导入 + `targets` 路由 js/native 两文件
- **顺带修一处真漂移**：`cmd/cli/help_topics.mbt` 的 `FIST_VERSION = "0.3.6"` 硬编码落后 moon.mod(0.3.8)，改 `fn fist_version()` 动态取 `@server.get_version()`（BUG-114 同族，`cli_flag_probe.py` 抓出）

**实测结果**：

- `moon check --target js` / `--target native`：均无 error
- `moon test --target js cmd/cli`：**5/5**（3 条 upgrade + 既有）
- `moon test --target js`（全量）：**731/731**
- 端到端 `node cli.js upgrade --check` → **rc=0**，输出「本地已装 v0.3.8 / 远端最新 v0.3.5 / 本地超前（可能是 dev 构建），未动作」
- `node cli.js upgrade --bogus` → **rc=2**（用法错，BUG-106）
- `node cli.js --upgrade-xxx` → **rc=2**（未知子命令，不被吞成 upgrade）
- `scripts/cli_flag_probe.py` → **PASS**

**遗留**：

- 阶段 2（`fist-mbt upgrade` 真写盘换二进制）**待指挥官批准**——按 AGENTS.md「不可逆操作只给方案+预案」
- native target 的 `--check` 在真机上回 rc=3 + stub 文案（本机 native 无 fetch，未实跑）
- GitCode fallback（`--channel` 等）留阶段 3
- `check_plugin_sync.py` 本轮红：真源 `src/server/server.mbt` 在并发 agent 手上做半成品，插件态投影漂移——**非本阶段代码所致**（本阶段只改 `cmd/cli/`，不进 gen_plugins 源面）

---

## 来源

- 子命令真源：`cmd/cli/subcmd.mbt` / `cmd/cli/main.mbt` / `cmd/cli/subcmd_wbtest.mbt`
- 安装器真源：`scripts/blackbox/install.ps1`（L77-201 下载/解包/shim/PATH；无 VERSION 写入）
- 升级安装器：`scripts/blackbox/upgrade_install.ps1`（tracked 真源，`-BaseUrl`/`-Force`/`-NoPath`）
- 版本源：`moon.mod` `version="0.3.8"`；BUG-114 常驻白盒锁 `src/server/fist-mbt_wbtest.mbt`
- 发布/安装硬化：`check_release_asset_names.py`、`scripts/blackbox/e2e_mirror_install.py`、`e2e_irm_line.py`、`e2e_transport_stack_fallback.py`（R5-R14）
- 判据入口：`scripts/cli_flag_probe.py`（BUG-106/114 入口锁）

---

## 附：BUG-E 发布工程收口（2026-10-11，方案①落地）

阶段 2 初版把升级安装器放在 `_release/js/install_onecmd.ps1`，但该路径被 `.gitignore` 忽略、且 `build_release.ps1` 清空 `_release/` 后不重新生成 ⇒ 干净 clone / 干净 release 构建后生产 `fetch_installer` 必 404（**BUG-236**）；强制重装又会删掉换入前刚写的 `.bak-<v>`（**BUG-235**）。

收口（指挥官批准方案①）：安装器提升为 **tracked 真源 `scripts/blackbox/upgrade_install.ps1`**（纯 ASCII；R1 空 Version exit 1；R6 PK+HTML 嗅探；R12 只重试传输层；R7 自检**判真回执非空**后才写 VERSION；强制重装 `-notlike 'fist-mbt.js.bak-*'` 保备份）。`fetch_installer` 改指 tracked 双源（GitHub/GitCode master raw）+ BaseUrl 形；e2e 镜像同步服务真源 + `/-/releases/download/vX/...zip`；新增常驻守卫 `check_upgrade_installer.py`（G1 跟踪面 / G2 零旧引用 / G3 纪律针，含 --selftest）并登记 ci.yml JS 轨硬步骤。旧 `_release/js/install_onecmd.ps1` 退役留底于 `temp/retired-install_onecmd.ps1`。

实测（指挥官独立终审，无并发独占跑）：`check_ps_encoding` PASS / 守卫 --selftest 与全量 PASS / `check_scripts_index` PASS / `moon check` js+native 0 errors / **e2e 五格 5/5 PASS**（沙箱清场、PATH 还原、真产物 sha256 before=after=`2213aa9b`）/ 全量 `moon test --target js` 742/742 failed:0 / `upgrade --check` rc=0、`--bad` rc=2（BUG-106 保留）。BUG-235/236 已入 `memory/bugs.md` 并 `### FIXED`。