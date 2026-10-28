# 待上报缺陷（MCP `report_bug` 不可用，Lane CL 本地代拟）

> **收件人：统帅**。本单 MCP 工具（`report_bug` / `output_validate`）不可用，
> 请代为调用 `report_bug(publish_task=false)` 上报下列 1 条。

---
## summary（照抄）
```
[gate] 9 个生命周期工具无任何身份门（BUG-467 同族）：delete/archive/submit/reject/retry/pause/resume/reopen_task/plan
```

## severity
`high`

## details（照抄）
```
【按形状搜的普查结果】机械扫描 server.mbt 的 14 个生命周期工具代码面（跳注释），
检测 8 种身份门形态。

结论：只有 3 个真有身份门（claim / execute / verify），9 个该有没有：
  delete / archive / submit / reject / retry / pause / resume / reopen_task / plan
另有 2 个（publish / publish_parallel）只有 ns_write_gate（ns 合法性，不看调用者），
其口子是 S1 的 created_by 自报，与这 9 个不同类，不混算。

【佐证】全仓 agent_write_gate 调用点只有 3 处：
  server.mbt:2154 (claim) / 2287 (execute) / 2500 (verify，上单 BUG-467 新加)

【判据】9 个都真调用了会改任务状态的引擎函数：
  plan→update_task+建子任务 / submit→eng.submit / reject→eng.reject_task /
  retry→eng.retry_task / pause→eng.pause_task / resume→eng.resume_task /
  reopen_task→eng.reopen_task / archive→eng.archive_force / delete→eng.delete_task
⇒ 符合「该动作改变任务状态 ⇒ 必须有门」。

【危害分级】
  最高危：delete / archive（不可逆：物理删除 / 归档后极难恢复）
  高危：submit / reject（质量闸门：盖章通过或被恶意打回）
  中危：retry / reopen_task / pause / resume / plan

【修法可行性（已验证）】
  acl_identity_pick 兜底为空身份 ⇒ "manual"（implicit=true）
  ⇒ 新增可选 agent 参数、缺省空 ⇒ 身份=manual：内存后端放行（零回归），
    sqlite 面 manual 无 can_write ⇒ 被拒（fail-closed），正是所需。
  但 7 个连身份参数都没有（只有 reject / archive 有 by），
  修法必须「新增可选 agent + 一道门」，不能直接照抄 verify（它复用现成 verifier）。

【建议】拆 3 单：不可逆类（delete+archive）→ 质量闸门类（submit+reject）
→ 状态类（其余 5）。

证据：reports/2026-10-28-lifecycle-identity-gate-audit.md
扫描脚本：temp/audit/lane_cl_gate.py
```
