# 获奖提升 · R18 汇报：文档/资源一致性修复（文档即实现扫尾）

> 日期：2026-09-25｜目标 pillar：项目整洁干净（文档与功能统一）＋ 结构化项目（让 agent 读项目一目了然）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮为一致性修复（不新增工具/测试）。

## 结果摘要
- **"文档即实现 + 项目整洁"扫尾**：全仓 grep 陈旧工具/测试计数，修两处漏网：
  1. `docs/agent-map.md`「工具分组概览」过期严重——标题还是 70 个、DAG(8)、把 board/status_summary/reserve/critic/challenge 都漏了 → 对齐 AGENTS 现分组（看板/脉冲/预订+DAG(11)、自我记忆/自进化(7)…），标题改为 **77 个**；
  2. `src/server/server.mbt` 里 `fist://map` 资源的「MCP 层 76 工具」→ **77**（让 agent 首读的地图也与实一致）。
- 顺带确认 `fist://overview`/`status_summary` version=0.2.4 与 moon.mod 一致；`atgc-selfdrive-demo.md` 的 191/191 与申报书 R4 的 199/199 均属历史快照，不误改。
- 验证：`moon test --target js` **216/216** 全绿；`moon build` 0 错误。工具数/测试数不变（77/216），纯文案/资源一致性。

## 资源消耗
- 修改：`docs/agent-map.md`（分组表对齐 + 标题），`src/server/server.mbt`（map_json 文案），`memory/2026-09-25.md`（R18）。
- 测试：无新增（不改语义）。

## 任务分配记录
- 直接实现（指挥官终审制）：以证据驱动（grep 全部 md/py 计数 + 核对 moon.mod 版本）；`moon test`/`moon build` 实机验证通过。

## 遗留风险
- `@fs.tmpdir` 在本工具链 `x/fs` 未暴露（memory 预警），"测试落盘收敛到系统 tmp" 的根因修复暂不可行，仍以 `cleanup_artifacts.py --check` 作整洁门禁兜底。
- `atgc-selfdrive-demo.md` 等历史快照文档保留当时数值（属 demo 记录，非当前项目计数）。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **Marketplace / Dynamic 能力路由**（远期，executor 抽象层朝"能力注册 + 按负载/专长分配"）；
  2. **OpenTelemetry per-tool span**（低优先，单机场景价值有限）；
  3. 若要根因去生成物，可自建一个 `@fs.tmpdir` 等价物（读系统 env TEMP/TMPDIR），再批量迁移测试落盘（中等改造）。

## 超额内容
- 把 agent-map 分组表与其说"8 大分组"改为"分组概览"，使其不再因工具数变化而频繁失禁。

## 来源
- 现状：`moon.mod`(version=0.2.4)、`git/README/AGENTS/ARCHITECTURE/USAGE/deliverable/申报书` 计数审计。
- 代码：`docs/agent-map.md`、`src/server/server.mbt`（map_json）。