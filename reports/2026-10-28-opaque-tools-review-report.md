# `opaque` 工具人工复核 —— 判据的盲区（Lane DB）

> 司令-γ · 2026-10-28 · **只读 + 修判据**（未改 `src/`）
> **结论先行：复核过程中发现「opaque 有 30 个」本身就是判据的缺陷** ——
> 修掉 2 个真 bug 后 opaque 降到 **4 个**，且**这 4 个全部干净、0 个死参数**。

---

## 结论

| 项 | 结果 |
|---|---|
| **Lead 说的 13 个** | 实测是 **30 个** —— 该读数来自判据的**缺陷**，不是真盲区 |
| **修判据后** | opaque **30 → 4** |
| **4 个的三分类** | **干净 4 · 真死 0 · 判不了 0** |
| **是否 `report_bug`** | **否** —— 没有真死参数 |

---

## 证据

### §1 判例-32 标定：先确认复核方法能识别「干净」

拿**已知干净**的 `cost_budget_check` 做正向标定：
```
handler（server.mbt:6712）→ @engine.budget_check_json(args)
engine 侧（src/engine/cost_tool.mbt:68/72）：
  let limit   = match jget(args, "limit")   { ... }
  let current = match jget(args, "current") { ... }
```
⇒ **方法可用**（能顺着 handler → helper → 消费点找到读点）。

### §2 ★ 判据的两个真 bug（这是本单主要发现）

**Bug ①：`*_args` 变量名被误判成透传**
```moonbit
run_check_external("git", git_args, project_dir, timeout_ms)
//                       ^^^^^^^^ 以 args 结尾
```
`OPAQUE_RX` 的 `\(\s*args\s*,` **从 `git_args` 里的 `args` 处命中** ⇒
`wt_create` / `wt_destroy` 等一批用 `*_args` 变量的工具被误判 opaque。
**修法**：`(?<![A-Za-z0-9_])args(?![A-Za-z0-9_])` —— 完整标识符边界。

**Bug ②：callee 名被窗口截断**
```moonbit
let detach = get_bool(args, "detach", default=false)
//           ^^^^^^^^ 旧实现从 m.start() 往前截 60 字符，恰好切成 "_bool"
```
`_bool` 不在 `READER_CACHE` ⇒ 仍判 opaque（**凡是读参数的 handler 全被判 opaque**）。
**修法**：**整段匹配**「`<ident>[.ident]*(` + `args`」三元组，`group(1)` 直接是完整 callee，
不依赖任何字符窗口。

**⇒ 修前 30 个 opaque，修后 4 个；selftest 14/14 不变。**

### §3 剩下 4 个的逐一复核（每个都给消费点）

| 工具 | schema 参数 | 消费点（handler → helper） | 结论 |
|---|---|---|---|
| `hat_run` | `config_json`, `round` | `hat_run_impl`：`:106` `get_str(args,"config_json")`、`:115` `get_int(args,"round")` | **干净** |
| `hat_merge` | `config_json`, `reports_json`, `round`, `topic` | `hat_merge_impl`：`:138` `get_str(args,"topic")`、`:142` `get_str(args,"reports_json")`、`:155` `parse_optional_config(args,topic)` → 其 `:352` 读 `config_json`、`:159` `get_int(args,"round")` | **干净** |
| `hat_debate` | `issue`, `left`, `right`, `rounds` | `hat_debate_impl`：`:177` `left`、`:178` `right`、`:190` `rounds`、`:194` `issue` | **干净** |
| `cost_budget_check` | `current`, `limit` | `@engine.budget_check_json(args)` → `cost_tool.mbt:68/72` `jget` 各读一个 | **干净** |

**⇒ 4/4 干净，0 死参数。**这 4 个**仍然是** opaque 是因为它们**整包透传 `args`**
（`hat_*_impl(args)` / `@engine.budget_check_json(args)`）——
判据按设计在透传处**主动弃权**，这是对的：静态判据看不到别的包/函数的内部。

### §4 复核过程中我自己的两次误判（诚实记录）

| 轮次 | 方法 | 误判 | 原因 |
|---|---|---|---|
| v1 | 只跟进 **1 层** helper | `hat_merge.config_json`、`execute.agent` 判死 | `parse_optional_config` / `execute_write_identity` 是**第 2 层** |
| v2 | **递归 3 层**不加限制 | 「30 个全干净」 | 作用域膨胀 **212 倍**（`plan` 的 1514 字符 → 321209）⇒ **把整个文件吃进来 ⇒ 恒绿** |
| v3 | 只跟进「真的把 args 传进去」的函数 + 膨胀上限 20x | 正确 | ✅ |

**v2 的假绿是被反向标定戳穿的**：拿**已人工确认的** `plan.challenge`（BUG-472 修复前）去测，
v2 判它「活」⇒ 说明 v2 不可信。**⇒ 没有反向标定的判据，绿了也不能信。**

---

## 分析：为什么这 4 个会 opaque —— 以及判据还能不能改进

**它们 opaque 的原因是「整包透传」，而这正是判据**应该**弃权的地方**：

| 透传目标 | 判据看得见吗 |
|---|---|
| 同文件函数（`hat_run_impl`） | **理论上可以**（跟进定义体）—— 已由 v3 的调研覆盖 |
| **跨包函数**（`@engine.budget_check_json`） | **看不见** —— 判据只扫 `src/server/` |

**⇒ 判据能改进的地方是「同文件/同包的透传跟进」，不能改进的是「跨包」** ——
跨包需要解析 `@pkg.fn` 的包内定义，那是编译器级的信息，静态正则做不到。

**这就是为什么 `opaque` 必须存在**：不是判据偷懒，是**有些地方静态判据结构上就到不了**。

### 一个判据的诚实度阶梯

| 级别 | 形态 | 本判据 |
|---|---|---|
| 1 | 能判出东西 | ✅ |
| 2 | 判出的**都是真的** | ✅ 14 格 selftest 含 5 个变异对照 |
| 3 | **知道自己哪里判不了并说出来** | ✅ `opaque` 主动弃权 |
| 4 | **说出来的「判不了」本身也是准的** | ✅ 本单：opaque 30→4，剩下 4 个**逐一复核确认干净** |

**上一轮做到第 3 级；本单做到第 4 级 —— 「opaque 列表」本身不再虚高。**

---

## 缺口与风险

- **R1** `opaque` 的 4 个**仍看不见**（整包透传给跨包/大 helper）⇒ `rc=0` 只能说「看得见的都干净」
- **R2** 本单**未测**「跨包消费点**是否真的存在**」的自动化 —— 4 个是我**人工**核实；
  若将来 opaque 数量增长，人工复核会不够
- **R3** `moon test` 未跑（本单只改 `.py` 判据 + 只读核实，不涉及 `.mbt`）；
  判据改动已过 `--selftest 14/14`
- **R4** 判据的两处修复**尚未进电池回归**（`run_guards.py` 的 `expected(..., 1)` 仍按旧的
  「3 处死参数」登记 —— 现读数仍是 0 死参数 / 2 设计如此，**需确认电池格是否已转绿**）

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-opaque-tools-review-report.md` |
| 判据修复 | `scripts/check_dead_params.py`（`OPAQUE_RX` 边界 + `is_opaque` 整段匹配） |
| 复核脚本 | `temp/audit/lane_db_{opaque,opaque_v2,opaque_v3,calibrate}.py` |
| **该记** | §4 的两次误判经验应并入判据 docstring：**递归必须有膨胀上限，且必须反向标定** |
