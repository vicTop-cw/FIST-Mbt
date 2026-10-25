# worktree 归零 · 执行与证据记录 · 2026-10-25

**结果**：worktree **6 → 3**（删 3 个 mergeability；留主仓 + `frp-wt` + `light-wt/cmd-beta`）

---

## 〇、先回答统帅的四问（含一处必须澄清的误解）

| 问 | 答 |
|---|---|
| ① 3 个 mergeability 是否已删 | **是**。`git worktree list` 现读 **3 条**（主仓 / frp-wt / cmd-beta）|
| ② 证据导出在哪 | **在 `_archive/wt-salvage/2026-10-25/mergeability/`**，7 个文件 / 60 KB（下方 §2 逐文件列出）。**导出发生在删除之前**，时间戳 `12:40~12:42`，删除在 `12:45` 之后 |
| ③ 判例-59 逐文件核结果 | **三个 worktree 合计 262 条 porcelain 条目，`★无历史` = 0 条**。即每个文件在 `git log --all` 都有历史（§3）|
| ④ 报告是否已写 | 本文件即该报告 |

**⚠️ 澄清统帅的核查误判**：你说「`_archive/wt-salvage/` 没有 mergeability/ 目录」——
**实际存在**。可能是你 `ls` 时用的是**主仓内**的 `_archive/`（主仓那棵是 `E:/IDEProjects/AI/FIST-Mbt/_archive/`），
而证据落在**同级兄弟目录** `E:/IDEProjects/AI/_archive/`（与 `_archive/` 同层，不在主仓里）。
两者同名不同位置 —— **这正是本会话反复出现的「同名 ≠ 同一物」形状**，我在下面给对照。

```
证据实际位置 : E:/IDEProjects/AI/_archive/wt-salvage/2026-10-25/mergeability/
主仓内同名   : E:/IDEProjects/AI/FIST-Mbt/_archive/   ← 另一棵，里面没有 wt-salvage
```

---

## 一、删除结果

| worktree | 删除前状态 | 处置 |
|---|---|---|
| `E:/IDEProjects/AI/FIST-Mbt` | 主树 | **保留** |
| `C:/Users/victo/AppData/Local/Temp/frp-wt` | 分支 `fix/render-release-priority-master` 仍在 | **保留**（等 γ 核完分支再处理）|
| `C:/Users/victo/AppData/Local/Temp/mergeability-bn5486xy/wt` | detached，158 unmerged | ✅ 已删 |
| `C:/Users/victo/AppData/Local/Temp/mergeability-okca3qgu/wt` | detached，0 unmerged | ✅ 已删 |
| `C:/Users/victo/AppData/Local/Temp/mergeability-xd7gqcjf/wt` | detached，64 unmerged | ✅ 已删 |
| `E:/IDEProjects/AI/light-wt/cmd-beta` | 别人沙箱 | **保留**（按边界不碰）|

`git worktree list | wc -l` → **3**；`git worktree prune -v` → 无残留。
删除后三个空壳父目录（0 字节）一并 `rmdir`。

---

## 二、证据导出清单（**删除之前**完成，7 文件 / 60 KB）

`E:/IDEProjects/AI/_archive/wt-salvage/2026-10-25/mergeability/`

| 文件 | 大小 | 行数 | 内容 |
|---|---|---|---|
| `bn5486xy/index-unmerged.txt` | 13,060 B | **158** | `git ls-files -u` 全文（三 stage 并存）|
| `bn5486xy/conflict-markers.txt` | 10,192 B | 137 | 6 份文件的 `<<<<<<<` 冲突上下文 |
| `bn5486xy/case59-history.txt` | 3,425 B | 104 | 判例-59 逐文件历史 |
| `xd7gqcjf/index-unmerged.txt` | 4,764 B | **64** | 同上 |
| `xd7gqcjf/conflict-markers.txt` | 10,672 B | 123 | 同上 |
| `xd7gqcjf/case59-history.txt` | 1,510 B | 58 | 同上 |
| `okca3qgu/case59-history.txt` | 3,280 B | 100 | 同上（该 wt **0 unmerged**）|

**冲突标记覆盖的文件**：`.dsh/fist-mbt-plugin/cordis.patch.yml` / `.githooks/README.md` /
`.github/workflows/ci.yml` / `.gitignore` / `AGENTS.md` / `ARCHITECTURE.md`。
样本首行实证：`100644 5b9324da… 2  .dsh/fist-mbt-plugin/cordis.patch.yml`（stage 2 = ours）。

---

## 三、判例-59 逐文件核（δ 的硬要求）

命令（逐 worktree 跑，输出落 `case59-history.txt`）：

```bash
git -C <wt> status --porcelain | awk '{print $2}' | while read f; do
  h=$(git -C <wt> log --all --format=%H -- "$f" 2>/dev/null | head -1)
  [ -n "$h" ] && echo "OK $f" || echo "★无历史 $f"
done
```

| worktree | 条目数 | `OK` | **`★无历史`** |
|---|---|---|---|
| bn5486xy | 104 | **104** | **0** |
| okca3qgu | 100 | **100** | **0** |
| xd7gqcjf | 58 | **58** | **0** |

**`★无历史` = 0 ⇒ 无需逐个人工判读内容**（δ 的要求是「`★无历史` 的必须逐个看内容」，本单不存在该类）。

### 抽样反证（不只信计数）
抽 2 个文件核它们的历史**在主仓对象库里真的存在**（而非只在这个 worktree 里）：

```
AGENTS.md            wt: 46c1382d feat(acl): 补 agent_acl_grant MCP 工具面…
                    main: 46c1382d （同一 commit）✅
memory/2026-10-14.md  wt: d359c69b fix(memory): 止住失控日志…
                    main: d359c69b （同一 commit）✅
```

---

## 四、删前其余核验

| 项 | 读数 |
|---|---|
| `MERGE_HEAD`（合并是否在进行）| **三个 worktree 全部 NO** ⇒ 试跑残留，非在途合并 |
| 运行中进程引用 | **0**（首轮脚本自匹配被告警 → 排除 `pwsh`/`DSH Desktop` 后重扫，`NO EXTERNAL PROCESS`）|
| 主仓 HEAD | 删前删后 **`46c1382d`**（未变）|
| 主仓 `git status` | 79 条（stat-dirty 噪音，判例-21）|

---

## 五、⚠️ 必须自曝：清理过程中发现 7 个「幽灵」目录，我**没有删**

删掉三个 `wt` 后，`C:/Users/victo/AppData/Local/Temp/` 下还有 **7 个 `mergeability-*` 目录**，
但 `git worktree list` 里**一个都没有**（`.git/worktrees/` 只有 `cmd-beta` / `frp-wt` 两条）：

| 目录 | 内容 | 我的处置 |
|---|---|---|
| `mergeability-4am4tf7u` / `f7_g687u` / `zi2h77_h` | **0 文件**，纯空目录 | **未删**（空壳，无害；本单授权面只到 3 个已登记 wt）|
| `mergeability-st-53phmu8e` / `kx5qdkkz` / `o97xwh16` / `onougk_3` | 各 **15 个文件 / 23 K**，全是 `.git/objects/` 下的 blob | **未删，且发现需裁决的事**（见下）|

### `st-*` 四个的实测（重要）

它们是**迷你独立仓库**（`.git` 是目录、但里面**没有 refs/HEAD**，只剩 15 个 object blob）。
我逐个核对这 15 个 blob 是否存在于主仓对象库：

```
present_in_main = 0 / 15        ← 一个都没有
```

⇒ **这 4 个目录各含 15 个主仓里不存在的 object**。
按判例-59 的同一口径（「status 的 A 标记 ≠ blob 不在对象库」的反面）：
**它们不是「已删分支的残余」，而是「对象库外的孤儿 blob」** —— 内容可能是某次试跑产生的、
从未进过主仓的中间态。**删即永久丢失，且无从判断价值。**

**我的处置：不删，报你裁决。** 若要删，建议先 `git cat-file -p` 逐个看内容再定。
（这也解释了它们为何不进 `git worktree list`：注册信息已失，只剩孤 object。）

---

## 六、遗留与风险

1. **`frp-wt` 未处理**（按裁决）：分支 `fix/render-release-priority-master` 仍在，
   工作树里 `dist/fist-mbt.js` 被删（0 增 / 108,931 删）。
   **已核实该删除无损**：`frp-wt` HEAD 的 blob = `11a5e730`、main 的 blob = 同 `11a5e730` ⇒
   内容在 main 里完好，删 worktree 不丢内容。等 γ 处理分支。
2. **`light-wt/cmd-beta` 未碰**（按边界）。顺带如实报：`dirty=3` 但 `git diff HEAD` **真改动 = 0**（判例-21 噪音）。
3. **7 个幽灵 `mergeability-*` 目录**（§5）**未删**，需裁决；其中 4 个含主仓外孤儿 blob（60 个 object）。
4. **`_archive/` 在 `.gitignore:220` 内** ⇒ 本报告所述的证据导出**不进 git**，属**本地史料**。
   若需随仓分发，必须另择落点（如 `reports/`）——本单未做，因为史料体积 60 KB 且 `_archive/` 是既定归档位。
