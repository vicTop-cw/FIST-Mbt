# T0r88 · P2 仓库池 `inbox/processing/processed/failed` 原子 rename（只读盘点 + 最小改动方案）

- 日期：2026-11-25
- 任务：T0r88（ns=`autoplan`，assignee=`atomcode`，created_by=`human_steward`，priority=高）
- 任务源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:25-27`
- 性质：**只读盘点 / 最小改动**；未执行任何不可逆操作（无删除、无发布、无合并、无 push）
- 工作树：dirty（他方 WIP 在场，`scripts/git_pool_bridge.py` 与 `crosspool_bridge.py` 均为 untracked）⇒ 本轮全部 git 操作仅限 scoped `-- <路径>`

---

## 一、结论摘要

| 格 | 结论 | 证据 |
|---|---|---|
| **命名口径分裂**（本任务真正的缺口） | **成立，且是唯一的硬冲突** | 设计真源 `fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:26` 与实现 `scripts/git_pool_bridge.py:38` **逐字一致**：三态 `{inbox, processed, .failed}`。而 active 计划的 P2 写四态 `{inbox, processing, processed, failed}` ⇒ **`processing` 在代码里不存在；`failed` 与 `.failed` 不是同一个目录名**（Windows 大小写不敏感但**点号**两端文件系统通用敏感） |
| `fist-msg-pool` 的协议真源 | **不在本仓** | `git_pool_bridge.py:39` `MSG_POOL_REPO_DEFAULT = "https://gitcode.com/VictorTop/fist-msg-pool.git"`；本仓无克隆、无本地目录。⇒ **该伴生仓的四态结构属代码外部边界，必须读回后才能定 rename 映射**（§五 G1） |
| YAML 池协议可复用 | **成立，实测通过** | `scripts/run_fist_task_pool.py`（已跟踪）：`STATUSES = ("backlog","claimed","done","failed")`；`--selftest` → `SELFTEST OK: 16 格 / RC=0`（含 M1/M2 两格变异对照）；`claim` 移 `claimed/<machine>/` + 写 owner、重复认领必拒；`release` 退 backlog、`archive`→done、`fail`→failed |
| 原子性现状 | **部分原子，跨卷会退化为非原子** | 状态流真源就是 `shutil.move`（`run_fist_task_pool.py:113`）；同盘 `os.rename` 原子，跨盘/UNC 退化为 copy+unlink（Windows `MoveFileExW` 跨卷同样复制）。⇒ 「原子 rename」在当前实现里**没有锁保护**，两进程可同时认领同一文件 |
| `processing` 缺位的后果 | **无法区分「未被领取」与「已被领取在执行」** | 现行 `msg_land()`（`git_pool_bridge.py:122-133`）只在 `processed`/`.failed` 存在时拒绝重投 ⇒ 消息一旦被 watcher 取走、尚未归档，**崩溃即静默重投**（这正是 `processing` 要解决的状态） |
| `mcp-watcher` 依赖面 | **本仓内零命中** | `grep` `src/`/`cmd/`/`tests/` 对 `.failed`/`processed` 仅命中 `ops_commissar.mbt` 的无关 JSON 字段 ⇒ 改名在本仓内**无测试面牵连**；真正消费者在 `mcp-watcher` 仓（不在本工作区） |

**一句话**：本任务不是「把四个目录建起来」，而是**先裁决 `failed` vs `.failed` 与 `processing` 缺位这两处口径分裂**，再给一条单文件常量级最小改动；rename 本身在 POSIX 同目录树下原子、跨介质不原子，这一点必须先说清。

---

## 二、现状盘点（逐条可复核）

### 2.1 现行目录常量与状态流

`scripts/git_pool_bridge.py`（**untracked，他方 WIP，mtime 2026-11-24 17:11**）：

```python
# :37-38
MSG_DIR = os.path.join(".fist-mbt", "msg")
MSG_SUBDIRS = ("inbox", "processed", ".failed")
```

| 函数 | 位置 | 行为 | 原子性 |
|---|---|---|---|
| `ensure_msg_dirs()` | `:117-119` | 幂等建三目录 | — |
| `msg_land(name, content)` | `:122-133` | 落 `inbox/`；已存在于 `processed` 或 `.failed` 则拒绝重投 | 直接 `open(dst,"w")`，**非原子写**（半成品可读） |
| `msg_pull_git()` | `:136-159` | fetch `origin/HEAD` → 读远端 `msg/inbox/*.json` → `msg_land` | 只读远端，无本地 rename |
| `msg_push_git()` | `:162-191` | 临时 index 基于 `origin/HEAD` 构造「仅含 msg 目录现状」的 commit，直接推远端分支 | 不动本地分支、对远端永远 fast-forward |
| `msg_sync_external()` | `:194-223` | 非 git 项目：`<项目名>/{inbox,processed}/` 分项目区，**copyfile**（非 move） | 复制语义，天然留双份 |

**注意**：`git_pool_bridge.py` **自身没有任何 rename/move 调用**——它只做 land 与 push。所以「原子 rename」这一动作**当前完全不存在于消息池代码里**，需要新引入（由 watcher/worker 在「取走」与「归档」两步执行）。

### 2.2 同机任务池（YAML）——协议参照真源

`scripts/run_fist_task_pool.py`（**已跟踪**）：

```
.git/fist/tasks/{backlog, claimed/<machine-id>, done, failed}/
init → publish(收进 backlog) → claim(移 claimed/<machine-id>/ + 写 owner)
     → release(退 backlog) / archive(进 done) / fail(进 failed)
```

关键实现：`Pool.move()` `:107-114` 用 `shutil.move(str(src), str(dst_dir/(tid+".yaml")))`；`claim` 有 `owner_guard`（重复认领 die）、`publish` 有 `dup_guard`（同 task_id 重复收进 die），两者都有变异对照格。

### 2.3 跨机消息池（`crosspool_bridge.py`）——**第三套口径**

`scripts/crosspool_bridge.py`（**untracked**，`:56`）：

```python
SUBDIRS = ("inbox", "outbox", "archive")
```

与消息池的两套命名（`{inbox,processed,.failed}` / `{inbox,outbox,archive}`）**又不同**。⇒ 本仓现存**三套互不相同的池目录词表**（见 §四 表）。

### 2.4 计划文档自身的口径漂移

`2026-11-25-fist-agent-worker-issue1.md:30` 的 P2+ 写「`.fist-mbt/pool/messages` **大写 F 实测口径**」，而同一 active 计划 P2（`:25`）写 `fist-msg-pool` 四态。同时 `.fist-mbt/pool/README.md` §3（2026-11-24 T-XPOOL-1 落地）记的是 `{inbox,outbox,archive}`。⇒ **计划文本内部就有两种写法，且都不等于 `git_pool_bridge.py` 的三态。**

---

## 三、最小改动方案（**只给方案，未执行**）

> 红线：默认不 push 不 merge（计划 `:40`）；`.fist-mbt/msg/` 为机器独有 gitignored 面。

### 方案 A（推荐）：单文件常量 + 兼容别名，不新建第二套实现

改动面：**仅 `scripts/git_pool_bridge.py`**（1 个常量 + 1 处幂等迁移 + 1 处判据）

1. **常量改为四态并保留旧名兼容**（`:38`）：

   ```python
   MSG_SUBDIRS = ("inbox", "processing", "processed", "failed")
   MSG_LEGACY_ALIASES = {".failed": "failed"}   # 只列真存在的旧名
   ```

2. **加一个幂等的 `migrate_msg_dirs()`**（`ensure_msg_dirs()` 内调用一次），只做**同目录树下**的 `os.replace`（POSIX/Windows 同卷原子）：把遗留 `.failed/` 整体并入 `failed/`，**不删旧目录**（先并后弃，留一轮观察期）；冲突文件名按 `name.<sha8>` 去重，不覆盖。

3. **补 `processing/` 语义**：新增 `msg_begin(name)` —— `inbox/<name>` → `processing/<name>`（原子 rename），带 `owner`+`pid`+`ts` 的 `.lock` 伴随文件；`msg_land()` 的重投递判定扩到 `{processing, processed, failed}`（进行中不重投，避免崩溃静默重投）。

4. **判据**（P2 必需，否则下次漂移）：`scripts/check_msg_pool_dirs.py` —— 断言 `MSG_SUBDIRS` 恰为四态、`msg_begin` 幂等、并发两进程只有一个成功（用确定性注入而非 `sleep`，判例-31）；`--selftest` 含至少一格**变异对照**（改坏四态常量 ⇒ 锁必红）。按本仓纪律：新脚本必须同批给执行面（`case(...)` / `expected(kind=...)` / `_`-前缀豁免，判例-5 族），并同步 `scripts/README.md` 条目与 battery 锚点。

**为什么是 A 而不是「直接改成四个目录」**：`git_pool_bridge.py` 是**他方 untracked WIP**，直接改写会与他人在飞的工作撞车；而 rename 兼容性只能靠旧名兜住，不能靠「另起一份」。A 的改动量 = 1 常量 + 1 迁移函数 + 1 判据，符合「最小改动」。

### 方案 B（备选，若 owner 裁定 `failed` 才是唯一权威名）

只把 `MSG_SUBDIRS` 的 `.failed` 改成 `failed` 并加一次性 `migrate`，**不引入 `processing`**。代价：失去「进行中」状态 ⇒ 崩溃重投问题不解决。**不推荐**，除非 owner 明确 `processing` 暂不做。

### 三处必须一并裁掉的口径分裂（否则改了也白改）

| # | 分裂 | 建议 |
|---|---|---|
| S1 | `.failed`（实现）vs `failed`（计划） | 以 `failed` 为准（无点号，跨平台无歧义），`.failed` 保留一轮兼容期 |
| S2 | `processing`（计划）vs 不存在（实现） | 补上（方案 A 第 3 步） |
| S3 | `crosspool_bridge.py` 的 `{inbox,outbox,archive}` vs 消息池 `{inbox,processing,processed,failed}` | **不动**——README §3 已裁决两者是「跨机 vs 同机两套介质」，强行统一会破坏 T-XPOOL-1 的既有判据面（该文件已接 `case("crosspool_bridge.py","--selftest")`，`run_guards.py:687`） |

---

## 四、风险与原子性边界（先说清，避免误信）

| 场景 | 是否原子 | 说明 |
|---|---|---|
| `inbox/` → `processing/`（同目录树、同卷） | **原子** | `os.replace` / POSIX `rename(2)` / Windows `MoveFileExW`（同卷） |
| `processing/` → `processed/` / `failed/`（同卷） | **原子** | 同上 |
| 上述任一跨**卷**（如介质根在 UNC / WSL 挂载 / 不同盘符） | **不原子** | 退化为 copy+unlink，中途失败会留下双份 |
| 跨机（经 `msg_push_git` / `msg_sync_external`） | **不可能原子** | 本质是两次独立提交/拷贝；只能用「manifest 声明 + 接收端按内容哈希去重」实现**效果幂等** |
| 两 worker 并发认领同一文件 | 当前**无保护** | `shutil.move` 无锁；必须引入 `processing/<name>.lock` 伴随文件或 `@store.FileLock` 语义 |

**⇒ 「原子 rename」的正确表述**：**单介质内的目录间移动原子；跨介质/跨机只能做到幂等 + 可恢复，不可能是原子的。** 计划文本若按后者理解，属需求表述需修正（§五 G2）。

---

## 五、验收标准（交给下一轮 P2 实现者）

1. `MSG_SUBDIRS == ("inbox","processing","processed","failed")`，判据锁死（含变异对照）。
2. 迁移幂等：连跑两次 `migrate_msg_dirs()` 结果一致；旧 `.failed/` 内容不丢。
3. `msg_begin` 并发只有一个成功（确定性注入，不用 `sleep`）。
4. `msg_land` 对 `processing/` 内的同名消息**不重投**。
5. `run_fist_task_pool.py --selftest` 仍 16 格 RC=0（YAML 池零回归）。
6. `crosspool_bridge.py --selftest` 仍绿（跨机池零回归）。
7. 报告 + 判据同批入库（scoped `-- <路径>`；不 add `-A`/目录）。

---

## 六、缺口与风险（诚实声明）

| # | 缺口 | 影响 |
|---|---|---|
| G1 | **`fist-msg-pool` 伴生仓未读**（无克隆、无网络凭据确认）⇒ 无法核对该仓现行是 `{inbox,processed}` 还是已有四态 | 若该仓已是四态，则本任务的 rename 对象其实已在仓内完成，改动只需对齐本地常量；若仍是两态，则跨机闭环会把 `processing/` 漏在远端 ⇒ **rename 映射可能因这一格而变** |
| G2 | 计划文本「原子 rename」未区分介质 | 需求表述待 owner 澄清；本报告按「介质内原子」立论 |
| G3 | `git_pool_bridge.py` / `crosspool_bridge.py` **均 untracked** | 本轮未改它们（避免带走他方 WIP）；方案落地时必须确认归属 |
| G4 | 本工作区无 `mcp-watcher` | 消费面（谁真正做 rename）不在可审范围内 ⇒ 方案第 3 步的落点须与 watcher 侧对齐后才能施工 |
| G5 | 本机未跑 `moon test`（P2 未改 MoonBit 源码，纯 Python 脚本面） | 声称「全绿」无意义；YAML 池自检已实测 RC=0 |

---

## 七、来源

- `fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:25-27`（任务真源）
- `fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:26,48-52`（消息池三态设计真源）
- `scripts/git_pool_bridge.py:37-40,105-223,279-361`（现状实现；untracked）
- `scripts/crosspool_bridge.py:56,244-251,317-346`（跨机池第三套词表；untracked）
- `scripts/run_fist_task_pool.py:36,93-169,234-245`（YAML 池协议；实测 `--selftest` 16 格 RC=0）
- `.fist-mbt/pool/README.md` §3（T-XPOOL-1 口径分家裁决）
- `scripts/run_guards.py:683-687`、`scripts/README.md:641,655-683`（两桥的执行面登记）
