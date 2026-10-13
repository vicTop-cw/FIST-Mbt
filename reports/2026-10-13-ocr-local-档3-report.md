# 2026-10-13 · ocr-local 集成 · 档3（ocr_scan MCP 工具）汇报

- **档位**：档3（`ocr_scan` 真调用 + bugfind 模板接线 + require_ocr 预检）
- **对应计划**：`docs/2026-10-13-ocr-local-integration-plan.md` §档3（L204-254）
- **FIST 闭环**：ns `ocr-local-integration`，根 `T0r`，子 `T0r4`（已 `verify` → 已完成）
- **Commit**：`feat(ocr_scan): add ocr_scan MCP tool with require_ocr precheck (#ocr-3)`（27 files / +1357 / -159）

## 一、结果摘要

把 bugfind 模式的 `require_ocr` 空头支票变成**默认可达的真实能力**：新增 `ocr_scan` MCP 工具，真实 spawn ocr-local 的 OCR CLI（windows-x64 宿主二进制），`--repo <project_dir>` 显式传目标项目；`preview=true` 时走 `--preview --format json`，`dry_run=true` 只回显 argv（一个进程不起）。

| 验收项 | 结果 | 证据 |
|---|---|---|
| `src/server/ocr_scan.mbt` 编译 0 错误 | ✅ | `moon check src/server` = 0 error |
| 白盒测试 10 条 | ✅ | `moon test --target js src/server` = **234/234**（含原 224） |
| 全仓 JS 测试 | ✅ | `moon test --target js` = **962/962** |
| MCP 冒烟（真调用） | ✅ | `fist.py call ocr_scan --subcmd files` → `ok:true, ocr_available:true, exit_code:0`，254 paths |
| MCP 冒烟（dry_run） | ✅ | `--dry-run true` → `{ok,ocr_available:true,dry_run:true,executed:false,args:[...]}` |
| bugfind 模板接线 | ✅ | `templates/pipeline_mode_bugfind.md` 核心动作 10→31 + `ocr_scan` 双轨 + `ocr_hits` 汇报格式 |
| `require_ocr` 预检 | ✅ | `watchdog_tick` / `pipeline_tick` 的 `mode=="bugfind"` 分支 probe 二进制并注入 `ocr_capability.available`（纯读，不 spawn） |
| 四态对齐 | ✅ | `gen_plugins.py` 重投影 = 147 工具；`check_plugin_sync.py`（cl7）= **PASS** |
| 文档同步 | ✅ | `AGENTS.md` / `README.md` 的 `issue_scan` 描述 10→31 条；`README` 运维组 22→23（+`ocr_scan`） |

## 二、关键设计（防走样）

1. **二进制探测优先级**（`ocr_probe_binary`）：env `FIST_OCR_BIN` → `../ocr-local/node_modules/.pnpm` glob → `{project_dir}/ocr-local/node_modules/.pnpm` glob。**注意**：ocr-local 是 FIST-Mbt 的**兄弟目录**（`E:\IDEProjects\AI\ocr-local`），不是 `{project_dir}/ocr-local`（那会塌缩成 `FIST-Mbt/ocr-local`，不存在）。
2. **spawn 的 cwd 用 server cwd（`"."`）**，`--repo <project_dir>` 显式传目标目录。此前用 `workdir=project_dir` 会让 server-cwd-相对的二进制路径解析错（`ENOENT`）。
3. **复用 `run_check_external`**（run_check_js.mbt L84），不新增 FFI；native target 该函数天然返回 `Err("run_check 需要 js/node 运行时…")` → `ocr_available=false` 显式降级，与计划 §L347「windows-x64-only 宿主依赖」一致。
4. **argv 形状（不经 shell）**：`scan --repo R --preview --format json [--path p] [--rule r]` / `delegate rule --repo R [--rule r] <path,...>` / `rules check <path>`。
5. **降级诚实**：平台不匹配或二进制缺失 → 回执 `ocr_available=false` + `note` 说明降级原因，**绝不静默成功**。

## 三、资源消耗

- **编译/测试**：`moon check src/server`（0 error）+ `moon test --target js` 全仓（962/962）+ `moon test src/server`（234/234）。
- **MCP 冒烟**：`fist.py call ocr_scan --subcmd files`（真 spawn，`--preview`，254 paths）+ `--dry-run true`。
- **四态**：`gen_plugins.py` 重投影（147 工具）+ `check_plugin_sync.py`（PASS）。
- **格式化**：`moon fmt`（改动文件）+ `moon info` 同步 `.mbti`。
- **耗时**：约 2 小时（含编译、并发 WIP 冲突排查、hunk 隔离尝试）。

## 四、任务分配记录

- 本档**未拆 FIST 子任务**（档3 是「把空头支票变真实能力」的单点工具接入，深度 3，一次到位）。
- **未委托 subagent**：代码改动横跨 `src/server/ocr_scan.mbt`（新）+ `server.mbt` 注册 + 模板 + 文档 + 插件态，边界紧、须同步终审，直接由指挥官实现。
- **FIST 任务**：`T0r4`（ns `ocr-local-integration`）claim → execute → submit → verify 全流程走完。

## 五、遗留风险

1. **平台限定**：`ocr_scan` 仅在 windows-x64 + 已安装 ocr-local 宿主时可用；其他平台/无宿主 → `ocr_available=false`（已显式降级）。Linux CI 上 bugfind 的 `ocr_hits` 恒为 0，属预期。
2. **preview 模式覆盖有限**：本轮冒烟 `--preview` 对 254 个文件全 `unsupported_ext`（`reviewable_count:0`），未验证真实 OCR review 产出；真实 review 需 `preview=false`（长耗时，未在本轮执行）。
3. **并发 WIP 混合提交**：本 commit 的 `server.mbt` / `AGENTS.md` / `README.md` / `plugins/` 与并发会话的 WIP hunks 混在一起（工作树当前全绿 962/962，未造成回归）；并发 WIP 收口后建议统一 `git diff HEAD` 复核一次归属。
4. **AGENTS.md 工具计数口径**：AGENTS.md 自述「152 tools」，gen_plugins 实测 147（口径不同：注册表去 debug 等）；本轮未改 AGENTS.md 的 152（避免引入新 diff），四态 cl7 以 gen_plugins 实测为准。

## 六、后续建议

1. **档4 `boundary_probe`（stretch）**：按计划 §档4 追加 `task_plan_deep` 的 `boundary_probe=true` 参数（边界审视叶 + 边界四问）。若今晚时间不足，诚实标注「未实施」，留给下一轮。
2. **真实 OCR review 冒烟**：在 windows-x64 上跑一次 `preview=false`（小样本），把 `ocr_hits` 落一次真数据到报告，验证双轨（`issue_scan` + `ocr_scan`）在 bugfind 模式下的端到端。
3. **并发 WIP 收口后**：重跑 nightly `moon fmt` 全仓重排，撤销 `continue-on-error`，恢复 fmt 门强度（AGENTS.md 版本差异说明）。
4. **`docs/issue-scan-skill.md` / `templates/pipeline_mode_advance.md` / `cron_pipeline_meta_prompt.md`** 仍有「内建 10 条」旧口径，本轮只改了 AGENTS/README；建议下一轮一并 sync 到 31 条。

## 七、超额内容

- `watchdog_tick` / `pipeline_tick` 的 bugfind 分支**额外**注入 `ocr_capability` 预检回执（原计划只在 `ocr_scan` 工具描述里写降级）；这是把「require_ocr 是硬约束」落成运行时可见证据，属计划意图的延伸，未新增工具数。
- `README.md` 运维组 `issue_scan` 描述的 10→31 条同步，属档1+2 遗留的 doc sync，本轮顺手收口。

## 八、来源

- 计划：`docs/2026-10-13-ocr-local-integration-plan.md`（档3 L204-254，验收证据链 L245-254）
- 代码：`src/server/ocr_scan.mbt`（新）、`src/server/ocr_scan_wbtest.mbt`（新）、`src/server/server.mbt`（注册 + 预检）
- 模板：`templates/pipeline_mode_bugfind.md`
- 文档：`AGENTS.md`、`README.md`
- 插件态：`plugins/`（`gen_plugins.py` 重投影）
- FIST 台账：ns `ocr-local-integration` / `T0r4`（已完成）
- Commit：`feat(ocr_scan): add ocr_scan MCP tool with require_ocr precheck (#ocr-3)`