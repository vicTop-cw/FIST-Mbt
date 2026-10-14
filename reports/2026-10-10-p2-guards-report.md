# P2 守卫族三新增候选收口报告 · 2026-10-10

## 结果摘要

将三个 P2 守卫候选（`check_model_auth_no_key` / `check_host_installable` / `check_skill_inject`）从「脚本已实现但文档未收口」推进到「AGENTS.md + README.md 双文档面同步」。三个脚本此前已在 commit `1934472` 收口（全量 rc=0），本轮补齐文档面。

## 资源消耗

- 时间：约 15 分钟
- 文件改动：AGENTS.md（+3 守卫条目）、README.md（+3 walkthrough 行）
- 未运行 `moon test`（纯文档改动，无 MoonBit 代码变更）

## 任务分配记录

通过 fist-mbt CLI（`scripts/fist.py`）发布根任务 T0r8，plan_deep 拆 4 组 12 叶，认领 T0r8.1.1 执行。

## 遗留风险

- CI 未更新：三个新守卫需加入 ci.yml JS 轨（当前未改 workflow）
- `check_host_installable.py` 的 T7 反向对照此前有 schema 混判问题（cordis.patch.yml vs mcp_config_scaffold 表单白名单），需确认是否已修

## 后续建议

- 将三个守卫加入 `.github/workflows/ci.yml` 的 JS 轨步骤
- 运行 `check_doc_surface.py` 验证文档面 J1-J15 无回归
- 运行 `check_tools_sync.py` 验证工具计数自述面无漂移

## 超额内容

- 使用 fist-mbt CLI 全流程（publish → plan_deep → claim → execute）驱动任务，验证 CLI 形态可用

## 来源

- `docs/improvement-plan-20261010.md` §6.2 新增守卫候选
- `memory/2026-10-10.md` line 14（P2 三守卫收口记录）
- commit `1934472`（P2 三守卫脚本实现）
