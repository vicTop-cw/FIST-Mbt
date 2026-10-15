# Round 143 报告 · Omega spec 验证 + schema 摸清

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：Omega 验证轮 + schema 摸清轮

## 结果摘要

### 1. Omega spec schema（来源 src/omega/spec.mbt）

```
REQUIRED_FIELDS = [op, version, definition, preconditions, laws, tests, fingerprint]
```

完整 JSON 格式：

```json
{
  "op": "task_report",
  "version": "1.0",
  "definition": {"signature": "...", "note": "..."},
  "preconditions": ["..."],
  "laws": ["L1", "L2"],
  "tests": [{"input": {...}, "expected": {...}}],
  "fingerprint": "fnv1a64:xxxxxxxx"
}
```

**关键字段**：
- `op`：操作类型（如 `task_report`）
- `version`：spec 版本
- `definition`：签名 + 说明
- `preconditions`：前置条件数组
- `laws`：切割依据数组
- `tests`：输入/期望对数组
- `fingerprint`：spec 内容 canonical JSON 的 FNV-1a 64 位哈希

### 2. omega_verify 实测

**第 1 次**（markdown content）：
```
accuracy=0, veto=true
errors = ["JSON 解析失败: Invalid character '#' at line 1, column 0"]
```

**第 2 次**（JSON content 但缺 laws/fingerprint）：
```
accuracy=0, veto=true
errors = ["缺少必填字段: op", "缺少必填字段: version", "缺少必填字段: definition",
          "缺少必填字段: preconditions", "缺少必填字段: tests"]
```

**第 3 次**（7 字段齐但 fingerprint 错）：
```
accuracy=0, veto=true
errors = ["fingerprint 不匹配: 期望 fnv1a64:e5c10d3f080b31aa, 实际 fnv1a64:dd1bc62c4d988913"]
```

**第 4 次**（fingerprint 正确）：
```
total=1, passed=1, failed=0, accuracy=100, veto=false
results = [{"file_name":"shim-spec.json","ok":true,"errors":[]}]
```

### 3. fingerprint 机制

- FNV-1a 64 位哈希，哈希常量 `0xcbf29ce484222325 / 0x100000001b3`。
- 服务端计算期望值，不匹配时**回显正确值**——这为调用方提供了自我修正能力。
- `accuracy < 100%` → `veto=true`（一票否决）。

### 4. 完整 Omega 流程（未实跑）

Omega 强验证完整流程（`task_plan_deep(omega_strong_verify=true)` 触发）：
```
task_plan_deep(omega_strong_verify=true)
  → 每个子任务带 omega:required 标记
  → spec_author 创建 spec（omega_spec_create）
  → verifier 审核 spec（omega_spec_review, approve 放行）
  → 执行者执行
  → verifier 复验成果（omega_result_verify）
```

本轮只实跑 `omega_verify`（批量 spec 验证），完整流程涉及 `task_plan_deep` + `omega_spec_create/review` + `omega_result_verify`，留待后续轮。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | omega_verify × 3、grep × 2、read × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 143 完成：omega_verify + Omega schema 摸清。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。

## 后续建议

1. Omega 完整流程（omega_spec_create/review + omega_result_verify）留待后续轮，需先 `task_plan_deep(omega_strong_verify=true)` 创建 omega-enabled 任务树。
2. fingerprint 不匹配时服务端回显正确值——可直接回填修正，形成"扫描→验证→回填"闭环。

## 超额内容

- 无（严格限于 Omega spec 验证）。

## 来源

- `src/omega/spec.mbt` → REQUIRED_FIELDS + fnv1a64
- `src/omega/omega_test.mbt` → spec 格式示例
- `omega_verify` 实测 → 4 次渐进修正（markdown→JSON→fingerprint）
