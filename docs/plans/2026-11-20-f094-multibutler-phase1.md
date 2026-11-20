# F094 Phase 1 收口 · file_binds 落库 + 生命周期挂钩 + 构建互斥

> 日期：2026-11-20 ｜ 目标版本：0.3.13 ｜ 状态：实施中
> 前置核查：BUG-119 已 FIXED（`scripts/blackbox/e2e_heartbeat_xproc.py` 8/8 + CI Heartbeat cross-process guard）——多 agent 并行硬前置满足。

## 一、现状（侦察结论）

| 件 | 状态 |
|---|---|
| `src/filebind/filebind.mbt` 纯逻辑层 | ✅ 完整：23 pub fn（fb_decide/fb_plan_bind/fb_apply_bind/fb_match/fb_plan_release/fb_apply_release/fb_ledger_parse/serialize），`now` 可注入，24 格白盒锁 |
| `server.mbt` 三工具（file_bind/file_release/file_status） | ✅ 已注册，但账本 = **进程内 Map**（`FileBindStore.ledger`，key=`ns|project_dir`） |
| 跨进程可见性 | ❌ 进程重启即丢绑定 → 多管家互踩 |
| 生命周期挂钩（§3.3） | ❌ verify/archive 自动 release、watchdog TTL 清理均未接 |
| 构建互斥（§四 Phase 2） | ❌ scope=build 未接 run_check |

## 二、实施项

### T1 · file_binds SQLite 表（跨进程可见性）
- `store_sqlite.mbt` 增表：
  `CREATE TABLE IF NOT EXISTS file_binds (id INTEGER PRIMARY KEY AUTOINCREMENT, ns TEXT NOT NULL DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', task_id TEXT NOT NULL, agent TEXT NOT NULL, path TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'file', scope TEXT NOT NULL DEFAULT 'edit', bound_at TEXT NOT NULL DEFAULT '', ttl_secs INTEGER, released_at TEXT)`
- Store trait 增三方法：`fb_list(ns, project_dir)` / `fb_upsert(rows)` / `fb_mark_released(ns, project_dir, task_id)`
- server 侧 `FileBindStore.ledger`（进程内 Map）改为**每次操作直读直写 store**——进程内 Map 降级为缓存或直接删除（取单一真相原则：持久化表是唯一真相，与 BUG-119 的修复哲学一致）
- 内存后端（MultiStore 的 memory 分支）：同语义内存表，保证双后端一致性测试可通过

### T2 · 生命周期挂钩（§3.3）
- verify / archive 成功路径 → 自动 `fb_plan_release + apply_release` 该任务全部 edit 绑定（服务端盖章，不靠 agent 自觉）
- reject / reopen → 绑定保留（打回重做还要用）
- watchdog_tick 顺带清理 TTL 过期绑定（复用既有看护 tick，不新增定时面）

### T3 · 构建互斥（scope=build）
- `file_bind(scope=build, ttl=构建超时)`：同项目同时只允许一个 build 绑定
- `run_check` 等构建类工具执行前自动 acquire（默认 advisory 开关 `FIST_BUILD_MUTEX=0`；多 agent 场景开 enforce）
- 冲突 → 返回持锁者信息，fail-closed

## 三、验收（§七）

- [ ] 两进程同时 bind 同一文件，恰好一成一拒（SQLite 事务 + 常驻黑盒判据）
- [ ] TTL 到期自动失效（watchdog_tick 清理）
- [ ] verify/archive 自动 release；reject/reopen 保留
- [ ] 单 agent 零回归（不开绑定时行为逐字不变）
- [ ] `moon test --target js` + native 全绿；黑盒 e2e 新臂入库
- [ ] 版本 0.3.13 发布（mooncakes + 双远端）

## 四、红线

零新依赖；v1.0 规则向后兼容；fail-closed；持久化表是唯一真相（进程内状态不许冒充落库，BUG-119 同族哲学）；凭据走环境变量。
