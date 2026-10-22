# R132 · `output_validate` 外部产物 invariant 假绿两入口 报告

## 一、结果摘要

- 修 `output_validate`（L4 交付硬门）两处「声明了 invariant 却没人读它」的假绿入口：
  1. **`{check_key, min_chars}` 组合**：旧实现只校验 `min_chars` 的值型，不拒绝它与 `check_key` 的组合；
     `check_external_artifact` 又不读 `min_chars` ⇒ 硬门按更弱的 `ok` 判 pass，detail 仍写「OK（外部检查 passed）」。
  2. **`{check_key, contains/not_contains}` + 非对象外部结果**（bare `true` / `"ok"`）：
     `check_external_artifact` 的非对象分支直接按 `ok` 判 pass——没有 `stdout` 可校验，
     却把声明过的 invariant 当作通过（BUG-143 的同类漏口）。
- 修复：组合非法在 `artifact_spec_errors` 拒绝（fail）；非对象 + 有 invariant 时 fail-closed 并点名 R132。
- 读数：修前 **369 中 367 过**（`r132_1`/`r132_2` 双红）；修后 **369/369**，全量 **1390/1390**，
  `issue_scan src/server --min-severity medium` = **0 findings**。
- 交付：分支 `slave/fix/output-validate-ext-invariant-r132`（基于 `gitcode/master` `dcefdeb8`）。

## 二、证据

修前（新锁已落、产品码未改）：

```text
汇总：Total tests 369 / passed 367 / failed 2
| test src/server/output_validate_ext_invariant_test.mbt:84 ("r132_2_check_key_contains_bare_bool_fails_closed") failed
```

第二条红为 `r132_1_check_key_min_chars_rejected`（同一轮 2 failed 的另一条）。
两条红的含义：外部结果本身合法且完整，失败只可能来自「声明了 invariant 但没人校验」。

修后：

```text
汇总：Total tests 369 / passed 369 / failed 0        # src/server
汇总：Total tests 1390 / passed 1390 / failed 0      # 全量 --target js
{"scanned_files":35,"total_findings":0,...}          # issue_scan medium+
```

反向对照 `r132_3`：未声明 invariant 的 bare bool 外部结果仍判 pass——收紧只作用于
「声明了却校验不到」这一档，不动既有便利路径。

## 三、分析

- `parse_artifact` 只读认识的键（BUG-31 的教训），`artifact_spec_errors` 后来补了
  「未知键」与「值型」两道门（BUG-31 / BUG-209），但**漏了「键与产物品类不匹配」**这一档：
  `min_chars` 是文件产物口径，配到 `check_key` 上既不被拒绝、也不被执行。
- 非对象分支是 `external_results` 的便利形态（`{"k": true}` / `{"k": "ok"}`），
  原实现只按 ok 判定；调用方一旦同时声明 `contains`/`not_contains`，这些 invariant 无处执行却静默通过。
- 假绿方向最危险：verdict=pass + detail「OK（外部检查 passed）」，回执上看不出 invariant 没跑，
  与 BUG-143「进程退出 0 ≠ 产出有效」是同一类错误。
- 为什么选择「拒绝 / fail-closed」而不是把 `min_chars` 实现到 stdout：
  工具描述与 schema 只对 `path` 产物承诺 `min_chars`；扩 API 面需要另立契约与文档同步，
  而该文件既有的立据（BUG-31/209/143）一贯是「不能执行的声明必须发红，不许降级」。

## 四、判据自证

- `r132_1`：去掉组合拒绝 → 该用例红（verdict 由 fail 变 pass）。
- `r132_2`：去掉 `has_inv` 分支 → 该用例红（非对象 + contains 直接 pass）。
- `r132_3`：反向对照，证明无 invariant 的 bare bool 不被误伤。
- 现网调用面普查：`min_chars` 仅出现在 `path` 产物示例与测试里
  （`docs/output-validate-skill.md`、`scripts/mcp_tool_tour.py` 均用 `{path, min_chars}`），
  无调用方依赖 `{check_key, min_chars}` ⇒ 收紧零回归。

## 五、资源消耗

- 本单约 25 分钟：审计候选（eval_feedback / text_diff / output_validate）约 8 分钟，
  双跑测试约 4 分钟，全量与扫描约 2 分钟，报告与日志约 8 分钟。
- 工具调用约 20 次（读文件 6、grep 5、测试 4、扫描 1、git 3）。

## 六、任务分配记录

- 主机任务池为空（`fist.py call list --ns default` → `[]`），本单为副机自驱自查自改；
  小单不拆子代理，由指挥官直接执行并终审（红→绿双读数自证）。

## 七、遗留风险

- `check_moon_test_summary` 目前取**最后一条** `Total tests:` 汇总行。若 `moon test` 多包输出
  含多条汇总行且最后一条来自绿包，前面包的失败可能被覆盖——本轮未实测 moon 的实际输出形态，
  列为后续审计候选，不在本单臆改。
- 行为收紧：此前传 `{check_key, contains}` + bare bool 的调用方会从 pass 变 fail（预期），
  如有外部脚本依赖旧行为需按 detail 提示改用对象形态并带 stdout。
- R129/R130/R131 三份时间解析器修复仍未合入主线，日历校验仍各自维护；本单不触那些文件。

## 八、后续建议

- 把 `artifact_spec_errors` 的「键 × 产物品类」矩阵补全（当前只拦 `min_chars`），
  未来新增键时同步问一句「这个键在另一类产物上有口径吗」。
- 若要给 `check_key` 增加输出长度门，建议新键（如 `min_stdout_chars`）并同步
  schema/工具描述/skill 文档，避免复用 `min_chars` 造成语义歧义。
- 用真实多包 `moon test` 输出验证 `check_moon_test_summary` 的多汇总行行为，再决定是否要求唯一汇总行。

## 九、超额内容

- 同步更新工具 schema 描述（`server.mbt` 的 artifacts 字段说明）：
  写明 `check_key` 不接受 `min_chars`、`contains/not_contains` 对 stdout 生效、
  非对象结果无 stdout 可验即 fail——调用面文档与实现不再各说一套。

## 十、来源

- 真源：`src/server/output_validate.mbt:65`（`artifact_spec_errors`，组合拒绝在 `:129`）、
  `:382`（`check_external_artifact`，非对象分支在 `:465`，R132 门在 `:473`）。
- 调用面：`src/server/server.mbt:6622`（artifacts schema 描述）。
- 新锁：`src/server/output_validate_ext_invariant_test.mbt`（`r132_1` at :63 / `r132_2` at :88 / `r132_3` at :110）。
- 同族旧账：BUG-31（未知键静默忽略）、BUG-209（值型静默降级）、BUG-143（外部检查忽略 stdout invariant）。
- 修前/修后读数见第二节；全量与环境：Node 24 + `scripts/moon_test_env.py`（无 `MOONC_OVERRIDE`）。

## 十一、终读

- 电池：66 格 / 失败 0 / SKIP 5 / 缺执行面 0（rc=0，首跑即绿）；补记后二次终读同口径。
