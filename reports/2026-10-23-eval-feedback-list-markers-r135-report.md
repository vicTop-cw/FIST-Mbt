# R135 报告：`eval_feedback` 列表标记假绿（`*` / `+` / 有序列表写下的缺陷被静默吞成 pass）

## 一、结果摘要

- **病灶**：`src/engine/engine_eval.mbt` 的 `parse_section` 只把 `- ` 开头的行当作列表项。Markdown 的另外两类无序列表（`* ` / `+ `）与有序列表（`1. ` / `1) `）写在 `## Defects` 段下会被**静默忽略**，`d == 0` ⇒ `verdict = pass`——缺陷被契约层吞掉，optimizer 据此收敛。这与 BUG-31「未知键静默忽略 ⇒ 假 pass」、R132「check_key 的 invariant 静默忽略」同族。
- **修复**：抽出 `list_item_text`（输入已 trim 的行，识别 `- ` / `* ` / `+ ` / `数字. ` / `数字) ` 五类标记），`parse_section` 全走它；`## Defects\n（无）` 这类非列表自由文本仍按「零缺陷」处理（既有契约与回归锁不破）。
- **自证**：先写 4 条对照（红前 3 红）再改实现——`moon test src/engine` 由 **197 / passed 194 / failed 3** 变为 **197 / 197**；全仓 `moon_test_env.py` **1394 / 1394**；`issue_scan src/engine --min-severity medium` 6 条命中全部是 `has_prefix` 守卫后的既有误报（`engine.mbt:1638-1648`），本单无新增。
- **文档**：`server.mbt` 中 `eval_feedback` 的工具描述与 `feedback` 参数说明两处「各段 - 列表项」同步为「各段列表项（- / * / + 或 1. / 1)）」——契约面不能只靠 `-` 才能命中。

## 二、证据

### 2.1 红前（新测试先落地、实现未改）

```
moon test --target js src/engine（经 scripts/moon_test_env.py）
汇总：Total tests 197 / passed 194 / failed 3
红格：efx_1 星号列表缺陷（defects 期望 1，实得 0 → verdict pass）
      efx_2 加号 + 有序列表缺陷（期望 3，实得 0）
      efx_4 有序验收项（acceptance 期望 2，实得 0）
```

### 2.2 红后

```
汇总：Total tests 197 / passed 197 / failed 0
全仓：Total tests 1394 / passed 1394 / failed 0（rc=0）
```

### 2.3 对照设计

- `efx_1`：`## Defects\n* …` → defects=1、fail。
- `efx_2`：`+ …` 与 `1. …`、`2) …` → defects=3、fail。
- `efx_3`：`## Defects\n（无）` → defects=0、pass（**反向对照**：自由文本不受新解析影响）。
- `efx_4`：有序验收项 → acceptance=2、pass（确认新标记在非 Defects 段同样生效）。

### 2.4 静态扫描

```
issue_scan src/engine --min-severity medium：scanned_files 24 / total_findings 6
全部为 substring-overrun，位于 engine.mbt:1638-1648 —— 每处都在 has_prefix 分支内，
end 由前缀长度决定、不可能越界，属扫描器已知误报；本单改动未引入新命中。
```

## 三、分析

1. **为什么这是假绿而不是格式挑剔**：工具的 `verdict` 是下游 optimizer 的收敛信号。「按契约该失败」的反馈因为符号写法不同被读成「零缺陷」，执行方会带着未修缺陷继续；而工具自己的 `note` 还写着「无缺陷且 acceptance 非空 → pass」。静默忽略比报错更危险，因为它给了确定性读数。
2. **为什么不把非列表正文一律判 fail**：既有测试与文档把 `## Defects\n（无）` 定义为零缺陷的合法写法，直接 fail-closed 会把这条正常路径误红。本次只扩标记集合，不改「自由文本 = 无缺陷」的语义；真正要堵死纯散文缺陷，需要新增「段落有非空正文但零列表项」诊断标志，属语义变更，留作后续（见 §七）。
3. **为什么有序列表也要收**：LLM 输出缺陷清单时用 `1.` 编号非常常见；`1)` 是 GitHub Markdown 渲染的有序列表变体，同样常见。只认 `-` 等于把最自然的两种写法排除在契约外。
4. **解析安全**：`list_item_text` 对 `line[1]` 的访问由 `n >= 2` 守卫；有序标记用 `i + 1 < n` 保证 `line[i+1]` 在界内，`line[i+2:n]` 允许空串（`"1. "` 这类），不会越界。

## 四、自证

- **红前**：3 格红（§2.1），不是「先改后补测试」。
- **红后**：engine 197/197、全仓 1394/1394。
- **反向对照**：`efx_3` 证明 `（无）` 不被误判；`efx_4` 证明新标记在 Acceptance 段计数正确。
- **格式化**：`moonfmt` 对两个改动文件输出与原文件逐行一致（diff_lines=0），无格式漂移。
- **扫描**：无新增静态命中（§2.4）。

## 五、资源消耗

- 时长：约 20 分钟（含两次全量测试与一次电池；电池因并发构建另计）。
- 工具调用：约 25 次（读实现/测试、写测试、编译检查、跑测试、扫描、电池）。
- 代码面：`src/engine/engine_eval.mbt` +26/−10、新增测试 4 条、`server.mbt` 两处字符串。

## 六、任务分配记录

- 本单由副机自主发起（主机任务池为空：`fist.py call list --ns default` 返回 `[]`）。
- 子代理：无（单函数缺陷 + 纯函数测试，按金条四由指挥官直接完成）。
- 冲突面：未触碰 R126（`src/server/run_check_js.mbt`、`scripts/moon_test_env.py`）与 R127（`src/server/issue_scan.mbt`）；本单叠在 R133 交付 tip 之上（`f5b6aecf`）。

## 七、遗留风险

1. **纯散文缺陷仍读成零缺陷**：`## Defects` 下写「缺陷：A、B」而非列表项时 `d` 仍为 0。要不要 fail-closed（带 `defects_unparsed` 标志）是契约决策，需 owner 或后续单元定；本单不做语义变更。
2. **列表标记的空白只认空格**：`-\tfoo`（标记后接制表符）不识别；Markdown 规范允许，但极少见。若后续出现实际反馈格式再扩。
3. **轮次号撞号**：本单开工时取 R134，按项目记忆「R134 已被轮次号基线占用」让号为 R135；本机早先的 R133（日志去重）与另一支 `slave/fix/memory-log-dup-r133` 同题撞号——交付时只推荐对方那支，本机 R133 分支作废不改号，避免再造第三支同题分支。
4. 本单叠在 R132/R133 之上；若主线先合其它分支，需按常规 rebase。

## 八、后续建议

1. 若决定收紧契约，可给 `eval_feedback` 增 `defects_unparsed` 诊断：`## Defects` 段存在且去掉列表项后仍有非空正文（且不是 `（无）`/`none`/`N/A` 白名单）⇒ fail 或至少 flag。
2. 把 `list_item_text` 抽成反馈/帽子/评审共用的列表解析单真源（`ops_hats.mbt` 也产四段式输出），避免三处各自的符号集合再次漂移。
3. 下一次取号前按项目约定查三面（远端分支名 / 主线 `reports/` / 当日日志与 `BACKLOG.md`），本次 R134 撞号即因未查基线记忆。

## 九、超额内容

- 顺带核对了 `ops_hats.mbt` 的四段式输出：帽子工具自己生成 `- ` 项，暂无同类假绿；但建议未来复用同一解析器（§八-2）。
- 报告发现：并发 agent 同时跑电池时 `whisperer.py --selftest` 会触发 600s 限时（本轮实测 1 格 TIMEOUT，单跑 rc=0）——电池读数的并发噪声，已在下一次终读中复核。

## 十、来源

- `src/engine/engine_eval.mbt:7-45`（`list_item_text` + `parse_section`）
- `src/engine/engine_eval_list_markers_test.mbt`（新增 4 条对照）
- `src/server/server.mbt:6419,6423`（描述与 schema 文案同步）
- `src/ops/ops_hats.mbt:9,171`（四段式契约的同族输出，未改）
- `memory/2026-10-23.md`（R135 条目）


## 十一、终读（电池）

- 电池 `python scripts/run_guards.py`（交付态、工作树含本单全部改动）：**格数 68（手写 68 + 自动 0）/ 失败 0 / SKIP 5 / 缺执行面 0**，rc=0（日志 `temp/r135_battery.log`）。
- 首跑唯一红 `whisperer.py --selftest got=TIMEOUT expect=0` 是另一支 agent 同时跑电池抢机器所致；该格单独复跑 rc=0（G1~G4 OK），终跑未再复现 ⇒ 未登记为期望红。
- 5 个 SKIP 均为缺 `temp/pt27.log` / `temp/chk47.json` 前置的既有格（`check_badge` / `check_test_sync` / `check_deprecated_text_census` ×2 / `check_deprecated_site_list`），与本单改动无关，不计失败也不构成通过证据。
- 结论：代码面 197/197（`src/engine`）、全量 1394/1394、电池 68/0/5/0 三面同一工作树读数，交付态不挂已知红。
