---
status: 提案中
decided_by:
decided_at:
decision:
---

# F094 Phase 3 · worktree 派发编排（wt_dispatch / wt_collect）

> 日期：2026-11-20 ｜ 目标版本：0.3.14 ｜ 状态：实施中
> 前置：Phase 1 已收口（0.3.13：file_binds 跨进程账本 + fb_txn + 生命周期挂钩 + 构建互斥）。

## 一、现状（侦察结论）

| 件 | 状态 |
|---|---|
| `wt_create_impl` / `wt_status_impl` / `wt_destroy_impl` | ✅ 完整：manifest 生命周期账（created_sha 锚点、ttl_min stale 判定）、porcelain 解析、reclaimable 判定 |
| `wt_status` 的 merged 判定 | ✅ 已有 `wt_merged_yes` + **脏先看**裁决序（脏+已并入 ⇒ blocked，防 ff 后误回收） |
| 派发编排 | ❌ 无：执行器自己手搓 worktree 路径/分支，管家无编排入口 |
| 合并收口 | ❌ 无：wt_destroy 只回收，分支成果合回主线需人工 git 操作 |

## 二、实施项（纯编排层，不碰 wt_* 已有语义）

### T1 · `wt_dispatch`（按执行器分配沙箱）
- 入参：project_dir(必)、task(必)、executor(必)、base(可选缺省 HEAD)、ttl_min(可选缺省 120)
- 行为：沙箱路径 = `<project_dir>/wt/<task>-<executor>`、分支 = `wt/<task>-<executor>`（同账复用：同 task+executor 已存在且 reclaimable ⇒ 幂等返回已有沙箱）；内部复用 `wt_create_impl`
- 回执：{ok, path, branch, task, created_sha, reused}
- 红线：路径/分支命名一律由服务端推导，调用方只给 task/executor——防路径注入

### T2 · `wt_collect`（合并收口 + 回收）
- 入参：project_dir(必)、task(必)、executor(必)、force(可选缺省 false)
- 脏先看：沙箱有未提交改动 ⇒ blocked（提示先 commit）；merged 已并入 ⇒ 直接回收
- 合并：`git merge --ff-only wt/<task>-<executor>` 打回主线；ff 不可行 ⇒ blocked + 点名（合并冲突由管家 reject 协调，force=true 才允许 --no-ff 强并）
- 收口：merge 成功后 `wt_destroy` 回收沙箱 + 账归档

### T3 · 构建互斥联动
- wt_collect 的 merge 属构建类操作：FIST_BUILD_MUTEX=1 时受 scope=build 互斥约束（复用 0.3.13 的 fb_build_mutex_acquire/release）

## 三、验收

- [ ] 双执行器 dispatch → 两个沙箱互不可见、分支各自独立
- [ ] executor 提交 → wt_collect ff-merge 回主线 → 沙箱回收、账归档
- [ ] 未提交改动 collect ⇒ blocked；ff 不可行（主线也前进了）⇒ blocked 点名
- [ ] 幂等：同 task+executor 重复 dispatch 不重建
- [ ] js 全量回归全绿 + e2e 入库 + 0.3.14 发布

## 四、红线

零新依赖；不碰 wt_* 既有裁决序（脏先看/manifest 锚点语义原样复用）；fail-closed；凭据走环境变量。
