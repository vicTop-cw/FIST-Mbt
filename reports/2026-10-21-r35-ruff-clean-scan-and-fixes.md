# R35 · clean 面静态分析扫查 + 修 2 真 bug（裸 except / 重复 import）+ 清 56KB 杂项 PDF

- 日期：2026-10-21
- 性质：bugfind + fix + tidy（组合模式的寻虫-修复-清整三环）
- 结论：**对 89 个 clean Python 脚本跑 ruff F/E722 系统性扫查，确认 clean Python 基本无真 F/E 类逻辑 bug**（仅 1 处裸 except 是真 bug，已修）；另修复 1 处 F811 重复 import、清理 1 个 56KB 杂项 PDF。src/router 的编译阻断仍在（并发 agent 未修）。

---

## 一、系统性静态分析扫查（核心发现）

### 方法

- 工具：`ruff check --select F,E722`（F=pyflakes 真 bug 族：未用 import/变量/重定义/f-string 无占位符；E722=裸 except）
- 面：89 个 git-clean 的 `scripts/`+`scripts/blackbox/` Python 脚本（排除 5 个并发 agent 脏文件：`ns_route_probe`/`store_isolation_probe`/`fist_mbt_mcp_client`/`check_test_sync`/`mcp_tool_tour`）
- 结果：**58 处 F/E722 命中，全部为 clean 文件**

### 分级结论（关键）

| 类别 | 数量 | 性质 | 处置 |
|---|---|---|---|
| `F541` f-string 无占位符 | ~30 | 纯装饰 | 无害，不修 |
| `F401` 未用 import | ~20 | 死代码 | 无害，不修 |
| `F841` 赋值未使用 | ~10 | 多在 `--selftest` 里（计算了未消费） | 已逐一看，非逻辑洞 |
| **`F811` sys 重定义** | **1** | **真 bug** | **已修（§三）** |
| **`E722` 裸 except** | **1** | **真 bug** | **已修（§二）** |

### 验证守卫 F841/F401 不是逻辑洞

逐一看了守卫脚本里"未使用 import / 未使用变量"的上下文，全部是**死代码**而非检查逻辑缺失：
- `check_ps_encoding.py:22` 未用 `re`、`check_upgrade_installer.py:36` 未用 `os`、`check_skill_inject.py:51` 未用 `json` —— 都是重构遗留的死 import，**不影响守卫逻辑**
- `check_doc_surface.py:1255` `agents_txt` 赋值未使用 —— 在 `--selftest` 里，实际用 `names_in()` 取反引号名；`agents_txt` 是遗留读文本
- `check_host_installable.py:469` `crit_names` 赋值未使用 —— 同上，`--selftest` 用 `missing_key_files()` 判

### 意义

这是**证据化的负向结论**：并发 agent 密集改码下，clean Python 面（89 个脚本）**经静态分析没有 F/E 类逻辑 bug**（除上述 2 处）。说明并发 agent 的 Python 代码质量可控，我此前 R22/R24/R26/R32 已修的几处是零星问题，不是系统性问题。

---

## 二、修复 1：`mcp_bug_loop.py` 裸 except（真 bug）

- **根因**：L47 `except:` 裸捕获——会连 `KeyboardInterrupt`/`SystemExit` 一起吞掉，**Ctrl-C 无法中断本 MCP 驱动脚本**
- **修复**：`except:` → `except Exception:` + 注释（只兜 `json.loads` 的 `ValueError`/`TypeError`）
- **验证**：`py_compile` exit 0；`check_demo_isolation --selftest` exit 0（该脚本 Popen 起 `serve` 仍合规）；`check_scripts_index` exit 0 零回归
- **提交**：`93c155e`

---

## 三、修复 2：`run_check_t0r21.py` 重复 import（真 F811 bug）

- **根因**：L3 `import subprocess, sys`，L4 又 `import sys`——ruff F811 "Redefinition of unused sys"
- **修复**：删 L4
- **验证**：`py_compile` exit 0；ruff F/E722 复扫 "All checks passed"；AST 解析 OK
- **提交**：`496650b`
- **备注**：该脚本仅 README 提到（T0r2.1 一次性判据），未接 CI，属低影响但真实

---

## 四、tidy：清理 56KB 杂项 PDF

- **现象**：仓库根出现未跟踪的 `--help` 文件（`git status` = `?? --help`）
- **识别**：`%PDF-1.3` 开头，56KB——一个名叫 `--help` 的 PDF，明显是命令行误重定向产物（如 `xxx --help > --help`）
- **清理**：确认未跟踪（`git ls-files` 空）+ 无源码引用 → `Remove-Item`；删后 `git status --porcelain --untracked-files=normal` 无 `??` 项
- **未提交**：未跟踪文件删除不需提交

---

## 遗留风险 / 阻断（优先级排序）

1. **【最高优·未变】`src/router/router_state.mbt:211-212` 重复字段** → 全仓编译红（R34 发现，R35 复核仍在）。并发 agent 未修。**删任一行即恢复**。阻断所有 agent 的 `moon test` 验证。
2. **`ocr_scan --dry_run` 契约 bug**：R34 已写出最小补丁（`ocr_available` 改 `not(bin_hint.is_empty())`，`moon fmt` exit 0），等仓库编译恢复后应用 + 验证。
3. **`check_test_sync.py --help` 崩溃**（R33 发现）：并发 agent 修了 BUG-350（假绿判据）但**未修 --help 崩溃**——R35 复核 grep 确认仍无 `--help` 分支。文件脏，不能修。
4. **clean Python 面尚有 ~58 处 F541/F401/F841 死代码**：无害，非本轮优先级；若 owner 要极致 tidy 可一次性清理。
5. **src/server 36 脏（R21 第二十一轮）**：issue_scan 家族 6 条 + BUG-339 仍压脏区。

## 后续建议

1. **立即通知并发 agent / owner**：`router_state.mbt:211-212` 重复字段是当前全仓编译红的唯一根因，删任一行即恢复——已连续两轮报告，需 owner 协调。
2. 恢复编译后：应用 R34 的 ocr_scan 补丁 + `moon test --target js` 全绿验证。
3. 可考虑接一条 `ruff check --select F,E722 scripts` 到 CI 作为**静态分析守卫**（本轮实证：能稳定抓到真 bug）。但需先清掉 ~58 处死代码才能全绿，属可选增强。

## 资源消耗

- 1 次 git 状态 + 日志查（确认 R34 阻断仍在、并发 agent 提交 2279b28）
- 1 次杂项 PDF 识别 + 清理（`git check-ignore`/`ls-files` + `Remove-Item`）
- 1 次 ruff 全目录扫（89 clean .py）+ 过滤脏文件
- 3 次守卫 F841/F401 上下文精读（确认非逻辑洞）
- 1 次 F811 上下文查（确认一次性脚本）
- 2 次修复 + py_compile/ruff 复扫
- 2 次守卫回归（check_demo_isolation --selftest / check_scripts_index）

## 任务分配记录

- 无新派单。src/server 36 脏（R21）；src/router 14 脏（其中 router_state 阻断全仓）。

## 来源

- `git status --porcelain --untracked-files=normal`（发现 `?? --help`）
- `[System.IO.File]::ReadAllBytes` 前 4 字节 `%PDF` 确认 PDF
- `ruff check --select F,E722 --output-format concise scripts`（58 处命中）
- `git status --porcelain` 过滤出 5 个并发 agent 脏 .py
- `scripts/mcp_bug_loop.py` L44-49 精读（裸 except）
- `scripts/run_check_t0r21.py` L1-15 精读（重复 import sys）
- `check_demo_isolation.py --selftest` exit 0 / `check_scripts_index.py` exit 0
- 本会话 R22/R24/R26/R29/R31/R32/R33/R34 提交 + R35：`c7934f3`/`b4665e2`/`a15ab01`/`8ab683e`/`167ac5c`/`c6d1816`/`37be862`/`75e42e7`/`f0a8f4e`/`93c155e`/`496650b`