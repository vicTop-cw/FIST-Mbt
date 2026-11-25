# T0r58 · longrun 白盒锁补全：checkpoint 写读回环 / resume 状态机 / baton 生成·消费 / guard 熔断与幂等

- 执行身份：codearts（ns=autoplan）
- 日期：2026-11-25
- 任务真源：`.fist-mbt/data/autoplan.db` `tasks` 表 T0r58（status=执行中，描述即本报告四项）
- 约束遵守：只读盘点 + 最小改动；不动 `src/engine/` `src/server/`，不加 MCP 工具（那是 P1 接线轮）

## 一、结果摘要

四项里**三项已有实现且已有白盒锁**，唯一真空是 **baton 的生成/消费**——契约文档（T0r54）早已定稿，但 MoonBit 侧一行实现都没有（`scripts/longrun_cli.py::make_baton` 只是 Python 草图，字段更少）。本轮补上该纯函数层与配套白盒锁，并为「checkpoint 写读回环」补上**真 IO** 往返格。

| 目标项 | 盘点结论 | 本轮动作 |
|---|---|---|
| checkpoint 写读回环 | 实现有（`write_snapshot`/`read_snapshot`），白盒只有内存往返（① 构造→解析） | **新增真 IO 往返格**（写盘→读盘逐项一致），沙箱自删 |
| resume 状态机迁移合法 | 已有实现 + 白盒（② 三合法六非法 + ③ 两层分工 + ⑥ 变异对照） | 零改动，复跑取证 |
| baton 生成/消费 | **零实现、零白盒**（server/engine 无 `fist_longrun_baton`） | **新增 `baton.mbt`**（`baton_body`/`parse_baton`/`BATON_FORMAT`）+ **6 格白盒** |
| guard 熔断与幂等去重 | 已有实现 + 白盒（5 格，含双阈值或关系、任务内作用域） | 零改动，复跑取证 |

**最终读数**：`moon test --target js src/longrun` = **Total tests: 20, passed: 20, failed: 0**（原 12 → 20）；`python scripts/check_fmt_gate.py` = PASS（rc=0）；`moon info` = 0 errors。

**白盒格清单（本轮新增 8 格，全部在 `src/longrun/`）**：

| # | 格 | 钉什么 |
|---|---|---|
| baton-① | body envelope and task projection | 信封八段齐全 + context/progress 由任务体投影（budget_used / checkpoint_path 回显） |
| baton-② | legal package round-trips (no false red) | **合法包不误红**（T0r54 §5 明列）——防两面各说各话 |
| baton-③ | consume gate order | 三道门顺序：非空 → JSON/format → 必填+归属；文案各点名一层 |
| baton-④ | consume rejects each missing required field by name | 契约 §2 **全 14 键**逐格抽掉必拒（含 format / progress 三键 / context 两可选键） |
| baton-④b | consume rejects missing sections | context / progress / next_step 整段缺失必点名拒 |
| baton-⑤ | generate rejects empty required inputs | 生成侧 7 个空入参必拒且点名 |
| baton-⑥ | mutation control: gates present in source | **变异对照**：锚源码真实分支行 |
| rt-① | checkpoint write/read round trip over real filesystem | **真 IO** 写盘→读盘往返（原①只钉内存构造→解析） |

**变异对照实证**（判例-30）：把 `parse_baton` 的归属闸 `if tid != expect_task_id {` 改成 `if false {` ⇒ **2 格同时红**（baton-③「别人任务的接力棒竟被接受」+ baton-⑥「源码里『task_id 归属闸』不见了」），18/20；恢复后 **20/20 复绿** ⇒ 锁真在看，不是恒绿。

## 二、资源消耗

| 项 | 量 |
|---|---|
| 新增实现 | `src/longrun/baton.mbt`（208 行，1 常量 + 2 pub fn + 1 私有助手） |
| 新增测试 | `src/longrun/baton_wbtest.mbt`（395 行，7 格）+ `longrun_wbtest.mbt` 增 1 格 = 共 8 格 |
| 变更文件 | 2 新 + 2 改（`longrun_wbtest.mbt`、`pkg.generated.mbti`）+ `.gitignore` 1 处兜底 |
| 编译/测试轮次 | moon info ×4、moon fmt ×7、moon test --target js ×12（含 3 轮编译错误修正 + 1 轮他方并发 temp 包竞态重试） |
| 额外依赖 | 零新增（复用 `@core` / `@json` / `@fs`，均为包内既有 import） |

## 三、任务分配记录

单 agent 独立完成（FIST 分流决策树「轻任务 → 直接子代理」档；无跨模块重构、无需验证循环外派）。全程未调用 FIST MCP 发布/认领（本任务已由池内直派），收尾按接力棒协议 submit + verify。

## 四、遗留风险

1. **`baton_body` 的 `context.summary` 语义是我方裁定的**：T0r54 §2 只写「当前所处阶段与局面的自解释描述，必填」，没定死拼法。实现取 `description + "；" + deliverable`（唯一可机读的现成语料）。P1 接线时若 owner 要求自由文本 summary，签名需加参数——**这是行为变更，不是 bug 修复**，已在 `baton.mbt` 头注释标注。
2. **契约与 Python 草图不同名**：`scripts/longrun_cli.py::make_baton` 的 context 用 `{description, deliverable, last_baton, checkpoint_path}`、progress 含 `status`，与 T0r54 §2 定稿字段集**不一致**。本轮以 T0r54 为准（该文件 §1 自述「契约定稿」），`baton.mbt` 头注释已写明；Python 侧漂移**未修**（属 T0r57 车道，不在本轮边界）。
3. **白盒不覆盖 server/engine 接线**：`fist_longrun_baton` 工具尚未注册（T0r54 §3/§5 列为 P1 接线轮），故 baton 的 IO 外壳/ACL/审计事件（`longrun_batoned`）本轮零覆盖。
4. **沙箱目录未入 `.git/info/exclude`，而是写入根 `.gitignore`**：理由是 `check_publish_payload` 看的是「工作树 − .gitignore」，`git add -A` 也会带走它。代价是 `.gitignore` 多 4 行噪声。

## 五、后续建议

1. **P1 接线轮**（`fist_longrun_baton`）应直接消费 `baton_body`/`parse_baton`，不要把契约校验再写一遍（判例：同一规则多份实现必漂移）。
2. **集成格缺口**：T0r54 §5 要求「checkpoint→baton→resume 全链后 `last_baton` 为新包且 `checkpoint_path` 仍在」。本轮只做纯函数往返，**全链集成需在 engine 接线后补**。
3. **`scripts/longrun_cli.py` 建议对齐 T0r54 字段集**（或明确标注「草图、非权威」），否则两份实现会在下一次契约演进时各漂一边。
4. 幂等键的**消费副作用顺序**（T0r54 §4.3 的 `<key>-step1` 前缀登记）仍无锁——那属于执行引擎的面，本轮未认领。

## 六、超额内容

无。严格限定在四项 + 实现所需的最小包装（常量命名、接口文件同步、`.gitignore` 兜底），未顺手清理 `scripts/longrun_cli.py` 的字段漂移、未动 engine/server、未加任何 MCP 工具。

## 七、来源

- 契约真源：`docs/plans/2026-11-25-longrun-baton-handover-contract.md`（T0r54，§2 字段裁决 / §3 生成 / §4 消费三道门 / §5 验收锚点）
- 计划：`fist-mbt/plan/draft/2026-11-22-longrun-baton-p0.md`
- 被测实现：`src/longrun/longrun.mbt`（P0，299 行）、`src/longrun/guard.mbt`（P1）
- core 写入口：`src/core/core_task.mbt:329 with_baton` / `:354 idempotency_add`
- 任务真源：`.fist-mbt/data/autoplan.db`（T0r58 / T0r54 / T0r57）
