# BUG-579 立账报告 —— C 盘满致 cl7 判据失明（环境态 · 投影面无漂移）

日期：2026-11-07 · 模式：fist-commander · 轮次：唤醒轮 171 · 提交：`020dd28f7`

## 结果摘要

- 唤醒轮 171 轮转巡检 `check_plugin_sync.py`（cl7）→ **FAIL rc=1**——本会话首个真红。
- **根因链**（逐级钉实）：
  1. cl7 红面引用的 traceback 被截断，看不到真异常行 ⇒ 直接跑 `python scripts/gen_plugins.py --check` 取原始栈；
  2. 真异常：`OSError: [Errno 28] No space left on device`（line 343 `write_text`，经 line 644 `generate(tmp, vals)`）；
  3. 崩的是 **tmp 生成半边**（Python 默认临时目录在 C 盘），不是 E 盘投影产物——`df` 实证：C 盘 `201G 201G 0 100%`，E 盘 355G 余量健康；
  4. **对照实验**：`TEMP/TMP/TMPDIR` 三变量改道工作区 `temp/tmp_e` → `gen_plugins.py --check` rc=0、`check_plugin_sync` 整门 rc=0（4 宿主 / 64 生成文件 / 182 工具 / v0.3.11）⇒ 投影面无任何漂移。
- **定性**：环境磁盘满让判据失明，非投影漂移。判例-34 同族（错误指向 ≠ 真实位置）——cl7 的 FAIL 输出只引截断栈、处置建议「重新生成后复跑」在本形下无效且误导。

## 处置记录

1. 立账 **BUG-579**（OPEN）：owner 侧清 C 盘为根因半；可选后续项 = cl7 捕 `OSError 28` 输出归因行，或 tmp 固定改道仓库内（与 check_demo_isolation 改道针同思路）——先立账不代修。
2. 账本条目自述初稿「生成物逐字节相同」被实测推翻（OPEN 条目推进抬头计数：BUG-1~579 / 564 条 / 6 条待修）——**当场改真**（自述滞后族预防）。
3. cl7 律同批重投影：`gen_plugins.py`（TEMP 改道，rc=0）→ 9 个插件态文件计数行刷新（+17/-17）→ `check_plugin_sync` 复跑 **rc=0**。
4. 受控提交 `020dd28f7`（memory/bugs.md + plugins/** 10 文件，落盘面=申报面逐字相等）。

## 资源消耗

1 次唤醒轮；bash ×12、写文件 ×4；无子代理派发（根因链单线，亲力诊断属统帅终审职责内）。

## 任务分配记录

无（根因钉实 + 立账 + 提交一气呵成，无并行面）。

## 遗留风险

1. **C 盘 0 字节可用**：凡 tmp 落 C 盘的判据/工具（Python tempfile 族）在本机随时会崩——cl7 只是第一个被撞响的。owner 清 C 盘前，本机跑判据建议统一 TEMP 改道。
2. cl7 失明形状（红面不显 Errno 28）未修，属可选后续项（BUG-579 内记）。

## 后续建议

1. **owner：清理 C 盘**（唯一根因半）。
2. 下一唤醒轮复跑 cl7（TEMP 改道）确认环境态无复发；C 盘清出空间后跑一次不改道的 cl7 作关闭取证。

## 超额内容

无（诊断 + 立账 + 投影纪律 + 提交，均在记账义务内）。

## 来源

- 唤醒协议（用户 prompt 标准动作 1~5，第 3 步「有新发现就立账」）
- `check_plugin_sync.py` / `gen_plugins.py --check` 实跑输出与 traceback
- `df -h` 读数；memory/bugs.md BUG-579 条目；memory/2026-11-07.md 唤醒轮 171
