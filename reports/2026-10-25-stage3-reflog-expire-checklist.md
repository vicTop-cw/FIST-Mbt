# Stage 3 · 方案 B（`reflog expire` + `gc --prune=now`）执行前 Checklist

> **性质**：**执行前检查清单，非执行文档**。本文档不含已执行动作。
> **起草**：commander-delta · 2026-10-25
> **关联**：`reports/2026-10-25-stage3-git-history-audit.md`（`28b41ae6`）
> **⚠️ 方案 B 不可逆**，须 owner 逐项签字后方可执行。

---

## 〇、方案 B 一句话

```bash
# ⚠️ 不可逆。以下仅为方案，未执行。
git reflog expire --expire=now --all
git gc --prune=now
```

**目标**：释放 `memory/2026-10-22.md` **reflog 独占的 3049 MB（解压）/ 约 1.3~1.7 GB（打包）**。
（该路径历史共 63 个版本 / 5317 MB 解压：分支可达 56 个 / 2268 MB，reflog 独占 7 个 / 3049 MB。
见 §6.1 实测。）
**原理**：这些 blob 只被 **reflog** 引用 ⇒ `gc` 视为可达、不丢弃；`reflog expire` 后它们变成不可达，`--prune=now` 才会真正删除。

---

## 一、备份（**两重，缺一不可**）

### 1.1 已有备份：α 的 `--mirror` 仓库（**已实测验证完整**）

```
路径 : /e/IDEProjects/AI/git-mirror-backup-20261025.git
类型 : bare（--mirror）
体积 : 593M   size-pack: 592.62 MiB
对象 : in-pack 18970
分支 : 284
HEAD : 31825272
```

**✅ 关键验证（本 checklist 新做）**：mirror 里 `memory/2026-10-22.md` 的历史版本覆盖面

```
shell 逐 blob 实测：56 / 56 可寻址，缺失 0
56 个版本合计解压体积：2268 MB（2.22 GB）
抽验：3639afb2 = 639,905,457 字节 ✅  /  7cc99f9a = 639,407,674 字节 ✅
```

**⇒ 结论：即使 reflog 全清、`gc --prune=now` 删掉这 2.22 GB，
56 个历史版本仍可从这个 mirror 完整恢复。**

**这是方案 B 最关键的安全垫** —— 它把「不可逆」降级为「可从 mirror 恢复」。

> ⚠️ **但 mirror 不含 reflog**（`logs/` 目录不存在）。
> 含义：**mirror 能恢复「提交状态」，不能恢复「HEAD 移动历史」**。
> 方案 B 要删的正是 HEAD 移动历史 ⇒ **mirror 不保护这部分，而是保护了内容本身**。
> 这个差别决定了：删 reflog 后**仍能取回那 2.22 GB 的内容**，但**取不回「当时 HEAD 怎么移动的」**。

### 1.2 待做备份：`.git` 整目录快照

```bash
# 在执行方案 B 之前
cp -r /e/IDEProjects/AI/FIST-Mbt/.git \
      /e/IDEProjects/AI/FIST-Mbt/.git.bak-before-reflog-expire
```

| 检查项 | 判据 |
|---|---|
| 磁盘余量 | `df -h /e/IDEProjects` 剩余 **> 3 GB**（.git 2.0G + 余量） |
| 副本完整性 | `du -sh .git.bak-before-reflog-expire` ≈ 2.0G |
| 副本可用性 | `git --git-dir=.git.bak-before-reflog-expire rev-parse --short HEAD` 有输出 |

**为什么 1.1 已有 mirror 还要 1.2**：mirror **不含 reflog**，而方案 B 删的正是 reflog 及其独占对象。
**只有 `.git` 整目录副本才包含 reflog**，是唯一能完整回滚方案 B 的东西。

---

## 二、Worktree 归零确认（**当前不满足**）

### 2.1 现读读数

```
git worktree list  →  6 个
  E:/IDEProjects/AI/FIST-Mbt                              0cfe1e90 [main]
  C:/Users/victo/AppData/Local/Temp/frp-wt                04429a10 [fix/render-release-priority-master]
  C:/Users/victo/AppData/Local/Temp/mergeability-bn5486xy/wt  b5c8a366 (detached)
  C:/Users/victo/AppData/Local/Temp/mergeability-okca3qgu/wt  95e3808a (detached)
  C:/Users/victo/AppData/Local/Temp/mergeability-xd7gqcjf/wt  b5c8a366 (detached)
  E:/IDEProjects/AI/light-wt/cmd-beta                     d0fe7da5 [lightwt/cmd-beta]
```

**🚫 现状 = 6 个，未归零 ⇒ 方案 B 前置条件②不满足。**

### 2.2 归零判据（每条都要满足）

| 判据 | 命令 | 期望 |
|---|---|---|
| worktree 只剩主仓 | `git worktree list \| wc -l` | **1** |
| 无 detached HEAD 残留 | `git worktree list \| grep -c detached` | **0** |
| 无死登记 | `git worktree prune -n` | 无输出（无待清理项） |
| 各沙箱无未提交 | 逐个 `git -C <wt> status --porcelain` | 空 |

### 2.3 归零动作（**由 owner/tidy 决定，不在本单执行**）

```bash
# 对每个非主 worktree，先验三条件再删（判例-51 教训）
git -C <wt> status --porcelain          # 必须空，或内容已确认可弃
git -C <wt> log --oneline HEAD --not --all   # 必须空（无独有提交）
git worktree remove <wt>                # 不加 --force；被拒则先查原因
```

**⚠️ 判例-51/59 提醒**：`git status` 的 `A` 标记 **≠ blob 不在对象库**。
`--force` 前必须 `git log --all -- <path>` 确认可恢复。

---

## 三、无 agent 并发检查

**为什么重要**：审计期间实测有 agent 并发执行 repack（packs 14→5），
方案 B 执行中若有并发读写 `.git`，可能造成索引/对象库不一致。

### 3.1 执行前瞬时检查

```bash
# ① 是否有 git 进程在跑
ps aux | grep -E "[g]it (gc|repack|commit|push)" || echo "无 git 进程"

# ② .git 是否被锁
ls -la .git/index.lock .git/gc.pid 2>/dev/null && echo "⚠️ 有锁，等待" || echo "✅ 无锁"

# ③ 最近 5 分钟 .git 是否被改（有并发迹象）
find .git -newermt '-5 minutes' -type f | head -5
```

### 3.2 协调判据

| 判据 | 期望 |
|---|---|
| 无 agent 声明正在操作本仓 | 统帅确认 |
| `find .git -newermt '-5 minutes' -type f` | **空** |
| `.git/index.lock` | **不存在** |
| 所有 teammate 状态 | **inactive** 或明确不碰本仓 |

---

## 四、回滚判据（压缩失败如何恢复）

### 4.1 回滚阶梯（由轻到重）

| 级别 | 触发条件 | 回滚动作 | 可逆性 |
|---|---|---|---|
| **L0** | 执行前发现前置不满足 | **不执行**，无损失 | — |
| **L1** | `reflog expire` 已跑、`gc` 未跑 | `cp -r .git.bak-…/. .git/`（覆盖 reflog）| ✅ 完全 |
| **L2** | `gc --prune=now` 已跑、发现数据缺失 | `cp -r .git.bak-…/. .git/` 整目录还原 | ✅ 完全 |
| **L3** | L2 副本损坏 | 从 `${MIR}` 恢复分支内容（**不含 reflog**）| 🟡 部分 |
| **L4** | 全部失守 | force-push 各远端重新克隆 | 🔴 有损 |

### 4.2 回滚验证判据

```bash
# 回滚后必须全部满足
git rev-parse --short HEAD                    # 应等于执行前记录的 SHA
git count-objects -vH | grep size-pack        # 应回到 ~1.89 GiB
git rev-list --objects --reflog | wc -l       # 应回到执行前的对象数
git fsck --no-progress                        # 应无 error
```

### 4.3 执行前必记的基线快照（**复制到本文档留档**）

```bash
git rev-parse HEAD                            # 基线 HEAD
git count-objects -vH                         # 基线对象读数
git rev-list --objects --all  | wc -l         # 基线可达对象数
git rev-list --objects --reflog | wc -l       # 基线 reflog 对象数
git worktree list                             # 基线 worktree 数
```

---

## 五、验收读数（压缩前后对比）

### 5.1 主判据

| 指标 | 执行前（基线） | 执行后期望 | 判定 |
|---|---|---|---|
| `size-pack` | **1.89 GiB** | **< 0.5 GiB** | 降幅 > 70% |
| `in-pack` | 20573 | 显著下降 | — |
| `packs` | 5 | ≤ 2 | 合并完成 |
| `.git` 目录体积 | **2.0G** | **< 0.8G** | 主判据 |
| `git fsck` | 无 error | 无 error | 完整性 |

### 5.2 功能判据（压缩后必须仍然工作）

```bash
git status                          # 干净
git log --oneline -5                # 正常
git rev-list --objects --all | wc -l   # 与基线一致（可达对象不应丢失）
git checkout -- . && git status     # 工作树可正常还原
```

### 5.3 ⚠️ 「可达对象不应丢失」这句的含义

`reflog expire` 只把 **reflog 独占对象** 变不可达；**分支可达对象必须一个不丢**。
执行后 `git rev-list --objects --all | wc -l` 若**变小**，说明误删了历史 ⇒ **立即 L2 回滚**。

---

## 六、Stage 3 前置缺口 G1：`--strip-blobs-with-ids` 试跑

**背景**：方案 B 清的是 **reflog 独占的 7 个 blob（3049 MB）**。
另有 **56 个 blob（2268 MB）被分支引用**，`reflog expire` 清不掉 —— 要清它们只能走 `filter-repo`。

### 6.1 认知澄清（**本 checklist 实测修正了起草时的初判**）

**起草本文档时我曾怀疑「方案 B 只能释放 ~12%」，实测推翻了该怀疑。**

| 集合 | 个数 | 体积（解压后） | `reflog expire` 能删？ |
|---|---|---|---|
| 分支可达 `--all` | 56 | **2268 MB** | ❌ 删不掉 |
| **reflog 独占**（`--reflog` 减 `--all`） | **7** | **3049 MB** | ✅ **能删** |
| reflog 全量 `--reflog` | 63 | 5317 MB | — |

**实测抽验**：`3fd915a4`（730,750,383 字节 = 696.9 MB）
`rev-list --objects --all` 命中 **0**、`--reflog` 命中 **1** ⇒ **纯 reflog 独占。**

**⇒ 方案 B 可释放 3049 MB（解压）≈ 打包后 1.3~1.7 GB。原估正确。**

**⚠️ 我起草时的错在哪（自曝）**：我按**个数**算比例（7/56 ≈ 12%），
但 blob 体积**极不均匀** —— 最大的几个（696.9 / 610.0 / 522.7 / 435.6 MB）
**恰好全部落在 reflog 独占的 7 个里**。
**个数少 ≠ 体积小。** 这是「口径自证」的又一实例（与判例-59 附记同族）。

**结论**：方案 B 是有实效的；方案 C（filter-repo）虽能连分支可达的 2268 MB 一起清，
但代价是全历史 SHA 重写 ⇒ **不值得**。**优先方案 B。**

### 6.2 G1 试跑方案（**只在 temp 克隆上，绝不动主仓**）

```bash
# 1) 在 temp 建克隆（不碰主仓 .git）
git clone --no-hardlinks /e/IDEProjects/AI/FIST-Mbt temp/g1-strip-test

# 2) 列出要剔除的 blob（56 个）
git -C temp/g1-strip-test rev-list --objects --all \
  | grep "memory/2026-10-22.md" | awk '{print $1}' | sort -u > temp/g1-blobs.txt

# 3) 试跑 filter-repo（--force 仅在 temp 克隆）
cd temp/g1-strip-test
git filter-repo --strip-blobs-with-ids temp/g1-blobs.txt --force

# 4) 验收
du -sh .git                           # 期望从 2.0G 降到 ~0.3G
git rev-list --objects --all | wc -l  # 记录变化
git log --oneline -5                  # 提交仍在（SHA 会变）
```

### 6.3 G1 试跑判据

| 项 | 期望 |
|---|---|
| temp 克隆体积 | < 500 MB |
| 非 `memory/2026-10-22.md` 的文件全在 | `git ls-files | wc -l` 与主仓一致 |
| 提交数 | 与主仓一致（SHA 会变，提交数不变）|
| **主仓 `.git`** | **一字节未动**（试跑前后 `sha1sum .git/objects/pack/*.pack` 比对）|

**G1 试跑结果用于回答**：「方案 C 到底能释放多少」—— 在动主仓之前先拿真实读数。

---

## 七、执行顺序（**建议，待 owner 批准**）

```
第 0 步  记录基线（§4.3 四条命令，结果贴进本文档）
第 1 步  确认 §1.1 mirror 完整（已验：56/56，2268 MB）✅
第 2 步  做 §1.2 的 .git 整目录备份 + 验证副本可用
第 3 步  确认 §2 worktree 归零（当前 6 个，需降到 1）
第 4 步  确认 §3 无 agent 并发
第 5 步  ★ owner 签字
第 6 步  执行方案 B（reflog expire + gc --prune=now）
第 7 步  跑 §5 验收读数
第 8 步  §6.2 G1 试跑（回答「方案 C 能释放多少」）
```

**第 8 步（G1 试跑）是可选的，且优先级低** ——
因为 §6.1 已实测确认**方案 B 能释放 3049 MB（解压）**，已是主收益；
方案 C 额外只能再清分支可达的 2268 MB，**代价是全历史 SHA 重写**，不划算。
**G1 只在 owner 想「一次清干净」时才做，且必须在 temp 克隆上。**

---

## 八、当前状态汇总（现读，非记忆）

| 前置条件 | 状态 | 现读 |
|---|---|---|
| ① owner 裁决 | ⏳ 待 | —— |
| ② worktree 归零 | **🚫 不满足** | **6 个**（需 1）|
| ③ 无 agent 并发 | ⏳ 待检 | —— |
| ④ mirror 备份完整 | **✅ 满足** | 593M / 56 版本全覆盖 / 2268 MB |
| ④' `.git` 整目录备份 | **🚫 未做** | —— |
| ⑤ 回滚判据 | ✅ 本文档 §4 | —— |
| ⑥ G1 试跑 | ⏳ 未做 | —— |

**⚠️ 结论：方案 B 当前不具备执行条件（worktree 未归零 + .git 备份未做）。**

---

## 九、一句话给 owner

**方案 B 可以做，收益已实测确认。**

> **reflog 独占 7 个 blob = 3049 MB（解压），打包后约 1.3~1.7 GB。
> 其中最大的 4 个（696.9 / 610.0 / 522.7 / 435.6 MB）全部是 reflog 独占，分支不可达。
> ⇒ `reflog expire` + `gc --prune=now` 能真正释放这 3 GB 里的绝大部分。**

**当前唯一缺的是两个可办的前置**：
1. **worktree 归零**（现读 6 个，需降到 1）
2. **`.git` 整目录备份**（mirror 已验完整，但不含 reflog ⇒ 回滚需要整目录副本）

**办完这两条 + owner 签字，即可执行。**

**（起草时我曾怀疑「方案 B 只释放 12%」，实测推翻了该怀疑 —— 错在按个数算体积。详见 §6.1。）**
