# 2026-10-07 BUG-136/137/138 报告：预订原子性 + 调用方身份 + CI 侧 stdout 编码闸

## 结果摘要

从 F094（多管家文件级协调）的价值评估出发，发现三类承重缺陷并全部修复：

| BUG | 严重度 | 问题 | 修法 |
|-----|--------|------|------|
| BUG-136 | high | `reserve_scope` 读-后-写跨进程既撞锁又丢互斥 | `PRAGMA busy_timeout=5000` + 新原语 `rsv_try_set`（单语句 upsert + 写后回读）+ 纯函数 `rsv_action` |
| BUG-137 | medium | `call_log` caller 列 95% 为空 | 纯函数 `caller_from_env`：FIST_CALLER 环境 > created_by 自述 > 空串 |
| BUG-138 | medium | 7 份 CI 脚本缺 UTF-8 stdout 闸，守卫崩在结论行之前 | 新常驻判据 `check_py_stdout_encoding.py`，扫描面从 workflow 反解 |

新增常驻判据 **J14**：工具计数自述与 CLI 帮助分组数字之和、分组数都必须等于真源注册表。

## 资源消耗

- JS 全量测试：573 → **576/576**（+2 store 测 +1 server 白盒测）
- 守卫族：18 → **20 步**全绿（新增 Reserve cross-process guard + Py-stdout encoding guard）
- 改动文件：34 个（含 4 宿主插件投影重生成）
- 新增文件：2 个（`scripts/check_py_stdout_encoding.py` + `scripts/blackbox/e2e_reserve_xproc.py`）

## 任务分配记录

本轮由指挥官直接执行，未派单。三个 BUG 同批落账（一条命令 `temp/b136_bookkeep.py` 做完，避免中间态红账本）。

## 承重证明

`scripts/blackbox/e2e_reserve_xproc.py` 两棵树各跑一次：
- **旧码树**（`git archive HEAD`）：rc=1，1 绿 5 红（含 `database is locked` 逐字错误）
- **修复树**：rc=0，6/6 绿（并发双绑 20 轮，双成功=0、一成一拒且带 held_by=20、行数=20）

## 遗留风险

1. **BUG-133 仍 OPEN**：上游 `mizchi/sqlite@0.3.1` native FFI 堆损坏，本仓侧门与判据已就位，等上游修复
2. **`FIST_CALLER` 注入面**：修复后若运维侧不注入 `FIST_CALLER`，caller 仍会是空串或自述——区别在于「空串是有含义的结论」而不是「代码没记」。已挂 BACKLOG P2 待办行（四宿主各需一个注入示例）
3. **非 CI 脚本 UTF-8 闸**：仍有 31 份缺闸（demo/selfdrive/verify 一族），扫描面按「CI 调用」界定所以不判红。扩扫描面或补闸交给 owner 裁决，已挂 BACKLOG P3 待办行

## 后续建议

- F094 的 Phase 1 仍不排期——承重墙已修，验收格「两进程同时 bind 恰好一成一拒」现在有常驻判据守着，但三工具（file_bind/release/status）的增量价值不足以覆盖实现成本
- `rsv_set`（无条件覆盖）仍保留给 release 路径与既有测试夹具，不是安全漏洞但值得在 F094 重新评估时审视

## 超额内容

- **一处修法上的自我修正**值得留在账上：第一版 BUG-136 留了「写前已看见活体持有者就不发这笔写」的短路，结果那条 SQL 的 WHERE 永远走不到——摘掉短路后同一支变异必红。「跳过」看起来与内存后端一致、还省一次写，代价是把判据架在不存在的路径上——这类短路从此按空门处理
- **J14 触发形状**：`fist://map` 资源正文写着「MCP 层 102 工具」而真源是 129，`check_tools_sync` 第 3 条不扫 src/、J3 只扫 README ⇒ 资源面与 CLI 帮助面两头没人认领

## 来源

- 起因：owner 问 F094 值不值得做，读调用面数据时发现
- 证据件：`temp/b136_judge_headtree.log` / `temp/b136_judge_after.log` / `temp/b136_js_full3.log` / `temp/b136_bear_proof.log`
- 台账：`memory/bugs.md` 137 卡，OPEN 1 / FIXED 123
- 盖章戳：2026-10-07T12:50:57Z
