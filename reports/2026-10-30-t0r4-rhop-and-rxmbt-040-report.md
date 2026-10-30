# T0r4 交付报告：rhop 两入口直测 + 上游修复 + RX-MBT 0.4.0 发布与升级

> 任务：`T0r4`（ns `fist-plan-20261029`，P2，**已按实测订正范围**）｜认领：`lead`
> rx-mbt 提交：`6f8e49d`（修复 + 9 格入口测试 + 账本）｜发布：`moon publish` → 0.4.0
> fist-mbt 提交：`4ecb9d3d`（依赖升级 + 删补丁 + 删 7 处 CI 步骤）

## 一、结果摘要

| 项 | 读数 |
|---|---|
| rx-mbt rhop 套件 | **172/172**（基线 163 + 9 格新入口测试） |
| rx-mbt 全仓 js | **860/860** |
| 0.4.0 发布 | `moon publish` → Check passed / Server status: 200 OK；沙箱项目 `moon add ...@0.4.0` 可解析，cache 有 `0.4.0.zip` |
| fist-mbt 全量 | **1964/1964**（升级后独立复跑） |
| 守卫 | `check_tools_sync` PASS、`check_test_sync --total 1964` PASS、`check_doc_surface` PASS |

## 二、订正后的 T0r4 范围（原任务书前提已被推翻）

原任务书写「rhop native 真实现 + rx-mbt 测试基线」，前提「0 测试 ⇒ 0/0 空真」**被实测推翻**
（rhop 有 163 格测试，全仓 851 全绿）。改后范围是两件**实测证明站得住**的事：

1. **给 `rhop_send` / `from_filesystem_with` 两个入口补直接用例**（163 格覆盖的是底层件，这两个入口 grep 0 命中，
   而它们正是 fist-mbt `ops_commissar.mbt:171/:215` 在用的）；
2. **版本对齐**：核对 0.3.0/0.4.0 的 API 签名 → 逐字节相同、零破坏 ⇒ 可直接升，但 registry 当时无 0.4.0 ⇒ 先发布。

## 三、抓到并修掉的真 bug（Windows-only）

`from_filesystem_with(skip_existing=true)` 在 **Windows** 上不生效：`seen` 集合两个来源分隔符口径不一致 ——
订阅种子 `ffi_list_files`（`rhop_js.mbt:176`）用 node `path.resolve` 产**反斜杠**，事件 `ev.path` 走 `join_path`
（`rhop_js.mbt:142` / `monitor/watcher_js.mbt:48`）产**正斜杠**（混合形态 `C:\...\dir/old-1.rhop`）⇒ 键对不上 ⇒
**订阅前已存在的 `.rhop` 被重放**。Linux/WSL 下两者都产 `/`，不触发 ⇒ **「WSL 绿不能代表 Windows 绿」的又一实例**。

**影响面**：fist-mbt `src/ops/ops_commissar.mbt:215` 正传 `skip_existing=true` ⇒ Windows 上政委 watch 重放历史信号。
**反证**：`RhopWatcher::skip_existing`（`watch.mbt:313`）用 `join_shared`（内部 `normalize_path`）预填 `seen`，
它的 skip_existing 用例是绿的 ⇒ 只有 `from_filesystem_with` 这支不一致。

**修法**（最小改动）：新增私有 `seen_key(path) = normalize_path(path)`（复用同包既有 `transport_local.mbt:76`），
在事件处理的 contains/add 与 `seed_seen_from_listing` 的 add 三处统一归一化 —— 无论 `shared_path` 是 `/` 还是 `\`
形态、无论哪个来源产的路径，落进 `seen` 的键都同口径。改动仅 `rhop/rhop_js.mbt`（+16/−3），`.mbti` 接口零变化。

**变异对照**：`seen_key` 退化为 identity ⇒ 同一格**重红**（`171/1`）；还原 ⇒ `172/172`。

## 四、账本与发布（按用户决定）

- bug 记在 **rx-mbt 自己的 `memory/bugs.md`**（该仓此前无账本，按 FIST-Mbt 口径新建）：`BUG-1 [high] FIXED`，
  含定位、纯 node 最小复现、平台差异说明、以及未修的同族隐患（`rhop/watch.mbt::handle_event` 的 `ev.path` 未归一化）。
- 用户授权后发布 **0.4.0**。
- fist-mbt 侧 `moon.mod` 升 `@0.4.0`、删 `patches/rx-mbt-bug480/`、删 **7 处** reapply 步骤
  （`ci.yml` ×3、`fist-ci.yml` ×2、`release.yml` ×2）。

## 五、阻塞点与处置（子代理上报，我同批收掉）

子代理守住红线只动 `ci.yml`/`fist-ci.yml`，但**上报** `release.yml` 还有 2 处 reapply 步骤 ——
补丁删了它们必 bash 127 ⇒ release 臂挂 ⇒ Release 零资产（BUG-488 同类）。**这是我这一改直接造成的后果**，
故与升级同批收掉（`4ecb9d3d`），并把「发布产物必须带补丁」的注释改写为「上游 0.4.0 已原生修复」。

## 六、缺口与风险（诚实标注）

1. **`check_plugin_sync` 红，与本单无关**：子代理已 A/B 证明（把 `moon.mod` 还原成 `@0.3.0` 仍报同样的 9 文件漂移），
   真因是并发 lane 的 BUG-490 账本变更尚未重新生成插件投影。按纪律未改 `memory/bugs.md`/`plugins/` 去「修绿」。
2. **2 处 `src/` 过时补丁注释**未动（属他人文件）：`src/ops/ops_bug480_watch_probe_wbtest.mbt:14`、
   `src/server/server.mbt:11011`，建议后续改成「上游 0.4.0 已原生修复」。
3. **未修的同族隐患**：`rhop/watch.mbt::handle_event` 把未归一化的 `ev.path` 直接喂 `process_file`/`seen`，
   现有 skip_existing 用例只走同步路径没暴露；建议另立单在 `handle_event` 前归一化。
4. **回退风险**：若有人把 `moon.mod` 回退到 0.3.0，`ops_bug480_watch_probe_wbtest` 会重新挂住（回退场景，非本次引入）。
5. **子代理的补丁删除未生效**：`patches/rx-mbt-bug480/reapply.sh` 在我复核时仍在（可能被并发 lane 恢复），
   由我 `git rm` 收掉（`4ecb9d3d`）。

## 七、后续建议

1. 清理那 2 处 `src/` 过时补丁注释（低风险）。
2. 跟进 `rhop/watch.mbt::handle_event` 的同族归一化（rx-mbt 侧）。
3. 让 BUG-490 账本 lane 重新生成插件投影，消除 `check_plugin_sync` 的红。

## 八、来源

- 上游对表：`reports/2026-10-29-plan-reconciliation-report.md`（指出 F094 / rhop 的真实缺口）
- 4pools 提案（含 2026-10-30 对「0 测试」说法的订正）：`docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md`
- rx-mbt 账本：`memory/bugs.md`（BUG-1）
