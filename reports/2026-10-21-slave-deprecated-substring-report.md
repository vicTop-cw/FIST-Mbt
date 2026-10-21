# 2026-10-21 R30 汇报：`slave/fix/deprecated-substring` —— 0020 `str[:]` 子族 42 处清零（565→523）

- 分支：`slave/fix/deprecated-substring`（stacked on `result-error-return`(#15) → `unused-value-params`(#16) → `deprecated-derive-show`(#14) → … → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0r11` 走完整生命周期 publish→claim→execute→submit→verify 至「已完成」（deliverable 落库），连续第十三轮自我迭代可证
- 台账：BUG-355（low，FIXED，轮次 R30）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 565 | **523** |
| 同判据 errors | 0 | **0** |
| `error_code` 0020 合计 | 524 | **482** |
| 其中 `str[:]` 子族 | 42 | **0** |
| `error_code` 2 / 6 / 1 / 9 / 7 / 27 / 78 | 11 / 12 / 9 / 3 / 2 / 1 / 3 | **逐格不变** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| `moon build cmd/cli --target js` | rc=0 | **rc=0** |
| moonfmt 新增分歧（14 份 .mbt） | — | **0**（D1==D0 逐文件） |
| `check_mbti_sync` | PASS（654 条） | **PASS（654 条）**（接口面零变化） |

改动 14 份 `.mbt`，+41/−70 行，全部在函数体内：42 处 `String::substring(start=,end=)` → `s[A:B].to_owned()`（其中 7 处三行链式折成一行、2 处 `X~`/`end~` label-passing、1 处省 `end` 开区间 `sid[k:]`）。`.mbti`、`moon.pkg`、`scripts/` 未动。

## 资源消耗

- 工具调用：约 26 次；`moon check` 全量 2 次（改后 523/0、折叠后复核 523/0）、`moon test src/server`（探针）2 次、`moon test` 全量 1 次、`moon build cmd/cli` 1 次、`moonfmt` 逐文件 14×2 轮（HEAD 与改后同尺对比）、守卫 6 项 1 轮、批量工具 2 版（`fix30.py` / `fix30b.py`）+ 分析脚本 5 份（`an20`/`an20b`/`ctx20`/`gap20`/`nw20`/`dump42`/`fmt30`/`fdiff`），FIST 生命周期 6 次调用。
- 本机墙钟：本单约 12 分钟（含一次等价性探针返工）。
- 返工 2 次：① 首版探针按 UTF-8 字节写 `substring(start=3, end=9)` 于 `"中文abcΩx"` ⇒ `String::substring.inner` panic（1 条 failed），读 core 才定性为 0.10.16 的 UTF-16 code unit 索引（`length()==7`），非语义不等；② `fix30.py` 首版链式分支接收者行号错一位且重拼接收者名（`let ktxt = restrest[...]`），dry-run diff 面暴露后修正。两次都在落盘前被拦下。

## 任务分配记录

- 指挥官亲自做：等价性定性（读 `string.mbt` / `stringview.mbt` 源码 + 白盒探针实跑）、0020 站点面与文本面 182∶42 的差额取证（规则 needle / 注释 / 被扫文案）、`issue_scan.mbt` 承重面判定（本仓既是规则实现者又是被改对象）、moonfmt 新增分歧的 D0/D1 同尺判定、终审判据实跑、记忆沉淀。
- 子代理：未派（42 处站点由判据 JSON 直接给出，loc 驱动一次成型，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r11` 全生命周期，连续第十三轮。

## 遗留风险

1. **`substring-overrun` 规则在真源码面现在恒 0 命中**。守卫识别器（BUG-164 / BUG-268 建的 `scan_substring_start` / `scan_guard_find_endvar` / `scan_guard_multi_line_length` / `scan_guard_mod_invariant`）按 `substring(start=N` 文本形态匹配，白盒夹具是字面量因此仍全绿。风险方向是"规则静默失效被当成精度改善"——本单不改规则，但把它列进后续建议②：给这档配一条定向自检。
2. **`ScanCtx.slice_only` 语义翻面**：`issue_scan.mbt` 用 `!has_substring_call` 计算它，改后 14 份文件全部 true。该标志只在 `rule == "substring-overrun"` 分支参与判断（`issue_scan.mbt:1357`），其它规则不受影响；但这是**运行时可观测面**的变动，属本单唯一非纯本地的副作用，如实记录。
3. **`.to_string()` 消除量比直觉大**：`code.substring(...).to_string()` 的 `to_string()` 也被一并去掉（`s[A:B].to_owned()` 直接给 String）。终判显示 0020 净减正好 = 42，未连带削减其它族（Debug-vs-Show 8、`@debug.Debug` 3 逐格不变）⇒ "去掉冗余 to_string 会不会改行为"的担忧未成立。
4. **接口面仍无生成器背书**（BUG-330 未解）：本单零接口变化，`check_mbti_sync` 654 条不动即是背书；`moon info` 在本机 0.10.16 仍不可用。
5. **stacked 合并顺序**：本支依赖 #16 → #15 → #14 → #13 → … → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
6. **6 处预存 CI 红**与本轮一致（badge 1108、test_sync 现状面、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入；`cleanup_artifacts --check` 仍 DIRTY（本机取证件累积），未跑破坏性清理。**"提交前零 WARNING" 在本仓当前不可达**（剩余 523 条里 430 条等 owner 决策），本单按"每轮清一个可证安全的子族、如实标注"推进。

## 后续建议

1. 下一单建议 **0020 的 `as_bool`(15) 或 `reinterpret_as_int64`(11)**：都是模式匹配改写（`json.as_bool()` ⇒ `if json is Boolean(b) { b } else { ... }`），有真语义面（默认值/None 分支）要逐站判，规模适中、适合再用本单的"dry-run 出 diff + 断言后落盘"形态。
2. **`Json::value` 430 条要先定形态**（owner）：引入包内 `priv fn json_value(j : Json, key : String) -> Json?` 才能机械铺开，否则每处都写 `match j { Object(o) => o.get(k) _ => None }` 会把可读性换掉——这是风格决策，不该由清理单替 owner 决定。
3. 给 `substring-overrun` 配"真源码恒 0 + 合成夹具恒命中"的成对自检（防规则静默失效）。
4. `docs/SOP.md` 仍建议补"批量改三件套：判据 JSON 出站点 → dry-run diff → 断言后落盘"，本链已连续两轮（BUG-351/355）在这条工序上吃亏或受益。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了 **core 源码级等价性证明**（`unsafe_substring` 共用同一实现）而不只是测试通过：把"切片是否等于 substring"从经验判断变成分支可查的结论，后续同类单（`as_bool`/`Json::value`）可直接引用同一取证形状。
- 加做了 **文本面 182 ∶ 判据面 42 的差额分解**（规则 needle、注释、被扫描文案、`unsafe_substring`），据此才敢动 `issue_scan.mbt` 自己的 21 处——否则会把规则表 needle 当调用改错。
- 加做了 **D0/D1 同尺格式判定**（HEAD 与改后各跑 moonfmt），既不 import 本机预存漂移 38/52/22 格，也不放过自己新增的 8 格。
- 未做：未加 `warnings = "-..."` 压制、未改 `substring-overrun` 规则或删其守卫检测、未动 `.mbti`/接口面、未删死码、未替 owner 决定 `Json::value` 形态、未跑破坏性 `cleanup_artifacts.py`。

## 来源

- 判据：`temp/chk31.json`（565/0，改前基线，0020=524、`str[:]`=42）、`temp/chk32.json`（523/0，改后）、`temp/chk33.json`（523/0，格式折叠后复核）、`temp/pt17.log`（`Total tests: 1302, passed: 1302, failed: 0`）、`temp/build17.log`（rc=0）。
- 等价性：`temp/p30.json` / `temp/p30t.log`（首版探针按字节写 ⇒ `String::substring.inner` panic，1 failed）、`temp/p30t2.log`（`Total tests: 328, passed: 328, failed: 0`，四组断言通过后探针文件已删）；core 真源 `string.mbt:144-156 / 274-283`、`stringview.mbt:198-201`。
- 站点面：`temp/an20.py`（0020 族分布）、`temp/ctx20.txt`（42 处逐条上下文）、`temp/gap20.txt`（182 文本 ∶ 42 判据 的文件级分解）、`temp/nw20.txt`（`issue_scan.mbt` 59 行非调用命中逐行）。
- 格式面：`temp/fmt30.py`（D0/D1 同尺，14 份文件全 OK）、`temp/fd_is.txt`（moonfmt 要求折叠的 7+1 格）。
- 守卫：`temp/g17_*.txt`（`check_mbti_sync` 654 条 / `check_pkg_imports` / `check_plugin_sync` / `check_tools_sync` / `gen_plugins --check` / `--selftest` 全 rc=0）。
- 改法脚本：`temp/fix30.py`（终版：解析 args + 链式折叠 + 断言后落盘）、`temp/fix30b.py`（moonfmt 要求的 8 处并行）；驱动 `temp/t11_drive.py`。
- 既有结论：BUG-344（复跑命中才算收口）、BUG-346/348/349/350/351（mbti 与批量工序，本轮第九次确认）、BUG-351（dry-run + 断言后落盘的直接来源）、BUG-164/268（substring-overrun 守卫检测面）、BUG-330（拼写漂移）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
