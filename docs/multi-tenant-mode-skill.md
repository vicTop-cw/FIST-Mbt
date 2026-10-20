# SKILL: multi-tenant-mode — 多租户命名空间（store_*）+ 自驱七模式（mode_*）

> 形态：skill（本文档，一源四态第三态）｜MCP 工具 `store_open` / `store_list` / `store_close` + `mode_list` / `mode_templates`
> 真源：`src/store/multi_store.mbt`（namespace 路由 + `data_dir_ok` / `safe_ns`，BUG-78）
> + `src/ops/ops_modes.mbt`（`all_modes` 7 模式注册表 + `mode_template_path`）
> + `src/server/server.mbt`（五个工具的 MCP 注册与参数 schema）
> 用途：给"多 agent 并发"与"自驱选模式"各一个**确定性抓手**——前者用独立 ns 把任务/状态/库
> 物理隔离，互不串用、不污染仓库根；后者让"用哪个开发模式"成为可复现的选择，而不是 agent 拍脑袋。

## 何时用

### 多租户（store_open / store_list / store_close）

- **多 agent 并发编辑同一项目**：每个 agent 一个独立 ns，各自的库 `{data_dir}/{ns}.db` 物理隔离，
  任务行、心跳、执行账本互不串用——并发冲突预防靠"各写各的库"，不靠抢锁。
- **临时验证 / 冒烟 / 演练**：`scratch=true` 让库落到 `temp/`（gitignore 临时区），跑完即弃，
  不污染仓库根的 `fist-mbt.db`，也不会把演示行提交进 git。
- **收尾清点**：`store_list` 看一眼当前开了哪些 ns 及任务数；`store_close` 关掉不再用的 ns
  （只关句柄，**不删**物理库文件）。

### 自驱七模式（mode_list / mode_templates）

- **AI 选模式**：接到"继续开发 / 打磨 / 验证 / 寻虫 / 修复合并 / 清整 / 探索"这类自驱任务，
  先 `mode_list` 拿到 7 种模式的完整信息（含 constraints 门禁键与 forbidden_tools），按场景挑一个。
- **开工前预检模板**：`mode_templates` 检查 `templates/pipeline_mode_*.md` 是否齐备
  （`missing` 非空就别开跑——模板缺席会让流水线 meta-prompt 拿不到正文）。

## 怎么调

> 参数名 = schema 真名，不是杜撰。

### A. 多租户 store_open / store_list / store_close

**`store_open` 三态参数**（`schema` 真名；必填列只有一个 `namespace`）：

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `namespace` | ✅ | — | 命名空间名；只允许字母/数字/`_`/`-`，拒分隔符与穿越（`safe_ns` 消毒） |
| `data_dir` | — | `.`（当前目录） | 库文件根目录；**只接受相对 server 进程 cwd 的相对路径**，库落 `{data_dir}/{ns}.db` |
| `scratch` | — | `false` | 临时 ns 开关：`true` 时**强制 `data_dir=temp/`**（gitignore），避免仓库根堆 `.db` |

```
tools/call store_open
  { "namespace": "ns-probe", "data_dir": "temp", "scratch": false }

// 返回（口径 {namespace, opened, data_dir, path}，path = {data_dir}/{ns}.db）
{ "namespace": "ns-probe", "opened": true, "data_dir": "temp", "path": "temp/ns-probe.db" }
```

```
tools/call store_open
  { "namespace": "scratch-verify", "scratch": true }        // scratch 覆盖 data_dir

// 返回
{ "namespace": "scratch-verify", "opened": true, "data_dir": "temp", "path": "temp/scratch-verify.db" }
```

```
tools/call store_list                                   // 无参数
// 返回
{ "active_namespaces": ["default", "ns-probe"], "stats": { ... } }

tools/call store_close
  { "namespace": "ns-probe" }                            // 只关句柄，不删物理库
// 返回
{ "namespace": "ns-probe", "closed": true, "active_namespaces": ["default"] }
```

失败原因**分列**：非法 ns 与非法 data_dir 各自独立报错，不合并成一句"打开失败"——
否则调用方不知道该改哪个参数（本仓对拒绝文案的一贯要求：自带出路）。

### B. 自驱七模式 mode_list / mode_templates

两个都是**无参数**（`schema({}, [])`），纯计算只读。

```
tools/call mode_list
// 返回 7 元素数组，每项 = { mode, name, description, constraints, template_path, forbidden_tools }
```

| `mode` | `name`（展示名） | constraints 门禁键 | `forbidden_tools` |
|---|---|---|---|
| `advance` | 持续开发新功能 | 无强制门禁键（默认模式） | — |
| `polish` | 打磨完善（不加新功能） | `forbid_new_features` | `publish` / `publish_parallel` / `dag_publish` |
| `verify` | API 枚举与完备性验证 | `require_api_enum` + `require_doc_check` | — |
| `bugfind` | 寻虫：issue_scan + 边界语料 | `require_issue_scan` + `require_test_corpus` + `require_ocr` | — |
| `fix_and_merge` | 修复 issues + 合并分支 | `require_github_token` | — |
| `tidy` | 项目打扫清整 | `forbid_new_code` | `publish` / `publish_parallel` / `dag_publish` |
| `explore` | 探索：按复杂度自选模式 | `require_complexity_scoring` + `allow_parallel_modes` + `require_disjoint_files` | —（selector，非 worker） |

> `template_path` 统一为 `templates/pipeline_mode_<mode>.md`；`mode_templates` 的名单从
> `all_modes()` 反解、**不硬编码**（注册表加模式而这里漏检查就是"模板缺席没人报"，BUG-118 同族）。

```
tools/call mode_templates
// 返回
{ "templates": { "advance": true, "polish": true, "verify": true, "bugfind": true,
                 "fix_and_merge": true, "tidy": true, "explore": true }, "missing": [] }
```

## 已知边界

- **`data_dir` 只认相对路径（BUG-78）**：必须相对 **server 进程 cwd**，`data_dir_ok` 拒绝
  空串、`..`（`../outside`、`temp/../../outside`）、前导分隔符（`/etc`、`\server` 的 UNC 形态）、
  盘符（`C:/evil`）。两条出路：① 传相对目录（如 `temp/ns-probe`）；② 直接 `scratch=true` 落 `temp/`。
  历史上 data_dir 原样拼接、指到哪就往哪建库，"命名空间物理隔离"形同虚设——这正是 BUG-78 修的形状。
- **`store_close` 不删物理库**：只关句柄，`{data_dir}/{ns}.db` 文件留在磁盘上；要清库得手动删文件。
- **`scratch=true` 覆盖 `data_dir`**：两者同传时以 scratch 为准（强制 `temp/`），不会用你给的 data_dir。
- **`mode_list` 是 7 模式全集且无参数**：加模式要改 `all_modes()` 注册表，`mode_templates` 会跟着
  反解检查，漏检查就是 BUG-118 同族（判据看不见样本就等于没判）。
- **`explore` 是唯一不亲自开发的模式**：它是 selector——先给目标复杂度打分（0..5，复用难度单一抽取来源），
  再从其余 6 个单模式里**自选**一个去跑。
- **并行多模式的硬前提 = 文件作用域两两不相交**：只有每个候选模式都申报了**非空**文件作用域、
  且作用域两两不相交（`reserve_scope` 预订成功 + 认领前 `conflicts_check` 可认领）才允许并行，
  否则**退回单模式串行**；申报空作用域或作用域重叠都直接退回串行。

## 多租户+自驱协同

> 独立 ns + worktree 隔离完整流程。

> 一句话：**store 层 ns 隔离 = 数据/状态隔离；git 层 worktree 隔离 = 文件/代码隔离**。
> 两者叠加，多 agent 并发各写各的库 + 各改各的文件，互不踩。

```
① 开独立 ns（每 agent 一份）
   store_open { "namespace": "<agent>", "scratch": false }     // 或 scratch=true 落 temp/
   → 引擎按 ns 路由到独立库 {data_dir}/{agent}.db（M5 库级物理隔离）；""/default 走模块级默认库

② 文件作用域两两不相交
   每个 agent 在自己的 git worktree（如 temp/wt-skill）里改文件；
   要并行多模式时：reserve_scope 预订 + conflicts_check 查重，重叠即退回串行

③ 选模式
   mode_list → 挑模式；explore 先打分再自选
   mode_templates → 预检模板齐备（missing 为空才开跑）

④ 自驱闭环（全部落在该 agent 的独立 ns 里跑）
   selfdrive_init（独立 ns）→ selfdrive_append 追加审视上下文
   → selfdrive_review_tick / selfdrive_review_ready（报告先行）
   → selfdrive_publish_next 发根任务 → selfdrive_pick_next 按能力认领
   → 执行 / 验收（叶子全绿后父任务自动 roll 到待验收，直接 verify，勿再 claim）

⑤ 收尾
   store_close { "namespace": "<agent>" }   // 关句柄（不删库）
   临时演练的 scratch ns 直接弃用，temp/ 不入库
```

**为什么这样协同**：ns 隔离保证"任务行/心跳/执行账本"各归各库，agent 之间读不到对方在改的任务；
worktree 隔离保证"代码文件"各归各 checkout，文件作用域不相交时 `conflicts_check` 才放行并行。
缺任何一层，并发就会在数据面或文件面上撞车。
