# 2026-10-14 · J14 扩面：提示词模板计数主张纳入工具计数自述对表（Round 110）

## 结果摘要

**一句话**：实施上轮建议 #1——把「提示词模板里的工具总数 == 真源」纳入判据。J14 增一面
`templates/tool_use_rubric.md`（提示词模板计数面），并给判据配上变异反证：模板改回 134 会被抓到、
现状 166 不误红。`check_doc_surface` selftest + 真状态全 PASS（rc=0），防再漂闭环。

## 为什么这一面单独进 J14

`templates/tool_use_rubric.md` 是 **pipeline 分支 A「按固定结构撰写」时原样追加到提示词末尾**的模板
（「逐字保留、不得改写」）。它告诉被驱动的 agent「本项目暴露 N 个工具」——上轮发现它写「134 个工具」
而真源 166，agent 被告知少 32 个，削弱 tool 幻觉防护的确定性清单基础。

**两头都没人看这句计数主张**：
- J8 只对模板里的**调用参数与 required 列表**（`j8_template_params`），不对总数
- J3 只对 README 的**分组和 == 实测**，不扫模板

⇒ 单独进 J14_FACES，与「MCP 资源面 / CLI 帮助面 / 架构自述面」并列。

## 交付（commit `d8a108e`）

`scripts/check_doc_surface.py`：
1. `J14_FACES` 增 `("templates/tool_use_rubric.md", "提示词模板计数面")`，并写清追加缘由的注释
2. FATAL 消息「三面」→「各面」（现在 4 面，面清单由动态 join 给出）

文件加载路径 `j14_tool_count_claims()` 是 `for rel,_ in J14_FACES: texts[rel] = read_text(...)`，
加面即自动加载校验，无需改加载逻辑。

## 验证（金条八：实际运行 + 变异反证）

| 项 | 结果 |
|---|---|
| `check_doc_surface`（selftest 16 格 + 真状态） | **PASS rc=0** |
| **变异反证**：模板内存改回「134 个工具」 | **J14 抓到**：「提示词模板计数面（templates/tool_use_rubric.md:13）自述『134 个工具』，真源注册表是 166 个」 |
| **现状反证**：模板「166 个工具」 | 不误红（False） |
| 全模板计数主张扫描 | 仅 `tool_use_rubric.md` L13 一处「166 个工具」（扩面无旁支误红风险） |

## 资源消耗

- 1 个提交：`d8a108e`（+8 行注释 + 1 行面 + 1 行消息）
- 1 支变异脚本（`temp/j14_mut.py`，内存变异不落盘，直接调 `j14_count_problems`）
- 0 `.mbt` 改动；0 `src/router/*` 触碰；0 plugins/ 触碰

## 任务分配记录

指挥官亲自：
- **把建议变成判据**：不满足于"修一次"，而是让这一面从此有人盯（J14 是"工具计数自述 ↔ 真源"的专属判据）
- **选对判据归属**：不塞进 J8（只管参数）或 check_template_ctrl（只管控制字符），而是进 J14——语义对齐
- **给判据配变异反证**：直接调 `j14_count_problems` 用内存变异证明"改回 134 必被抓 + 166 不误红"，
  避免"加了面但没验证能红"的空判据（BUG-50/J10 教训：判据必须能自证会红）
- **确认扩面无旁支误红**：先扫全模板计数主张，确认只有一处且已是 166，才动 J14_FACES

## 遗留风险

1. **J14 扩面只覆盖 tool_use_rubric.md 一处**：其它提示词注入面若未来新增计数主张，仍不在射程。
   后续可把扫描面改成 `templates/*.md` glob，但会牵动 FATAL 逻辑，留待确有需要时再做。
2. **`check_plugin_sync` 仍红**：并发 agent WIP（加 router 工具未重投影），等收口。
3. **README.md 计数主张**：投影文件，需在投影真源层修（非本轮范围）。

## 后续建议

1. **若要覆盖全部模板**：把 J14_FACES 的模板面改成 glob `templates/*.md`，并给 FATAL 判据补
   "模板目录读不到必自拒"子判据（防扫描面空转）。
2. **同族思路推广**：`src/` 里的 doc comment 计数主张（如 laya_route.mbt「104 工具」，已修）也可纳入
   同类扫描，但优先级低于模板（不注入 agent）。
3. **并发 agent 收口后**：`check_plugin_sync` 归绿，再统一跑一轮全守卫确认无旁支。

## 超额内容

- **给"文档即实现"补了一层防再漂**：这类"散文里写个工具数"的漂移，最难的不是修、是**没人盯**——
  J3 管 README 分组和、J8 管模板参数、check_tools_sync 管 AGENTS/README 工具可查，但"模板里的总数"是
  三者的接缝。本轮把这处接缝焊进 J14，是"守卫族要覆盖接缝不覆盖重叠"的具体一例。

## 来源

- 判据：`scripts/check_doc_surface.py` J14_FACES / `j14_count_problems` / `j14_tool_count_claims`
- 上轮修复：`templates/tool_use_rubric.md` L13「166 个工具」
- 变异反证：`temp/j14_mut.py`（内存变异，不落盘）
- 真源：`scripts/_tool_registry.py`（166）
