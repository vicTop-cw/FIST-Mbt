# 轮 198 唤醒巡检报告（WIP diff 足迹基线换面）

- **时间**：2026-11-11 20:00（UTC 12:05 记账）
- **轮次**：r198（ExploreWatchdog）
- **前序**：r197（e8b1c8cbe）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 3 文件） | `src/server/mcpcf_embed_bug583_wbtest.mbt` 14:29 / `scripts/run_guards.py` 14:33 / `memory/bugs.md` 14:35 |
| 冻结时长 | ~5.4h（14:35 → 20:00） |
| **diff 足迹（本轮新基线）** | **15 文件 +281/−64，无暂存** |
| 新提交 | 无（r193 738831411 后零功能性新提交，r194–197 均为巡检报告） |
| 状态位 | 已知挂起，r193 已升级 owner 决策，按既定不再重复上报 |

禁区遵守：WIP 文件未 touch（本轮只读 + 新建 `reports/` 一份）。

## Round C 队列

确认过期（r195/r196/r197 已核实，不重复）：BUG-527 owner 否决（e0ef45c5e 回滚）/ BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册（run_guards.py:175）。

## 换面巡检：WIP diff 足迹面（r194–197 未扫过的新面）

**为什么换这一面**：前几轮对「WIP 是否还活着」的证据只有 **mtime**（最后一写时刻）。
mtime 只能证明「最后一次写是 14:35」，证明不了「这坨改动有多大、是不是完整的一步」。
本轮补 **diff 足迹**（改动行数 + 暂存面）作为第二个独立硬证据轴：

| 维度 | 读数 | 含义 |
|---|---|---|
| 文件数 | 15 | 一次规模不小的跨面改动（文档 12 + 守卫脚本 + 白盒锁 + 黑盒探针） |
| 行数 | +281 / −64 | 净增 217 行，偏「新增/加固」而非「重写」 |
| 暂存面 | 空（`git diff --cached` 无） | WIP 未走到 `git add` 阶段，仍在编辑中 |
| stray DB | `fist-mbt.db `（尾随空格、0 字节、14:37） | r197 已定性，维持不立账不删 |

**足迹判读**：15 文件 +281/−64 + 无暂存 + mtime 冻结 5.4h ⇒ 这是一坨**已经成型但未收口**的
改动（代码量足以自洽），不是「刚开始摸」。对 owner A~D 裁决的参考价值：**若 WIP 一路已死，
这 281 行是可直接评估的半成品**，不是散沙。

### WIP 定性（读 diff 得出，供 owner 裁决用）

WIP 是 **BUG-591 ⑤ + BUG-588 ② 探针/注入加固面**，性质合法（非越界、非破坏）：

1. **BUG-591 ⑤（`scripts/run_guards.py` +19 / `e2e_acceptance_recheck.py` +245）**：
   把 `e2e_acceptance_recheck.py --selftest` 从「要真 server」改成**内存级**（不 spawn server、
   不碰 node/js/sqlite，缺前置回 rc=2），并进 `SPECIAL_CASES`（`case(..., "--selftest")`）、
   从 `REGISTRY` 移出（避免「同一脚本既有 case 又在 REGISTRY，读起来像在册但不跑」）。
   补 ST5/ST6/ST7 三格：六格承诺清单完整性（承诺表缩水或某格 record 被搬走 ⇒ rc=2 自拒）。
   六格**活体**面仍手动（`--selftest --live`）。
2. **BUG-588 ②（`src/server/mcpcf_embed_bug583_wbtest.mbt` +31）**：
   新增格 5 `bug588_02_ops_init_data_dir_redirects_db`——`mcpcf.ops_init(data_dir=…)`
   把 SQLite 落到注入目录、回执 db 字段逐字回报；不传 data_dir 回默认。
   注释如实标注**残余**：其它工具走的 `ensure_engine()` 仍按 env/LOCALAPPDATA fail-open 自建库。

**判读**：两件事都是「给文档承诺补真守卫 + 给数据目录注入补白盒锁」，与本仓
「判据自证 / 承诺面不许文档自称」的纪律同向。**若 WIP 一路死掉，这坨改动值得 owner
评估是否直接收口**（方向对、量成型），而不是作废重来。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r194 | OFM 端点 + byte-slice | 容忍诊断 / PASS |
| r195 | check_host_installable + byte budget | PASS / PASS |
| r196 | NUL-byte（src+scripts） | 干净 |
| r197 | untracked / stray-DB | 1 项 0 字节异常（已定性，不立账不删） |
| **r198** | **WIP diff 足迹 + WIP 定性** | **15 文件 +281/−64 冻结、方向合法，半成品可评估** |

## FIST 闭环

ns `iter-1111r198w`：publish（T0，附 BUG-411 两道门警告）→ acl_grant（wd-r198 can_write=true，
granted_rows 落库）→ claim（已领取）→ execute（执行中，deliverable 指本报告）→ submit（待验收）
→ verify（**已完成**，completed_by=wd-r198）⇒ **全链绿，T0 收口**。

## 遗留

- WIP 挂起 ~5.4h（15 文件 +281/−64 成型未收口），等 owner A~D 裁决（不重复上报）。
  **给 owner 的增量信息**：这坨是 BUG-591 ⑤ / BUG-588 ② 加固面、方向合法且量成型——
  若 WIP 一路已死，可直接评估收口，不必作废。
- `fist-mbt.db `（尾随空格、0 字节）未跟踪未忽略：WIP 收口时建议清掉。
- 本地领先远端 128+ commit（历史积压，推与否归 owner）。
