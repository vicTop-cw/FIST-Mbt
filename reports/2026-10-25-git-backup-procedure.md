# `.git` 整目录备份操作单（Stage 3 方案 B 前置）

> **服务对象**：`reports/2026-10-25-stage3-reflog-expire-checklist.md` §1.2
> **性质**：操作单，**未执行**
> **起草**：commander-delta · 2026-10-25

---

## 〇、为什么要这一份（不能只靠 mirror）

| 备份 | 含内容 | 含 reflog？ | 能回滚 `reflog expire`？ |
|---|---|---|---|
| α 的 `--mirror` 仓库 | 全部分支/标签的提交与 tree/blob | **❌ 无 `logs/` 目录** | **❌ 不能** |
| **`.git` 整目录副本** | 全部对象 **+ reflog + index + 配置** | **✅ 含** | **✅ 能** |

**方案 B 删的正是 reflog 及其独占对象（3049 MB / 7 个 blob）。**
mirror 里这 7 个 blob **依然存在**（因为分支可达的 56 个里有它们的副本？—— 不，实测它们**只被 reflog 引用**，
mirror 是 `--mirror` 克隆，**不含 reflog ⇒ 也不含这 7 个 blob**）。

**⇒ 结论：mirror 救不了方案 B 删掉的东西。`.git` 整目录副本是唯一回滚路径。**

> **✅ 已实测证实（2026-10-25）**：mirror 里那 7 个 reflog-独占 blob **全部缺失（0/7）**。
> 详见 §六。

---

## 一、现读基线

| 项 | 读数 |
|---|---|
| `.git` 大小 | **1956 MB（1.91 GiB）** |
| 磁盘可用 | `E:` 535 GB / 954 GB（44% 已用）|
| 备份后剩余 | ≈ 533 GB ✅ **余量充足** |
| mirror 备份 | `/e/IDEProjects/AI/git-mirror-backup-20261025.git`，593M，bare，18,970 对象，284 分支 |

---

## 二、备份操作（三条命令）

### 2.1 目标路径

```bash
SRC=/e/IDEProjects/AI/FIST-Mbt/.git
DST=/e/IDEProjects/AI/FIST-Mbt/.git.bak-before-reflog-expire
```

**放在同盘同目录**：便于整体还原；`.git.*` 已被 `.gitignore` 覆盖（需确认，见 §2.4）。

### 2.2 执行

```bash
# ① 确认目标不存在（幂等保护）
[ -e "$DST" ] && echo "已存在，先决定是否复用" && exit 1

# ② 复制（保留权限与时间戳）
cp -a "$SRC" "$DST"

# ③ 记录校验和（用于日后比对完整性）
(cd "$DST" && find . -type f -name '*.pack' -exec sha1sum {} \;) > "$DST.sha1manifest"
```

**为什么用 `cp -a` 而不是 `cp -r`**：`-a` 保留 mtime/权限/符号链接，
而 git 的 `objects/pack` 依赖 mtime 判断是否需要 repack（`cp -r` 会重置 mtime，虽不影响正确性但会让后续 gc 误判）。

### 2.3 验证（**四条，缺一不可**）

```bash
# ① 体积相当（允许 1% 误差）
du -sm "$SRC" "$DST"

# ② 对象库可寻址
git --git-dir="$DST" rev-parse --short HEAD          # 应输出 sha

# ③ reflog 副本完整（这是本备份的核心价值）
ls "$DST/logs" 2>/dev/null | wc -l                   # 应 > 0
git --git-dir="$DST" rev-list --objects --reflog 2>/dev/null | wc -l
                                                     # 应与主仓现读一致

# ④ 7 个 reflog-独占 blob 可寻址
for b in 3fd915a4f11c6818c74444f6914407272d2cffa1 \
         ab70530ff760fdc0d0a61a0a35e23eb8f4810c4a \
         aae2de0deeb403c8a46648615f47137bf6ae53a9 \
         e8feb12f7a2ad54678a92aae06454d71749261ae \
         46239788c5bc1fd7914adee724ef05beeb8ac222 \
         49f67168e75f4a31838af92c4ba59f4081012a52 \
         c82d0e53ee55dbfcbdae5a9a36d1038aa5eb1177; do
  git --git-dir="$DST" cat-file -s "$b" 2>/dev/null && echo "OK $b" || echo "★MISSING $b"
done
```

**④ 是本备份的成败判据** —— 若任何一个 `★MISSING`，备份不能用于方案 B 回滚。

### 2.4 `.gitignore` 确认（防备份被误提交）

```bash
git check-ignore -v .git.bak-before-reflog-expire
# 期望输出规则行；无输出 ⇒ 未被忽略 ⇒ 必须先加 .gitignore 规则
```

**⚠️ 若未被忽略**：**不要** `git add -A`（AGENTS.md 已禁），
先单独提交一条 `.gitignore` 规则：`/.git.bak-*/`，再备份。

---

## 三、还原操作（回滚用）

```bash
SRC=/e/IDEProjects/AI/FIST-Mbt/.git.bak-before-reflog-expire
DST=/e/IDEProjects/AI/FIST-Mbt/.git

# ① 先把当前坏掉的 .git 挪开（不删，留证据）
mv "$DST" "$DST.broken-$(date +%Y%m%d%H%M%S)"

# ② 还原
cp -a "$SRC" "$DST"

# ③ 验证
git rev-parse --short HEAD
git count-objects -vH | grep size-pack      # 应回到 1.89 GiB
git fsck --no-progress                      # 应无 error
git rev-list --objects --reflog | wc -l     # 应回到基线
```

**为什么把坏的挪开而不是删**：保留现场供事后分析（判例-38：确认「以为删了其实没删」）。

---

## 四、生命周期

| 阶段 | 动作 |
|---|---|
| 方案 B 执行前 | 创建备份 + 跑 §2.3 四条验证 |
| 方案 B 执行后 | 跑验收读数（checklist §5） |
| 验收通过后 **7 天** | 备份可删（`.git.bak-before-reflog-expire` 约 1.9 GB）|
| 验收失败 | 立即 §3 还原 |

**保留 7 天的理由**：`reflog expire` 的副作用可能要几天后才被发现（某个旧 SHA 引用失效）。

---

## 五、风险与边界

| 项 | 说明 |
|---|---|
| 磁盘占用 | +1.9 GB（现余 535 GB，无压力）|
| 时间 | `cp -a` 1.9 GB，机械盘约 30~60 秒，SSD 更快 |
| 对主仓影响 | **零**（只读源目录，写新目录）|
| 是否算「写 `.git`」 | **不算** —— 写的是 `.git.bak-*`，不碰 `.git` 本身 |
| **不可逆** | 备份本身可逆（删新目录即可）|
| 执行者 | 任意（低风险），但建议 β 与 worktree 归零一起做 |

---

## 六、✅ 前置验证已做：mirror 里**确实没有**那 7 个 blob

**2026-10-25 实测（不必重跑，但要理解含义）：**

```
MIR=/e/IDEProjects/AI/git-mirror-backup-20261025.git

  ★缺失 3fd915a4f11c      ★缺失 ab70530ff760
  ★缺失 aae2de0deeb4      ★缺失 e8feb12f7a2a
  ★缺失 46239788c5bc      ★缺失 49f67168e75f
  ★缺失 c82d0e53ee55

存在: 0 / 缺失: 7
```

### 6.1 含义（三条）

| # | 含义 |
|---|---|
| A | **符合 `--mirror` 语义**：只克隆 refs（分支/标签），**reflog 不在其中** ⇒ reflog 独占对象必然缺失 |
| B | ⇒ **方案 B 删掉的 3049 MB 无法从 mirror 恢复** |
| C | ⇒ **`.git` 整目录副本是唯一回滚路径** —— 本单 §1.2 的判断被实测证实 |

### 6.2 反直觉之处：mirror 缺它们 ≠ 它们不重要

**有人会想**：「mirror 是权威备份，它都没有这 7 个 blob，那它们大概不重要。」

**这是错的。** 理由：
- mirror 缺它们是因为**克隆机制只包含 refs 可达对象**，不是因为它「判定不重要」
- 这 7 个 blob **正是方案 B 要释放的 3049 MB** —— 它们只被 reflog 引用
- **如果它们不重要，方案 B 就没有收益可言了**

⇒ **mirror 的「缺失」是「方案 B 有收益」的证据，不是「它们可弃」的证据。**

### 6.3 对方案 B 的最终确认

```
reflog 独占 7 个 blob = 3049 MB（解压）
mirror 覆盖率        = 0 / 7   ← 无法从 mirror 恢复
.git 整副本覆盖率    = 7 / 7   ← 唯一回滚路径（§2.3 ④ 验证）
⇒ 方案 B 收益确认：3049 MB 解压 / 约 1.3~1.7 GB 打包
```

---

## 七、给执行者的一句话

**这份备份的价值 100% 取决于 §2.3 的第 ④ 条**：
**7 个 reflog-独占 blob 必须全部可寻址。**

若只验了「体积相当 + HEAD 能读」，备份看着完整、但方案 B 一跑就发现回滚不了 ——
**那正是「判据看的不是它以为在看的东西」的备份版。**
