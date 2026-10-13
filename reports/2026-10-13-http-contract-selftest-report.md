# 2026-10-13 · e2e_http_contract 补 --selftest 报告（判据先自证会红）

## 结果摘要

**一句话**：我先前挂进 CI 的 HTTP 契约自证（六臂）**自己没有自检**——本轮按本仓 BUG-50 明文纪律
（「判据必须先证明自己会红，否则它自己坏了也照报绿」）补了 **23 格 `--selftest`**，
并用**五处变异**证明它真会红；同时把判定抽成纯函数、把自证挂进 CI。

| 项 | 读数 |
|---|---|
| `--selftest` | **rc=0，23 格全过**（不起真桥、不碰网络/端口） |
| 变异实测 | **5/5 被抓住**（每处 rc=1 且点名对应格），还原后 rc=0 |
| 真桥全链（重构后） | **6/6 PASS**（A 端口 / B 163 工具带 inputSchema / C ok=True 7 模式 / D 400 / E 502 桥活 / F 老口信封） |
| 守卫链 | `check_demo_isolation` PASS / `check_py_stdout_encoding --all` **64/64 PASS** / `check_scripts_index` PASS / `check_ps_encoding` PASS |
| CI 实证 | `ci.yml #297` js,ubuntu：`HTTP contract self-proof` **success**（先自证再跑真链） |

提交：`14b85e3`（脚本 + CI 挂点）、`2dac0bc`（scripts/README 登记同步），双远端同步。

## 缺口是怎么来的（自查）

上一轮我加 `e2e_http_contract.py` 时只做了"真跑通就挂 CI"，**漏了同族脚本都有的自检**：

| 脚本 | 有无 `--selftest` |
|---|---|
| `e2e_native_heap_probe.py` | 有（四格：rc 分解 + 计数口径正负对照 + rc 隔离对照 + 构建门） |
| `check_test_sync.py` | 有（八变体） |
| `e2e_http_contract.py`（我加的） | **无** ← 本轮补 |

本仓为此返工过多次（「红着没人读等于没锁」），所以这不是可选项。

## 关键设计：先把判定抽成纯函数，再逐格喂合成回执

**为什么必须先抽函数**（写进源码注释）：判定若埋在 `main()` 的实时回执里，`--selftest` 就只能靠
"起真桥"来验；而真桥一坏判据自己先崩 ⇒ 自检退化成"整条链通不通"，**验不出"某支判据会不会红"**。

抽出 7 个纯函数：`p_health` / `p_tools_unwrapped` / `p_tool_call_live` / `p_body_not_object_400` /
`p_unknown_tool_no_crash` / `p_legacy_mcp` / `arms_consistent`；`main()` 改为调用它们
（消除"判定在两处各写一遍"的漂移面）。

**23 格覆盖**（正/反/边界三类；格子清单从实现反解、不手写计数——本仓已因手写计数返工过）：
- A(3)：200 过 / 500 红 / 0（连接失败）红
- B(5)：120 工具带 schema 过 / **仍是 jsonrpc 信封**红 / **缺 inputSchema** 红 / 工具太少红 / 非对象红
- C(4)：完整回执过 / **result 被剥掉**红 / ok 非 true 红 / data 太少红
- D(2)：400 过 / **200（静默当空 arguments）**红
- E(3)：502+桥活过 / 桥死了红 / 不是 502 红
- F(3)：信封+工具量级过 / **信封被剥**红 / 工具太少红
- ARM(3)：逐字一致过 / 少一臂红 / 多一臂红

## L4 实测（金条八：不靠自述）

**变异实测 5/5**（这是"能红"的硬证据，不是"我写了对照"）：

| # | 变异 | 自检抓到 |
|---|---|---|
| 1 | `p_health` 改恒 True | A-red-500 / A-red-0 |
| 2 | 剥壳判定放宽到不查 `inputSchema` | B-red-缺inputSchema |
| 3 | 去掉 result 原样保留 | C-red-result被剥掉 |
| 4 | 把 400 判成 200 | D 两格 |
| 5 | 臂一致性改恒 True | ARM-red-少一臂 / 多一臂 |

变异脚本备份原文件、逐处变异后跑 `--selftest`、**最后还原并复跑 rc=0**（`temp/mutate_e2e.py`）。

**真桥全链零回归**：重构后无参数运行仍 6/6 PASS（163 工具 / 7 模式 / 400 / 502 / 老口信封）。

## 资源消耗

- `--selftest` 跑 7 次（1 次初始 + 5 次变异 + 1 次还原）；每次**不新起进程池、不碰端口**；
- 真桥全链 1 次（起停 1 条桥，台账改道 `temp/`）；
- 守卫链 5 支各 1 次；本链零 `.mbt` 改动、零网络请求。

## 任务分配记录

- 指挥官亲自：缺口自查 → 判定抽函数 → 23 格设计 → 变异实测 → CI 挂点 → 登记同步。
- **未派子代理**：变异实测的每一处都要与"哪一格该红"对表，且 CI 挂点涉及并发 WIP 面
  （`ci.yml` / `scripts/README.md` 都在他人手中），归属判定不可外包。
- 边界：只动 `scripts/blackbox/e2e_http_contract.py` + `ci.yml` 一行 + `scripts/README.md` 一行；
  `ci.yml` 与 `scripts/README.md` 的并发 WIP（各 30 / 23 行）**用索引法精确绕开**，事后复核仍完整保留。

## 遗留风险

1. **`--selftest` 覆盖的是判定逻辑，不是"桥这一侧的对接"**：23 格全在纯函数层，故它绿
   **不等于**真桥连得上——后者由无参数运行负责。两条命令在 CI 里串跑（先 `--selftest` 再真链），
   这个分工已写进自检输出与 README。
2. **`Format check` 仍红且其后 21 步 skip**（`ci.yml #297` 实证）：本轮自证恰在 Format **之前**，
   故能跑；但它之后的 `Test (js)` 与守卫族仍被 skip —— 与上一轮报告同因（owner 面）。
3. **变异脚本属临时件**（`temp/mutate_e2e.py`，gitignored）；它做的"改自己再还原"若中途崩，
   会留下被变异的脚本。本轮已确认还原成功（复跑 rc=0）；建议后来者跑变异前先备份（脚本已内置备份步骤）。
4. `scripts/README.md` 登记面**随实现漂移的时机**是"脚本改了但 README 没跟上"；本轮已同步，
   但本仓无守卫自动比对"脚本 `--selftest` ↔ README 登记"（属可选增强）。

## 后续建议

1. **给 `e2e_heartbeat_xproc.py` / `e2e_reserve_xproc.py` 也补 `--selftest`**：本轮普查发现这两支同族
   e2e 同样没有自检（它们只靠"起两个真进程"验，同族缺陷面）。可按本轮同一手法抽判定函数。
2. **把"判据有无 `--selftest`"列入登记面守卫**：可写一支只读脚本，扫 `scripts/**` 里以"判据"自述
   的脚本，报出缺 `--selftest` 的（排除真链型 e2e 的合理例外）。
3. **变异实测固化成脚本**：本轮手写的 `temp/mutate_e2e.py` 思路可复用（备份 → 逐处变异 →
   要求 `--selftest` 报红 → 还原），比"写几格对照然后声称能红"更硬。

## 超额内容

- 顺带**抽出了 7 个纯判定函数**，消除"判定在 `main()` 与自检两处各写一遍"的漂移面。
- 顺带做了**五处变异的实测**（本仓对"能红"的通行做法是 `--selftest` 里放合成违例；
  本轮额外用变异证明"合成违例真能触到判定"）。
- 顺带**普查了同族 e2e 的自检覆盖**（发现 heartbeat/reserve 两支也缺），并写进后续建议。

## 来源

- 自检实现：`scripts/blackbox/e2e_http_contract.py`（`p_*` 纯函数 + `selftest()`；`__main__` 分派 `--selftest`）。
- 变异实测：`temp/mutate_e2e.py`（5/5 被抓住，输出落 `E:\temp\mut.txt`）。
- 真桥全链：无参数运行输出（6/6 PASS）。
- CI 实证：`ci.yml #297` js,ubuntu（`Migrate ✅ / Check(js) ✅ / HTTP contract self-proof ✅ / Format ✗`）。
- 登记同步：`scripts/README.md` 的 `blackbox/e2e_http_contract.py` 条目（补 `--selftest` 说明）。
- 纪律依据：BUG-50（判据必须先证明自己会红）/ J10（判据范围自述==实现）/ 本仓「红着没人读等于没锁」。
- 提交：`14b85e3`、`2dac0bc`。
