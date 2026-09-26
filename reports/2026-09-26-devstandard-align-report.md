# 2026-09-26 · 开发规范单文件化与全量文档合规（自驱式【验证】模式）

- 任务：`[verify] 开发规范单文件化与全量文档合规稽核（R116 · 一源四态）`，ns=`stdalign`，根 `T0r354`，叶 `T0r354.1`（Omega 语料 `spec:T0r354.1:r1` 已 approve）
- 规范版本：`project_standards` **R116**（正文真源 `AI-DEVELOPMENT-STANDARD.md` + cl1~cl7 七项）
- 终审人：指挥官（调用面实测，不信自述）

## 一、结果摘要

1. **规范单独成文**：新增 `AI-DEVELOPMENT-STANDARD.md`（10.4 KB，规范性正文）。它是"给目标项目的 AI 开发文档规范"——含术语表、通用 5 条、**目标项目必备文档集骨架**（7 类文档各自的必填段/更新时机/门禁）、FIST 专项 5 条 + **自我迭代四开关的可量化判据表**、四态验收 checklist 7 项、一轮流程（真实参数名）、违例分级与历史豁免、已知边界。
2. **一源四态用在规范自身**：正文=人类真源，`project_standards`=机器投影（新增 `canonical_doc` 字段），README/AGENTS 降为"摘要 + 指向正文"。此前是 README/skill/工具描述**各写一套口径**（用户指出的"根本没对齐"就是这个）。
3. **口径对齐 35 处**：README(4) / AGENTS(2) / docs×5 / templates×5 / scripts×2(3 处) / server.mbt(3 处) / 工具属性说明(1)。历史陈述（`memory/` `reports/` `CHANGELOG`）**不追改**——规范 §2 明确豁免边界，避免把证据改成假话。
4. **守卫扩面**：`check_doc_surface` J1-J5 → **J1-J8**（J6 正文↔投影、J7 旧口径禁词、J8 模板调用参数==真源 schema），`--selftest` 加合成违例证明三条判据都能红。
5. **入账 6 条**（BUG-45~50，其中 45/46/47 为驱动重跑导致的**重复条目**，已在账本内如实标注并交叉指向 48/49/50）。

## 二、证据（每条都可复跑）

| 层 | 证据 | 结果 |
|---|---|---|
| L4 文件系统 | `output_validate` 15 项 artifacts（6 项 `not_contains` 反证旧口径/旧参数），`require_evidence=true` | **verdict=pass / 15-0** |
| 调用面 | `temp/stdalign_verify.py`（真实 MCP stdio 入口，ns=stdalign） | **21/21 PASS** |
| 单调性 | `temp/j_before_after.py`：新判据跑 HEAD 内容 | **32 条发红**（J6=2/J7=11/J8=19）→ 工作树 **0** |
| 回归 | `moon test --target js` | **406/406 passed 0 failed** |
| 守卫族 | doc_surface / tools_sync / test_sync(406) / badge / scripts_index / plugin_sync | 6/6 绿 |
| 自我迭代活证据 | `call_log` 本轮记录 **31 个不同工具**（publish/task_plan_deep/claim/execute/submit/verify/report_bug/output_validate/project_standards/laya_decide/omega_×3/store_open/bug_list…） | 非回忆，取自表 |
| 零回归对照 | 对照组根任务默认参数拆解 ⇒ 子任务无"边界四问/父计划回注"文本 | PASS |

## 三、发现的三类"文档不自洽"（都已入账）

1. **描述与输出矛盾（BUG-48）**：`project_standards` 返回 R115+ 四态 + cl7，但它的**对外描述**仍写"一源三态/三形态必须对齐/三形态 checklist（cl1 到 cl6）"。白盒锁 `project_standards_wbtest.mbt` 的意图③"文案不得残留三形态"只作用在**输出**上，描述面没人管 ⇒ 116 个客户端读到旧口径。
2. **模板教错调用（BUG-49）**：`check_results` / `dry_run` / `project_dir`（project_standards 根本没有）/ `round` / 已废弃的 `now`。`_instrument` 只校验 `schema.required`，**未知键静默丢弃** ⇒ 照模板执行 = 以为跑了硬门，实际什么都没验。这是 BUG-31/33 的文档面同族。
3. **数值声明无人管（BUG-50）**：`docs/agent-map.md` 写"316 项全绿"（实测 406）。`check_test_sync` 的判据形状是"实测数出现在指定 4 份文档"，结构上测不到"第 5 份文档写着别的数"。**该判据缺口本轮未闭合**，已如实入账。

## 四、资源消耗

- 会话时长 ≈ 27 分钟（含 6 次批量守卫/测试运行）；`moon test --target js` 一轮、`moon build` 一轮。
- MCP 调用 ≈ 60 次（全部落 `call_log`，ns=stdalign）；新增文件 1（规范正文）+ 报告 1 + 驱动 3（`temp/stdalign_verify.py`、`temp/j_before_after.py`、`temp/patch_docs.py`）。
- 未新增依赖、未改 `moon.mod/moon.pkg`、未做 git 写操作、无公开 API 签名变更（只增 `canonical_doc` 输出字段与 R116 版本值）。

## 五、任务分配记录

| 环节 | 承担者 | 说明 |
|---|---|---|
| 现状取证（谁说了什么） | 指挥官 | `grep` 逐面清点 + `temp/docstd_audit.py` 首轮稽核（17 条旧口径 + 14 条模板违例） |
| 规范正文成文 | 指挥官 | 唯一新文件，属"定义契约"级写作，不下放 |
| 批量口径替换 | 脚本 `temp/patch_docs.py` | 35 条替换，每条断言命中次数，任一不中则整批不落盘 |
| 判据扩展 | 指挥官 | J6/J7/J8 + `--selftest` 合成违例 |
| 生命周期与取证 | FIST 自身（dogfooding） | publish→task_plan_deep(omega+boundary+reinject)→叶级 Omega 链→claim→execute→verify |

## 六、遗留风险

1. **J8 只覆盖 `templates/*.md`**：`docs/*-skill.md` 里的调用示例暂未纳入同一判据（skill 文档格式更自由，depth-1 提取需先归一化代码块），当前只由 J7 管旧口径。
2. **数值声明无判据**（BUG-50 未闭合部分）：需要"全量文档 + 历史数字豁免"的判据重设计，否则 `check_test_sync` 的白名单形状永远测不到第 5 份文档。
3. **正文与投影仍是"约定同文"**：J6 校 id 与版本号，但正文里每条规则的**表述**与 `.mbt` 里的 `body` 文本不逐字比（比了会把正常的措辞差异判成漂移）。语义等价靠 verify 模式人审。
4. 重复入账 BUG-45/46/47 暴露驱动缺幂等：重跑同一审计脚本会重复 `report_bug`。
6. **新发现 BUG-51（已入账，未修）**：路径口径在工具间相反——`report_bug`/`bug_list` **拒绝**绝对 `project_dir`，而 `run_check` 又**拒绝** `workdir="."`（任务记的是绝对根，判"与项目不同根"）⇒ 照同一个相对根跑完整 verify 链路必卡在第 3 步。本轮改为 `run_check(workdir=<绝对根>)` + `output_validate(check_key)` 走通（verdict=pass / l4-pass），但**口径本身需要统一或在各工具描述里写明**，属策略决定，交裁决。
7. 驱动重跑不幂等：同一审计脚本跑两次会重复 `report_bug`（本轮产生 BUG-45/46/47 三条重复条目，已在账本内标注交叉指向 48/49/50）。

5. 四宿主插件态是生成投影，未在真实宿主内装载验证（既有边界，本轮只重投影未验证装载）。

## 七、后续建议

1. 把 J8 的调用面判据从 templates 扩到 `docs/*-skill.md`（先统一 skill 文档的示例代码块格式）。
2. 重设计 `check_test_sync` 为"全量文档数值声明清点 + 白名单豁免"，闭合 BUG-50 缺口。
3. 给 `report_bug` 加幂等键（同 summary 二次上报返回既有 id），无人值守轮次才敢重试。
4. 目标项目接入路径已写进规范 §2；建议下一轮用另一份真实项目（如兄弟项目）试跑一遍，检验"规范可移植"这条主张。

## 八、超额内容（未要求但做了）

- 除文档对齐外补了 `--selftest` 合成违例与 HEAD 单调性证明（无这两条，"新判据"可能只是装饰）。
- 顺手清掉模板里 4 处已废弃的 `now` 广告（BUG-33 的文档面残留）。

## 九、来源

- 规范正文：`AI-DEVELOPMENT-STANDARD.md`（R116）
- 机器投影：`src/server/project_standards.mbt` + 白盒锁 `src/server/project_standards_wbtest.mbt`
- 判据：`scripts/check_doc_surface.py`（J1-J8）
- 取证：`temp/stdalign_verify.py`、`temp/j_before_after.py`、`temp/docstd_audit.py`、`temp/patch_docs.py`
- 账本：`memory/bugs.md` BUG-45~50（含 FIXED 段与重复标注）

*（内容由AI生成，仅供参考）*
