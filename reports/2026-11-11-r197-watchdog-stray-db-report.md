# 轮 197 唤醒巡检报告（untracked / stray-DB 换面）

- **时间**：2026-11-11 19:31
- **轮次**：r197（ExploreWatchdog）
- **前序**：r196（b6e23f696）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 3 文件） | `src/server/mcpcf_embed_bug583_wbtest.mbt` 14:29 / `scripts/run_guards.py` 14:33 / `memory/bugs.md` 14:35 |
| 冻结时长 | ~5h（14:35 → 19:31） |
| 新提交 | 无（r193 738831411 后零功能性新提交，r194–196 均为巡检报告） |
| 状态位 | 已知挂起，r193 已升级 owner 决策，按既定不再重复上报 |

禁区遵守：WIP 文件未 touch（本轮只读 + 新建 `reports/` 一份）。

## Round C 队列

确认过期（r195/r196 已核实，不重复）：BUG-527 owner 否决（e0ef45c5e 回滚）/ BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册（run_guards.py:175）。

## 换面巡检：untracked / stray-DB 面

**目标**：本轮换到前几轮没扫过的一面——仓库根的**未跟踪文件**与 stray DB（BUG-122/455 族特征：根目录曾积 81 个 `*.db`）。

| 文件 | 大小 | mtime | 备注 |
|---|---|---|---|
| `.aider.chat.history.md` | 5.8KB | 11-08 11:04 | aider 历史，无关本仓功能 |
| `.aider.input.history` | 1.7KB | 11-08 11:04 | 同上 |
| `.qoder/` / `.workbuddy/` | 空目录 | 11-06 / 11-03 | 空，无内容 |
| **`fist-mbt.db `（尾随空格）** | **0 字节** | **11-11 14:37** | **本轮新发现** |

### 发现：0 字节 `fist-mbt.db `（尾随空格）

- **形状**：仓库根、**未跟踪且未被 gitignore**（`git check-ignore` 无命中）⇒ 会污染 `git status`、有被 `git add -A` 误纳的风险（本仓纪律明令禁 `git add -A` / `git add <目录>`）。
- **尾随空格是异常**：代码面默认路径 `src/store/store_sqlite.mbt:173` `let default_db_path : String = "fist-mbt.db"`（**无空格**），且白盒锁 `src/store/store_db_path_wbtest.mbt` 钉死 `db_path_from_env(None) == "fist-mbt.db"` ⇒ **代码路径产生不了带空格的名字**。⇒ 尾随空格是**外部来源**（`FIST_DB_PATH` 环境变量尾部空格，或某条 shell 命令文件名误带空格）。
- **0 字节**：未写入任何行 ⇒ 无数据、无功能影响；最可能是「打开即失败/空建」后留下的空壳。
- **时间窗**：mtime 14:37 落在 WIP 窗口内（承重文件 14:29–14:35 之后）⇒ 大概率是 WIP 那一路自己的副产物。

### 处置（本轮不修、不删）

- **不立 BUG-NNN 账**：① 0 字节无功能缺陷；② 落在另一 agent WIP 窗口、其 `memory/bugs.md` 14:35 刚被改，立账会越俎代庖其诊断；③ 代码本身正确（常量 + 白盒锁均无空格）⇒ 这不是代码缺陷，是外部来源的卫生面。
- **不删文件**：不可逆 + 可能是 WIP 一路的在途文件（禁区意识）。
- **给 owner / WIP 一路的提示**：`fist-mbt.db `（尾随空格、0 字节）未进 gitignore，收口 WIP 时建议一并清掉，避免污染 `git status`。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r194 | OFM 端点 + byte-slice | 容忍诊断 / PASS |
| r195 | check_host_installable + byte budget | PASS / PASS |
| r196 | NUL-byte（src+scripts） | 干净 |
| **r197** | **untracked / stray-DB** | **1 项 0 字节异常（已定性，不立账、不删）** |

## FIST 闭环

ns `iter-1111r197w`：publish（T0，附 BUG-411 两道门警告）→ acl_grant（wd-r197 can_write=true，granted_rows 落库）→ claim（已领取）→ execute（执行中，deliverable 指本报告）→ submit（待验收）→ verify（**已完成**，completed_by=wd-r197）⇒ **全链绿，T0 收口**。

## 遗留

- WIP 挂起 ~5h，等 owner A~D 裁决（不重复上报）。
- `fist-mbt.db `（尾随空格、0 字节）未跟踪未忽略：WIP 收口时建议清掉，防止污染 `git status`。
- 本地领先远端 128 commit（历史积压，推与否归 owner）。
