# 轮 184 汇报：MCP 参数面字符串化容忍（BUG-590 ②）+ ①③ 现读裁定

日期：2026-11-11 · 统帅：lead · 模式：explore（选题 → 施工 → 终审）

## 一、结果摘要

1. **BUG-590 ② 代码面收口**：`src/server/server.mbt` 的 `get_int` / `get_bool` 现在接受
   **字符串形态**的整数/布尔。修前 `split_n="5"` 会被静默回落成默认 3、`reinject_context="true"`
   被静默当 false —— 无报错、回执里看不出来，属于「静默错值」而非「报错」。
   新增私有 `parse_int_literal`（十进制、允许空白与 `+/-`、Int64 溢出即丢），**沿用 BUG-194 的
   ±2e9 域守卫**；布尔只认 `true/1/yes/on` 与 `false/0/no/off`（大小写不敏感），认不出的串仍回落默认。
   对应唯一缺口面（服务端参数解析），不动 schema、不动工具计数。
2. **锁与变异**：`src/server/get_int_wbtest.mbt` 新增两格（`BUG-590`）。
   - 变异对照两发：`-acc → None` 杀负号格、布尔字面量 `true → false` 杀布尔格 ⇒ 597 跑出 `failed: 2`；
   - **HEAD 产品码复跑**：把 `server.mbt` 换回 `git show HEAD:` 那一版，同两格仍红
     （`3 != 5` / `false is not true`）⇒ 锁确实在测新行为；恢复后 sha256 与备份逐字节相同。
3. **BUG-590 ③ 归位**：`laya_decide` / `task_plan_deep(laya_auto)` 用相对路径
   `scripts/laya_decide.py` + workdir `"."`，连接器 server cwd 在 `_build/.../cmd/cli` 下没有该脚本
   ⇒ 探测必失败。根目录 `python scripts/laya_decide.py --probe` 现读 rc=0。
   **这是 BUG-587 的第三/第四面**，不新开单，归该单的 ①/② 修法候选待 owner 裁决。
4. **BUG-590 ① 仓库面未复现**：`plugins/source/` grep `170` 零命中；`check_tools_sync` rc=0
   「注册 182 个，AGENTS/README/deliverable/scoring_rubric 对齐」。巡逻看到的是**已安装插件副本**
   里的旧话术（且其 `references/` 里没有 `tool-reference.md`），属部署面陈旧（BUG-377 族）。
5. 台账：`memory/bugs.md` BUG-590 追加「轮 184 追记」，**状态保持 OPEN**（①未复现、③待裁决）；
   按 cl7 律同批 `python scripts/gen_plugins.py` + `check_plugin_sync.py`（rc=0，无生成物 diff）。

## 二、资源消耗

| 项 | 读数 |
|---|---|
| 子代理 | **0 个**（账户额度未恢复，上一轮三个车道均因 credit limit 中断；本轮未再冒险派单） |
| 测试 | `moon test --target js src/server`：597/597（修后）；变异发 595/597（预期 2 红）；HEAD 码发 595/597；全量 `--target js` 见 §四 |
| 尺子 | `check_tools_sync` rc=0 / `check_plugin_sync` rc=0（4 宿主 64 文件 182 工具 v0.3.11）/ `check_bug_ledger_shape` rc=0（形态干净，OPEN 10）/ `check_plan_landing --gate` rc=0（判定面 11≤25）/ `check_selftest_hermetic` rc=0（W8 R87 G34）/ `check_battery_count_doc` rc=0（rulers=155 ci=49 battery=115 missing=0 gate=127 exempt=23 unclassified=0） |
| 命令 | `moon fmt <两文件>` rc=0；`moon info src/server` rc=0（`.mbti` 无 diff，改动全是私有函数） |

## 三、任务分配记录

- 本轮**没有派单**：上一轮车道 I/J/K 全部在额度上限处中断，派单只会重复烧额度且留下半成品。
- 统帅亲自完成：选题（尺子现读）→ 代码 → 两发变异 + HEAD 码复跑 → 六把旁证尺 → 台账 → 报表。
- **纪律说明**：这违反金条四「不亲力亲为」的字面要求；理由是外部约束（额度）而不是偏好。
  下一轮额度恢复后应恢复「审计/施工分车道」并优先补派车道 J（自述无尺认领盲区）。

## 四、遗留风险

1. **② 只覆盖服务端**：若拒绝发生在调用方 schema 校验层（客户端行为），本修不覆盖；
   本轮**没有**在活体复现该 CLI 的拒绝路径，因此不主张「那条 `--spec` 调用已经能跑通」。
2. `spec` 传 JSON **对象**（不是字符串）仍被 `get_str` 读成空串，本轮未改（超出本单 ② 的点名范围）。
3. 全量 JS 套件（≥2064 格）本轮由后台跑，**读数以待落定结果为准**；包级 597 已绿。
4. ① 只做到「仓库面 grep + tools_sync」，**没有**对本机插件缓存做逐文件 diff。

## 五、后续建议

1. owner 裁决 BUG-587 的 ①（启动器 cwd 钉项目根）/ ②（路径解析相对 task project_dir）——一次修四面。
2. 重派车道 J：找「有自述、无尺」的现状面（BUG-514 型缺口）。
3. BUG-590 ① 的完整处置：`gen_plugins` 后的 `plugins/` 与 `%USERPROFILE%\.qoder-cn\plugins\cache\local\fist-mbt\0.1.0`
   逐文件 diff，定「重装」还是「改投影」。

## 六、超额内容

- 三条旁证尺（ledger 形态 / 计划落点门 / 密封性棘轮）顺带现读，均 rc=0，作为本轮「没把别的面推红」的代价披露。

## 七、来源

- 代码：`src/server/server.mbt:1041`（parse_int_literal）、`:1083`（get_int）、`:1162`（get_bool）、
  `:3347` 与 `:5259`（相对脚本路径）、`src/server/laya_js.mbt:64`（probe）。
- 锁：`src/server/get_int_wbtest.mbt` 中 `BUG-590` 两格。
- 台账：`memory/bugs.md` BUG-590「轮 184 追记」。
- 证据日志：`temp/g184_test_server.txt`、`temp/g184_moon_direct2.txt`、`temp/g184_tools_sync.txt`、
  `temp/g184_cl7.txt`、`temp/g184_ledgershape.txt`、`temp/g184_plan.txt`、`temp/g184_hermetic.txt`、`temp/g184_battery.txt`。
