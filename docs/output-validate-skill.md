# SKILL: output-validate — 交付物硬门验证（报告不是证据，产物才是）

> 形态：skill（本文档）｜MCP 工具 `output_validate`｜CLI `python scripts/output_validate.py <dir> --artifacts <json>`
> 用途：给 agent 一个**确定性验收抓手**——不靠自述、不靠 LLM 自评，到机上查文件实际状态。
> 五层证据梯（L1→L5）中本工具实现 **L4 产物状态层硬门**，是"文档即实现"标准的核心执行器。

## 何时用

- **任务收尾前必跑**：`execute` / `submit` 交付后、`verify` 前，对产物清单做硬门验证。
- **CI 流水线**：`run_check` 之后紧接 `output_validate`，构建+测试都过了不算完，产物落地才算真交付。
- **自证闭环**：任务描述里说"已写 README.md + main.mbt"——跑一下，文件在不在、内容对不对，一眼看全。
- **拒假防御**：L1（agent 报告）→ L2（tool 消息）→ L3（测试通过）都可以被"制造"，L4 必须到文件系统查。

## 怎么调

### MCP 形态（server 内）
```
tools/call output_validate
  {
    "project_dir": ".",
    "artifacts": [
      { "path": "README.md", "contains": "FIST", "min_chars": 50 },
      { "path": "src/main.mbt", "contains": "pub fn main", "not_contains": "panic!" },
      { "check_key": "moon_test" },
      { "check_key": "issue_scan" }
    ],
    "external_results": {
      "moon_test": { "ok": true, "code": 0, "stderr": "" },
      "issue_scan": { "ok": true, "code": 0, "stderr": "" }
    },
    "evidence": "已完成 README + main + moon_test + issue_scan",
    "require_evidence": false
  }
```

返回：
```json
{
  "verdict": "pass",
  "passed": 4,
  "failed": 0,
  "checks": [
    { "artifact": "README.md", "ok": true, "detail": "OK（存在/非空/invariant 全部通过）" },
    { "artifact": "moon_test", "ok": true, "detail": "external ok=true, code=0" }
  ],
  "evidence_layer": "l4-pass",
  "evidence": "已完成 README + main + moon_test + issue_scan"
}
```

- `verdict=pass` 当且仅当所有 artifact 检查通过；任一失败即 `fail`。
- `path` / `check_key` 二选一：`path` 走文件检查，`check_key` 走外部结果字典引用。
- 文件检查：存在 → 非空 → 逐个 invariant（contains/not_contains/min_chars）。
- 路径防御：拒绝空串 / `..` 穿越 / 绝对路径 / 盘符。
- `require_evidence=true` 时强制 `evidence` 非空（防"什么都没说就过了"）。

### CLI 形态（免写 JSON-RPC）
```bash
# 简单：文件 + contains 检查
python scripts/output_validate.py . \
  --artifacts '[{"path":"README.md","contains":"FIST"}]'

# 混合：文件 + 外部结果引用
python scripts/output_validate.py . \
  --artifacts '[{"path":"moon.mod","contains":"vicTop-cw"},{"check_key":"moon_test"}]' \
  --external-results '{"moon_test":{"ok":true,"code":0}}' \
  --evidence "README + moon_test 双过"

# artifacts 放文件里（大清单）
python scripts/output_validate.py . \
  --artifacts artifacts.json \
  --external-results ext_results.json

# 退出码：verdict=pass → 0，fail → 1
```
先 `moon build --target js cmd/main` 保证 main.js 新鲜。

### 三形态关系
- **单真源 = MoonBit 实现**（`src/server/output_validate.mbt`）：MCP 工具直接调它；
  CLI 是薄封装（拉起 server → 调工具 → 打印 JSON），不复制验证逻辑。
- skill（本文档）教 agent 何时用、怎么写 artifacts 清单、怎么解读 fail 并回修。

## Artifact 规范书

### path 型（文件存在性 + invariant）

| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `path` | ✅ | string | 相对路径（拒绝绝对/穿越/盘符） |
| `contains` | ❌ | string | 文件内容必须包含此串 |
| `not_contains` | ❌ | string | 文件内容**禁止**包含此串 |
| `min_chars` | ❌ | int | 文件最少字符数（防空壳文件） |

### check_key 型（外部结果引用）

| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `check_key` | ✅ | string | 在 `external_results` 字典里查这个 key |

`external_results` 里每个值：
```json
{ "ok": true, "code": 0, "stderr": "", "stdout": "" }
```
- `ok=true` **或** `code=0` → 通过。
- `stderr` / `stdout` 可选；失败时会被并入 detail 供诊断。

## 证据梯位置（L4 在哪）

```
L1 示意层（最弱）  agent 报告字符串 —— 默认不信，仅参考
L2 动作层          tool 成功消息 —— 仍可假
L3 测试层          run_check / moon test 退出码 0 —— 比自述强
L4 产物状态层 ✅    output_validate —— 到交付产物实际机上查（本工具）
L5 外部接受层（最强） omega 复验 / 验收方通过 —— 最终门
```

`output_validate` 是 L3→L5 之间**唯一硬门**。L3 过了不代表产物落地；L5 没它也没东西可验。

## 闭环（execute → output_validate → verify）

1. **execute**：交付物记录到 FIST（`scripts/` / `docs/` / 代码文件）。
2. **output_validate**：跑硬门，verdict=pass 才能继续；fail 则根据 checks.detail 回修。
3. **eval_feedback**（可选）：给四段式契约（Defects/Evidence/Fix/Acceptance）进一步收敛。
4. **verify**：验收通过（FIST 生命周期），结果进档案库。

## 已知边界

- **文件检查是字节级**：不解析语法（md/mbt/json），只看存在/非空/invariant。
- **外部结果不执行**：`check_key` 只是引用 `external_results` 字典，不会自己跑 `moon test`。
  调用方先跑 `run_check` / `moon test`，把结果塞进来（enforce 闭环）。
- **无 glob**：不支持 `*.mbt` 批量匹配；每条 artifact 必须是具体路径。
- **路径防御偏严**：`..` / 绝对路径 / 盘符一律拒绝，防路径逃逸注入。
