# R121 报告 · CRLF 治理 + 判例库形态尺（统帅亲做）

- 日期：2026-11-02
- 轮次：R121（goal round 121/256）
- 来源：R120 双分派（delta→判例库尺、gamma→CRLF 治理）均 failed-with-no-output ⇒ 按本会话判例（R59/R103/R120：小单反复失败 = 需单一上下文持续到结论）统帅亲做。

## 结果摘要

| # | 事项 | 落点 | 验证 |
|---|---|---|---|
| 1 | CRLF 治理：`.gitattributes` 追加 `*.mbt text eol=lf` + `moon.pkg text eol=lf`（11 行） | `1ab085c2` | tracked 假脏 38→0；blob sha 不变（`git diff HEAD` 仅 .gitattributes）；moon check 0 errors |
| 2 | 判例库形态尺 `scripts/check_precedents_doc.py` + 电池两格 + README 条目 + 锚点 148/107/120→149/108/121 | `7c5c8a45` | `--selftest` 9 格 rc=0；真跑 PASS（32..42 连续 11 条）；四把门 rc=0；`--list` 尺 149 / 电池面 108 / 缺面 0 与锚点逐键一致 |
| 3 | BUG-527 决策单（beta 死后接手） | `0fe9146a6` | 出路②上游 issue 为主行动，证据包 5 条已拟；③否决；①已证伪；④新增缓解 |
| 4 | R121 日志段落 | `e9b54977d` | 已推送 |

## 资源消耗

- 统帅亲自执行（两路子代理均死后的兜底）：约 6 个 tool-call 批次；电池后台 1 发（`bash-9ac64d6c27c040df`）。
- 无新依赖；脚本 ~150 行 Python。

## 任务分配记录

- delta（判例库尺）/ gamma（CRLF）/ beta（BUG-527 决策单）三轮分派全部 failed-no-output ⇒ 三件均统帅亲做。
- 教训沉淀位：AGENTS 判例库 `docs/AGENTS-precedents.md`（判例-32~42）；「分派失败三连 ⇒ 亲做」已三次实证，暂不立新判例（预算 49,237/65,536，余量充足但该形状与既有判例同族）。

## 遗留风险

1. **+2 `unused_package` warning（46→48）**：属别的 lane 漂移（worktree 字节已 == HEAD 才跑的 check）；`check_warning_ledger` 对 48 rc=0 可容，但下一个想抬基线的 lane 应先查这 2 条的归属。
2. **BUG-527 出路②需 owner 动作**：上游 issue 是否发、署名谁，等裁决（金条四：发布类操作执行权留 owner）。
3. 判例库尺只看**形态**（编号/指针/日期戳），不看内容质量——内容被写坏但形态完好时它不红（已写进 README 条目）。

## 后续建议

- 完整电池读数收 `temp/battery_r121.log`（后台跑）。
- 下轮可把「GATE_PREFIXES 与 AUTO_CASE_PREFIXES 口径不一致」待办清掉（R118 记账，与本轮无依赖）。

## 超额内容

- 无（三件均为分派内工作；gamma 任务包里的「普查未跟踪顶层目录」部分在 R115 已由 `.tnr_decompose/` 处理覆盖）。

## 来源

- 会话：DSH lead（goal-5e53e081）；commit 链 `1ab085c2` → `7c5c8a45` → `e9b54977d`；电池日志 `temp/battery_r121.log`（本轮收数后补追记，不抄进本文）。
