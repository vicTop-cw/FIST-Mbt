# 设计：推送守卫可持续化 + 当前面路径硬编码清零（合并吞面回收）

> 分支 `slave/fix-push-guard-sustainability-r1`（基线 `fcd210b8` = gitcode/main）。
> 承接 FIST 任务 ns=`self-iterate-r1` T0 + 账本 BUG-389(2)。目标：让「直推 gitcode/main 拦截」
> 不再依赖某台机器的手装文件，并把被合并通道吞掉的「路径硬编码清零」现状面回收干净。

## 目标（一句话）
pre-push 拦截收进跟踪面 + 安装器即真源 + 一把「拦截当前是否生效」的尺；同时把当前面
（脚本/插件真源/文档/源码注释/测试夹具）的机器身份路径清零，并回收 PR#17 被合并吃掉的登记面。

## 要改哪些文件（精确路径）
| 文件 | 动作 |
|---|---|
| `.githooks/pre-push` | 新增：跟踪态钩子壳（`exec python check_direct_push.py`，无 python 即拒、不静默 fail-open） |
| `scripts/install_git_hooks.py` | `REQUIRED` 收编 `pre-push`（安装器=真源），文档补 BUG-389(2) 追记 |
| `scripts/check_direct_push.py` | 抽出纯函数 `decide()` + `--selftest` 语义矩阵（7 格）；`main` 从 stdin 读 |
| `scripts/check_push_guard.py` | 新增尺：H0 安装器 REQUIRED / H1-H3 钩子+脑在跟踪面且壳引用脑 / S1 stdin 语义矩阵 / S2 壳未掐 stdin；E1 本机安装态只报不判。`--selftest` 六格（含两格变异台） |
| `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl` | 开发层模板化：占位符 `{{FIST_MBT_LAUNCHER}}`/`{{FIST_MBT_ROOT}}`，形状对齐社区层 launch-mcp.mjs |
| `.dsh/fist-mbt-plugin/cordis.patch.yml` | **脱跟踪**（gitignore）：本机渲染产物 |
| `scripts/render_dsh_patch.py` | 默认入口改 `packaging/dsh/launch-mcp.mjs`（机器无关、随构建自愈）；占位符改名 |
| `scripts/check_hardcoded_paths.py` | 修自命中：文档去字面量、fixture 运行时拼接（尺写进自己被检面会自锁扫红） |
| `scripts/check_host_installable.py` | D1 模板占位符改名，保持双态档 |
| `scripts/run_guards.py` | 点名 `check_direct_push --selftest`（禁裸跑格，防挂 stdin 空转）+ `check_push_guard` 两格 + `run_light_wt --selftest`（补 G1 缺面） |
| `scripts/README.md` | 登记 16 个缺登记脚本（含 PR#17 被吞的 render/hardcoded + 我的新尺）+ BATTERY-REGISTRATION 同批改数 |
| `.github/workflows/ci.yml` | 接 Push-guard / Machine-path / render 三格（position-why 锚点在步骤块内） |
| `scripts/{_run_check_t0r21,fist_mbt_mcp_client,tmp_merge_batch}.py/.sh`、`gen_plugins.py`、`scoring_rubric.md`、`blackbox/e2e_reserve_xproc.py` | 机器身份路径 → env/相对/中性 |
| `AGENTS.md`、`docs/SOP.md`、`plugins/source/SKILL.commander.md`、6 份 docs | 同上（四宿主经 gen_plugins 重投影） |
| `src/server/{write_gate,run_check_guard,issue_scan}.mbt` + 3 测试夹具 | 中性化机器身份字面量，**保留 main 的 ns_write_gate/legacy 覆盖**（235 行 base 版为底，只换字面量） |

## 不改哪些文件（边界）
- `src/core/**`（`dc_3` 基线预存红，pristine 基线同红取证 → 指路并行修复单 `feat/fix-desc-clip-utf8`，不占号不越界修）。
- 只追加历史面（`CHANGELOG.md`/`reports/`/`memory/` 叙述段/`docs/archive/`）、构建产物 `dist/`、生成件 `*.mbti`。
- 不碰 `packaging/dsh/`（社区发布层，b5c8a366 已在位且零绝对路径）。
- `doc_dup`/`slave_task_list`/`unit_number` 的基线预存红不在本 PR 处置（另开车道，避免成合并撞车磁石）。

## 四态覆盖
- cl1 MCP 工具：无新增工具（纯脚本/守卫面）。cl6 文档：README 登记 + 本设计 + 汇报。
- cl7 插件态：gen_plugins 重投影 + check_plugin_sync PASS。测试：src/server 384/384。

## 验收标准（可执行）
1. `check_push_guard --selftest` + 全量 → rc 0；`check_direct_push --selftest` → rc 0
2. `check_hardcoded_paths --selftest` + 全量 → rc 0（当前面零机器身份）
3. `render_dsh_patch --selftest` + 开发层 `--check` → rc 0
4. `check_host_installable --selftest` + 全量 → rc 0（干净检出无渲染件也不自拒）
5. `check_plugin_sync` / `check_scripts_index` / `check_ci_step_position`(≤34) / `check_battery_count_doc` → PASS
6. `moon check --target js` → 0 errors；`moon_test_env --target js src/server` → 全绿
7. `run_guards --list` → 缺执行面 0
