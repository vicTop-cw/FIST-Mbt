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

一句话：**发上去了，且发的是当前码；代价如实付在了版本号前进一格上。**

---

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

---

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
| 1 | **没有 push**：本轮所有提交只在本地（含 `v0.3.5`/`mooncakes-0.3.5` 两个本地 tag）。公网安装线（GitHub raw/Release 的 `fist-mbt-js-v0.3.5.zip`）因此**尚不存在**，照 README 那条线装的人仍拿旧码；注册表这条线已是最新 ⇒ 两线短期"新码/旧码"并存，与 BUG-128 同形状但方向已知且已在账本写明 | 等授权 | owner（push + 发 GitHub Release） |
| 2 | **0.3.4 同号两树撤不回**：注册表版本不可覆盖。可选缓解 = `moon deprecate vicTop-cw/fist-mbt@0.3.4`（对外署名动作） | 等裁决 | owner |
| 3 | native 端本轮未复跑（沿用「权威稳定门槛 = JS 后端」的既有口径，不据旧数宣称双端同版全绿） | 如实留白 | 无需决定 |
| 4 | `store_isolation_probe` 默认优先命中**安装态产物**（本机那一份仍是上一版安装产物）；这是设计（探的是用户跑的产物），但意味着不带 `FIST_PROBE_JS` 时它不验新码。本轮两个身份都跑了 | 已记录 | 无需决定 |
| 5 | 发布版本号的**下一次**前进会再撞同一个缝：`v<版本号>` 标签与注册表载荷必须同树，目前靠我手工对表。已把"载荷 == 被 tag 的树"写进 USAGE §10 第 3 步，但没有常驻判据（要联网解包，CI 不该跑网络） | 已知缺口 | 下轮建议 |

---

## 7. 后续建议（按性价比）

1. **push + GitHub Release 重做到 `124a20a`**（或 owner 认可的下一个提交），让公网安装线与注册表同号同码——
   这是本轮唯一还会被用户直接撞到的面。
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
    `temp/v35_docs_selftest.log`、`temp/v35_docs_full.log`、`temp/v35_guard_sweep.log`、
    `temp/v35_isolation.log`、`temp/v35_isolation_local.log`、`temp/bug128_close_receipt.json`、
    `temp/bug128-close.db`、`temp/pkg_install_probe/**`（含 0.3.5 解包载荷）。
  - 再生命令：全量测试 `moon test --target js -j 1`；守卫单条 `python scripts/<name>.py [temp/v35_js_test.log]`；
    载荷对表 `moon add vicTop-cw/fist-mbt@0.3.5` → `find .mooncakes/vicTop-cw/fist-mbt -type f` ↔ `git ls-tree -r 124a20a --name-only`。
- 提交/tag：`124a20a`（0.3.5 载荷，`v0.3.5` 与 `mooncakes-0.3.5` 同钉）；`a0dfef3`（`fist-final-review-20260929`，不回改）；
  `af54d5e`（`v0.3.4`，与注册表旧载荷不同树，即 BUG-128 的正身）。
- 账本：`memory/bugs.md` 的 `### FIXED(2026-09-29T10:44:53Z / BUG-128)`（抬头状态位与 `bug_fix` 回执 `heading_changed: 1`）；
  日志：`memory/2026-09-29.md` 发布轮段。
