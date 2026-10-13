# 2026-10-13 · CI Format check 红的定因报告（nightly moon fmt 的 Int→Int32 规范化）

## 一句话结论

`Format check`（ci.yml / fist-ci.yml 的 js 臂）红**不是文件脏、也不是谁的 WIP 没格式化**，
而是 **CI 的 moon 是 `latest`（实测 nightly `0.1.20261012`）、本地是钉版 `0.1.20260920`，
两代 `moon fmt` 的类型规范化规则不同**：新版会把函数签名里的 `Int` 改写成 `Int32`。

WSL 实测（同 CI 版 nightly moon，`git archive HEAD` 干净副本，逐文件 `moon fmt` 后 diff）：
- `atgc/atgc_base.mbt`：`pub fn base_to_int(c : Char) -> Int?` → `Int32?` 等 3 处
- `atgc-old/atgc_base.mbt`：同形 3 处
- `cmd/cli/subcmd.mbt`：`const USAGE_ERROR_EXIT_CODE : Int = 2` → `Int32`、`fn exit_code_of(cmd : Subcmd) -> Int` → `Int32`、
  **`extern "js" fn js_try_exit(code : Int) -> Bool` → `Int32`（FFI 边界签名，改动有 ABI 含义）** 等 3 处
- 其余 6 个 CI 点名的文件 nightly fmt **零改动**（本地老版 fmt 也零改动，md5 不变 ⇒ 双向确认）

⇒ 本机 `moon fmt` 对这些文件"无改动"与 CI "报未格式化"**两者都正确**，差别只在工具链版本。

## 为什么不该由本轮顺手"修掉"

1. **`Int` → `Int32` 是语义改动不是格式**：本仓账本记过 `Int32` 溢出类缺陷（BUG-218 secs overflow 同族），
   `atgc` 的碱基编码运算、`subcmd` 的退出码虽都在安全值域，但批量改签名等于替整个仓做工具链升级决策。
2. **FFI 边界**：`extern "js" fn js_try_exit(code : Int)` 改 `Int32` 跨 JS 边界，需确认两端 ABI 期望。
3. **该面 owner 已在追这条红**：`cmd/cli/subcmd.mbt` 的最后提交 `2426a66` 标题即
   "style(mbt): 补 moon fmt 的形"，且该文件当前是 ` M`（并发会话未提交 WIP）⇒ 由它收口更安全。
4. **`atgc/atgc_base.mbt` + `atgc-old/atgc_base.mbt` 是已提交干净基线**（status 空、最后提交 `4cf2a41`），
   不是任何人的 WIP——但要改就是改公共面，需 owner 拍板（与 BACKLOG P0「async 0.22.x 升级」同族的决策边界）。

## 给出该面 owner 的可执行修复（二选一，均需 owner 裁决）

**A. 升级面（推荐，与 CI 的 latest 对齐）**：用 nightly moon（WSL `/root/moon-nightly` 或 CI 同源）
跑 `moon fmt`，接受 `Int` → `Int32` 的规范化并提交；提交前跑全量 `moon test --target js` 确认零回归
（`Int32` 溢出类缺陷的守门就是这条）。此后本地与 CI 的 fmt 面同源，这条红永久消失。
**B. 钉版本面**：把 ci.yml / fist-ci.yml 的 `Install MoonBit toolchain` 从 latest 钉到
`0.1.20260920`——**实测此路不通**：`cli.moonbitlang.com/binaries/<具体版本号>/` 一律 S3 403
（只有 latest / nightly 可取；2026-10-13 复验 0.1.20260920 / 0.1.20261012 均 403、latest / nightly 均 206），
且安装脚本 `CLI_MOONBIT="https://cli.moonbitlang.com"` 是**硬编码常量**（unix.sh L108，
不可环境变量覆盖）⇒ 无法指向自建镜像。详见 memory/2026-10-13「钉版证伪」段。
**B′. 自建镜像面（2026-10-13 追加实测，同样不通）**：本地 `~/.moon` 确有完整的 0.1.20260920
（544MB：bin/lib/include/registry/share），但它是 **Windows 二进制**——WSL 实测解包后
`bin/moon` 在 Linux 下 `No such file or directory`（Windows 的 `moon.exe` Linux 不可执行）。
要产出 Linux 版 0.1.20260920 tarball，得先有一台 Linux 机器装上该版本（而 WSL 里只能装到
nightly，官方不提供旧版）⇒ 镜像的素材本地不存在，除非另找一台机器提前装存档。
⇒ **实际只剩 A**。

## 边界（不许读成"CI 全绿只差这一步"）

本轮已把**另一颗雷**（新版 moon 拒 `.mooncakes/moon.mod.json`）在全部四个执行面排掉
（ci.yml js/native/windows + fist-ci js/native，迁移步 CI 实证 success、windows 臂整个 job success）。
Format 是**当前唯一挡住守卫族（含 HTTP 契约自证那一步）的红**，但它不是本轮引入、
也不是迁移器能修的——它是工具链升级决策，按金条四留在 owner。

## 来源
- WSL 实测：`temp/fmt_probe_direct.txt`（nightly moon `0.1.20261012` 逐文件 diff 原文）
- WSL 镜像探测：`temp/mirror_probe_direct.txt`（本地 `~/.moon` 是 Windows 二进制、Linux 下不可执行）
- CI 实证：#271 js,ubuntu `Format check` failure、#271 js,windows **success**（迁移步生效的对照）
- 版本事实：本地 `moon 0.1.20260920`；`cli.moonbitlang.com/binaries/<version>/` S3 403（钉版不通，
  复验 0.1.20260920 / 0.1.20261012 = 403、latest / nightly = 206）；安装脚本 `CLI_MOONBIT` 硬编码（L108）
- 归属：`git log -1` 显示 `atgc*` 两文件基线提交 `4cf2a41`、`subcmd.mbt` 最后提交 `2426a66` 且当前 ` M`
