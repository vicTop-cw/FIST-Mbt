# R135 报告：`eval_feedback` 缺陷解析假绿（非 `-` 列表标记与散文缺陷都被静默吞成 pass）

## 一、结果摘要

- **病灶**：`src/engine/engine_eval.mbt` 的 `parse_section` 只把 `- ` 开头的行当作列表项。Markdown 的另外两类无序列表（`* ` / `+ `）与有序列表（`1. ` / `1) `）写在 `## Defects` 段下会被**静默忽略**，`d == 0` ⇒ `verdict = pass`——缺陷被契约层吞掉，optimizer 据此收敛。这与 BUG-31「未知键静默忽略 ⇒ 假 pass」、R132「check_key 的 invariant 静默忽略」同族。
- **修复**：抽出 `list_item_text`（输入已 trim 的行，识别 `- ` / `* ` / `+ ` / `数字. ` / `数字) ` 五类标记），`parse_section` 全走它；并补 `prose_lines`——`## Defects` 下既非列表项、也非「无 / 无缺陷 / 暂无 / 暂无缺陷 / （无） / (无) / none / n/a」标记的散文行，计入 `counts.defects_unparsed` + `flags=defects_unparsed:N`，verdict 强制 fail（读不到缺陷数就不判 pass，fail-closed）；显式「无」标记仍按零缺陷处理（既有契约与回归锁不破）。
- **自证**：两批对照都先红后绿——列表标记批 **197 / passed 194 / failed 3** → **197 / 197**；散文批（旧实现 + 新测试）**200 / passed 197 / failed 3** → **200 / 200**；全仓 `moon_test_env.py` **1411 / 1411**（最新主线基线 + 本单 7 条）；`issue_scan src/engine --min-severity medium` 6 条命中全部是 `has_prefix` 守卫后的既有误报（`engine.mbt:1638-1648`），本单无新增。
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
汇总：Total tests 200 / passed 200 / failed 0
全仓：Total tests 1411 / passed 1411 / failed 0（rc=0）
```

### 2.5 散文缺陷的红前对照（旧实现 + 新测试）

把 `src/engine/engine_eval.mbt` 临时还原为主线（`92d0edba`）的旧实现，只跑新测试：

```
汇总：Total tests 200 / passed 197 / failed 3
红格：efx_5 散文缺陷（期望 defects_unparsed=1，旧实现无此计数）
      efx_6 显式「无」标记（期望 defects_unparsed=0，旧实现无此键）
      efx_7 列表 + 散文混写（散文未被识别）
```

随后按字节还原实现文件（`git diff` 只含本单新增行），红后 200/200。

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
2. **为什么散文也要 fail-closed**：`（无）` 是显式「零缺陷」写法，必须放行；但「缺陷：A 和 B」同样不是列表项，旧实现会读成零缺陷 → pass——仅凭「非列表」无法区分两者。因此引入显式「无内容」白名单：白名单内仍是零缺陷，白名单外的非空正文计 `defects_unparsed` 并强制 fail。这是有意的语义变更：宁可在写不清时判 fail 让调用方重写，也不给「确定性 pass」的假绿。
3. **为什么有序列表也要收**：LLM 输出缺陷清单时用 `1.` 编号非常常见；`1)` 是 GitHub Markdown 渲染的有序列表变体，同样常见。只认 `-` 等于把最自然的两种写法排除在契约外。
4. **解析安全**：`list_item_text` 对 `line[1]` 的访问由 `n >= 2` 守卫；有序标记用 `i + 1 < n` 保证 `line[i+1]` 在界内，`line[i+2:n]` 允许空串（`"1. "` 这类），不会越界。

## 四、自证

- **红前**：3 格红（§2.1），不是「先改后补测试」。
- **红后**：engine 200/200、全仓 1411/1411（干净分支、最新主线基线）。
- **反向对照**：`efx_3` / `efx_6` 证明「（无）/ (无) / none / NONE / n/a / 暂无」6 种显式标记不被误红；`efx_4` 证明新标记在 Acceptance 段计数正确；`efx_7` 证明列表项照常计数、散文只报不吞。
- **红前（散文）**：还原旧实现后 200 / 197 passed / 3 failed（§2.5），不是先改后补测试。
- **格式化**：`moonfmt` 对两个改动文件输出与原文件逐行一致（diff_lines=0），无格式漂移。
- **扫描**：无新增静态命中（§2.4）。

## 五、资源消耗

- 时长：约 40 分钟（两批红前对照、两次全量测试、两次电池；电池含一次全仓 `moon build`，受另一支 agent 并发构建影响）。
- 工具调用：约 35 次（读实现/测试、写测试、红前还原对照、两次全量测试、moonfmt 校形、文档面守卫、两次电池）。
- 代码面：`src/engine/engine_eval.mbt` +54/−3（相对上一提交）、新增测试 7 条、`server.mbt` 两处字符串。

## 六、任务分配记录

- 本单由副机自主发起（主机任务池为空：`fist.py call list --ns default` 返回 `[]`）。
- 子代理：无（单函数缺陷 + 纯函数测试，按金条四由指挥官直接完成）。
- 分支基点：从最新 `gitcode/master`（`92d0edba`，已合 r131/r126）重切；早先的同名分支 `slave/fix/eval-feedback-list-markers-r135` 叠在已作废的 R133（日志去重）之上，**作废、勿开 MR**——它会把 639MB 的 `memory/2026-10-22.md` 与 README 锚点冲突卷进本单，与本单语义无关。
- 冲突面：未触碰 R126

## 七、遗留风险

1. ~~纯散文缺陷仍读成零缺陷~~（本单已收口）：`## Defects` 下的散文行现在计 `defects_unparsed` 并 fail-closed。白名单只认 8 个显式「无」标记；其它写法（含 `> 引用`、子标题）都会判 fail——若真实反馈里有更多合法的「无缺陷」措辞，需按真实语料补白名单（取舍是宁可误红，也不静默放行）。
2. **列表标记的空白只认空格**：`-\tfoo`（标记后接制表符）不识别；Markdown 规范允许，但极少见。若后续出现实际反馈格式再扩。
3. **轮次号撞号**：本单开工时取 R134，按项目记忆「R134 已被轮次号基线占用」让号为 R135；本机早先的 R133（日志去重）与另一支 `slave/fix/memory-log-dup-r133` 同题撞号——交付时只推荐对方那支，本机 R133 分支作废不改号，避免再造第三支同题分支。
4. **预存面（不代修）**：主线 `src/server/server.mbt` 相对本机钉版 moonfmt 有 9 处既有格式漂移（与 BUG-388 的 fmt 世代差同族）；本单只改一处字符串字面量，不整文件重排（避免把 9 处无关漂移卷进 MR）。
5. 本单从 `92d0edba` 重切，若主线再前进按常规 rebase。

## 八、后续建议

1. 已落地：`defects_unparsed` 诊断 + fail-closed（§2.5、`efx_5~7`）。若 owner 认为白名单过窄导致误红，可退成「只 flag 不判 fail」，但建议保持 fail-closed。
2. 把 `list_item_text` 抽成反馈/帽子/评审共用的列表解析单真源（`ops_hats.mbt` 也产四段式输出），避免三处各自的符号集合再次漂移。
3. 下一次取号前按项目约定查三面（远端分支名 / 主线 `reports/` / 当日日志与 `BACKLOG.md`），本次 R134 撞号即因未查基线记忆。

## 九、超额内容

- 顺带核对了 `ops_hats.mbt` 的四段式输出：帽子工具自己生成 `- ` 项，暂无同类假绿；但建议未来复用同一解析器（§八-2）。
- 报告发现：并发 agent 同时跑电池时 `whisperer.py --selftest` 会触发 600s 限时（本轮实测 1 格 TIMEOUT，单跑 rc=0）——电池读数的并发噪声，已在下一次终读中复核。

## 十、来源

- `src/engine/engine_eval.mbt:7-87`（`list_item_text` + `parse_section` + `is_none_marker` + `prose_lines`）
- `src/engine/engine_eval_list_markers_test.mbt`（新增 7 条对照）
- `src/server/server.mbt:6419,6423`（描述与 schema 文案同步）
- `src/ops/ops_hats.mbt:9,171`（四段式契约的同族输出，未改）
- `memory/2026-10-23.md`（R135 条目）


## 十一、终读（电池）

- 电池 `python scripts/run_guards.py`（提交 `e8fc8a0f` 已推送后的交付态）：**格数 68（手写 68 + 自动 0）/ 失败 0 / SKIP 5 / 缺执行面 0**，rc=0（日志 `temp/r135e_battery.log`）。
- 前一发（同内容但未入库）唯一红 `check_publish_payload` 是「新测试文件还没进 index ⇒ `moon publish` 会把它打进载荷」的登记顺序噪声；`git add` 后该格单独复跑 rc=0（1337 件 / 未跟踪 0）。
- 中间一发（已提交但未推送）唯一红 `check_delivery_gap` 是「本地领先 = 未交付」的判据本色；推送后转为 rc=0，终发不再复现。
- 5 个 SKIP 均为缺 `temp/pt27.log` / `temp/chk47.json` 前置的既有格（`check_badge` / `check_test_sync` / `check_deprecated_text_census` ×2 / `check_deprecated_site_list`），与本单改动无关，不计失败也不构成通过证据。
- 结论：代码面 200/200（`src/engine`）、全量 1411/1411（`moon_test_env.py` rc=0）、电池 68/0/5/0 三面同一工作树读数，交付态不挂已知红。
