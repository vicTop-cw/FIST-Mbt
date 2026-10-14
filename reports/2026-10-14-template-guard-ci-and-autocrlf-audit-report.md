# 2026-10-14 · 模板判据收口：字节级守卫 autocrlf 审计 + check_template_ctrl 接入 CI（Round 107）

## 结果摘要

**一句话**：把上轮报告的两条遗留建议（#2 判据接 CI、#3 核查其它字节级判据的 autocrlf 假阳性）
**全部落地**——审计确认 `check_ps_encoding` 等字节级判据**免疫** autocrlf 陷阱（只有模板判据有、已修），
并把 `check_template_ctrl` **接入 CI**，闭环。全守卫链 PASS。

## 核心认知

**字节级判据的 autocrlf 免疫判据**：判据的**谓词是否依赖行尾**。
- `check_template_ctrl`（**曾经有陷阱**）：谓词是"字节里不得含 CR"——**依赖行尾**，CRLF 被当裸 CR ⇒ 假阳性。
  已改为"只判裸 CR"（后接 LF 的 `\r` 容忍）+ `.gitattributes text eol=lf` 双保险。
- `check_ps_encoding`（**免疫**）：谓词是"带 UTF-8 BOM 或纯 ASCII"——**不依赖行尾**（CR=0x0d<0x7F，
  纯 ASCII 加 CRLF 仍纯 ASCII）。模拟验证：纯 ASCII LF 和纯 ASCII CRLF 都合规，只有真无 BOM 中文才红。

**结论**：只有依赖行尾谓词的字节级判据才受 autocrlf 污染。审计全仓 `read_bytes`/`rb` 扫描的判据，
仅 `check_plugin_sync` 用字节比较但那是"一源四态逐字节 diff"（本就该字节相等，CRLF 注入是同步缺陷不是噪声）。

## 交付

### ① CI 接入 `check_template_ctrl`
`.github/workflows/ci.yml` 新增一步（插在 PowerShell 编码守卫后、Py-stdout 前，字节级守卫聚堆）：
```yaml
- name: Template control-char guard (templates/*.md 禁裸控制字符——裸 CR 会吃掉工具名首字母)
  shell: bash
  run: |
    python3 scripts/check_template_ctrl.py --selftest
    python3 scripts/check_template_ctrl.py
```
沿用同族模式（先证判据自己会红，再全量）。**为什么现在能挂**：此前故意不挂（普查出 9 份模板含
353 处裸控制字符，挂了必红破坏构建）；现已把真缺陷修归零 + 判据强化，现状全绿。

### ② 审计其它字节级判据
全仓字节级判据只有 `check_template_ctrl`（已修）+ `check_ps_encoding`（免疫）+ `check_plugin_sync`
（本应字节相等）。无其它同类陷阱。

## 验证（金条八：实际运行）

| 项 | 结果 |
|---|---|
| ci.yml YAML 合法性（pyyaml safe_load） | 合法，新步骤被发现 |
| `check_doc_surface`（含 J11/J12 workflow 扫描） | PASS |
| `check_template_ctrl` | PASS（11 份只含 LF/TAB） |
| `check_ps_encoding` | PASS（7 个 .ps1 全合规） |
| `check_scripts_index` | PASS |
| autocrlf 模拟（纯 ASCII LF vs CRLF） | 均 0 违例（不误红） |
| 真违例模拟（无 BOM 中文） | 1 违例（仍能红） |
| `git show HEAD:.github/workflows/ci.yml` | 含 `check_template_ctrl`（HEAD 有、HEAD~1 无） |
| 三端同步 | `4c3b199` |

## 资源消耗

- 2 个提交：`efbeaaa`（CI 接入）+ 本轮报告/memory（待落）
- 0 `.mbt` 改动；ci.yml 新增 1 步（~9 行）
- 1 支审计模拟脚本（`temp/audit_ps.py`）+ 1 支 YAML 校验脚本（`temp/yaml_check.py`）

## 任务分配记录

指挥官亲自：
- 判断**哪些字节级判据值得审计**（用 `read_bytes`/`rb` 特征筛，避免无差别全扫）
- 判定 **ci.yml 是否并发 WIP**（先查干净再动，避免覆盖对方未提交面）
- 选 CI 接线位置（字节级守卫聚堆）+ 写清"为什么现在能挂"的注释（防未来有人看到又摘掉）

## 遗留风险

1. **`moon test` 当前 1041/1042**：`cfg_ofm_2` 败在 `src/router/router_config_wbtest.mbt:27`，
   是并发 agent 未提交 WIP（加 `RouterConfig` 字段未登记投影锁），**未动 `src/router/*`**。
2. **并发 agent 已在我 ci.yml 之上再提交**（`4c3b199` Round 13 memory+report）——本提交被推了上去，
   三端已含双方工作。
3. **CI 尚未实际跑过**：本地 YAML + 守卫验证通过，但没在真实 runner 上验证。建议下次推后看 CI 状态。

## 后续建议

1. **等 CI 跑一次**确认新步骤在 runner 上绿（本地验证 ≠ CI 验证）。
2. **并发 agent 修好 `cfg_ofm_2` 后**全仓 1042/1042，复跑 `moon test` 确认。
3. **模板判据的 CI 闭环**意味着这类"文档即实现"缺陷从此有常驻闸，建议后续把同族判据（如 docs/ 归档面）
   也纳入，防止文档面缺陷复发。

## 超额内容

- **发现了一个可复用的判据设计原则**：字节级判据设计时要问"谓词依赖行尾吗"——依赖则必须容忍 CRLF，
  否则 Windows 开发者本地必红、CI（Linux/LF）却绿，判据变成"只在开发机响的闹钟"。
- **ci.yml 注释写清了"为什么现在能挂"**：防未来有人把这条判据又摘掉（"挂了必红"的记忆会丢失）。

## 来源

- 判据免疫审计：`scripts/check_ps_encoding.py`（BOM/ASCII 谓词，不依赖行尾）
- autocrlf 陷阱修复：`scripts/check_template_ctrl.py`（T1 容忍 CRLF）+ `.gitattributes`
- CI 接入：`.github/workflows/ci.yml`（新步骤，插在 PowerShell 编码守卫后）
- 验证：`git show HEAD:.github/workflows/ci.yml | grep check_template_ctrl` 确认入 HEAD
