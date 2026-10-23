# ocr-local 融入 FIST-Mbt bugfind 模式 · 计划

**日期**：2026-10-13
**状态**：修订版 v3（**四档全部实施完成**；档 1+2 = commit 8caa71b，档 3 = commit `feat(ocr_scan)`，档 4 = commit `feat(boundary_probe)`）
**关联模式**：`bugfind`（`require_issue_scan` + `require_test_corpus` + `require_ocr`）
**修订记录**：v2 新增 §0 评审视角 / 每档验收证据链 / §8 发布即同步 / §9 评审演示场景 / §10 执行节奏；保留原四档方案、风险表、验收总表不变。**v3 收口**：四档全部落地——档 3 `ocr_scan`（真源 `src/server/ocr_scan.mbt`，windows-x64 宿主二进制，FIST `T0r4` 已完成）、档 4 `boundary_probe`（真源 `src/server/boundary_probe.mbt`，纯计算按规则类型路由，FIST `T0r5` 已完成）；`require_ocr` 从空头支票变默认可达真实能力（档 3 完成前不得宣称已集成的纪律已兑现）。四档报告：`reports/2026-10-13-ocr-local-档3-report.md`、`reports/2026-10-13-ocr-local-档4-report.md`。

---

## 0. 评审视角（先读）

### 0.1 对照验收失败教训：本计划要消灭的"空头支票"

FIST-Mbt 黑客松正式验收 6 项失败的核心教训是**申报承诺与实现/产物不符、空头支票**。本计划把该教训逐条映射为"承诺纪律"，杜绝"预留接口 / 占位实现 / 文档先行 / 发布滞后"：

| # | 验收失败教训（事实） | 本计划的承诺纪律 |
|---|---|---|
| 1 | 承诺物理多租户隔离，默认行为仍走全局单库 | `require_ocr` 一旦声明为 bugfind 约束键，就必须有**默认可达**的真实能力（档 3 完成前不得宣称已集成） |
| 2 | 自动修复三轮返回零修复（fixes_applied 恒空） | 任何"预留接口"禁止交付：`rules_file` 必须真解析（档 2）、`ocr_scan` 必须真跑二进制（档 3），不允许 `let _ = rules_file` 式占位残留 |
| 3 | 外部 Executor 报 readonly（白名单硬编码拒绝） | OCR 二进制不可用时必须**显式降级 + 回执标注** `ocr_available=false`，禁止假装可用或静默跳过 |
| 4 | native serve/demo 仅输出帮助（argv 偏移回退） | native 目标不支持 OCR 必须**文档 + 工具描述双声明**（见 §7），禁止留白让评审当漏洞打 |
| 5 | DAG 接受成环（文档与实现背离） | 四态同步（README / AGENTS.md / CLI-help / 插件态）必须一致，守卫不过不许合入 |
| 6 | Omega 门被 archive 绕过 | 发布即同步（§8）：评审运行的是发布版 `fist-mbt.js`，不是开发版 `_build/cli.js`，功能不会"评审时失踪" |

### 0.2 每档"承诺 → 实现 → 证据"三要素总览

| 档 | 承诺（申报口径） | 实现（代码落点） | 证据（验收时出示） |
|---|---|---|---|
| 档 1 | issue_scan 内建规则 10 → ~25 条 | `src/server/issue_scan.mbt` `scan_rules()` 扩展 + `scan_file` regex 分支 | `moon test --target js` 全绿 + `issue_scan(dir="src").by_rule` ≥ 20 + 守卫 PASS + git 提交 |
| 档 2 | `rules_file` 真解析外部 JSON | `scan_parse_external_rules()` + `issue_scan()` 入口合并去重 + 白盒测试 | 白盒测试绿 + 合法/非法/零回归三用例 + git 提交 |
| 档 3 | `require_ocr` 变真实能力，新增 `ocr_scan` MCP 工具 | `src/server/ocr_scan.mbt` + `server.mbt` 注册 + bugfind 模板 + 四态 | `ocr_scan` dry_run/真实调用输出 + 降级回执 + 守卫 PASS + git 提交 |
| 档 4 | `boundary_probe` 自动生成边界语料 | `src/server/boundary_probe.mbt` + 注册 + 模板 | 规则类型路由单测 + 模板第四步不再是人工提示词 + git 提交 |

> 纪律：**没有证据链的验收项不写入总表**；每个验收项在 §3 对应档下附完整证据链（moon test / 守卫 / 四态 / git 四类证据）。

---

## 1. 背景与问题

FIST-Mbt 的 `bugfind` 模式在 `src/ops/ops_modes.mbt:125-130` 声明了三把约束键：

```moonbit
"bugfind" => {
  m.set("require_issue_scan", Json::boolean(true))
  m.set("require_test_corpus", Json::boolean(true))
  m.set("require_ocr", Json::boolean(true))
}
```

但 `require_ocr` 是**空头支票**——OCR（open-code-review）从未真正接入 FIST-Mbt。具体表现：

1. `issue_scan.mbt:4` 注释写"复用 ocr-local 的规则路由模式"，但实现是**纯内建 10 条规则**，与 ocr-local 的 20 条规则无关。
2. `issue_scan` 的 `rules_file` 参数（`server.mbt:5950`）是**空占位**（`issue_scan.mbt:869` `let _ = rules_file`），不解析外部 JSON。
3. bugfind 模板 `templates/pipeline_mode_bugfind.md:18,46-47` 明确写"ocr-cli 躬身入局版**尚未集成**，当前 fallback 跳过"。
4. 守卫和模板工具清单里没有任何 OCR 相关工具。

前几轮寻虫只用了 `issue_scan`（规则扫描），75 findings 全是已有守卫的误报——**OCR 这一环的缺失，导致 bugfind 模式只有"内建单行正则"一条腿，缺少 LLM 级的语义审查和边界语料生成**。

---

## 2. 两侧现状盘点

### 2.1 ocr-local（`E:\workspace\AI\ocr-local`）

| 资产 | 说明 |
|---|---|
| `rules/moonbit-rules.json` | **20 条 MoonBit 专项规则**：error 9 / warning 8 / info 3，覆盖 correctness / security / concurrency / maintainability 四类 |
| `ocr.ps1` | PowerShell 封装脚本，6 个子命令：`scan` / `files` / `diff` / `delegate` / `rules` / `doctor` |
| `node_modules/.pnpm/@alibaba-group+ocr-win32-x64@.../bin/opencode review.exe` | OCR CLI 二进制（open-code-review） |

20 条规则清单（与 FIST-Mbt 内建 10 条的重叠标注）：

| ocr-local 规则 | 严重度 | 类别 | FIST-Mbt 是否已有 |
|---|---|---|---|
| moonbit-result-discard | error | correctness | 部分（ignored-error 只匹配固定前缀） |
| moonbit-map-set-no-rebind | error | correctness | 无（Map 不可变 set 不绑定） |
| moonbit-noop-assignment | warning | correctness | 无（字段自赋值） |
| moonbit-string-interpolation-escape | error | correctness | 无（`\\{` / `}\\` 畸形插值） |
| moonbit-match-exhaustive | error | correctness | 无（非穷尽 match） |
| moonbit-array-index-bounds | error | correctness | **重叠**（string-index / index-out-of-bounds） |
| moonbit-unsafe-unwrap | warning | correctness | **重叠**（unsafe-get / unwrapped-unwrap） |
| moonbit-async-main | error | correctness | 无（async main 返回 Future 无人 poll） |
| moonbit-private-field-leak | warning | security | 无（公开导出敏感字段） |
| moonbit-path-traversal | error | security | 无（路径拼接无校验） |
| moonbit-json-injection | warning | security | 无（JSON 字符串拼接） |
| moonbit-divide-by-zero | error | correctness | **重叠**（unprotected-division / div-by-zero） |
| moonbit-floating-point-equality | warning | correctness | 无（浮点 == 比较） |
| moonbit-race-condition | error | concurrency | 无（跨 async 可变状态竞争） |
| moonbit-resource-leak | error | correctness | 无（资源打开未关闭） |
| moonbit-integer-overflow | warning | correctness | **重叠**（possible-overflow / secs-overflow） |
| moonbit-dead-code | info | maintainability | 无（abort 后死代码） |
| moonbit-empty-match | warning | correctness | 无（catch-all match 吞所有 case） |
| moonbit-long-function | info | maintainability | 无（函数超 50 行） |
| moonbit-shared-mutable | warning | correctness | 无（let mut 从字段派生，修改不回写） |

### 2.2 FIST-Mbt 侧

| 项 | 现状 |
|---|---|
| `issue_scan` 内建规则 | 10 条（div-by-zero / index-out-of-bounds / unwrapped-unwrap / unsafe-get / unprotected-division / substring-overrun / ignored-error / string-index / possible-overflow / empty-collection-singleton / secs-overflow） |
| `rules_file` 参数 | 空占位，不解析 |
| OCR CLI 调用 | 无 |
| 边界语料生成 | 仅在 bugfind 模板里作为人工提示词 |
| `require_ocr` 预检 | 无（约束键只声明，pipeline_tick 不检查） |

---

## 3. 融入方案（四档）

### 档 1：规则融合 — ocr-local 20 条规则内建进 issue_scan

**目标**：`issue_scan` 从 10 条规则扩到约 25 条（去重后），覆盖 ocr-local 的四类关注点。零外部依赖。

**做法**：

1. **移植规则**：把 `ocr-local/rules/moonbit-rules.json` 的 20 条规则逐条转成 `scan_rules()` 里的 `ScanRule` 条目。
   - `pattern`：ocr-local 用单条 regex 字符串，FIST-Mbt 用 `Array[String]` 子串匹配。简单模式直接转；复杂 regex（如 `match\s+\w+\s+\{[^}]*\}[^;]`）保留 regex 形式，在 `scan_file` 里加一个 regex 匹配分支（MoonBit 内置 `Regex`）。
   - `why` / `hint`：照抄 ocr-local 的 `description` / `why`。

2. **去重合并**：重叠规则合并为一条，pattern 数组取并集：
   - `array-index-bounds` ↔ `string-index` + `index-out-of-bounds` → 合并
   - `unsafe-unwrap` ↔ `unsafe-get` + `unwrapped-unwrap` → 合并
   - `divide-by-zero` ↔ `unprotected-division` + `div-by-zero` → 合并
   - `integer-overflow` ↔ `possible-overflow` + `secs-overflow` → 合并

3. **守卫过滤增强**：对需要上下文的规则，复用现有 `prev_window` 机制：
   - `race-condition`：检查命中行前 10 行是否有 `mut` 声明 + 是否跨 `await`
   - `resource-leak`：检查 `@lib.*::open` 后是否紧跟 `match` / `using`
   - `match-exhaustive`：检查 match 块是否有 `_ =>` 兜底（有则降低严重度或过滤）

4. **规则表文件自跳过**：现有 `scan_is_rules_table` 只跳过 `issue_scan.mbt`，移植后规则表仍在同文件，无需改动。

**边界**：
- 只改 `src/server/issue_scan.mbt`
- 不改 `server.mbt` 注册（参数不变）
- 不引入外部二进制
- `rules_file` 参数仍占位（档 2 再激活）

**验收标准**：
- `moon test --target js` 全绿
- `issue_scan(dir="src")` 返回的 `by_rule` 键数 ≥ 20
- 守卫 `check_doc_surface` PASS（工具描述里"10 条"同步更新成新数）
- 守卫 `check_plugin_sync` PASS（插件态工具描述同步）

**验收证据链（档 1）**：

| 维度 | 证据内容 |
|---|---|
| 承诺 | issue_scan 内建规则从 10 条扩到 ≥20 条（去重后约 25 条），覆盖 ocr-local 四类关注点 |
| 实现落点 | `src/server/issue_scan.mbt`：`scan_rules()` 新增规则条目、`scan_file` 新增 regex 匹配分支、守卫过滤（race-condition / resource-leak / match-exhaustive） |
| 自动化证据 | `moon test --target js` 汇总行 `N passed, 0 failed`；`issue_scan(dir="src")` 返回 JSON 中 `by_rule` 键数 ≥ 20（键名清单打印入证据文件） |
| 守卫证据 | `check_doc_surface` PASS（工具描述规则数更新）；`check_plugin_sync` PASS（插件态工具描述同步）；`check_tools_sync` PASS |
| 四态同步 | README / AGENTS.md / CLI-help / `gen_plugins.py` 重投影均无 diff（`git diff --exit-code` 为空） |
| git 证据 | 提交 `feat(issue_scan): merge ocr-local 20 rules into scan_rules (#ocr-1)`；规则表与守卫过滤分 commit 提交，便于评审逐项 diff |

---

### 档 2：外部规则文件解析 — 激活 `rules_file` 参数

**目标**：`issue_scan(dir, rules_file=...)` 真的解析外部 JSON（ocr-local moonbit-rules.json 风格），与内建规则合并去重。规则维护不进仓库代码。

**做法**：

1. **新增解析函数** `scan_parse_external_rules(json_text : String) -> Result[Array[ScanRule], String]`：
   - 解析 `{rules:[{name, languages, severity, pattern, description, why}]}`
   - `name` → `ScanRule.id`，`severity` → `ScanRule.severity`，`pattern` → `ScanRule.pattern`（单字符串转单元素数组），`description` → `ScanRule.why`
   - 字段缺失 / 类型错误 → 返回 Err，不静默回落（BUG-62 政策）

2. **入口改造** `issue_scan()`：
   - 若 `rules_file` 非空 → `scan_dir_ok` 校验路径（禁绝对/穿越/盘符）→ 读文件 → 解析 → 与 `scan_rules()` 合并 → 按 `id` 去重（外部同名覆盖内建）
   - 若 `rules_file` 为空 → 仅内建规则（零回归）

3. **白盒测试** `src/server/issue_scan_external_rules_wbtest.mbt`：
   - 合法 JSON 解析出 N 条规则
   - 非法 JSON 返回 Err
   - 内建 + 外部合并去重后总数正确
   - 外部同名规则覆盖内建
   - 路径防御：绝对路径 / `..` 穿越被拒

**边界**：
- 改 `issue_scan.mbt` + 新增白盒测试
- 不改 `server.mbt` schema（`rules_file` 参数已存在）
- 不把 ocr-local 规则文件拷进仓库（档 2 只做解析能力，规则文件由用户提供或档 3 从 ocr-local 探测）

**验收标准**：
- 传入一个合法的 moonbit-rules.json 能解析出 20 条规则
- 非法 JSON / 缺字段返回 Err
- 内建 10 条 + 外部 20 条合并去重后总数正确（约 25 条）
- `rules_file=""` 时行为与改造前完全一致（零回归）

**验收证据链（档 2）**：

| 维度 | 证据内容 |
|---|---|
| 承诺 | `issue_scan(dir, rules_file=...)` 真实解析外部 JSON，与内建合并去重，同名外部覆盖内建；空参零回归 |
| 实现落点 | `scan_parse_external_rules(json_text) -> Result[Array[ScanRule], String]`；`issue_scan()` 入口增加 `scan_dir_ok` 路径校验 → 读文件 → 合并去重；新增 `src/server/issue_scan_external_rules_wbtest.mbt` |
| 自动化证据 | `moon test --target js` 全绿（白盒 5 用例：合法解析 / 非法 Err / 合并总数 / 同名覆盖 / 路径防御）；传入真实 `ocr-local/rules/moonbit-rules.json` 解析出 20 条 |
| 守卫证据 | `check_doc_surface` / `check_tools_sync` / `check_plugin_sync` PASS（`rules_file` 参数描述从"占位"改为"外部规则文件"） |
| 四态同步 | README / AGENTS.md / CLI-help 中 `rules_file` 参数说明一致，`gen_plugins.py` 重投影后 `git diff --exit-code` 为空 |
| git 证据 | 提交 `feat(issue_scan): activate rules_file parsing with wbtest (#ocr-2)`；实现与白盒测试同 commit，证据不可拆分 |

---

### 档 3：OCR CLI 集成 — 新增 `ocr_scan` MCP 工具

**目标**：新增 MCP 工具 `ocr_scan`，封装 ocr-local 的 `scan`/`files`/`delegate`/`rules` 子命令，与 `issue_scan` 形成"内建规则 + OCR LLM review"双轨。`require_ocr` 从空头支票变真实能力。

**做法**：

1. **新增 `src/server/ocr_scan.mbt`**：
   - 纯计算层 `ocr_build_args(project_dir, subcmd, path, rules_file) -> Array[String]`：argv 构造，不经 shell，防注入（复用 `executor_run` 的 argv 固定模式）
   - IO 层 `ocr_run_cli(bin_path, args, timeout_ms) -> Result[String, String]`：spawn 二进制，超时/失败归因
   - 二进制路径探测（优先级）：env `FIST_OCR_BIN` → `{project_dir}/../ocr-local/node_modules/.pnpm/@alibaba-group+ocr-win32-x64@*/node_modules/@alibaba-group/ocr-win32-x64/bin/opencode review.exe`（glob 探测）→ 报错提示安装

2. **注册 `ocr_scan` 工具**到 `server.mbt`：
   - 参数：`project_dir`（必填，相对路径）、`subcmd`（scan|files|delegate|rules，必填）、`path`（可选）、`rules_file`（可选）、`timeout_ms`（可选默认 180000）、`dry_run`（可选默认 false：只回显 argv 不起进程）
   - 返回：`{ok, stdout, stderr, exit_code, args}`（dry_run 时 args 有值、stdout 为空）

3. **bugfind 模板更新** `templates/pipeline_mode_bugfind.md`：
   - 第二步从"预留接口，fallback 跳过"改成真实调用 `ocr_scan`
   - 工具清单硬规则段追加 `ocr_scan`

4. **`require_ocr` 预检**：
   - 在 `pipeline_tick` / `watchdog_tick` 的 bugfind 分支里加预检：探测 OCR 二进制是否可用
   - 不可用 → 降级为"只用 issue_scan"，回执标注 `ocr_available=false`，不报错
   - 可用 → 走 issue_scan + ocr_scan 双轨

5. **四态对齐**：
   - README / AGENTS.md / CLI-help / 插件态 追加 `ocr_scan` 工具描述
   - `gen_plugins.py` 重投影

**边界**：
- 新增文件 `ocr_scan.mbt` + 注册 + 模板更新 + 文档
- OCR 二进制是宿主依赖，不进仓库（`.gitignore` 已有 `node_modules`）
- 不把 ocr-local 整个项目搬进 FIST-Mbt（保持独立）

**验收标准**：
- `ocr_scan(project_dir=".", subcmd="files", dry_run=true)` 返回正确 argv
- `ocr_scan(project_dir=".", subcmd="files")`（OCR 可用时）返回 FIST-Mbt src/ 文件列表
- OCR 不可用时返回结构化错误，不崩溃
- bugfind 模板第二步不再写"未集成"
- 守卫 `check_tools_sync` / `check_plugin_sync` / `check_doc_surface` PASS（新工具四态对齐）
- `moon test --target js` 全绿

**验收证据链（档 3）**：

| 维度 | 证据内容 |
|---|---|
| 承诺 | 新增 MCP 工具 `ocr_scan`，封装 OCR CLI 子命令，`require_ocr` 从空头支票变真实能力；不可用显式降级并标注 |
| 实现落点 | `src/server/ocr_scan.mbt`（`ocr_build_args` 纯计算 + `ocr_run_cli` IO + 二进制路径三级探测）；`server.mbt` 注册；`templates/pipeline_mode_bugfind.md` 第二步真调用；`pipeline_tick`/`watchdog_tick` bugfind 分支加预检 |
| 自动化证据 | `ocr_scan(project_dir=".", subcmd="files", dry_run=true)` 返回正确 argv（无副作用）；OCR 可用时返回 FIST-Mbt src/ 文件列表；OCR 不可用返回结构化错误且回执含 `ocr_available=false`，不崩溃 |
| 守卫证据 | `check_tools_sync` / `check_plugin_sync` / `check_doc_surface` 三守卫 PASS（新工具四态对齐） |
| 四态同步 | README / AGENTS.md / CLI-help / 插件态均含 `ocr_scan` 工具描述，`gen_plugins.py` 重投影后 `git diff --exit-code` 为空 |
| git 证据 | 提交 `feat(ocr_scan): add ocr_scan MCP tool with require_ocr precheck (#ocr-3)`；工具实现、模板与文档同步在同一提交内 |

---

### 档 4：边界语料生成器 — `boundary_probe` MCP 工具

**目标**：把 bugfind 模板里"构造边界 case"从人工提示词变成 MCP 工具，对 issue_scan/ocr findings 自动生成边界输入并跑验证。

**做法**：

1. **新增 `src/server/boundary_probe.mbt`**：
   - 输入：finding（`file`, `line`, `rule`, `code`）
   - 输出：该位置的边界输入建议数组（空串 / 零 / 负数 / 极值 / 并发交错 / 超长串），按规则类型路由
   - 纯计算，不跑测试

2. **与 `run_check` 联动**：
   - `boundary_probe` 只生成建议，不执行
   - 调用方（bugfind 模式）把建议喂给 `run_check` 跑，能触发 panic/崩溃的标记为 `confirmed=true`

3. **bugfind 模板更新**：
   - 第四步从"自造边界 case"改成调 `boundary_probe` + `run_check`

**边界**：
- 这是最远的一档，依赖档 1-3 的输出结构稳定后再做
- 新增文件 + 注册 + 模板 + 四态对齐

**验收标准**：
- `boundary_probe(finding={rule:"divide-by-zero", code:"x / y"})` 返回包含 `y=0` 的边界建议
- 不同规则类型返回不同的边界输入集
- bugfind 模板第四步不再是人工提示词

**验收证据链（档 4）**：

| 维度 | 证据内容 |
|---|---|
| 承诺 | `boundary_probe` 按规则类型自动生成边界输入建议，喂给 `run_check` 可确认 panic/崩溃 |
| 实现落点 | `src/server/boundary_probe.mbt`（纯计算，按规则类型路由）；`server.mbt` 注册；`templates/pipeline_mode_bugfind.md` 第四步改调 `boundary_probe` + `run_check` |
| 自动化证据 | `moon test --target js` 全绿；规则路由单测：divide-by-zero → 含 `y=0`、string-index → 含超长串/空串、concurrency 规则 → 含并发交错建议 |
| 守卫证据 | `check_tools_sync` / `check_plugin_sync` / `check_doc_surface` PASS（新工具四态对齐） |
| 四态同步 | README / AGENTS.md / CLI-help / 插件态含 `boundary_probe` 描述，`gen_plugins.py` 重投影后 `git diff --exit-code` 为空 |
| git 证据 | 提交 `feat(boundary_probe): add boundary input generator (#ocr-4)` |

---

## 4. 推荐执行顺序与优先级

| 档 | 工作量 | 依赖 | 风险 | 收益 | 建议 |
|---|---|---|---|---|---|
| **档 1** 规则融合 | 中 | 无 | 低（纯内建，零外部依赖） | issue_scan 覆盖面 10→~25 条 | **立即做** |
| **档 2** 外部规则解析 | 中 | 档 1 | 低 | ocr-local 规则可热插拔 | **与档 1 合并做** |
| **档 3** OCR CLI 集成 | 高 | 档 2 | 中（宿主二进制依赖、路径探测） | `require_ocr` 变真实能力，双轨寻虫 | 独立任务 |
| **档 4** 边界语料生成 | 高 | 档 3 | 中 | bugfind 全自动闭环 | 独立任务 |

**建议**：档 1 + 档 2 合并为一个任务包（零外部依赖，最稳，收益直接），把 ocr-local 的 20 条规则吃进 issue_scan，同时激活 `rules_file` 参数。档 3、档 4 作为后续独立任务。

---

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| ocr-local 规则的 regex 在 MoonBit 里行为不一致 | 每条规则移植后跑一次 `issue_scan` 实测，对比 ocr-local 的 `scan` 输出，命中数差异 >20% 则人工复核 |
| 规则数增加导致误报率上升 | 复用现有守卫过滤机制（`_safe` 钳制 / `prev_window` / 注释行跳过），新增规则同样走过滤 |
| OCR 二进制路径探测不稳定 | 多级 fallback（env → 项目内 glob → 报错），`dry_run` 面保证零副作用可测 |
| 档 3 引入宿主依赖破坏"零外部二进制"原则 | 档 3 的 OCR 是可选增强，不可用时降级为 issue_scan 单轨；档 1+2 仍保持纯内建 |
| 规则文件路径穿越 | `rules_file` 复用 `scan_dir_ok` 校验，禁绝对路径 / `..` / 盘符 |

---

## 6. 验收总表

| 档 | 验收项 | 证据 |
|---|---|---|
| 1 | 规则数 ≥ 20 | `issue_scan(dir="src").by_rule` 键数 |
| 1 | 测试全绿 | `moon test --target js` 汇总行 |
| 1 | 文档同步 | `check_doc_surface` PASS |
| 2 | 外部规则可解析 | 传入 moonbit-rules.json 返回 20 条 |
| 2 | 零回归 | `rules_file=""` 行为不变 |
| 3 | OCR 工具可用 | `ocr_scan(files)` 返回文件列表 |
| 3 | 四态对齐 | `check_tools_sync` + `check_plugin_sync` PASS |
| 3 | 降级安全 | OCR 不可用时不崩溃 |
| 4 | 边界建议生成 | `boundary_probe` 返回规则对应边界输入 |

---

## 7. 不在本计划范围内

- 把 ocr-local 整个项目搬进 FIST-Mbt（保持独立）
- OCR CLI 的 LLM review 结果自动判 bug（仍由 agent 读上下文复核，issue_scan 的"候选"定位不变）
- 修改 ocr-local 项目本身（只消费其规则和二进制）
- native 目标的 OCR 集成（OCR CLI 是 Windows x64 二进制，native 目标暂不支持）

> **native 边界显式声明（防评审当漏洞打）**：
> - `ocr_scan` 工具描述必须显式标注平台约束：`platform: windows-x64 only (open-code-review binary)`，并在不可用时的结构化错误中输出 `unsupported_target: native`。
> - README 增加"平台支持"小节：`issue_scan`（js/native 均可用）/ `ocr_scan`（仅 windows-x64 + js 运行时）/ `boundary_probe`（js/native 均可用）。
> - AGENTS.md 与 CLI-help 同步上述平台约束，不得出现"native 可用 OCR"的歧义表述。
> - 评审演示只运行于 Windows x64 环境；若评审在非 windows-x64 平台执行，`require_ocr` 预检返回 `ocr_available=false` 属**预期降级**而非缺陷（回执必须含此标注）。

---

## 8. 发布即同步（防评审运行旧版）

### 8.1 问题

验收失败教训 #6 的同类风险：功能在开发版实现、文档已更新，但**发布版仍是旧版**——评审运行发布版时功能缺失，等于"承诺与产物不符"的再现。FIST-Mbt 的既有事实：Marvis 各 `.mcp.json` 的 fist-mbt 启动命令指向**发布版** `%LOCALAPPDATA%\Local\FIST-Mbt\fist-mbt.js`（即 `AppData\Local\FIST-Mbt\fist-mbt.js`），开发版 `_build/cli.js` 不参与实际调用。

### 8.2 同步流程（每档完成后必须执行，收口时全部执行）

| 步骤 | 操作 | 证据 |
|---|---|---|
| 1 | 开发版构建：`moon build --target js`，产出 `_build/cli.js` | 构建输出无 error |
| 2 | 全量测试 + 守卫：`moon test --target js`、三守卫 PASS | 汇总行 + PASS 输出存档 |
| 3 | 备份发布版：复制 `fist-mbt.js` → `fist-mbt.js.bak-<日期>` | 备份文件存在 |
| 4 | 同步发布版：将 `_build/cli.js` 覆盖到 `AppData\Local\FIST-Mbt\fist-mbt.js` | 覆盖后 `Get-FileHash` 与 `_build/cli.js` 一致 |
| 5 | 重启引用该命令的服务 / 定时任务，确认无残留旧进程 | 进程列表无旧 PID |
| 6 | 用发布版复跑 §9 评审演示全部步骤 | 演示输出与开发版一致 |
| 7 | 公网 Release（如有）：打 tag `v0.3.9` 并上传对应构建产物 | Release 页面 tag + 产物链接 |

### 8.3 同步证据

- 哈希对比：`Get-FileHash _build/cli.js` 与 `Get-FileHash AppData\Local\FIST-Mbt\fist-mbt.js` 输出一致（两份存档）。
- 版本戳：发布版 `fist-mbt.js` 内嵌 `VERSION = "0.3.9"`，发布版 `fist --version` 输出 `0.3.9`。
- git：收口提交 `chore(release): v0.3.9 sync publish build` + tag `v0.3.9`。
- 定时任务：本计划涉及的废调度由用户在定时任务列表清理，同步完成后 Agent 确认清理，避免旧版定时触发误报。

---

## 9. 评审演示场景（一键复现 bugfind 双轨闭环）

> 目标：评审在 Windows x64 环境、FIST-Mbt 仓库根目录，按下面顺序执行即可完整复现"内建规则 + OCR review"双轨闭环，全部基于**发布版** `fist-mbt.js` 的真实行为。

### 9.1 前置（评审机准备）

1. `git -C E:\workspace\AI\FIST-Mbt checkout v0.3.9`（或评审分支）。
2. 确认 OCR 二进制可探测：设 `FIST_OCR_BIN` 指向 ocr-local 的 `opencode review.exe`；或保持 `E:\workspace\AI\ocr-local` 目录结构不变走 glob 探测。
3. 确认发布版已同步（§8）：`fist --version` 输出 `0.3.9`。

### 9.2 演示步骤与预期输出

| 步骤 | 命令 / 调用 | 预期输出 |
|---|---|---|
| 1 测试全绿 | `moon test --target js` | 汇总行 `... passed, 0 failed`（含 issue_scan 与外部规则白盒用例） |
| 2 规则数达标 | `issue_scan(dir="src")` | `by_rule` 键数 ≥ 20，JSON 含新增规则 id（如 `moonbit-race-condition` / `moonbit-resource-leak`） |
| 3 dry_run 面 | `ocr_scan(project_dir=".", subcmd="files", dry_run=true)` | `{ok:true, stdout:"", exit_code:0, args:["opencode","review.exe","files",...]}` |
| 4 真实文件列表 | `ocr_scan(project_dir=".", subcmd="files")` | `ok:true`，stdout 为 FIST-Mbt `src/` 下 `.mbt` 文件列表 |
| 5 OCR review 扫描 | `ocr_scan(project_dir="src", subcmd="scan")` | 输出 OCR 对 FIST-Mbt 自身源码的 review findings（含规则 id / 文件 / 行号） |
| 6 双轨闭环回执 | bugfind 模式跑一轮（模板第二步+第三步） | 回执含 `require_ocr: satisfied, ocr_available=true`，issue_scan 内建命中 + OCR findings 双轨汇总 |
| 7 降级面 | 临时移除 OCR 二进制后跑 bugfind | 回执含 `ocr_available=false`，仅 issue_scan 单轨，**不报错不崩溃** |
| 8 守卫三连 | `check_doc_surface` / `check_tools_sync` / `check_plugin_sync` | 三个 PASS |
| 9 四态无 diff | README / AGENTS.md / CLI-help / `gen_plugins.py` 重投影 | `git diff --exit-code` 为空 |
| 10 git 证据 | `git log --oneline -n 10` | 可见 `feat(issue_scan)` / `feat(ocr_scan)` / `chore(release): v0.3.9` 等提交 |

### 9.3 预期输出示例（供评审对照）

```json
// 步骤 4 示例（节选）
{ "ok": true, "exit_code": 0, "stdout": "src/server/issue_scan.mbt\nsrc/server/ocr_scan.mbt\nsrc/server/boundary_probe.mbt\n..." }
```

```json
// 步骤 5 示例（节选）
{ "ok": true, "findings": [
  { "rule": "moonbit-race-condition", "file": "src/server/xxx.mbt", "line": 42 },
  { "rule": "moonbit-resource-leak", "file": "src/server/yyy.mbt", "line": 87 }
] }
```

```text
// 步骤 6 示例（节选）
bugfind 双轨闭环：
- issue_scan 内建命中：N 条（by_rule >= 20）
- ocr_scan OCR review：M 条（LLM 级语义审查）
- require_ocr: satisfied | ocr_available: true
```

> 注：步骤 5-6 的具体命中数取决于 OCR 模型输出，属可复现的"流程输出"而非固定值；评审只需确认**流程闭环**与**字段存在**。

---

## 10. 执行节奏

| 时间 | 工作包 | 收口要求 |
|---|---|---|
| 立即（2026-10-13 起） | **档 1 + 档 2 合并任务包**（规则融合 + rules_file 解析，零外部依赖最稳） | 测试全绿 + 守卫 PASS + 四态同步 + §8 发布即同步 |
| 本周（2026-10-19 前） | **档 3**（OCR CLI 集成 + `ocr_scan` 工具 + require_ocr 预检） | 双轨演示可复现 + 降级安全 + 四态同步 + 发布同步 |
| 视时间 | **档 4**（boundary_probe，stretch goal） | 若档 3 提前完成则启动；时间不足则明确标记"未实施"，**不得虚报**（§0.1 纪律 #2） |
| 并行 | **6 项验收失败修复**（物理多租户隔离 / 自动修复三轮 / Executor 白名单 / native serve-demo / DAG 成环 / Omega 门） | 与本计划并行推进，互不阻塞；均以证据链收口 |
| 收口 | **统一发布 v0.3.9**（2026-10-19 前） | 全部交付物同步发布版 + 四态无 diff + §9 演示复跑通过 + tag `v0.3.9` + Release 产物（如需） |

> 若档 4 无法按期完成：验收总表对应行明确标注"未实施（stretch goal）"，并在演示中说明，**严禁**以占位/预留接口充数——这正是 §0.1 承诺纪律 #2 禁止的行为。
