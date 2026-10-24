# Whisperer 合并马拉松 · 会话总结报告（2026-10-23 ~ 10-24）

**角色**：Whisperer（贤者）；**授权边界**：gitcode 权威 / gitHub 仅镜像；本地 agent = developer
**起点**：HEAD `29db3251`（packaging: cordis.patch.yml.tpl）
**终点**：HEAD `a8b67464`
**模式**：混合模式 —— Whisperer 只做 cherry-pick / 按文件取版本，从不直推 main（`check_direct_push.py` 常驻守）

---

## 一、结果摘要

| 维度 | 结果 |
|---|---|
| **真 ahead 处理** | **34 个**（全部 cherry-pick / 按文件合入，零冲突遗留） |
| **判据转绿** | **17 个** |
| **守卫电池** | FAIL **14+ → 0**（仅 5 SKIP = 缺 temp 前置件） |
| **测试** | **1449 / 1449 passed** |
| **moon check** | 0 errors / 502 warnings（基线，无漂移） |
| **三端一致** | local = gitcode = `a8b67464` ✅ |

---

## 二、合并面：三种判据的建立与使用

filter-repo 重写历史后，传统 ahead 判据（`rev-list` / `comm -23` / `git cherry`）**全部失效**。
本会话建立并实用了三种判据，各有盲区、互补：

| 判据 | 方法 | 抓到什么 | 盲区 |
|---|---|---|---|
| **J1 新增文件** | `diff-filter=A`（排除已知删除清单） | T0r5 agent 指纹注册表、R141 J17 toolchain.json | 修 main 缺陷的分支不新增文件 |
| **J2 符号集差分** | 分支 pub 符号集 − main 符号集 | 排除大量基线倒退噪音 | 只覆盖 `pub`；方法/非 pub 函数抓不到 |
| **J3 commit message** | 关键词（修 main/仍红/假绿/撤掉/安全…） | main 缺陷修复类、文档真值类 | 依赖 message 写得好 |

### 本会话合入的重要功能

| 分支 / Commit | 内容 |
|---|---|
| T0r5 `feat/agent-fingerprint-pid-guard` | **PID-guarded agent registry + default-deny ACL**（+425 store / +252 wbtest / +140 server），安全语义 fail-closed |
| R141 `slave/gate/toolchain-floor-guard-r141` | **J17 工具链地板 ↔ toolchain.json 单一真源**（+207 判据），上岗第一跑即抓到 Node 版本矛盾 |
| `slave/fix/whisperer-head-state-r120` | **Step 0 安全重写**：撤掉默认 `git reset --hard` + `git push --force` 两远端 |
| `fix/mcp-smoke-ns-and-store-locks` | 4 个补丁，含修 main 唯一的测试红 `dc_3`（17/18 → 18/18） |
| r152 / r156 | CLI 失败归因分档 + 按失败档准入重试 |
| r172 / r170 / r179 / r153 | doctor 退出码、CWD 锚点 ×2、W 档 hermetic、check_selftest_hermetic 常驻 |
| 6 条合并就绪分支 | py_stdout_encoding / memory_log_empty_universe / slave_task_anchors / backlog restamp ×5 |
| r175 / r160 | BACKLOG 撤陈旧计数、撤「JS+Native 双端全绿」假绿自述 |

---

## 三、修掉的 4 个真事故（非合并面）

| 事故 | 发现方式 | 后果 |
|---|---|---|
| `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl` 内容是 **git 报错文本** | 把 `render_dsh_patch --selftest` 接进电池后 T13 红 | 模板缺占位符 ⇒ 渲染件漏值 |
| `fist-gate.py` 是 **4 份文件串接**（1384 行 / 4 个 `__main__`） | `check_script_single_copy` | 后 3 份死代码，含唯一的 `ck_ws`（whisperer 检查）与 TASK-004 八格 |
| `.verify-wt` 被 `git add -A` 当 **gitlink(160000)** 入库 | 自己引入后立即自查 | `check_merge_markers` 等读不到正文 ⇒ 整尺红 |
| `whisperer.py` Step 0 默认 **`reset --hard` + `force push` 两远端** | J3 message 扫描 + 逐行比对 | 每 15 分钟替所有 feature 分支工作者做不可逆裁决 |

---

## 四、判据面修复（17 个转绿）

`slave_task_list` · `py_stdout_encoding --all` · `memory_log_dedupe` · `backlog_yaml_integrity` ·
`plugin_sync` · `scripts_index` · `merge_markers` · `diff_scope` · `bug_reference_integrity` ·
`moon_env_probe` · `doc_surface(J17)` · `text_control_chars` · `selftest_inventory_doc` ·
`hardcoded_paths` · `selftest_call_face` · `battery_count_doc` · `branch_ancestry`/`delivery_gap`（改诊断口径）

### 其中三个是「把尺寸子扶正」的根因修复

1. **`run_guards` 宇宙叠 Git 跟踪面**：`os.walk` 把 gitignored 本机文件（`pol_keeper_*` / `fix_esm_require.py`）
   当仓内脚本 ⇒ G1 缺面 ⇒ 有人塞 REGISTRY 图绿 ⇒ G2 在**别的机器上**把整台电池卡 FATAL。
2. **`check_text_control_chars` 改扫跟踪面**：旧实现递归到并排的**其它工程**（`_proj_lang-zone/`）
   报 14262 处违例、且递归 `.verify-wt/` 让整格被 SIGTERM（rc=143）。修后 **2m20s → 1.7s，违例 0**。
3. **`check_scripts_index` 词界判据**：旧判据纯子串 ⇒ `fist.py` 被 `fist-mbt-http.py` 命中就算登记，
   **核心入口从未被要求登记**。

---

## 五、自己引入并修正的 3 个缺陷（如实记录）

| 缺陷 | 成因 | 教训 |
|---|---|---|
| 把 4 个 **gitignored 脚本**误加进 REGISTRY + README | 判据报「缺面」，我按「脚本存在但无执行面」处理，实际是「不在仓里」 | 修复前先确认文件是否在**跟踪面** |
| `.verify-wt` gitlink 入库 | `git add -A` 在含临时 worktree 的仓库里是危险动作 | **只 add 明确路径**，永不用 `-A` |
| 测试夹具 `E:/IDEProjects/AI/Cypy` → `E:/proj/Cypy` 段数从 4 掉到 3 | 中性化时顺手删了结构段，而 `run_check_guard` 按**段列表**判等 | 只换**身份那段**（目录名/用户名），不动结构段 |

---

## 六、遗留风险

1. **GitHub 镜像落后**：`b5c8a36` vs `a8b67464`（约 1050 提交）。安全入口已就绪
   `python scripts/whisperer.py --sync-mirror`（默认 0 push，显式才推且只推 origin）。
   属 force push 类不可逆动作，**留 owner 决定**。
2. **196 支与 main 无共同祖先**（filter-repo 后果）：`git merge` 拒绝 unrelated histories，
   合并只能 cherry-pick。已登记为 `check_branch_ancestry` 诊断读数。
3. **5 个电池格 SKIP**：缺 `temp/pt27.log` / `temp/chk47.json` 运行时产物。
   按判据纪律 **SKIP 不构成「这格过了」的证据**，需在产出这些 temp 件的流程里复跑。
4. **`worktree/skill-docs2` 本地支未删**：被 `temp/wt-skill` worktree 占用，属本机临时态。

---

## 七、后续建议

1. 把 J3（commit message 扫描）固化成常驻判据——它是本会话唯一抓到「修 main 缺陷」与
   「文档真值修正」两类零新增文件分支的手段。
2. `check_hardcoded_paths` 的豁免规则可再收：本轮新增了「判据自指」与「`scripts/_` 临时件」两条，
   但测试夹具里的虚构盘符路径仍计入扫描面（目前靠中性化通过）。
3. BACKLOG 的计数面**至今没有尺**（J14 只扫 AGENTS/README 的 CLI 分组面）——本会话靠分支修正，
   但同族残留仍可能再长。建议补一格 `check_backlog_no_count`。

---

## 八、超额内容

- 修 `check_selftest_call_face` 的 J2 缺口：**46 → 30**，并按棘轮纪律同批把常量 `40 → 30`。
- 修 `check_doc_surface` J17 的**引文假阳性**（历史转述被当成现状声明）。
- 回填账本 4 个幽灵编号（BUG-390/397/398/399），消除注释面悬空引用。
- 补 `docs/tasks/diff-scope-claims.txt` 声明面（判据原本 FATAL 无真源）。

---

## 九、来源

- 会话：Whisperer 定时巡检会话（30min 周期，2026-10-23 ~ 10-24）
- 判据：`scripts/run_guards.py`（电池）+ 各 `check_*.py`（尺）
- 证据：每条 commit message 内含验证命令与读数；报告见 `reports/2026-10-2*-*-report.md`
