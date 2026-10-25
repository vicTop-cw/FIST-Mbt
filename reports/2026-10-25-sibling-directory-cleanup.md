# 兄弟目录 34 个 —— 逐个核查与分类 · 2026-10-25

> 核查面：`/e/IDEProjects/AI/*`（不含主仓 `FIST-Mbt`），共 **34 项**。
> 本报告为**只读核查结论**；本轮**未执行任何删除/移动**（见 §5 待批清单）。

## 前置更正（我必须先说清）

**统帅指令里写「先读 `reports/2026-10-24-branch-cleanup-execution.md` 里你记的 34 个清单」——
那份清单不存在。** 昨晚我做兄弟目录盘点时被中途改派为「侦察兵」，清单**从未落盘**。
本报告的 34 项是**今天现场重新枚举**的，不是复读旧清单。
（现场枚举命令：`ls -1d E:/IDEProjects/AI/*/ | sort` → 34 项，与审计组早前报的「38 个」差 4，
差额是 δ 已处置的 `.atomcode`/`.codeartsdoer`/`.loomy-attachments`/`.workbuddy` 等隐藏目录的计法差异。）

## 一、分类计数

| 类别 | 数量 | 说明 |
|---|---|---|
| 🟢 **别的项目本体**（绝对不动） | **17** | 独立 git 仓库，各有自己的 origin |
| 🟡 **本仓副本 / 派生物**（可处置，但有前置保全） | **3** | `FIST-Mbt-slave-*` 三个克隆 |
| 🔴 **主仓内临时产物 / 本地杂项**（可删） | **14** | 非 git、非他项目、可重建或一次性 |

---

## 二、🟢 别的项目本体（17 个，绝对不动，只记录）

| # | 目录 | 大小 | origin | 判定 |
|---|---|---|---|---|
| 1 | `Pentad` | 22,927.5 MB | `gitcode:VictorTop/Pentad.git` | 活项目，**统帅明令不许碰** |
| 2 | `Tnr` | 14,905.4 MB | `gitcode:VictorTop/Tnr.git` | 他项目 |
| 3 | `Tnr_p0` | 5,751.6 MB | `gitcode:VictorTop/Tnr.git`（**同 origin**）| Tnr 的另一份检出 —— ⚠️ 见 §4 |
| 4 | `Tnr_merge_check` | 479.4 MB | `gitcode:VictorTop/Tnr.git`（**同 origin**）| Tnr 的合并检出 —— ⚠️ 见 §4 |
| 5 | `vq` | 23,615.5 MB | `gitcode:VictorTop/VQ.git` | 他项目 |
| 6 | `lang-zone` | 4,353.4 MB | `github:vicTop-cw/lang-zone.git` | 他项目 |
| 7 | `vools` | 1,042.6 MB | `github:vicTop-cw/vools.git` | 他项目（`_proj_vools` 指向它）|
| 8 | `兹` | 484.5 MB | `gitcode:VictorTop/ZI.git` | 他项目。⚠️ 目录名含 **U+5179**，不是「兹」的常见写法，**任何按名删除都会误伤** |
| 9 | `rx-mbt` | 441.1 MB | `atomgit:VictorTop_atomcode-apps/rxmbt.git` | 他项目。⚠️ **origin URL 内嵌明文 OAuth token**，见 §4 |
| 10 | `sigma-lang` | 383.5 MB | `github:vicTop-cw/sigma-lang.git` | 他项目 |
| 11 | `lang-pulgins` | 180.5 MB | **无 .git**（未纳入版本控制） | ⚠️ 非 git 且有内容（调研文档 + 插件实现），见 §4 |
| 12 | `mcpconftest` | 172.2 MB | `atomgit:VictorTop/mcpconftest.git` | 他项目 |
| 13 | `Actus` | 113.4 MB | `atomgit:VictorTop/actus.git` | 他项目 |
| 14 | `fist-evidence` | 14.2 MB | `github:vicTop-cw/fist-evidence.git` | FIST **实证伴生仓**（不是主仓，是独立发布物）|
| 15 | `NPU-Tnr-test` | 1.2 MB | `gitcode:VictorTop/NPU-Tnr-test.git` | 他项目 |
| 16 | `Nodea` | 0.6 MB | **无 .git** | 设计评论文档集（4 份 review md）—— ⚠️ 孤本文档 |
| 17 | `Nodea-ATGC` | 0.5 MB | **无 .git** | ATGC 设计规格（DESIGN/SPECS）—— ⚠️ 孤本文档 |

**注**：`fist-evidence` 虽属 FIST 家族，但它有独立 origin、独立发布面，**不是主仓的副本**，按「非主仓项目本体」处理（不动）。

---

## 三、🟡 本仓副本/派生物（3 个，可处置但必须先保全）

三个都是 **`github:vicTop-cw/FIST-Mbt.git` 的独立 clone**（不是 worktree、不是链接）。

| # | 目录 | 大小 | 分支 | 与 main 关系 | ⚠️ 未入库内容 |
|---|---|---|---|---|---|
| 18 | `FIST-Mbt-slave-wt02` | 44.5 MB | `feature/wt-lifecycle-tools` | HEAD 不在 main | **🔴 703 行孤本**：`src/server/wt_tools.mbt`(505) + `wt_tools_wbtest.mbt`(198) **未被 git 跟踪**，`git status` 报 `??`；另 `server.mbt` +92、`pkg.generated.mbti` +61/−23 未提交。**main 里 0 命中这些工具名** ⇒ 删即永久丢失 |
| 19 | `FIST-Mbt-slave-guard01` | 18.0 MB | `guard/check-model-auth-no-key` | HEAD 不在 main | **🟡 38 行未提交**：`check_model_auth_no_key.py` +38/−1、`scripts/README.md` +1/−1（main 现版 355 行 vs 此份 392 行）|
| 20 | `FIST-Mbt-slave-wt03` | 14.8 MB | `feature/wt-sparse-scripts` | HEAD 不在 main | 0 脏；但 `docs/design-wt-sparse-scripts.md` **main 里不存在**（设计稿孤本，已 commit 在本 clone 里）|

**处置建议**：三个**都不能直接删**。顺序必须是：
1. wt02 → `git add` 那 2 个孤本 + 提交，或 `format-patch`/`copy` 到 `_archive/`；
2. guard01 → 先判断那 38 行是否已被 main 的后续版本覆盖（当前看**没有**）；
3. wt03 → 把 `docs/design-wt-sparse-scripts.md` 捞进主仓 `docs/`（判例-24 同型：孤本设计稿须救回）；
4. 三件都保全后，才谈删 clone。

---

## 四、🔴 主仓内临时产物 / 本地杂项（14 个，可删）

| # | 目录 | 大小 | 判定 | 依据 |
|---|---|---|---|---|
| 21 | `_archive` | 22,839.4 MB | **待分级，不能一把删** | 内含 `Ceres`/`ClipRelay`/`CustEditor`/`Cypy` 等多个**别的项目的历史归档**。⚠️ 这是「别的项目的史料」，删前必须逐项目确认已在各自 origin |
| 22 | `_lz_night_scratch` | 11,201.8 MB | 可删（大件） | 夜跑 scratch：`Tnr`/`_work`/`baseline_demo.log`/`demo_fix.log` 等一次性产物 |
| 23 | `DownLoads` | 19,703.2 MB | **用户下载目录，不属本仓** | 含 `SineCode-学习版.exe` 等。⚠️ **不是本仓产物，建议不动**（列出但不删）|
| 24 | `_fist_atgc_v2_ctl` | 1.2 MB | 可删 | ATGC v2 实验副本（`_build` + 3 份 .mbt + 测试）|
| 25 | `_fist_atgc_v2_exp` | 1.1 MB | 可删 | 同上（另一发实验）|
| 26 | `_fist_meta_prompts` | 3.3 MB | 可删 | 元提示词实验（README + backup + plugin-dev + `实例`）|
| 27 | `_fist_iso` | 0.4 MB | 可删 | 隔离实验（`_meta`/`actus`/`backup`/`fist-mbt.db`）|
| 28 | `backup` | 1.4 MB | 可删 | 4 个 `AI__.xxx.zip`（即已处置的 4 个隐藏目录的旧备份）|
| 29 | `competition` | ~0 MB | 可删 | 单份 md（`202610-MoonBit-方向推荐.md`）—— 建议先归档该 md 再删目录 |
| 30 | `name-squats` | 0.1 MB | 建议保留 | `moon`/`pypi`/`rust` 占名占位 —— **有对外用途**，删前问 owner |
| 31 | `temp` | ~0 MB | 建议保留 | 仅 `rsv-xproc-box`（可能是 α/他人的测试沙箱）|
| 32 | `AI` | ~0 MB | 可删 | 仅 `backup` 子目录 —— ⚠️ 疑似**路径拼接事故**产生的嵌套同名目录（与本会话早段删掉的 `E`+U+FD3A 同族）|
| 33 | `light-wt` | 101.4 MB | **不删** | 司令沙箱（`cmd-beta` 等）+ 各 agent 账号 json —— 统帅明令不许碰 |
| 34 | `.atomcode`/`.codeartsdoer`/`.loomy-attachments`/`.workbuddy` | ~0.2 MB | δ 已处置 | 隐藏目录，δ 已批准删，**不重复处置**（且不在 34 项计数内，仅说明）|

> **合计可删（不含待分级/不动项）**：`_lz_night_scratch` 11,201.8 + `_fist_atgc_v2_*` 2.3 +
> `_fist_meta_prompts` 3.3 + `_fist_iso` 0.4 + `backup` 1.4 + `competition` ~0 + `AI` ~0
> ≈ **11,209 MB（约 11 GB）**。

---

## 五、必须由统帅先裁决的四件事（我不擅自动）

### ⚠️ A. `rx-mbt` 的 origin URL 内嵌明文 OAuth token
```
atomgit:  https://oauth2:<TOKEN>@atomgit.com/…/rxmbt.git
```
本报告**不回显 token 本体**。这属于凭据事故面（BUG-127 同族：凭据形状不入跟踪面/不回显）。
**建议**：另开一单做 `git remote set-url` 去掉凭据 + 改走 SSH/凭据管理器。**不在本单删目录的范围。**

### ⚠️ B. `Tnr` / `Tnr_p0` / `Tnr_merge_check` 同 origin 三份检出
三者 `origin` 同为 `VictorTop/Tnr.git`，但**没有一个是 worktree**（各自独立 clone）。
⚠️ 按判例-51/53：**「同 origin」≠「同内容」**。删任何一份前必须
`git -C <dir> log --all --oneline` 与 `git status` 双向确认独有提交/未提交改动。
**本报告未做这个确认，故三份全部判「不动」**。

### ⚠️ C. 三个非 git 且有内容的项目目录
`lang-pulgins`(180.5 MB) / `Nodea`(0.6 MB) / `Nodea-ATGC`(0.5 MB) —— **没有版本控制**，
按判例-51 口径**删除即不可恢复**。三份都像「别的项目」，但**不在 git 里就没有「已在 origin」的证据**。
**判定：全部不动，需 owner 决定是否纳入某个仓库。**

### ⚠️ D. `_archive`(22.8 GB) 是多项目史料库，不能整目录删
内含 `Ceres`/`ClipRelay`/`CustEditor`/`Cypy` 等**别的项目**的归档。
整删 = 删别人的历史。必须先逐项目证明「已在各自 origin」，再按 owner 的「归档后删原件」原则处理。

---

## 六、我本轮实际做了什么 / 没做什么

| 动作 | 状态 |
|---|---|
| 34 项逐个枚举 + 大小 + 链接/目录 + origin + git 归属 | ✅ 已做（只读） |
| 三个 `FIST-Mbt-slave-*` 的脏面与孤本识别 | ✅ 已做（只读） |
| 识别 `wt02` 的 **703 行未入库孤本** | ✅ 发现（**高风险，删前必须保全**）|
| 识别 `rx-mbt` 的**明文 token** | ✅ 发现（另单处置）|
| **删除任何东西** | ❌ **一件都没删** |

**为什么没删**：统帅的红线里「🟢 别的项目本体绝对不动」与「🔴 主仓内临时产物可删」之间，
`_archive` / `DownLoads` / 三个非 git 项目目录**跨界**，且都含**别人的史料**；
按金条四「不可逆操作只给方案+预案」，我先交分类，等裁决。

## 七、下一步（等你批）

**第一批（低风险，可立即执行）**：
`_fist_atgc_v2_ctl` / `_fist_atgc_v2_exp` / `_fist_iso` / `backup` / `AI`（≈ 2.6 MB）
—— 纯实验副本 + 旧备份 + 路径事故残留，无 git、无他项目内容。

**第二批（需你先确认）**：`_lz_night_scratch`（11.2 GB，夜跑 scratch）

**第三批（需先保全）**：三个 `FIST-Mbt-slave-*` —— 先捞 `wt02` 的 703 行孤本与 `wt03` 的设计稿

**第四批（需 owner 决策）**：`_archive` 分级 / `DownLoads` / `lang-pulgins` / `Nodea*` / `name-squats` / `temp`
