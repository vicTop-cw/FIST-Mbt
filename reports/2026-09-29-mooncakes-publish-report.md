# 2026-09-29 · 发布到 mooncakes（0.3.4 → 0.3.5）收口报告

> 触发：owner 追加指令「再确认一遍，确保都搞定了，然后发布到 moonbitlang」。
> 本轮两次发布：**0.3.4**（收口态首发，2026-09-29T09:26:54Z）→ 发现同号两树（BUG-128）→ owner 选出路① →
> **0.3.5**（2026-09-29T10:35:10Z，注册表当前 Latest）。
> 本报告只记这一轮；终审面（缺陷清零、demo 可用、开发文档合规）见 `2026-09-29-final-review-prep-report.md`，
> 那份的身份仍钉 `a0dfef3`，本轮不回改它的事实、只在 §7 那格加了指向本报告的追记。

---

## 1. 结果摘要

| # | 主张 | 实测 | 证据 |
|---|---|---|---|
| 1 | 发布前"都搞定了"是真的 | `moon test --target js -j 1` = **572/572**、`moon info`/`moon fmt` no work（190 tasks）、台账 **0 条待修**（`BUG-1~129 共 128 条入账：0 待修 / 115 已修 / 9 重复并入 / 4 误报`，口径 = 仓内现成计数器 `gen_plugins.py`） | `temp/v35_js_test.log`、`temp/v35_info_fmt.log`、`memory/bugs.md` 抬头 |
| 2 | 注册表上现在是**最新码**且**版本号能分辨** | `moon view vicTop-cw/fist-mbt --versions` = 10 版，首位 `0.3.5`；`Latest: 0.3.5 / Published 2026-09-29T10:35:10.876305+00:00`；三处版本真源（`moon.mod` / `server.mbt::project_version` / `help_topics.mbt::FIST_VERSION`）逐字 == `0.3.5`（R11 + 白盒锁） | 本轮 `moon view` 回执；`scripts/check_release_asset_names.py` R11 |
| 3 | 别人拉这一版**编得动**（不是"注册表列出了号"） | 空壳消费工程 `moon add vicTop-cw/fist-mbt@0.3.5` 后 `moon check --target js` **rc=0（58 个任务）** | `temp/pkg_install_probe/check*.log` |
| 4 | **公开的就是我 tag 的**（BUG-128 的根因那一格） | 解包载荷 **552 件** vs `git ls-tree -r 124a20a` 非点号跟踪面：双向差集 **0/0**，逐件比字节（仅归一 CRLF）**0 处不一致**；载荷内 `__cli_pkg.mbt.tmp` = **0 件**（BUG-127 的修在下一版兑现）；凭据形状扫载荷 **0 命中** | 本报告 §3.3 |
| 5 | 收口面在新版本上仍成立 | §3.4 那张表 **15 行 / 表内 17 次调用**逐条 rc=0（`check_*` 13 个，doc_surface 与 release_asset_names 那两行各含"自检 + 全量"两步；另有 `mcp_tool_tour --surface-selftest` 与 `store_isolation_probe`），探针那行按**两个产物身份**实跑 2 次 ⇒ 累计 18 次 | 本报告 §3.4 |
| 6 | 两线合上：GitHub 侧也有能装的 0.3.5 | owner 授权后 `master`+`v0.3.5` 推到 **GitHub + GitCode**（fast-forward，`ahead` 归 0）；`release.yml` run 36648312524 = meta/build-js/release success，Release `v0.3.5` published 2026-09-30T00:03:17Z、资产 `fist-mbt-js-v0.3.5.zip` **376617B**（与 v0.3.4 那发的资产数量/形状一致）⇒ §3.5 那条"公网线指旧码"的实测从此反转，见 §3.7 | §3.7 + `temp/rel_035.json` |
| 7 | 两条 owner 裁决都落在文档面，**注册表未被误伤** | ① `moon deprecate --dry-run` 实测作用域 = **整模块 10 版全标（含 0.3.5）** ⇒ owner 选**不动 0.3.4**，限制写进 USAGE §10 第 4 步；② push 后新增两笔是纯文档（`.mbt`/`moon.mod` 0 差异）⇒ owner 选**不发 0.3.6**，包内文档落后这一格记为已知边界（§6 第 2b 行） | 本报告 §3.7 / §6 |

一句话：**发上去了，且发的是当前码；代价如实付在了版本号前进一格上。**

---
> **追记（cl7 回归轮，2026-09-30T01:01:18Z）**：第 1 行那句「台账 0 条待修」是**发布当时**的读数，保留不覆写。
> 当日其后新入账两条：**BUG-130**（CI 的 native 门自 09-28 起持续红，OPEN 等 owner 选门）与
> **BUG-131**（**我这次 push 把 `Plugin-form guard cl7` 推红了**，本机却绿——由权威 CI 抓到、当轮自修并转正，见 §3.8）。
> 现口径 = **BUG-1~131 共 130 条入账 = 116 已修 / 9 重复并入 / 4 误报 / 1 待修（BUG-130）**。


## 2. 这一轮挣到的是什么（不是复述上一轮）

- 0.3.4 那一发让「打包面 ≠ git 跟踪面」这一格**第一次可观测**：`moon publish` 打的是**工作树 − `.gitignore`**。
  这道缝此前 12 个守卫没有一个认领 ⇒ 当场入账 **BUG-127**（修 ignore 面）与 **BUG-129**（把对表做成常驻第 13 个守卫
  `scripts/check_publish_payload.py`）。
- 0.3.4 那一发又让「本地 tag ≠ 注册表载荷」暴露 ⇒ **BUG-128**：同一版本号对应两份码，而 `fist version` 只回版本号，
  用户无法分辨。这是 BUG-114（源码常量落后 moon.mod）的**另一面**——那次是"版本号说低了"，这次是"版本号不够用了"。
- 0.3.5 那一发把 USAGE §10 从"dry-run→publish→读回"三步升级成**四格**：新增「重试纪律」与「树身份对表」。
  两条都是**实测踩出来的**，不是补写的（见 §3.1/§3.3）。

---

## 3. 实测账

### 3.1 发布序列（两次尝试，逐字引用）

| 步 | 命令 | 回执（原文） | 处置 |
|---|---|---|---|
| 1 | `moon publish --dry-run` | `Server status: 202 Accepted, detail: Dry run completed successfully. No changes were made. The dry-run was made for package vicTop-cw/fist-mbt version 0.3.5.` | 通过 |
| 2 | `moon publish`（第 1 发） | `Check passed` 之后 `request or response body error for url (https://mooncakes.io/api/v0/publish): send failed because receiver is gone` + `Error: \`moon publish\` failed`，`PUBLISH-RC=127` | **不盲目重试**：先 `moon view --versions` 读回 = 仍 9 版、无 0.3.5 ⇒ 确认没收下 |
| 3 | `moon publish`（第 2 发） | `Check passed` → `Server status: 200 OK` | 成功；注册表读回 10 版 / `Latest: 0.3.5` |

失败那一发与 BUG-116/125 是同一类（本机链路 TLS/连接抖动），但**方向相反**：zip/资产下载可以对确定性结论（404/403）换源，
而上传不能——版本不可覆盖不可撤销，"以为没发出去"就重发会吃 409，真发出去却以为没发会烧号。所以重试前置动作是**读回注册表**，
这一条已写进 `USAGE.md` §10 第 2 步。

### 3.2 版本自述面（R11/R13/J3/J4/cl7）

- 三真源相等：`moon.mod version` == `src/server/server.mbt:566 let project_version` == `cmd/cli/help_topics.mbt:4 const FIST_VERSION` == `0.3.5`。
- 调用面自证：`scripts/cli_flag_probe.py` 起真产物 `node cli.js version` 回显 `0.3.5`；真 RPC 响应文本内 `0.3.5` 出现 3 次、`0.3.4` 0 次。
- README 离线线 `fist-mbt-js-v0.3.5.zip` 字面量随 R13 同步；注册表发布版本自述**只**在 `BACKLOG.md`（J4）。
  本轮 J4 打回过我一次：我给 `scripts/README.md` 写的 `check_publish_payload` 条目里带了注册表版本号 ⇒ 第二处自述即红。
  这不是误伤：本轮之前**没有复核通道**（WebFetch 被策略拦过），两处自述只能互相打架。
- 插件态重投影 + cl7 逐字节：`PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.5`。

### 3.3 发布后载荷对表（USAGE §10 第 3 步，含树身份）

```
payload = .mooncakes/vicTop-cw/fist-mbt        552 件
git ls-tree -r 124a20a（剔点号条目）            552 件
只在包中 0 / 只在树中 0
逐件比字节（CRLF 归一后）                       0 处不一致
__cli_pkg.mbt.tmp 命中                          0
凭据形状（守卫 SECRET_RE 口径）扫载荷            0 命中
```

关于"凭据形状"那一格要如实交代过程：我先前用一条宽松的 `grep -E` 扫载荷，报了 2 个文件
（`memory/2026-09-27.md`、`scripts/check_publish_payload.py`）；换成守卫自己的 `SECRET_RE`（带 `{16,}` 长度地板）
对载荷复扫 = **0 命中**，那两处一是散文里写"扫过 token 形状（命中 0）"、一是 `SECRET_RE` 的模式文本本身。
**宽松口径的假阳与守卫口径的真阴不能混着报**，所以这条主张的证据是后者。

### 3.4 守卫族复跑（0.3.5 树上，逐条 rc）

> 这张表自带口径：**15 行 / 表内 17 次调用**（`check_*` 13 个；`check_doc_surface` 与 `check_release_asset_names`
> 各占一行但跑了两步"自检 + 全量"），`store_isolation_probe` 那行按两个产物身份**实跑 2 次** ⇒ 累计 18 次。
> 上一版这里写的是"守卫族 14 项"——那个数既数不出表体、也没算自检步，属于「范围数字本身就是主张」（J10 同型）。

| 判据 | rc | 结论行（尾部原文） |
|---|---|---|
| `check_tools_sync` | 0 | `PASS 工具单一真源一致：server.mbt 注册 129 个，AGENTS/README/deliverable/scoring_rubric 对齐` |
| `check_test_sync temp/v35_js_test.log` | 0 | `PASS 测试总数单一真源一致：实测 572；扫描现状面 107 份文档，24 条声明全部等于实测` |
| `check_test_sync --selftest` | 0 | `SELFTEST PASS 8 个变体各自命中自己指名的判据（计数由 run_case 实测累加，非手写）` |
| `check_badge temp/v35_js_test.log README.md` | 0 | `PASS 自检注释一致：README 『→ Total tests: 572, passed: 572』 == 实测 572` |
| `check_scripts_index` | 0 | `PASS 工具类辅助代码单一索引完整` |
| `check_plugin_sync`（cl7） | 0 | `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.5` |
| `check_doc_surface --selftest` / 全量 | 0 / 0 | `SELFTEST OK: 真源解析到 129 个工具，J4/J6/J7/J8/J9/J10 对合成违例均发红` / `PASS 文档面一致：… 当前自述版本=0.3.5 …` |
| `check_store_tables_wired` | 0 | `PASS store schema 接线一致：12 张表 = 11 张有写入点 + 1 张显式预留（runs）` |
| `check_demo_isolation` | 0 | `PASS spawn 面隔离一致：29 个脚本 spawn \`serve\` 时都把 FIST_DB_PATH 交给了子进程（显式子句 2 项 + 豁免 1 项锚点均成立）` |
| `check_ps_encoding` | 0 | `PASS PowerShell 编码守卫：6 个 .ps1 全部带 BOM 或纯 ASCII` |
| `check_entry_paths` | 0 | `PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个（扫描面 130 份文件，历史面与守卫自身除外）` |
| `check_release_asset_names --selftest` / 全量 | 0 / 0 | `SELFTEST OK（干净不误红 + 变异必红；清单从已执行格子反解：R1×2 / … / R14×5）` / `PASS 分发面同源（判据范围从正文反解：R1–R14）` |
| `check_publish_payload`（新） | 0 | `PASS 发布载荷面干净：将随包公开 552 件，其中未被 git 跟踪的 0 件（另有 18 件点号条目 moon 本来就不打包）` |
| `mcp_tool_tour --surface-selftest` | 0 | `SURFACE-SELFTEST: OK —— 12 支（10 违例 + 1 干净 + 1 自拒），不符 0 支` |
| `store_isolation_probe` | 0 | `PROBE: GREEN —— 2 格中红 0 格`（**两个身份各跑一遍**：安装态 `fist-mbt.js sha256:616b7632`；`FIST_PROBE_JS` 指本地 0.3.5 产物 `sha256:11355248`） |

**两条我一开始跑错、不是回归的记录**（写下来防下轮重踩）：`check_test_sync` 与 `check_badge` 都要**接测试日志参数**
（CI 里传 `/tmp/moon_test.log`）。我第一次不带参数跑，两条各回 `rc=1`（`FAIL 无法从参数/日志解析测试总数` / 空输出）——
那是调用姿势错，补上 `temp/v35_js_test.log` 后双双 rc=0。**判据红先怀疑尺子怎么被用的，再怀疑被测。**

上表 `check_publish_payload` 那行的原文取自**发布那一刻**的扫描。这个数是**跟着文档面走的活值**：
`124a20a` 上 552 → 本报告落盘后 553 → 再补 `memory/2026-09-30.md` 后 554，**三次 rc 都是 0**，
且「未被 git 跟踪的」始终 **0 件** ⇒ 判据锁的是"别把本地残留带上车"那一维，不是某个数。
引用时要么带时刻，要么带规则；单写一个 552 就是在造一颗下一轮就红的定时漂移雷（BUG-126 同型）。

### 3.5 公网安装线：把"未 push 的后果"从推断改成实测（`e2e_irm_line.py`，两档沙箱）

复核对 §6 第 1 行做了一次真跑（沙箱档，不碰 `--real`、不动真用户产物）——**它红了，而且红得有信息量**：

```
主档   （irm / .NET）      ：FAIL·链路侧 无法连接到远程服务器；n/a(传输层)；（安装器收尾汇总，属后果不是病因：下载全部失败）
兜底档 （curl.exe / Schannel）：FAIL·确定性 输出无可识别诊断、判据针未命中：回执缺 '0.3.5'（版本从 moon.mod 反解）
  FAIL 沙箱里 fist version 不是 0.3.5：探针回执='…/irm-sandbox-fallback/User/.local/bin/fist\nFIST-Mbt v0.3.4\n(moon.mod version 单一真源)\ndoctor=0'
curl.exe 对照（同一时刻、同一 URL）｜ exit=0 ｜ HTTP=200 bytes=16011 首字节=EFBBBF23
IRM-E2E-RC=1
```

三格读数分开说：

- **兜底档是"确定性红"**：脚本取回来了（16011 字节、带 BOM、`-File` 跑通、`doctor=0`），安装也**真装成了**——
  装成的是 `FIST-Mbt v0.3.4`。⇒ 「公网那条线今天给的是旧码」这一格**不再是推断**，`fist version` 的回执就是量场。
  病因是 **GitHub 侧未 push**：raw master 的 `moon.mod` 还写 0.3.4，安装器的版本单一真源正是从那里反解的（R1）。
- **主档是"链路侧红"**（BUG-116 那一类），按 R12 的规矩单列、不与确定性混报，也**不**因为兜底档绿了就免印。
- **这条在 CI 里是观测臂**（`continue-on-error: true`），不拦整条流水线；push `master` + 发 `v0.3.5` 的 GitHub Release 资产后，
  两档的针（`0.3.5` / `fist-mbt-js-v0.3.5.zip` / `fist (PATH)` / `POSIX shim, LF`）才可能对得上。
  ⇒ 这就是 §6 第 1 行那句"公网线仍指旧码"的**可复跑版本**，owner push 完可以直接拿这条当验收判据。

### 3.5b push 之后同一判据复跑：这条红现在**归因到链路**，两栏都干净地分开

push + Release 到位后再跑一次同一份 `e2e_irm_line.py`（沙箱档，`temp/irm_after_push.log`，`IRM-E2E-RC=1`）：

```
主档   （irm / .NET）      ：FAIL·链路侧 无法连接到远程服务器；n/a(传输层)；（安装器收尾汇总，属后果不是病因：下载全部失败）
兜底档 （curl.exe / Schannel）：FAIL·链路侧 无法连接到远程服务器；n/a(传输层)；（同上）
curl.exe 对照（同一时刻、同一 URL）｜ exit=56 ｜ HTTP=000 bytes=0 ｜ curl: (56) Recv failure: Connection was reset
```

与 §3.5 那次（push 前）的区别要说准：那次兜底档是**确定性红**（拿得到脚本、装成了 `v0.3.4`）；
这一次两档都归 **链路侧**，且脚本自己在同一时刻贴出 `curl` 对照 `exit=56 / HTTP=000`——本机走系统代理时
`raw.githubusercontent.com` 正在被重置连接（BUG-116 的原始形状），**不是** Release 资产缺失。
⇒ 所以这条判据此刻**不能**当"push 后两线已合上"的验收证据；那个结论另有独立证据：
GitHub API 读回 Release `v0.3.5` 已 published、资产名与大小都在（§3.7 + `temp/rel_035.json`）。
**（这一格随后由 §3.5c 第三次复跑取到绿而闭合；上面两段留作过程——它们记录的是「判据当时不能当验收」这个判断本身成立，不是最终状态。）**

**取证侧又踩的一手（也说清）**：这次读日志早于进程退出，看到 71 字节的 `started=` 行就判"后台 stdout 被回收"，
实际是**块缓冲到退出才刷**——进程结束后同一份文件长成 7504 字节并带 `IRM-E2E-RC`。
我当场用 `Get-Process python` 查活体没查到，那一条读数也不可信（同机 Windows Store 的 `python` 别名会换进程名）。
**修法**：要么 `-u` 无缓冲跑，要么判活看"有没有新的子进程 spawn"，别拿日志字节数当存活信号（本仓旧坑重现，这次是我自己踩）。

同一判据在无缓冲下又跑了一次（`temp/irm_after_push2.log`，`ended=2026-09-30T00:22:02Z`，`IRM-E2E-RC=1`），
两次合起来才是完整读数——**这次的红比第一次更有信息量**：

```
主档   ：FAIL·链路侧 基础连接已经关闭；接收时发生错误
兜底档 ：FAIL·链路侧 无法连接到远程服务器；n/a(传输层)（下载全部失败）
curl.exe 对照（同一时刻、同一 URL）｜ exit=0 ｜ HTTP=200 bytes=18795 首字节=EFBBBF23
```

- `curl` 对照同一刻对 **raw** 拿到 **200 / 18795 字节**（push 前那次是 16011 字节）⇒ **push 生效可证**：
  线上那份安装器已经是带 R14 的新版（124a20a 那批改的正是 `install_onecmd.ps1`，之前从未上过远端）。
- 但前两次取 **zip 资产**那一段仍在传输层被断（raw 通、release-assets CDN 不通）。按 R12 的规矩，
  这两次**不能**当验收，也不据此宣布产品红。

### 3.5c 第三次复跑：两档全 PASS ⇒ 公网线这格从"已发布"升级成"判据已验收"

`temp/irm_after_push3.log`（`started=…` 身份行这次用 `>>` 追加保住了，`IRM-E2E-RC=0`，`ended=2026-09-30T00:24:04Z`）：

```
主档   （irm / .NET）      ：PASS
兜底档 （curl.exe / Schannel）：PASS
  目标版本 v0.3.5（来源：https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/moon.mod）
  尝试: https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v0.3.5/fist-mbt-js-v0.3.5.zip
  尝试: https://github.com/vicTop-cw/FIST-Mbt/releases/download/v0.3.5/fist-mbt-js-v0.3.5.zip
  0.3.5                    命中（版本从 moon.mod 反解）
  fist-mbt-js-v0.3.5.zip   命中（资产名与发布产物同源）
  fist (PATH)              命中（自检经 shim 出回执（BUG-109））
  POSIX shim, LF           命中（无扩展名 shim 门（BUG-105））
  沙箱 bash  …/User/.local/bin/fist | FIST-Mbt v0.3.5 | (moon.mod version 单一真源) | doctor=0
  取回的脚本 字节=18795 首4字节=EFBBBF23 sha256:5dec201f
```

⇒ **三次读数按序成立：红（确定性·指旧码）→ 红（链路侧）→ 绿（两档，装到 v0.3.5）**。
这条判据从"登记风险"变成"验收门"，且 §6 第 1 行的闭环不再是靠 GitHub API 的间接读数——
用户照 README 抄那一行，今天装到的是 **v0.3.5**，`fist doctor=0`，无扩展名 POSIX shim 也在。


### 3.6 复跑在 `0815c72`（发布后两笔文档提交之上）——数字没有老化

| 面 | 命令 | 回执 |
|---|---|---|
| 代码面是否动过 | `git diff --name-only 124a20a..HEAD` | 16 个文件**全是文档/投影**，`.mbt`/`moon.pkg`/`moon.mod` **0 个** ⇒ 572 那组数字与被发布载荷同源 |
| 全量测试 | `moon test --target js -j 1`（tree `0815c72`） | `Total tests: 572, passed: 572, failed: 0.` + `MOON-TEST-RC=0`（`temp/final_js5.log`，日志首行自带 `started=`/`tree=` 身份） |
| 格式门 | `moon fmt --check` | `Finished. moon: no work to do` `FMT-RC=0` |
| 看护跨进程 e2e | `scripts/blackbox/e2e_heartbeat_xproc.py` | `=== E2E-HEARTBEAT-XPROC PASS：8 格全绿（跨进程看护语义已锁） ===` + 基数门 `8/8` |
| 入口调用面 | `scripts/cli_flag_probe.py --selftest` / 全量 | 自检 7 支对照全按预期；全量 rc=0（版本旗回 `0.3.5`） |
| 各守卫自检 | `gen_plugins --check/--selftest`、`store_tables_wired/ps_encoding/entry_paths/publish_payload/release_asset_names --selftest`、`mcp_tool_tour --surface-selftest` | 逐条 rc=0（`temp/recheck_selftests.log`） |
| 整洁面 | `cleanup_artifacts.py --check`（**只读档**，不带 --check 的那版会删证据，本地不跑） | `DIRTY: 仓库残留 75 个根 .db + 121 个 temp/ 文件 + 0 个 scripts/ _ 临时脚本（共 196）`——**存量脏，非本轮引入**（终审准备报告 §7.4 已记；CI 那步是先清后查） |
| 不可见字符 | 对本轮改动的 7 份文件扫 `Cf/Cc` + ZWSP/NBSP/BOM | 命中 **1 处**：`memory/bugs.md:510` 里 `grep -rniE "\bruns\b"` 的两个 `\b` 被当年的 Python 串吃成 **U+0008 退格符**（引入者 `a3657a2`，非本轮）；已按字节断言还原为字面 `\b`（diff 恰好 1 行、+2 字节、行数不变），此处登记而不改口径 |


### 3.7 push 轮（owner 授权后）：两线合上，权威 CI 交出两条新读数

**动作**：`git push origin master` = `3d27271..c67bd19`（fast-forward，`ahead` 归 0）→ `git push origin v0.3.5`（`* [new tag]`）
→ 同两步再做给 `gitcode`（SSH pushurl 那条线，`The server may need to be upgraded` 只是 OpenSSH 后量子告警，推送成功）。
本地 `mooncakes-0.3.5` 与 `fist-final-review-20260929` **仍不外推**（沿用既有惯例：远端只挂 `v*`，非 `v` 标签是本地身份记录）。

**Release 侧实测（匿名 API，只 GET、不带凭据）**：

```
release.yml run 36648312524（head_branch=v0.3.5）：meta success / build-js success / release success
                                              build-native-linux failure / build-native-windows failure（两者都有 continue-on-error）
Release v0.3.5 published=2026-09-30T00:03:17Z  资产 = fist-mbt-js-v0.3.5.zip  376617B
对照 v0.3.4：published=2026-09-28T17:25:12Z     资产 = fist-mbt-js-v0.3.4.zip  372836B   ⇒ 资产形状与数量一致，native zip 两条版本号都从未上过
```

⇒ 公网那条线现在**有了能装的 0.3.5**；同一判据 push 后跑了三次：§3.5b 两次链路侧红、§3.5c 第三次两档全绿（§3.5 那条 push 前的「确定性红」读数保留不动，它记录的是当时线上确实指旧码）。

**权威 CI（`FIST CI — Build + Test`，run 36648283575，master）两条新读数**：

| job | 结论 | 关键差别 |
|---|---|---|
| `check + test (js, ubuntu)` | **success** | 含 `Format check`——09-28 那两次它还是红的（run 36463333299 / 36461416256），BUG-118 把格式门搬进权威 CI 之后今天首次转绿 |
| `check + test (native, ubuntu)` | **failure** | 红的只有一格 `Test (native, j=1)`；`Check (native)` success ⇒ **编得过、测试不过**。同一格在 09-28 两次 run 里同样红 ⇒ 不是本轮引入 |
| `nightly self-check` | skipped | 定时轨，push 不触发 |

这一格已**入账为 BUG-130（OPEN）**而不是划进"已知边界"：AGENTS.md 确实声明 native 非权威门槛，但 ci.yml 里这一步**没有** `continue-on-error` ⇒ 一条"设计上允许红"的门挂成了"会红且没人解释"的门（BUG-114 那句「红着没人读等于没锁」的 CI 版）。**【同轮追记，%s】这一段的两句要限定**：① 『只拿得到步骤名』写窄了——失败**退出码**匿名可取，路径是 `GET /repos/<owner>/<repo>/check-runs/<job_id>/annotations`，两个 native job 的 failure 级原文逐字为 `Process completed with exit code 255.`（`temp/bug130_annotations.json`）；② 『取不到』只对 **stderr 正文**成立（`/actions/jobs/<id>/logs` 确实 403）。另外把『CI』在匿名窗口内可见的 23 次运行逐 job 读过：最早三发（run#176 @ 09-28T00:59:43Z）三个 job 全红，native 那一格在窗口内**从未绿过** ⇒ 原句『自 09-28 起持续红』的下界要推到匿名可见的最早一发。

**定因我取不到，这一点也写进账**：匿名取 job 日志回 `403 Must have admin rights to Repository`，我在调用面只拿得到步骤名与结论；本机复现 native 要 sqlite-dev + MSVC 同会话（或 WSL），且与 CI 那台的失败形态不必然同因——所以不拿"本机跑绿"宣布关闭。出路三条（削权成观测臂 / 由有日志权限的人定因后修真因 / native 轨只留 workflow_dispatch）留给 owner，我不自行改门。

**两条 owner 裁决（同日）**：① **不给任何版本打 deprecate**——`moon deprecate --dry-run` 实测作用域是**整模块 10 个版本全标（含 0.3.5）**，`--undo` 也只能整模块一起清，用它换"单号消歧"会把最新号一起消音；这条限制已写进 `USAGE.md` §10 第 4 步。② **不发 0.3.6**——push 后多出的两笔提交是纯文档（`.mbt`/`moon.mod` 0 个差异），0.3.5 载荷的**代码面**与 master 逐字节相同；代价说清了：包内 CHANGELOG/plugins 文本落后于 GitHub 上的同名文档，这一格作为已知边界记录，不烧不可回收的版本号。

---

### 3.8 cl7 回归轮（自抓自修，含 CI 读数）：`Plugin-form guard cl7` 红→绿是同一步

**发现面不是本机，是 CI**：push 之后照口径拿权威 CI 当验收。§3.7 记的那发 js 轨 success 是 run 36648283575（@ `124a20a`）；
今天再读后续那发 **run 36650601254（@ `ec4c347`，我 push 上去的最后一笔文档提交）** 时，`check + test (js, ubuntu)` 已经变 failure，
唯一红格步骤名 = `Plugin-form guard cl7 (一源四态：四宿主插件目录==真源投影)`。
⇒ 这一格红是**我推上去的**（把本机残留的名字固化进投影那一笔就是 `124a20a`），不是既有边界；而本机复跑 cl7 一直 PASS ⇒ 按旧例先怀疑尺子的输入面。

**CI 等价面复现**（`git archive HEAD` 解到 `temp/cl7repro`，那棵树里没有本机残留）：

| 命令 | 本机工作树（修前） | CI 等价面（修前） | 两侧（修后） |
|---|---|---|---|
| `gen_plugins.py --check` | rc=0 | **rc=1**：4 份投影各差一行 | 两侧 rc=0 |
| `gen_plugins.py --selftest` | rc=0（旧四格） | rc=0（旧四格） | 两侧 rc=0（新五格） |
| `check_plugin_sync.py`（cl7） | rc=0 | rc=1（转抄 J1 漂移） | 两侧 rc=0 |

差的那一行是投影正文那句『MCP server 真源在仓库根 **X**（129 工具 / v0.3.5）』里的文件名：提交面 `X=.mcp.json`、
CI 面 `X=.mcp.dev.json`。根因机器可检：`gen_plugins.py` 与 `check_plugin_sync.py` 各写
`MCP_CANDIDATES = ('.mcp.json', '.mcp.dev.json')` 并取第一个存在的，而 `MCP_NAME = ROOT_MCP.name` 要写进投影正文 ⇒
取到哪一份由**本机磁盘上有什么**决定。仓库根那份 `.mcp.json` 是**未跟踪也未被 ignore** 的本机 MCP 连接器配置
（`git ls-files` 空 + `git check-ignore` 空 + `git status` 回 `??`，内容与跟踪真源逐字节相同，三份 sha256 前缀 `7a609527`）。

**修法与判据**：两处顺序改**跟踪面优先**——`MCP_CANDIDATES = ('.mcp.dev.json', '.mcp.json')`，
`.mcp.json` 降级为搬家前的别名兜底；`--selftest` 四格→五格（第五格在临时目录放两份候选、要求解析到 `.mcp.dev.json`，**期望值写死字面名**）；
`--check` 的 OK/FAIL 行与 cl7 的 PASS 行都打印取到了哪一份真源。
恒真判据那一手又犯了一次：第五格第一版写成 `if got != MCP_CANDIDATES[0]`，与实现同公式 ⇒
顺序打回旧口径照样绿；**反向对照**（内存里换回旧顺序重跑自检）才是要那把尺子，实测旧顺序 rc=2 双红。

**为什么现有守卫看不见**：`check_publish_payload`（BUG-127/129）的 P1 只管非点号件（点号条目 moon 本来就不打包）⇒
『点号 + 未跟踪 + 未忽略 + 同时是投影输入』这一格没人认领。对照面：`check_entry_paths` 会点名
『仓库根另有 N 份未入库 .py』——那姿势只覆盖 .py。这一型不泄漏、只让生成产物随机器变，**比泄漏难发现，因为开发机上永远是对的**。

**收口读数（匿名只读 API）**：

```
run 36652585906  workflow 『CI』@ 00e64bd
  job check + test (js, ubuntu)   conclusion=success
    step #13 Plugin-form guard cl7 (一源四态：四宿主插件目录==真源投影) = success   ← 本次的验收格
  job check + test (js, windows)  conclusion=success
  job check + test (native, ubuntu) conclusion=failure  · 红格 Test (native)      ← BUG-130，另案
run 36652585908  workflow 『FIST CI — Build + Test』@ 00e64bd
  js/ubuntu success · native/ubuntu failure(Test (native, j=1)) · nightly skipped
```

**同一步连读三笔 push**（每笔两个 workflow 各一发，匿名只读 API）：`00e64bd`（修复本体）→ run 36652585906『CI』
的 `step #13 Plugin-form guard cl7` **success**；`9545b58`（文档收口）→ run 36653233709『CI』#13 **success**、
36653233734『FIST CI — Build + Test』js/ubuntu success；`206a912`（读数追记）→ run 36653471185『CI』#13 **success**、
36653471311 js/ubuntu success ⇒ 不是一次性转绿。三笔的整体 conclusion 都是 failure，
唯一红格自始至终是 native 那一格（`Test (native)` / `Test (native, j=1)`）= BUG-130，不由本格顶掉。

⇒ 入账 **BUG-131** 并已 `bug_fix` 盖章 **FIXED**（`### FIXED(2026-09-30T01:00:35Z / BUG-131)`，抬头 `heading_changed: 1`）。
本机那份 `.mcp.json` **原样保留未动**——它是本机连接器在读的配置，删不删、要不要跟踪仍是 owner 的开放问题；
修完之后投影不再依赖它，所以留着也不会再让 CI 分叉。


## 4. 资源消耗

- 网络动作：`moon publish --dry-run` ×1、`moon publish` ×2（1 失败 1 成功）、`moon view --versions` ×3（含重试前置确认）、
  空壳工程 `moon add` ×1。**无凭据参与**——`moon publish` 用本机 moon 登录态，我不读取、不探测、不回显任何 key。
- 计算：JS 全量测试 1 次（572/572）、`moon info && moon fmt` 1 次（190 tasks）、消费者 `moon check --target js` 1 次（58 tasks）、
  守卫族 1 轮（含自检）、`store_isolation_probe` 2 次（两个产物身份）。
- 服务端调用账（本轮 RPC）：`report_bug`/`bug_fix` 共 **12 次**，按 `call_log` 表实测分库计数——
  `bug124-125.db` 4、`bug126.db` 2、`bug127-128.db` 3、`bug129.db` 2、`bug128-close.db` 1。
  这些行落在**各自隔离库**（spawn 时带 `FIST_DB_PATH`），根自举台账未被本轮写行；根账计数在 demo 审计里逐字核过
  （`tasks=1987 / call_log=6909` 不变，见终审准备报告 §4）。
- 会话侧：一次上下文压缩后接续；接续时先做"载荷 vs 树"身份复算，没有采信摘要里的 tag 指向。

---

## 5. 任务分配记录

- 本轮**未派子代理**：所有动作都是发布链路上的不可省略步骤（版本真源改动、发布、对表、账本收口），
  且都要指挥官本人终审——派出去只会多一层转述。按金条四这属于"亲自做"的那类（终审 + 不可逆动作只出方案）。
- 唯一的外部分派仍是上一轮挂着的 **task #15**（外部模板库抓手 4 补丁），仍在发起人处，未动。

---

## 6. 遗留风险与需要 owner 决定的事

| # | 事项 | 状态 | 需要谁 |
|---|---|---|---|
| 1 | ~~**没有 push**~~ **本日已闭合**：owner 授权后 `master` 与 `v0.3.5` 都推到了 GitHub 与 GitCode（fast-forward，ahead 归 0），Release 出到 `fist-mbt-js-v0.3.5.zip`（§3.7），且同一判据第三次跑到**两档全 PASS**、装到 `FIST-Mbt v0.3.5 / doctor=0`（§3.5c）⇒ 两线同号同码，这格有判据绿背书；`e2e_irm_line` 的 push 后读数在 §3.5 末尾 | 已闭合 | — |
| 2 | ~~**0.3.4 是否 deprecate**~~ **本日裁决：不动**。理由不是我原先写的那条，而是量出来的新事实：`moon deprecate` 作用域是**整模块全部 10 版（含 0.3.5）**，`--undo` 也只整模块清 ⇒ 换不到"单号消歧"，只会把最新号一起消音。限制写进 USAGE §10 第 4 步；0.3.4 那对 `v0.3.4`(af54d5e) / `mooncakes-0.3.4`(a0dfef3) 的树身份仍可一行命令对出来 | 已裁决并落文档 | — |
| 2b | **注册表载荷的文档面落后 GitHub**（owner 选"维持 0.3.5"，不烧 0.3.6）：0.3.5 包内 CHANGELOG 最新段仍是 `v0.3.4`、plugins 文本同落后，而**代码面**与 master 逐字节相同（`.mbt`/`moon.mod` 0 差异） | 已知边界，有意留 | 下一个真改动自然带走 |
| 2c | **BUG-130（新入账，OPEN）**：权威 CI 的 `Test (native, j=1)` 自 09-28 起连续三次红（`Check (native)` 绿 ⇒ 编得过测不过），且该步**没有** `continue-on-error`，与 AGENTS 声明的"native 非权威门槛"互相矛盾；匿名取不到定因（job 日志 403）。三条出路留在账里等 owner：降级成观测臂 / 有权限者取日志定因 / native 轨只留 dispatch。台账现 **129 条入账 = 115 已修 / 9 重复并入 / 4 误报 / 1 待修**（**追记：这一格的台账数已被同轮新入账的 BUG-131 顶掉，现口径见 2d 行；原文保留不覆写**） | 等裁决 | owner（门怎么改）|
| 2d | ~~**cl7 在 CI 上红（BUG-131）**~~ **本日自抓自修并转正**：插件投影引用的启动参数真源文件名由本机未跟踪残留 `.mcp.json` 决定 ⇒ 本机绿 / CI 红；改跟踪面优先 + 第五格常驻判据（反向对照 rc=2 可红）。CI 第 13 步 `Plugin-form guard cl7` 实测 success（§3.8）。现台账 = **BUG-1~131 共 130 条入账 = 116 已修 / 9 重复并入 / 4 误报 / 1 待修（BUG-130）** | 已闭合（判据在 CI 面读回） | — |
| 2e | **仓库根 `.mcp.json` 已按 owner 裁决走 ignore**：`.gitignore` 加**根锚定**的 `/.mcp.json`（裸形会盖住跟踪件 `plugins/claude/.mcp.json`）。实测：`git check-ignore -v .mcp.json` 命中新行、对 claude 那份无命中、`git status` 的 `??` 消失；文件本体仍在盘上供本机连接器读，投影无影响（BUG-131 后解析本就选 `.mcp.dev.json`） | 已闭合 | — |
| 2f | **BUG-132（新入账，OPEN）**：`fist-ci.yml:85` 的 `nightly self-check` 条件钉 `refs/heads/main`，而本仓默认分支是 `master`、全仓无 `schedule:` ⇒ 恒假死门；其最后一步也只是三条 `echo` 的 TODO 占位。与 BUG-130 同一裁决面（native 轨若降级，这条是唯一还剩的 native 巡检位）。出路三条在账里：改 ref / 补 schedule 并写实体命令 / 删作业 | 等裁决 | owner（两条一起选） |
| 3 | native 端本轮未复跑（沿用「权威稳定门槛 = JS 后端」的既有口径，不据旧数宣称双端同版全绿） | 如实留白 | 无需决定 |
| 4 | `store_isolation_probe` 默认优先命中**安装态产物**（本机那一份仍是上一版安装产物）；这是设计（探的是用户跑的产物），但意味着不带 `FIST_PROBE_JS` 时它不验新码。本轮两个身份都跑了 | 已记录 | 无需决定 |
| 5 | 发布版本号的**下一次**前进会再撞同一个缝：`v<版本号>` 标签与注册表载荷必须同树，目前靠我手工对表。已把"载荷 == 被 tag 的树"写进 USAGE §10 第 3 步，但没有常驻判据（要联网解包，CI 不该跑网络） | 已知缺口 | 下轮建议 |

---

## 7. 后续建议（按性价比）

1. ~~**push + GitHub Release 重做到 `124a20a`**~~ **本日已完成**：`master` + `v0.3.5` 推到 GitHub 与 GitCode，
   Release 资产 `fist-mbt-js-v0.3.5.zip` 到位（§3.7）⇒ 这条从"下一轮建议"变成"已闭合"。
   接手口径：以后这条线红了就跑 `e2e_irm_line.py`，按它分好的「链路侧 / 确定性」两栏读，别把环境当产品杀。
2. 给 `check_release_asset_names` 加 **R15**：Release 作业的资产名 ↔ **本地 tag 指向的树**（`git rev-list -n1 v$(moon.mod 版本)`）
   一致，且该 tag 必须存在——现在 R13 只钉"资产名字面量 == moon.mod"，钉不到"那棵树上有没有这个 tag"。
   这条是 §6 第 5 格缺口里**离线可判**的那半边，值得做。
3. `memory/` 的活体计数（tasks/call_log）与报告里的读数分离：演示与审计都让根账在长，任何写死数字的文档条目都会漂（BUG-126 同型）。

---

## 8. 超额内容（本轮顺手、不在指令内）

- `check_publish_payload` 的 **G1' 替换**：开发期新守卫自己必然未跟踪 ⇒ "干净不误红"这一支永远做不到；
  换成更强的不变式（红面与未跟踪面**双向对齐**、不许幻影红），而不是删门或放宽阈值。
- 载荷扫凭据那格：把守卫源码里的假 token 改成**运行时拼接**（第一版写字面量里，P2 当场打到守卫自己）。
- USAGE §10 补「载荷边界」18 件清单（点号文件/目录 moon 一律不打包）⇒ 从 mooncakes 装的人拿不到 `.mcp.json`，
  MCP 配置要自己写；此前 README 的 mooncakes 用法段没说这格。

---

## 9. 来源

- 注册表：`moon view vicTop-cw/fist-mbt --versions`（2026-09-29 11:2x 本机复跑，10 版、首位 0.3.5）。
- 证据文件（`temp/` 已 gitignore，**会被回收**；下表分"现存 / 已回收 + 再生命令"两栏）：
  - 现存：`temp/v35_info_fmt.log`、`temp/v35_build.log`、`temp/v35_js_test.log`、`temp/v35_dryrun.log`、
    `temp/v35_publish.log`（= 第 1 发失败，内含 `PUBLISH-RC=127`）、`temp/v35_publish_try1.log`（= 第 2 发 `200 OK`，
    **文件名与次序反着，别按名字读时间线**；两份的先后以 mtime 与本表为准：18:33 失败 / 18:35 成功）、
    `temp/v35_docs_selftest.log`、`temp/v35_docs_full.log`、`temp/v35_guard_sweep.log`、`temp/v35_guard_sweep2.log`、
    `temp/v35_isolation.log`、`temp/v35_isolation_local.log`、`temp/bug128_close_receipt.json`、
    `temp/bug128-close.db`、`temp/pkg_install_probe/**`（含 0.3.5 解包载荷）；
    **复跑那一轮（§3.5/§3.6，tree `0815c72`）**另存 `temp/final_js5.log`（首行 `started=… tree=0815c72` +
    `Total tests: 572 … MOON-TEST-RC=0`）、`temp/recheck_fmt.log`、`temp/recheck_selftests.log`、
    `temp/recheck_hb.log`（看护 8 格）、`temp/recheck_irm.log`（公网线两档分栏，`IRM-E2E-RC=1` 即 §6 第 1 行的实测）。
  - 再生命令：全量测试 `moon test --target js -j 1`；守卫单条 `python scripts/<name>.py [temp/v35_js_test.log]`；
    载荷对表 `moon add vicTop-cw/fist-mbt@0.3.5` → `find .mooncakes/vicTop-cw/fist-mbt -type f` ↔ `git ls-tree -r 124a20a --name-only`。
- 提交/tag：`124a20a`（0.3.5 载荷，`v0.3.5` 与 `mooncakes-0.3.5` 同钉）；`a0dfef3`（`fist-final-review-20260929`，不回改）；
  `af54d5e`（`v0.3.4`，与注册表旧载荷不同树，即 BUG-128 的正身）；收口三笔 `6a03093`/`0815c72`/`c67bd19` 与 push 轮这一笔都在 `master` 上，
  **已推送到 GitHub 与 GitCode**（`git rev-list --count origin/master..HEAD` = 0）。
- push 轮的对外读数（匿名只读 API，不带凭据）：`temp/api_jobs.json`（run 36648283575 逐 job/逐步骤结论）、
  `temp/api_hist.json`（branch=master 最近 8 次 run 结论，含 09-28 两次同型红）、
  `temp/api_joblogs.json`（403 `Must have admin rights to Repository` 原文）、
  `temp/rel_035.json`（Release `v0.3.5` 与资产清单）、`temp/rel_jobs.json`（release.yml run 36648312524 的 5 个 job 结论）。
  `e2e_irm_line` push 后三份：`temp/irm_after_push.log`（RC=1·两档链路侧红）、`temp/irm_after_push2.log`（RC=1·红，但同刻 raw 侧 curl 对照 200/18795B）、`temp/irm_after_push3.log`（**RC=0·两档全绿**，`started=`/`ended=` 双戳齐全）。
  BUG-130 的 RPC 回执：`temp/bug130_receipt.json`（`report_bug` → `BUG-130 / OPEN`，隔离库 `temp/bug130.db`）。
- 账本：`memory/bugs.md` 的 `### FIXED(2026-09-29T10:44:53Z / BUG-128)`（抬头状态位与 `bug_fix` 回执 `heading_changed: 1`）；
  日志：`memory/2026-09-29.md` 发布轮段。

**cl7 回归轮追加（2026-09-30T01:00:35Z）**：
- CI/远端读数（匿名只读，不带凭据）：`temp/cl7_ci_poll.log`（run 36652585906 / 36652585908 逐 job 与 **CL7 CELL 第 13 步结论**，
  `started=`/`ended=` 双戳）、`temp/cl7repro/`（修前 CI 等价面，`--check` rc=1 点名 4 份投影）、
  `temp/cl7ci3/`（修后 CI 等价面 = `git archive HEAD`，三步 rc=0）。
- 修复与判据：commit `00e64bd`（19 files, +116/−38，已 fast-forward 推 origin + gitcode）；
  `scripts/gen_plugins.py`（`MCP_CANDIDATES` 顺序 + 第五格）、`scripts/check_plugin_sync.py`（同顺序 + PASS 行打印真源名）。
- 账本：`memory/bugs.md` 的 `## BUG-131 ... FIXED` 与 `### FIXED(2026-09-30T01:00:35Z / BUG-131)`；
  RPC 回执 `temp/bug131-report.log`（`report_bug` → `BUG-131 / OPEN`）与 `temp/bug131_close.log`
  （`bug_fix` → `heading_changed: 1 / note_written: true`），两者都跑在隔离库 `temp/bug131.db` / `temp/bug131-close.db`。
