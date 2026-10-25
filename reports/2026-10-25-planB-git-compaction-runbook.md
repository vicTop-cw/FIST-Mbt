# 方案 B 执行手册：`.git` 2.0G → ~100M 压缩归档

**状态：草案 · 待统帅下令执行**（本文档不执行方案 B，只固化步骤与判据）

- 编写：2026-10-25 ｜ 执行人：（待派）｜ 模式：不可逆操作，须统帅逐步确认
- 目标：把 `.git` 从 **2.0 GiB** 压到 **~100–200 MiB**，同时**不丢任何可达对象**
- 回滚保险：`_git-full-backup-20261025-16ac3432`（含 reflog，**已就绪并验证**，见 §1）

---

## 0. 为什么要做（机理）

`.git` 的 2.0G 里，**主体不是可达历史，而是 reflog 撑着的 unreachable 对象**：

| 面 | 读数（2026-10-25 实测） |
|---|---|
| `size-pack` | 1.89 GiB |
| `fsck --no-reflogs --unreachable` | **2689 个 unreachable blob** |
| 9 个大 blob（>100M） | 合计 ~4.3G，**全是同一份 R70 whisperer report 的 9 个历史版本** |
| 其中不在 mirror 的 | 7 个（合计 ~3049M） |

`reports/` 下的 whisperer report 每 append 一次就产生一个新 blob；reflog 让旧版本一直「算可达」，
所以 `gc` 不敢回收。**清 reflog ⇒ 这些旧 blob 变真正 unreachable ⇒ `gc --prune=now` 才能回收。**

> **前提已确认**：main 已有等价报告 `reports/2026-10-24-whisperer-merge-marathon-report.md`，
> 旧版本只在 reflog 里可回溯，**业务上无保留价值**（统帅已裁决）。

---

## 1. 回滚保险（已就绪）

```
路径: E:/IDEProjects/AI/_git-full-backup-20261025-16ac3432
```

| 验证项 | 期望 | 实测 |
|---|---|---|
| 大小 | ≈ 2.0G | ✅ **2.0G** |
| `logs/HEAD` | 存在（含 reflog） | ✅ 58,555 B |
| `reflog \| wc -l` | > 0 且与源一致 | ✅ **270**（源亦 270） |
| `rev-parse HEAD` | == 源 HEAD | ✅ `16ac34327985…`（源相同） |
| unreachable blob | 2689（回滚要点） | ✅ **2689** |
| refs 总数 | 280 | ✅ **280** |
| 大 blob 抽查 | 3 个 >600MB 可读 | ✅ 639905457 / 639407674 / 639656096 |

**关键**：`git-mirror-backup-20261025.git`（593M）**不含 reflog** ⇒ 删掉这 5.5G 无法从 mirror 恢复。
**整副本是唯一回滚路径。回滚 = 停掉所有进程 → 把整副本改名回 `.git`。**

---

## 2. 执行前检查（每一条都必须过，任一不过就停）

```bash
cd /e/IDEProjects/AI/FIST-Mbt

# ① 三端收敛：gitcode 不许落后
git rev-list --count gitcode/main..HEAD        # 必须 0
git fetch gitcode && git rev-list --count gitcode/main..HEAD   # fetch 后再验一次

# ② worktree 归零（只能有主树，或至多 2）
git worktree list | wc -l                      # 必须 ≤ 2

# ③ 回滚保险在位
test -f /e/IDEProjects/AI/_git-full-backup-20261025-16ac3432/logs/HEAD && echo BACKUP-OK

# ④ 工作树干净（无未提交改动会被 gc 波及误判）
git status --porcelain                         # 必须为空

# ⑤ 没有删分支/删 worktree 的进程在跑（并发 agent 全部停手）
```

> **⑤ 是最容易被忽略的一条**。方案 B 期间若有 agent 在 `git checkout` / `commit`，
> reflog 会被重新写入、对象会被重新引用 ⇒ 压缩率打折扣，甚至把正在写的对象 prune 掉。
> **执行前必须由统帅宣布「全员停手」。**

---

## 3. 执行步骤（严格按序，每步后验读数）

### 3.1 记录「可复原面」基线（**最重要的一步，必须先存**）

```bash
git log --all --oneline | wc -l                       >  /tmp/planB-before.txt
git for-each-ref | wc -l                              >> /tmp/planB-before.txt
git rev-list --objects --all | cut -d' ' -f1 \
  | git cat-file --batch-check='%(objecttype)' \
  | sort | uniq -c                                    >> /tmp/planB-before.txt
git fsck --no-reflogs --unreachable | grep -c blob    >> /tmp/planB-before.txt
cat /tmp/planB-before.txt
```

**2026-10-25 实测基线（执行时必须与本行逐项对比）**：

```
commits(all)      = 1995
refs total        = 280
blob  (可达)      = 8203
tree  (可达)      = 9035
commit(可达)      = 1995
tag   (可达)      = 18
unreachable blob  = 2689
```

> ⚠️ **不要用 `git rev-list --objects --all | grep -c blob`** —— 本次实测它恒返回 **0**。
> 原因是 `rev-list --objects` 的输出是 `<sha> <path>`，**不含对象类型列**（本仓 19251 行全都不含类型名），
> 所以 `grep blob` 什么都匹配不到。
> **正确量法**是上面那条 `cut -f1 | git cat-file --batch-check='%(objecttype)' | sort | uniq -c`。
> 这条坑是写手册时自己踩到的：**一个「恒为 0 的判据」看起来像「没有 blob」**，正是判例-25 同族——
> 判据的真源读错了字段，它报的绿/红都没有意义。

### 3.2 清 reflog（**这一步删 5.5G 的可回收前提**）

```bash
git reflog expire --expire=now --expire-unreachable=now --all
```

验证：

```bash
git reflog | wc -l          # 应变 0
ls -la .git/logs/           # logs/ 下应为空或不存在
```

**此刻不可逆开始**：reflog 一清，旧 blob 只存在于 `_git-full-backup-20261025-16ac3432` 里。
**若这步后想反悔 ⇒ 立即走 §5 回滚，不要继续 3.3。**

### 3.3 压缩 + 剪枝

```bash
git gc --prune=now --aggressive
```

> `--aggressive` 耗时较长（分钟级到十分钟级），但能显著提高压缩率。
> 若嫌慢可退化为 `git gc --prune=now`（不带 aggressive），读数会略高但安全等价。

### 3.4 验证（六条，逐条对 §3.1 基线）

```bash
du -sh .git                                              # 期望 100M–200M
git log --all --oneline | wc -l                          # 必须 == 1995
git for-each-ref | wc -l                                 # 必须 == 280
git rev-list --objects --all | cut -d' ' -f1 \
  | git cat-file --batch-check='%(objecttype)' \
  | sort | uniq -c                                       # 四类计数必须与基线全等
git fsck --full --no-dangling                            # 必须无 dangling（allow "commit-graph too long" 已知噪声）
git status --porcelain                                   # 必须空
```

### 3.5 回归（这一步不可省）

```bash
python scripts/moon_test_env.py --target js
# 判绿看汇总行：Total tests: N, passed: N, failed: 0
# 基线 N = 1457（2026-10-23 实测；执行时以当场 HEAD 的真实数为准，不抄旧数）
```

外加两条轻量守卫确认仓库没坏：

```bash
python scripts/check_repo_shape.py          # PASS
python scripts/check_publish_payload.py     # PASS（载荷面未受 .git 影响，但顺手验）
```

### 3.6 mirror 备份更新（方案 B 之后）

```bash
git clone --mirror . /e/IDEProjects/AI/git-mirror-backup-20261025.git.new
mv /e/IDEProjects/AI/git-mirror-backup-20261025.git /e/IDEProjects/AI/git-mirror-backup-20261025.git.old
mv /e/IDEProjects/AI/git-mirror-backup-20261025.git.new /e/IDEProjects/AI/git-mirror-backup-20261025.git
```

**保留 `.old` 至少 7 天**再删 —— 它是「如果整副本和现行 `.git` 都坏了」的最后一道。

---

## 4. 预期读数

| 面 | 执行前 | 执行后（期望） | 不可退让的硬约束 |
|---|---|---|---|
| `du -sh .git` | **2.0G** | **~100–200M** | 只许降 |
| `size-pack` | 1.89 GiB | ~100–200 MiB | 只许降 |
| unreachable blob | **2689** | **0** | 必须 0（这是本方案的目的） |
| commits(all) | **1995** | **1995** | **必须完全一致** |
| refs | **280** | **280** | **必须完全一致** |
| 可达对象（blob/tree/commit/tag） | **8203 / 9035 / 1995 / 18** | 同左 | **必须完全一致** |
| `moon test` | 1457 passed | 同数全绿 | **必须全绿** |

---

## 5. 回滚预案（三道，按严重度排序）

### 5.1 轻度偏差（某个验证数对不上，但 git 仍可用）

**先别急着回滚** —— 诊断是哪一类：

```bash
git fsck --full 2>&1 | grep -v "commit-graph" | grep -v "too long"
```

- 只有 `dangling` ⇒ **正常**（gc 后的悬垂对象，`--no-dangling` 只是别看它）
- 出现 `missing blob/tree` ⇒ **严重**，走 5.2

### 5.2 严重损坏（missing 对象 / ref 丢失 / 测试全红）

```bash
# ① 全员停手（统帅宣布）
# ② 把坏掉的 .git 改名留证，不要直接删
mv .git .git-broken-$(date +%Y%m%d-%H%M%S)
# ③ 整副本改名回来
cp -r /e/IDEProjects/AI/_git-full-backup-20261025-16ac3432 .git
# ④ 验
git rev-parse HEAD                  # 应 16ac3432…
git log --all --oneline | wc -l     # 应 1995
git status                          # 应 clean
```

> **用 `cp -r` 而不是 `mv`** —— 整副本要保持完好，以备第二次尝试。

### 5.3 最坏（整副本也坏了 —— 理论上不会，已 7 项验证）

```bash
git clone --mirror /e/IDEProjects/AI/git-mirror-backup-20261025.git.old .git-recovered
```

**代价**：mirror 不含 reflog ⇒ 5.5G 历史版本永久丢失（业务上已知无价值，故可接受）。
**这也是为什么 §1 的整副本是「唯一真正的保险」。**

---

## 6. 风险清单

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| 1 | 执行时有 agent 在写 ⇒ reflog 被重写 | **中高** | 压缩率打折，最坏 prune 掉正在写对象 | §2-⑤ 全员停手，执行前后各查一次 `git status` 与 `reflog` |
| 2 | `--aggressive` 在 2G 库上跑很久 | 中 | 只是慢 | 可退化为不带 aggressive |
| 3 | Windows 文件锁导致 `gc` 失败 | 中 | 命令报错，但通常无损 | 关掉所有 git GUI/编辑器/DSh 连接器后再跑 |
| 4 | 整副本被误删后才发现需要回滚 | 低 | 5.5G 永久丢失 | 整副本放在 `.git` **之外**的兄弟目录，且**方案 B 全程不许清理它** |
| 5 | `check_badge` / 测试数对不上（判例-25 快照陷阱） | 中 | 误判回归 | 测试数以**当场实跑**为准，不抄 README 徽章与 `temp/pt27.log` |
| 6 | 清 reflog 后「想找回某个旧版本 report」 | 低 | 只能从整副本翻 | 整副本在手即无损 |

---

## 7. 判例关联（本文档遵守的既有纪律）

- **判例-11（最终形态）**：任何 `git commit` 带 `-- <明确路径>`。本手册 §3.6 的 `git clone --mirror` 不涉及提交，但**方案 B 后若有任何提交，仍走 `scripts/commit_scoped.sh`**。
- **判例-25（快照陷阱）**：本手册 §3.5 明确「测试数以当场实跑为准，不抄徽章/`pt27.log`」。
- **判例-24（尺子判可删 ≠ 内容无独有）**：本手册 §1 不靠「`du -sh` 看起来对」就宣称备份可用，而是逐项验 reflog/unreachable/refs/大 blob。

---

## 8. 一页速查（打印用）

```
前提：gitcode 差=0 ｜ worktree≤2 ｜ 整副本 logs/HEAD 在 ｜ status clean ｜ 全员停手
基线：commits 1995 ｜ refs 280 ｜ 可达 blob 8203 ｜ unreachable blob 2689
步骤：记基线 → reflog expire → gc --prune=now --aggressive → 六条验证 → moon test → mirror 更新
合格：.git ~100-200M ｜ commits/refs/四类对象全等 ｜ unreachable=0 ｜ 测试全绿 ｜ status clean
回滚：cp -r /e/IDEProjects/AI/_git-full-backup-20261025-16ac3432 .git
```
