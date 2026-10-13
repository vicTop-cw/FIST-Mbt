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

**追加实测（2026-10-13，决定 owner 可选空间）**：同版 nightly 下
`moon check --target js` **rc=0** 而 `moon fmt --check` **rc=255**，且把 `Int` 改成 `Int32` 后 check **仍 rc=0**
⇒ **`check` 与 `fmt` 的标准不一致**（fmt 单方面要求规范化、check 两种都收）。
这意味着这不是"代码有错"而是"两把尺不同步"，owner 除"全仓重排"外还有**低风险落法**（见下方 A′ 三条）。

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

**A′. A 的低风险变体（2026-10-13 追加实测：`check` 与 `fmt` 的标准不一致）**：
WSL 同版 nightly 实测三支读数——`moon check --target js` **rc=0**（CI #271 亦实证 success）、
`moon fmt --check` **rc=255**（CI #271 实证 failure）、把 `Int` 改成 `Int32` 后 `moon check` **仍 rc=0**。
⇒ 新版 **`fmt` 单方面要求类型规范化（`Int`→`Int32`）、而 `check` 对两种写法都接受**——这不是"代码错"，
是两把尺的标准不一致。故 owner 的落法实为两条有效（第三条已证伪，见下），风险从低到高：
1. **降 fmt 门强度**（最低风险）：`moon fmt --check` 只作**信息步**（失败不阻断），并把
   「nightly fmt 与本地 fmt 标准不同步」写进步骤注释——保住守卫族（含 HTTP 契约自证等 24 步）继续跑，
   代价是 fmt 面暂时弱化；
2. ~~只对本次 diff 面 fmt~~ **已证伪（同版受控实验）**：`moon fmt --check` 的最小粒度是**包**不是文件
   （help 原文：`[PATH]` = "files **selecting their containing package**"；传 `codon.mbt` 实测输出列了
   `atgc-old` 整包四个文件）⇒ 存量文件散布多包内，按包检查仍被带红。
3. **全面 A**（最高风险但最彻底）：用 nightly `moon fmt` 全仓重排并提交，含 `Int→Int32` 的
   FFI 签名改动，提交前必须跑全量 `moon test --target js` 守 `Int32` 溢出类缺陷（本仓有 BUG-218 同族账）。
本报告只把落法与读数并列，**落哪条属 owner 裁决**（金条四：改共享 CI 定义与公共基线是"方案+预案"）。
> 注：`grep -icE "error"` 在 check 日志里数到 162 行，那是把 warning 文本里的 "error" 字样也算进去了
> 的噪声；判绿只按 **rc=0** 与 `moon check` 的汇总行，不按 grep 计数——写在这里免得后来者被那个数误导。

## 边界（不许读成"CI 全绿只差这一步"）

本轮已把**两颗同源雷**排掉：
1. **新版 moon 拒 `.mooncakes/moon.mod.json`**——迁移器挂进全部四个执行面（ci.yml js/native/windows +
   fist-ci js/native），CI 实证各臂 `Migrate` 步 success、windows 臂整个 job success。
2. **native 双臂 `Reapply BUG-133` 长期红**——本轮 WSL 实测定因为**步序错**（不是 nightly 不兼容）：
   `moon update` 之后 `.mooncakes` **根本不存在**（依赖惰性解包），reapply 找不到 `stub.c` 必 rc=1；
   而在能触发解包的 `migrate`（内含 `moon check`）之后，reapply rc=0、`--verify` rc=0。
   两处臂已改为 `migrate → reapply → check`，**CI #275 / #105 实证 native 臂全绿**
   （Migrate ✅ / Reapply ✅ / Check(native) ✅ / Native heap gate ✅）。
   ⚠️ 这条同时推翻了我同日早些时候写进注释的「migrate 须在 Reapply 之后」——注释已同步纠正，
   留这段记录防后来者再按那句反话改回去。

Format 是**当前唯一挡住守卫族（含 HTTP 契约自证那一步）的红**：CI #275 实证它一个步红就 skip 其后
**24 步**（Test(js) 到 Cleanliness guard 全没跑）。

**已就位的对策（`64101be`，本轮执行）**：把 **HTTP 契约自证步从第 25 位移到 `Check (js)` 之后、
`Format check` 之前**（只移我自己加的步，不碰 owner 面的 Format 门）。CI #277 实证新位置生效：
`Migrate ✅ → Check(js) ✅ → **HTTP contract self-proof ✅** → Format ✗`——该自证**首次在真实 runner 上
真跑通过**（此前它挂在 Format 之后，被 skip、从不执行；「挂了但没跑 = 没挂」）。
仍被 Format 挡住的是它**之后**的 22 步（Test(js) 与全部守卫族）——那部分要等 Format 门的落法定下来。

**A′ 第 2 条（diff-scoped fmt）经同版受控实验**证伪**（temp/fmt_scope_direct.txt + fmt_scope2_direct.txt）**：
`moon fmt --check <单文件>` 对**所有**文件都 rc=255；help 原文写明 `[PATH]` 是
「packages, files **selecting their containing package**」⇒ 传文件 = 检查它**所在的整包**，
最小粒度是包不是文件。实测传 `atgc-old/codon.mbt` 时输出列的是 `atgc-old` 整包四个文件。
且我上一轮"codon 无需改动"的读数本身有污染（那次测完未还原就接着测下一个文件）——
同版对照里 in-place `moon fmt atgc-old/codon.mbt` **确实改动了该文件**（"实为需要改动"）。
⇒ 存量文件散布在多个包内，按包检查仍会被带红 ⇒ 该路不可行，A′ 只剩第 1 条（降门）与第 3 条（全面 A）。
**这条自我纠错留档的原因**：我先前在报告里写"文件级 check 实测可行（atgc_base rc=0）"，
那是拿**本地老 moon** 的单文件读数去比 **nightly** 的整仓读数——不同版不可比，是同一条纪律
（判据的两支必须同版同环境）的反面教材。

## 来源
- WSL 实测：`temp/fmt_probe_direct.txt`（nightly moon `0.1.20261012` 逐文件 diff 原文）
- WSL 同版三读数：`temp/check_vs_fmt_direct.txt`（check rc=0 / fmt --check rc=255 / 改 Int32 后 check 仍 rc=0）
- WSL 镜像探测：`temp/mirror_probe_direct.txt`（本地 `~/.moon` 是 Windows 二进制、Linux 下不可执行）
- WSL 步序实测：`temp/reapply_order_direct.txt`（update 后 .mooncakes 不存在 ⇒ reapply rc=1；
  migrate 后 stub.c 出现 ⇒ reapply rc=0、verify rc=0）
- WSL fmt 粒度受控实验（同版 nightly）：`temp/fmt_scope_direct.txt`（整仓/单文件/无害文件三支全 255）、
  `temp/fmt_scope2_direct.txt`（help 原文 `[PATH]`=选所在包；实测传 codon.mbt 输出列 atgc-old 整包四文件；
  in-place fmt 证明该文件实需改动 ⇒ 我先前"无需改动"的读数有污染）
- CI 实证：#275 / #105 native 臂**全绿**（步序修正后）、js,windows success（迁移生效）、
  js,ubuntu `Format check` failure 且 skip 其后 24 步
- 版本事实：本地 `moon 0.1.20260920`；`cli.moonbitlang.com/binaries/<version>/` S3 403（钉版不通，
  复验 0.1.20260920 / 0.1.20261012 = 403、latest / nightly = 206）；安装脚本 `CLI_MOONBIT` 硬编码（L108）
- 归属：`git log -1` 显示 `atgc*` 两文件基线提交 `4cf2a41`、`subcmd.mbt` 最后提交 `2426a66` 且当前 ` M`
