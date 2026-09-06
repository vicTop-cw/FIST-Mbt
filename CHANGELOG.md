---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode1: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode2: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
---

# CHANGELOG

本项目变更记录（参赛期间每日至少 1 条，保证提交可追踪）。

## [0.1.0] - 2026-09-05

### 首版（root commit 147e642）

- 新建 MoonBit 工程 `vicTop-cw/fist-mbt`，声明依赖 colmugx/mcp@0.17.4、mizchi/sqlite@0.3.1、
  moonbitlang/async@0.21.0。
- 领域核心：
  - `core_task.mbt`：任务实体 + 七态状态机（待领取/已领取/拆分中/执行中/待验收/已完成/已归档）与状态迁移校验。
  - `core_role.mbt`：八角色权限矩阵。
  - `core_principle.mbt`：FIST 七条金条原则。
  - `store.mbt`：Store trait + MemoryStore 内存实现。
  - `engine.mbt`：FistEngine 完整闭环（publish/plan/claim/execute/submit/verify/archive/list/get/delete）。
- MCP 层：
  - `server.mbt`：注册 10 tools + 2 resources（fist://principles、fist://overview）+ 2 prompts（fist:check_in、fist:verify）。
  - `cmd/main`：async 可执行入口，`run_stdio()` 启动 STDIO 传输。
- 修复记录：
  - 根包别名含点号非法 → 使用 @mcp_types/@mcp_resource。
  - main 入口 async/raise 问题 → 引入 moonbitlang/async 并改用 `catch` 包裹 run_stdio。
  - engine.claim 此前一步跳到「执行中」，导致 plan（要求已领取）无法走通 → 改为 claim 只做
    待领取→已领取，execute 进入执行中；同步更新 server 文案。
- 质量：`moon test` 7 项黑盒单测全绿；MCP STDIO 全链路冒烟通过。
*（内容由AI生成，仅供参考）*
