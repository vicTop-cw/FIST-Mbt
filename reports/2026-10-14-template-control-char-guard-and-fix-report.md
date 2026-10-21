# 2026-10-14 · 模板「无裸控制字符」判据 + 修复 + autocrlf 假象纠正（Round 103-106）

## 结果摘要

**一句话**：落地上轮报告建议 #1（加判据）**并把它做到底**——不仅加了 `scripts/check_template_ctrl.py`，
还用**真源注册表做权威锚**把模板里被转义序列吃掉的工具名**全部修复归零**（353 → 0），
并在过程中**发现并纠正了一个 autocrlf 假阳性陷阱**，配套钉了 `.gitattributes` 双保险。
全链路 `moon test` + 守卫链 + 干净 checkout 三重验证通过。

**4 个提交**（三端 `3b983f7` 同步）：`ffcf957`（判据）→ `8b1ba7a`（修复模板）→
`4ec2bc6`（gitattributes）→ `3b983f7`（判据 CRLF 强化）。

## 核心认知（本轮最重要的发现）

**353 处裸控制字符分两类，性质完全不同**：

| 类别 | 文件 | 成因 | 性质 |
|---|---|---|---|
| **真缺陷** | 7 份 `pipeline_mode_*.md` | git blob 里确有裸 CR（如 advance blob CR=12），转义序列解释吃掉首字母 | **实质**：工具名错字母，执行者调不到工具 |
| **autocrlf 假象** | `pipeline_meta_prompt.md` / `tool_use_rubric.md` | `git cat-file` 实测 **blob CR=0**，工作树里的 159/53 个 `\r` 是 Windows `core.autocrlf=true` checkout 注入的 CRLF | **假象**：不是提交缺陷 |

**教训**：**判据扫"工作树字节"，会被 checkout 行尾污染**。如果只看工作树不看 blob，
会把 autocrlf 假象当真实缺陷。这提醒所有字节级判据——**先分清"提交面"和"工作树注入面"**。

## 交付

### ① 判据 `scripts/check_template_ctrl.py`
- T1 `templates/**/*.md` 字节里不得含**裸**控制字符（白名单 LF/TAB；**容忍 CRLF**，后接 LF 的 `\r` 跳过）
- T2 一份 .md 都枚举不到 ⇒ FATAL
- `--selftest` **7 格**：干净不误红 / CR 必红 / ESC+VT 必红 / TAB 放行 / **CRLF 容忍** / **裸CR 必红** / 枚举非空 —— 全过
- 只点名不自动修（修复需作者意图知识）

### ② 修复模板（真源锚定，零猜测）
用 `scripts/_tool_registry.py` 真源注册表验证每处修复：`t`+`ask_plan_deep`→`task_plan_deep`（注册工具 ✓）、
`r`+`un_check`→`run_check`（✓）、`b`+`ug_list`→`bug_list`（✓）…… **144 处字母修复全锚定注册工具或确定词**。
`is_boundary` 守卫不误伤词中控制字符、表格缩进。**7 份 pipeline_mode_*.md 修复入 blob**（blob CR→0）。

### ③ `.gitattributes`：`templates/*.md  text eol=lf`
窄范围（只列 templates），从源头钉 checkout 行尾，防 autocrlf 再注入裸 CR 导致判据假阳性。

### ④ 判据 CRLF 强化
发现 autocrlf 假象后，把判据从"见 CR 就红"改为"见**裸** CR 才红"，并加 2 格自检证明宽容不误放。

## 验证（金条八：实际运行）

| 项 | 结果 |
|---|---|
| `moon test --target js` | **1042/1041**（1 败）——败在 `src/router/router_config_wbtest.mbt:27` `cfg_ofm_2`，是并发 agent 未提交 WIP（`src/router/*` 加字段未登记投影锁），与本提交无关 |
| `check_template_ctrl --selftest` | SELFTEST OK（7 格）rc=0 |
| `check_template_ctrl` 全量 | **PASS**（11 份只含 LF/TAB）rc=0 |
| `check_doc_surface` / `check_plugin_sync` / `check_tools_sync` / `check_scripts_index` | 全部 PASS |
| **干净 checkout（`git archive HEAD`）** | 11 份 .md，含裸控制字符 **0 份** —— 修复入 blob |
| 变体测试 | CRLF 合法 0 违例 / 裸 CR 吃字母 ≥2 违例 / CRLF 混裸CR 恰 1 违例 |

## 资源消耗

- 4 个提交：判据(~200行) / 模板修复(7 文件) / gitattributes(9 行) / 判据强化(~20 行 diff)
- 2 份报告：Round 103 判据报告 + 本轮收口报告
- 零 `.mbt` 改动、零 `ci.yml` 改动（模板是 `.md`，不参与编译）

## 任务分配记录

指挥官亲自（不做可委派活，这轮是判断密集型）：
- 普查 → **分清两类缺陷**（真缺陷 vs autocrlf 假象）——这是关键判断
- 用**真源注册表做权威锚**逐处验证修复（144 处零猜测）
- 抵住"一刀切全修"的诱惑（第三次）：`pipeline_meta_prompt.md` 的 159 CR 是 autocrlf 假象，
  **没把它们当错名去"补字母"**（否则会造出 `rread` 这种错词）
- 发现判据会被 autocrlf 污染 → 强化判据 + 配套 `.gitattributes` 双保险

## 遗留风险

1. **`moon test` 当前 1 败**（`cfg_ofm_2`）——并发 agent 在 `src/router/*` 加字段未登记投影锁，
   **未提交未推**，是对方责任。我未越权改 `src/router/*`。
2. **`check_template_ctrl` 仍未挂 CI**：现在对现状必绿（可挂）。建议下一步接入 CI。
3. **同类字节级判据的 autocrlf 陷阱**：其它扫工作树字节的判据（如 `check_ps_encoding`）是否也有此隐患？
   **建议**后续核查。

## 后续建议

1. **把 `check_template_ctrl` 接入 CI**：现在全绿，接上才闭环（之前不接是因为必红）。
2. **核查其它字节级判据的 autocrlf 假阳性**：`check_ps_encoding` 等是否会把 CRLF 当裸 CR 误红。
3. **并发 agent 修好 `cfg_ofm_2` 后**全仓 1042/1042，需复跑 `moon test` 确认。

## 超额内容

- **纠正了一个会长期误导的假阳性**：如果不做 blob 级核查，判据会永远红在 autocrlf 假象上，
  反而掩盖了真正的 7 份错名缺陷。这比"加判据"本身更有价值。
- **第三次抵住"顺手全修"**：把 159 个 autocrlf CR 当"被吃字母"去补 `r` 会造出 `rread` 这种错词。
- **干净 checkout 验证**（`git archive HEAD`）证明修复入 blob，不只改工作树。

## 来源

- 判据实现：`scripts/check_template_ctrl.py`（T1 含 CRLF 容忍 + `--selftest` 7 格）
- 修复脚本：`temp/apply_fix.py`（真源锚定）+ `temp/analyze_fix.py`（144 处验证）
- blob 核查：`git cat-file blob HEAD:templates/<f>` 实测 CR=0（meta_prompt/rubric）vs CR=12（advance）
- 登记：`scripts/README.md`（check_template_ctrl 条目追加追记）
- 验证：干净 checkout `git archive HEAD | tar -x` + 判据扫干净树 = 0 违例
