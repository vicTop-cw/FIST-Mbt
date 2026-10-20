# SKILL: boundary-probe — 边界输入建议生成器（寻虫第四步前置）

> 形态：skill（本文档）｜MCP 工具 `boundary_probe`
> 用途：给 agent 一个「按规则类型构造边界输入」的确定性抓手——纯计算，不 spawn、不跑测试，
> 只把 finding 位置该喂哪些边界输入（空 / 极值 / 负下标 / 并发交错 / 元字符注入 / 路径穿越……）列出来，
> 真正的验证交给 `run_check`。与 `issue_scan` / `ocr_scan` 组成「扫描 → 边界构造 → 真实验证」三段闭环，
> 治弱语料下的 Goodhart 下界（atgc-merge 归因报告机理 1/2：语料只断言"做了没"，执行体就会停在判据边界上）。

## 何时用

- **在 `issue_scan` 扫出 finding 之后、用 `run_check` 真实验证之前**。
  拿到一条 `{ rule, severity, file, line, code }` 后，先调 `boundary_probe` 问"这个位置该喂哪些边界输入"，
  再把返回的 `input` 一条条喂给 `run_check`，能触发 panic / 崩溃的才认定是真缺陷。
- **治弱语料下的 Goodhart 下界**：当语料（验收标准 / 测试集）只覆盖了"正常路径"、对边界没有断言时，
  执行体会理性地停在判据边界上——"验收没写就不做"。`boundary_probe` 把"该试哪些边界"显式列出来，
  逼着验证者去戳这些语料没覆盖的域，把下界抬起来。
- **bugfind 模式第四步的前置能力**：`issue_scan`（第一步扫描）→ 逐条判真伪 → `boundary_probe`（构造边界输入）
  → `run_check`（真实验证）→ 真缺陷喂 `report_bug`。本工具是这一步与真实验证之间的桥。
- **不该用的时候**：你只是想知道"这段代码有没有高危模式"——那是 `issue_scan` / `ocr_scan` 的活；
  你已经知道具体输入、想直接跑——那是 `run_check` 的活。`boundary_probe` 只负责"给我列边界输入建议"。

## 怎么调

### MCP 形态（server 内）
```
tools/call boundary_probe
  { "rule": "divide-by-zero", "code": "x / y", "line": "42", "file": "src/a.mbt" }
```
- **参数名与注册集逐字对齐**：`rule` / `code` / `line` / `file`。
- `rule`（**必填**）：规则 id 或关键词。按子串匹配路由到对应规则族，
  如 `divide-by-zero` / `string-index` / `array-index` / `substring` / `unsafe-unwrap` /
  `unsafe_get` / `empty-match` / `match-non-exhaustive` / `potential-overflow` / `secs-overflow` /
  `race-condition` / `json-injection` / `path-traversal` / `float-equal` / `resource-leak` / `async_main` 等；
  未命中任何规则族时落到通用边界（空 / 极值 / 非法）三件套。
- `code`（**必填**）：代码片段（finding 命中的那行 / 那段）。
- `line`（可选）：行号字符串。
- `file`（可选）：文件路径。
- `rule` 或 `code` 为空时直接回 `{ ok: false, error: "rule 与 code 均为必填" }`，不落任何建议。

### 返回结构
```
{
  "rule": "divide-by-zero",
  "file": "src/a.mbt",
  "line": "42",
  "code": "x / y",
  "suggestions": [
    { "kind": "divisor-zero",     "input": "y = 0",      "note": "除数置 0，验证除零保护",   "confirmed": false },
    { "kind": "divisor-extreme",  "input": "y = 1e308",  "note": "除数取极大值，验证溢出/精度路径", "confirmed": false },
    { "kind": "divisor-negative", "input": "y = -1",     "note": "负除数，验证符号处理",       "confirmed": false }
  ],
  "total": 3,
  "confirmed_count": 0,
  "note": "纯计算建议，不执行。调用方（bugfind 第四步）把 input 喂给 run_check，触发 panic/崩溃的再回写 confirmed=true"
}
```
- `suggestions[]` 每项：`{ kind, input, note, confirmed:false }`——
  `kind` 是边界类别标签，`input` 是可直接喂给 `run_check` 的边界输入，`note` 说明该输入验证什么，
  `confirmed` **恒为 `false`**（本工具不执行，验证权在调用方）。
- `total` = `suggestions` 条数；`confirmed_count` 初始恒 `0`（由调用方喂 `run_check` 后才可能上升，本工具不改它）。
- 同一 `rule` 返回同一族建议（确定性、零依赖）；不同 `rule` 返回不同族——
  除零族 3 条、下标族 4 条、并发族 3 条、JSON 注入族 3 条、未知名落通用族 3 条，依此类推。

## 已知边界

- **纯计算，不 spawn、不跑测试、不碰文件、不写库**：零副作用、零依赖，只按 `rule` 字符串做路由 + 拼建议数组。
  所以它**判不了真伪**——它只列"该试什么"，试没试出 panic 是 `run_check` 的事。
- **`confirmed` 默认 `false`，需调用方喂 `run_check` 触发 panic 才回写 `true`**：
  本函数产出时 `confirmed` 恒为 `false`、`confirmed_count` 恒为 `0`；
  调用方把 `input` 喂给 `run_check`，能触发 panic / 崩溃的那条才在后续流程里被标 `confirmed=true`。
  不要指望本工具自己把 `confirmed` 翻成 `true`——它不执行。
- **按 `rule` 子串路由，未知名落通用族**：规则族靠 `rule.contains(...)` 命中，
  名字对不上就落到"空 / 极值 / 非法"通用三件套（不会报错、但建议更泛）。
- **三段闭环中的定位**：`issue_scan` / `ocr_scan` 负责"扫出 finding"（有哪些位置可疑），
  `boundary_probe` 负责"构造边界输入"（这个位置该喂什么），`run_check` 负责"真实验证"（喂进去到底崩不崩）。
  三者各管一段，缺一段闭环就断——只扫不构边界、只构边界不真跑，都会漏掉弱语料藏起来的缺陷。
- **只产出建议，不做判定**：命中一条边界输入 ≠ 发现一个缺陷；是否缺陷以 `run_check` 的实际结果为准。

## 闭环示例（issue_scan → boundary_probe → run_check → confirmed=true）

1. **扫**：`issue_scan` 扫 `src`，命中一条 finding
   ```
   { "rule": "divide-by-zero", "severity": "high", "file": "src/a.mbt", "line": "42", "code": "x / y" }
   ```
2. **构**：把这条 finding 的 `rule/code/line/file` 原样喂 `boundary_probe`
   ```
   tools/call boundary_probe
     { "rule": "divide-by-zero", "code": "x / y", "line": "42", "file": "src/a.mbt" }
   ```
   返回 `suggestions[]`（divisor-zero / divisor-extreme / divisor-negative 三条，均 `confirmed:false`）。
3. **验**：调用方把每条 `input`（如 `y = 0`）拼进对应调用路径喂 `run_check`：
   - `y = 0` → `run_check` 触发 panic / 崩溃 → 这条标 **`confirmed=true`**（真缺陷坐实）；
   - `y = 1e308` → 不崩（精度路径安全）→ 保持 `confirmed=false`。
4. **报**：把 `confirmed=true` 的边界缺陷喂 `report_bug`（`publish_task=true` 自动发布修复根任务），
   进入「扫描→上报→修复」闭环；`confirmed=false` 的记为已探明安全的边界，防下次重探。

> 一句话：`issue_scan` 告诉我"哪可疑"，`boundary_probe` 告诉我"该喂什么"，
> `run_check` 告诉我"喂进去崩没崩"——三者串起来，弱语料藏不住的边界缺陷才浮得上来。
