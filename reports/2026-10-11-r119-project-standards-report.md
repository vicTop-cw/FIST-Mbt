# R119 · project-standards r6-no-hardcode + issue_scan 字面量内通道 — 执行报告

- 日期：2026-10-11
- 轮次：R119（规范性 surface：一源四态新增第 6 条硬门 + 检测面第 12 条规则）
- 执行模式：直接落地（非 FIST 任务树发布，未产生新 FIST 任务 / 未改动工具计数 / 未改动缺陷账本）

## 结果摘要

- **规范面（真源 `AI-DEVELOPMENT-STANDARD.md` §1 通用规范 5 → 6 条）**：新增
  `r6-no-hardcode`（severity=hard，禁止硬编码绝对路径/盘符/UNC）；how_to_check 点名
  `issue_scan` 的 `hardcoded-abs-path`，并明示「命中只是候选，须读上下文复核」；
  明写 `http://` / `./x` / `src/a.mbt` 不命中。
- **投影面 `project_standards`**：`general_rules` 6 条 / `count_total` 11 / `version` R119
  （两分支一致）；`project_standards_wbtest.mbt` 增白盒锁（r6 存在 / severity=hard /
  body 点名盘符与 UNC / how_to_check 点名 issue_scan + hardcoded-abs-path + 候选 /
  版本 R119 / 计数 11）。
- **检测面 `issue_scan`（内建 12 条）**：`ScanRule` 增 `scope`（`"code"`/`"literal"`）；
  新增第 12 条 `hardcoded-abs-path`（medium）走**字面量内**通道，补上 BUG-72 通道
  （只在字面量外匹配）看不见的那半边。`scan_literal_parts` / `scan_hardcoded_path_literal`
  确定性判定盘符（`C:\`/`C:/`，排除 `http://`/`https://`）、UNC（`\\srv\share`）与
  Unix 绝对前缀；相对路径与 URL 一律不命中。
- **文档面**：`README.md` / `AGENTS.md` / `docs/deliverable.md` / `docs/project-standards-skill.md`
  的 issue_scan 与 project_standards 条目、`templates/pipeline_mode_bugfind.md`、
  `CHANGELOG.md` 同步；`templates/pipeline_mode_verify.md` / `templates/tool_use_rubric.md`
  经复核已与本轮口径一致（无旧口径残留，J7 绿）。

## 证据（判绿读数）

| 判据 | 命令 | 读数 |
|---|---|---|
| 编译 | `moon check` | `Error: [N]` 计数 **0** |
| JS 全量测试 | `moon test --target js` | **`Total tests: 742, passed: 742, failed: 0`**（BUG-142：判绿以汇总行为准，不认 exit 0） |
| 文档面 J6/J7/J8 | `python scripts/check_doc_surface.py` | **PASS**（exit 0，含 J6 规范正文↔投影一致 / J7 无旧口径 / J8 模板调用面契约干净） |
| 插件态 cl7 | `python scripts/gen_plugins.py && python scripts/check_plugin_sync.py` | **PASS 插件态一致：4 宿主 / 64 生成文件 / 136 工具 / v0.3.8**（exit 0） |
| 接口 | `moon info && moon fmt` | 0 errors；`src/server/pkg.generated.mbti` 增 `scan_hardcoded_path_literal` / `scan_literal_parts` 两个 pub 签名 |
| 实跑 | `python scripts/fist.py call issue_scan --dir src --max_findings 300` | 87 文件 / 77 findings；`by_rule` 含 `hardcoded-abs-path` **count=2**（均为规则/工具自身描述里的文档示例） |

新增测试：`issue_scan_test.mbt` 2 条集成夹具（真盘符命中 / URL·相对路径·空·普通字面量不命中）、
`issue_scan_wbtest.mbt` 5 把成对锁（命中/不命中 + 双通道互补 + 整行注释跳过 + 转义反斜杠回归锁）。
测试总数 **573 → 742**（含本仓其它在途增量），失败 0。

## 实跑 `hardcoded-abs-path` 命中清单（2 条，均属文档示例，不算缺陷）

1. `src/server/project_standards.mbt:68` —— `r6-no-hardcode` 规则正文里的 `C:\\...`/`\\\\server\\share` 示例。
2. `src/server/server.mbt:5666` —— `issue_scan` 工具描述里的 `C:\\`/`\\\\srv\\share` 示例。

两者都是「规则自己教的示例」，正属 how_to_check 明示的「测试夹具/文档示例除外」；
不是产品代码硬编码，**未上报缺陷**。

## 执行中发现并已修掉的缺陷：UNC 检测器对 JSON 转义的误报

首轮实跑 `hardcoded-abs-path` 命中 **8 条**，其中 6 条落在 `src/server/mcp_config_scaffold.mbt`
L108–112/L115：`"\\n"` / `"\\r"` / `"\\t"` / `"\\b"` / `"\\f"` / `"\\u"` 这些 **JSON 转义字面量**被误判成 UNC。

**根因**：初版 `scan_unc_at` 只要求「两连反斜杠 + 紧跟 ASCII 字母」。而 MoonBit 字符串里
`"\\n"` 的**原文**恰是 2 个反斜杠 + 字母 `n`（`\` 转义另一个 `\`）——与 UNC 服务器名前缀形状完全相同。

**修复（`src/server/issue_scan.mbt` `scan_unc_at`）**：改为数连续反斜杠的**条数**，
须 `>= 4` 连反斜杠之后紧跟字母（真 UNC 源码写作 `"\\\\srv\\share"`，即 4 连 + 服务器名）
才算 UNC；`"\\n"` 这类 2 连转义不再命中。真盘符（`C:`+`/` 或 `\`）检测不受影响。

**回归锁**：`issue_scan_wbtest.mbt` 新增
`hardcoded_abs_path_转义反斜杠非UNC_真UNC仍命中`（`\\n`/`\\t`/`\\u` 不命中 + `\\\\srv\\share` 仍命中）。

**修复后实跑**：`hardcoded-abs-path` count **8 → 2**，误报清零；真盘符通道仍正常
（合成夹具 `"C:\Users\me\a.json"` 命中，`https://` / `./x` / `src/a.mbt` 不命中）。

**诚实标注**：该误报是本次新增规则的缺陷，已在本轮内发现并修复、有锁钉住。
**补录追记（2026-10-11 终审后）**：经指挥官裁决，该缺陷已用 `report_bug` 补录为
**BUG-237 [medium] OPEN**（只追加不追改账本），summary/detail 附实跑 8→2 证据与回归锁；
因 bugfind 模式已接 `require_issue_scan`，BUG-237 后续可由自驱流水线认领复核。
按执行边界，**未改动 `server.mbt` 工具计数 / 未新增 MCP 工具 / 未发布 FIST 修复任务**。

## 分析

- `scan_literal_parts` 采用「保留原文、不做反义转义」策略，是本次 UNC 误报的放大器：
  正因为把 `\\n` 原样交给判定函数，才需要判定函数自己分辨「2 连 = 转义」与「4 连 = UNC」。
  两条路都确定性（纯函数、无 IO），选了较简单的「判定函数自证」路径；若日后需要解码字面量，
  必须在 `scan_literal_parts` 一处集中解码并给解码后的字节/字符流加同款测试。
- 盘符与 URL 的区分依赖「`:` 前字母再往前是否仍是字母」——`C:` 前是引号/空白 ⇒ 命中，
  `http:` 前是 `p` 再前是 `t` ⇒ 排除。该启发在单字母盘符上成立；对 `CC:/x` 这类畸形形状
  会静默不命中（保守，宁可漏报不误报，符合「命中只是候选」的口径）。
- `project_standards_wbtest.mbt` 的 5 把白盒锁与 `issue_scan` 的黑盒/白盒锁互为锚点：
  规范面说「r6 存在且 hard」，检测面真能扫出形状，两端对齐才构成「一源四态」不是「两本账」。

## 缺口与风险

1. **误报缺陷未入账本**（见上）——建议指挥官补录，避免「发现缺陷不留痕」。
2. **2 条剩余命中是文档示例**，属预期自噪声；若日后把 `project_standards.mbt` / `server.mbt`
   的规则描述文本抽到非 `.mbt` 资源里，这两条会自动消失，届时可复核是否把规则文本本身
   也加入 `scan_is_rules_table` 的跳过面（本轮未做，避免扩大作用域）。
3. **Unix 绝对前缀走子串判定**（`/home/` 等 10 个前缀），比盘符/UNC 更粗——一个字符串里
   偶然出现 `/tmp/` 也算命中；同样是「候选」口径兜底，未做前后语义判定。
4. **未跑 native 后端**（BUG-133 依赖面，权威稳定门槛为 JS 后端）；本轮改动为纯函数 + 测试，
   不涉 FFI，风险低但未在 native 上验证。
5. `CHANGELOG.md` 本轮新增的标题为 `R119（规范性 surface …）`，**未使用 `## v` 前缀**：
   因本轮不改 `moon.mod` 版本、不构成一次发布，刻意避开 `release-fact:` 的发布状态短语对表；
   J13 绿（该节未自述发布状态，故无「戳晚于事实」）。

## 后续建议

- 指挥官裁决是否补录「UNC 误报」缺陷（附本条证据）。
- 下一轮可考虑把 `issue_scan` 的 Unix 前缀判定升级为「词边界 + 前后非 URL」语义，
  降低 `/tmp/` 类偶然命中；属可选优化，非必需。

## 超额内容 / 来源

- 超额：修复了新增规则的 6 处误报并加回归锁（原计划未含）。
- 来源：本轮对 `AI-DEVELOPMENT-STANDARD.md` / `project_standards.mbt` / `issue_scan.mbt`
  的改动，全部由本次执行产生；未改动 `server.mbt` 工具计数、未改动 `memory/bugs.md`。
