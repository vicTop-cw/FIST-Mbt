# R36 · ruff B(bugbear) 二次扫查 + 守卫 F541 验证 + 关键守卫零回归确认

- 日期：2026-10-21
- 性质：bugfind + verify（组合模式的寻虫-验证两环）
- 结论：**clean Python 经 F/B 双规则扫查均确认无系统性问题**（F 58 处仅 2 真 bug 已修；B 29 处全为风格类）。R29 接入的 4 个关键守卫 + 3 个 selftest **全部 exit=0，并发改动零回归**。src/router 编译阻断**仍在**（连续三轮报告）。

---

## 一、ruff B(bugbear) 二次扫查（新规则维度）

对 clean Python 跑 `ruff --select B`（bugbear，比 F 抓更微妙的 bug）：

| 规则 | 含义 | 数量 | 性质 |
|---|---|---|---|
| `B904` | raise 未 `raise ... from` 链上下文 | 最多 | 风格，非逻辑 bug |
| `B007` | 循环控制变量未在体内使用 | 若干 | 风格（如 `for h in x` 但没用 `h`） |
| `B905` | `zip()` 无 `strict=` | 1 | 潜在未来 bug（见下） |
| `B006` | 可变默认参数 | 0 | 无 |

### B905 详查：`gen_plugins.py:221` `zip(names, pairs)`

- 若 `names`/`pairs` 长度不等，zip 会**静默截断**，导致投影丢项
- **但 L216 已有前置校验**：`README 分组和 {total} != 注册表实测 {n} ⇒ 拒绝投影`（两侧长度一致才走到 zip）
- 故**当前无风险**；加 `strict=True`（Python 3.10+）是未来增强，非必要修复。未改。

### 结论

B 类 29 处全为风格性（B904 raise 上下文 / B007 未用循环变量 / B905 zip strict），**无真逻辑 bug**。与 F 类扫查结论一致。

---

## 二、守卫 F541 逐条验证（排除"错误消息丢了变量"）

R35 发现守卫有若干 F541（f-string 无占位符）。逐一验证是否属于"本该插值却丢了变量"的真 bug：

| 位置 | 消息 | 判定 |
|---|---|---|
| `check_tools_sync.py:327` | "R7 server.mbt:1 头注释没有三元组（判据无从比对）" | 静态诊断，无需插值 |
| `check_plugin_sync.py:238` | "处置：python scripts/gen_plugins.py 重新生成后复跑本守卫" | 静态指引，无需插值 |
| `check_doc_surface.py:956` | "J4 扫描面为空——没抓到声明不等于没有问题，先判枚举器坏" | 静态诊断，无需插值 |

**判定：全部为无害的静态消息**（作者多写了 `f` 前缀），非逻辑 bug。F541 在守卫里不构成问题。

---

## 三、关键守卫零回归确认（并发改动验证）

并发 agent 密集改码下，R29 接入的守卫是否仍工作？实跑：

| 守卫 | exit | selftest exit |
|---|---|---|
| `check_scripts_index` | **0** PASS | **0** PASS |
| `check_demo_isolation` | **0** PASS（34 spawn 脚本全合规） | — |
| `check_desc_enum_sync` | **0** PASS | **0** PASS |
| `check_upgrade_installer` | **0** PASS | **0** PASS |

**结论**：并发 agent 的改动**未破坏**本会话接入的守卫。4 守卫 + 3 selftest 全部 exit=0，守卫族稳定。

---

## 遗留风险 / 阻断（优先级排序）

1. **【最高优·连续三轮】`src/router/router_state.mbt:211-212` 重复字段** → R36 复核**仍在**（L211-212 逐字重复）。并发 agent 未修。**删任一重复行即恢复全仓编译**。阻断所有 agent 的 `moon test` 验证与 R34 ocr_scan 补丁落地。**建议立即协调 owner 收口。**
2. **`ocr_scan --dry_run` 契约补丁**：R34 已写好（`ocr_available` 改 `not(bin_hint.is_empty())`，`moon fmt` exit 0），等编译恢复后应用 + 验证 + 提交。
3. **`check_test_sync.py --help` 崩溃**：并发 agent 修 BUG-350 未修 --help（R33 发现），文件脏不能改。
4. **clean Python 面 ~58 处 F541/F401/F841 死代码**：无害，非优先级。

## 后续建议

1. **优先协调 owner** 删 `router_state.mbt:212`（任一行）——连续三轮未修，是唯一全仓编译红根因。
2. 恢复编译后：应用 ocr_scan 补丁 + `moon test --target js` 全绿 + 提交。
3. 若 owner 想要极致 tidy：一次性清 clean Python 的 58 处死代码（F541/F401/F841），再考虑把 `ruff --select F,B,E722` 接进 CI 作静态分析守卫（本轮 F+B 扫查能稳定抓到真 bug，如 mcp_bug_loop 裸 except）。

## 资源消耗

- 1 次 router_state 复核（确认阻断仍在，连续三轮）
- 1 次 ruff B 全目录扫查（29 处 B 类，全部风格性）
- 1 次 gen_plugins B905 上下文精读（确认有前置 total 校验，无风险）
- 3 次守卫 F541 上下文精读（确认静态消息，非丢变量）
- 1 次关键守卫批量实跑（4 守卫 + 3 selftest 全 exit=0）

## 任务分配记录

- 无新派单。src/router 14 脏 / src/server 36 脏（R21 后未减）。

## 来源

- `git status --porcelain`（确认 router_state 重复字段仍在 / ocr_scan clean）
- `ruff check --select B --no-cache --output-format concise scripts`（29 处 B 类）
- `scripts/gen_plugins.py` L214-228 精读（B905 前置校验）
- `scripts/check_tools_sync.py` / `check_plugin_sync.py` / `check_doc_surface.py` F541 上下文
- `python scripts/{check_scripts_index,check_demo_isolation,check_desc_enum_sync,check_upgrade_installer}.py`（4 守卫 exit=0）
- `python scripts/{check_scripts_index,check_desc_enum_sync,check_upgrade_installer}.py --selftest`（3 selftest exit=0）