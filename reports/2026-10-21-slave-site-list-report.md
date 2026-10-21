# 2026-10-21 · 副机 R38 单元报告：不可入表族的「站点清单 + 结构归属」读数器

- 任务号：FIST **T0r19**（自我迭代根任务 T0 的第 19 轮）
- 分支：`slave/guard/deprecated-site-list`（链在 `2a88c75` 之后，单独一支，不与在审 MR 混线）
- 缺陷单：BUG-362（弃用调用普查的判据失真）追记 · 状态仍 **OPEN**（owner 五裁未落）
- 交付：**1 支新守卫**（只读数、不挂 CI）+ 4 处文档面

## 1. 结果摘要

| 项 | 读数 | 说明 |
|---|---|---|
| 新守卫 | `scripts/check_deprecated_site_list.py`（712 行，LF） | 六族判据行 ⇒ `file:line:col` + loc 切片 + 结构归属 |
| 真源读数 | 判据行 **19** / 站点 **16** / 文件 **11** | `temp/chk44.json`（489 诊断 / 0 error / 宇宙 290 个跟踪 .mbt） |
| 关键纠正 | Show 族 **11 行 ⇒ 8 个站点** | 3 处被两条 Show 文本同时命中，`…for collections` 新增 0 站 |
| 自检 | `--selftest` **20 支全绿** | 含 1 支「同行 extern」反证、5 支自拒、1 支「报告永不给 1」 |
| 真数据变异 | **2 支**（M1 marker 漂移 / M2 列口径 +3） | M1⇒rc=0+漂移点名；M2⇒rc=2 点名 S5 |
| 错误路径 | **4 支** 全 rc=2 且文案点名 | 非 dump / 缺 `diagnostics` 键 / `diagnostics` 空 / 文件不存在 |
| 对照跑器 | `temp/run_site_list.py` 8 格 | 8/8 ok，bad=0 |
| MoonBit 源码 | **未改** | 本单元纯工具+文档面，判据基线仍是 489 warnings / 0 errors |
| 挂 CI | **不挂** | 报告没有资格判红（与 `--dump-distribution` 同一条律） |

## 2. 实测读数（承重证据）

### 2.1 六族结构归属（真源，非合成）

| 族 | 判据行 | 站点 | 结构归属读数 |
|---|---|---|---|
| show-debug | 8 | 8 | to_string() 调用 ×3（`pub_res`/`r3`/`w1`）· 字符串插值 ×2 · inspect() 实参 ×3；生产面 1 / 测试面 7 |
| show-collections | 3 | 3 | **全部与 show-debug 同站** ⇒ 新增 0 站 |
| js-ffi-array | 3 | 3 | extern "js" 抬头在其上 **1、2、2 行** ⇒ 行级正则 0/3 能单独判定 |
| implicit-promotion | 1 | 1 | impl 段 50–56 / 57–68，站点 71 在**体外**（落在 `fn delegate_execute`） |
| derive-show(0027) | 1 | 1 | `derive(Eq, Debug, Show)`，**Debug 已在列表** ⇒ 删一个 token 即可 |
| result-error-return(0078) | 3 | 3 | 3/3 **私有**转换辅助 ⇒ 对外契约面 0 |

### 2.2 两支真数据变异对照

- **M1 判据文本漂移**：六族 marker 各改一个字母，命中 19 条 ⇒ `rc=0`，表头打出
  「全清单 6 族都读到 0 处，而诊断面非空 ⇒ 大概率是判据文本漂移而不是族已清空」并指回
  `check_deprecated_text_census.py --dump-distribution` 对 code 面。
- **M2 列口径漂移**：表内族 `loc` 起止列整体 +3 ⇒ `rc=2`，
  `FATAL S5 本族全部 3 个站点的切片都不含本族点名的符号（期望 'Array'）`。
- **不对称（写进 docstring）**：只有判据**点名符号**的族（Array / 0027 的 Show / Result）能自证列口径；
  Show 的 0020 判据不点名 token，同一份变异里它 8 个站点全读成「未分类」——数字不会自拒，
  但小结一片「未分类」就是进料信号。

### 2.3 自检 20 支

Show 双文本并站 / 三形状 / 测试面-生产面 / 未知形状不硬塞 / FFI 跨行 / **FFI 同行反证** /
提升 impl 段定位 / derive 含 Debug / 0078 私有 / 0078 pub / S1 空诊断 / S2 宇宙被换小 /
S3 站点越出跟踪面 / S4 行号越界 / S4 列切片为空 / S4 站点跨行 / S5 列口径漂移 / S6 零读数免责 /
全清单零读数指回 code 面 / 报告永不给 1。

## 3. 四条非显然判定

1. **行数 ≠ 站点数**：同一 `(file,line,col)` 可被两条判据文本命中。按 11 行派工会多算 3 处。
   这是行级普查的第二种失真——第一种是判据静默少报（判据 < 文本），两种都在这张族表上同框出现。
2. **跨行归属可以机械化，不用断言**：条目抬头 = 自站点行向上最近的 0 缩进 `extern/impl/fn/enum/test/...` 行；
   条目段落粗界 = 下一个顶层条目起始行 − 1。不猜花括号，读不到就 `FATAL` 自拒。
3. **报告与裁决分开**（本单元把它做成硬约束而非口号）：本工具**不可能**返回 1；
   `rc=2` 只留给「尺子读不出可比读数」（S1–S5），`rc=0` 里可以装着「0 处」这种不合口味的数字。
   与棘轮表**故意不收同一个族**（utf8 3 条只在表里），否则两支尺改口径时会互相掩盖。
4. **判据文本自述可反解**：`The method \`run\` is implicitly promoted from \`impl Executor for X\``
   里带着 trait/type/建议形态；`derive(Show)` 那处带着「Debug 已在列表」的改法线索。
   把判据文本当数据源读，而不是只当分类键，是这张清单能给出「怎么改」的原因。

## 4. 资源消耗

- 子代理：0（本单元判断点全在结构归属的机械化，代读会丢实测细节）
- 工具调用：约 24 次（其中 3 次是探针/跑器自身的缺陷返工）
- 令牌：in 11 800 / out 10 600（FIST 台账登记，model `qoder-agent`，成本 0.32 单位）
- 墙钟：约 22 分钟（本机 UTC 20:27→20:49）

## 5. 任务分配记录

| 环节 | 承担 | 结论 |
|---|---|---|
| 站点结构实测 | 主代理（`temp/probe50.py`/`probe51.py`） | 19 行 / 16 站 / 11 文件，逐站切片+上下文落档 |
| 守卫实现与自检 | 主代理 | 712 行 / 20 支全绿 |
| 真数据变异对照 | 主代理（`temp/run_site_list.py`） | 8 格全 ok |
| 文档面同步 | 主代理（`temp/edit_r38.py`，锚点断言） | README 登记 / 决策稿 §3.7 / 台账 R38 / 日志 R38 |
| FIST 生命周期 | `scripts/fist.py` 驱动 `temp/t19_drive.py` | T0r19 publish→claim→execute→submit→verify 六步 rc=0 |

## 6. CI 与预存红

- 本单元**不给 CI 加步骤**（工具不判红，加了就等于把报告升格成门）。
- 权威 CI 既有两步（census 的 `--selftest` + 真判据）不受影响：新脚本与它们无耦合，
  族表与清单**故意不收同族**。
- `check_scripts_index.py`：新脚本已登记 ⇒ PASS（登记是它的硬要求）。
- 三条预存红照旧、非本单元引入，逐条已在 MR 说明里如实标注：
  `check_py_stdout_encoding --selftest` / `--all`（owner 裁「交 CI 当门，PR 里如实标注」）、
  `cleanup_artifacts --check` DIRTY、`check_upgrade_installer` 缺前置。

## 7. 遗留风险

1. **跨行站点直接自拒**：`loc` 的 l1≠l2 时本清单 rc=2 而不是跳过。真源今天 0 条；工具链改版后若出现，
   整张清单会读不出来（属"自拒"而非"假绿"，方向安全但会挡住读数）。
2. **Show 族的列口径不可自证**：0020 的 Show 判据不点名 token，S5 对它无效；只能靠「未分类」桶变胖报警，
   而那是人读的一格，不是门。
3. **六族 marker 是硬编码子串**：判据文案改版 ⇒ 全清单静默 0 处（虽有漂移点名行，但仍需有人看）。
4. **站点清单是证据单，不是消账凭证**：owner 裁完（改 / 不改 / 挂账）必须回落台账，否则下一单元会照单再读一遍。
5. 未派子代理 ⇒ 本单元全部读数出自同一台机器同一份 dump（`temp/chk44.json`，工具链 0.10.16）。

## 8. 后续建议

1. 给 owner 的**最小可裁单元**已经成形：Show 8 站（其中 7 站在测试面，改断言文本即可）、
   Array 3 站（`FixedArray[String]`，三行都在 `*_js.mbt`）、0027 1 站（删 `Show` 一个 token）、
   0078 3 站（私有辅助，改 `raise` 或写明保留理由）、提升 1 站（显式限定）。
   按这个颗粒度逐族裁，比按 448 条判据行裁要省力得多。
2. 若要给「未分类」桶加闸：本清单可加一个**可选**上限模式（表内声明未分类上限，超限 rc=2 而非 1），
   仍不破「报告不判红」那条律。
3. `--dump-distribution`（进料口）与本清单（证据单）可在一个跑器里串成「形状 → 站点」两段读数，
   省一次 dump 解析；但两支尺的族表要保持故意不重叠。
4. 台账侧建议把「行数 / 站点数」两栏并存（BUG-362 已记 11 行 ⇒ 8 站这一例），
   防止下一单元又按行估工作量。

## 9. 超额内容（自审）

- `temp/probe50.py` 第一版按 `messages` 键读 dump，得到「判据 0 处」的静默假绿——
  上一单为 R1 哨兵写下的教训在本轮自己身上二次验证；据此把「`diagnostics` 是非空数组」钉成 S1 硬前置。
- 自检夹具列号第一版手算，4 支错位（`to_string(` 读成 `3.to_strin`）；改为按 `line.index(token)` 反算后全绿。
  这条已写进日志的「方法坑」：**切片约定只能靠反算校准，不能靠印象**。
- `resolve_ffi` 的形参名提取第一版用整行正则，同行 extern 时读不到；改成对站点前缀做
  `([a-z_]\w*)\s*:\s*$` 匹配，两种形状都能拿到（自检两支覆盖）。
- 未做（刻意）：不给 CI 加步骤、不改 MoonBit 源码、不把 utf8 族复制进本清单。

## 10. 来源

- 判据真源：`temp/chk44.json` = `moon check --target js --json`（489 诊断 / 0 error，工具链 0.10.16）
- 代码：`scripts/check_deprecated_site_list.py`（docstring 记全设计与两条律）
- 登记：`scripts/README.md` census 条目之后一条
- 决策稿：`docs/decisions/2026-10-21-json-value-430-decision.md` §3.7
- 台账：`memory/bugs.md` BUG-362 的 `landed[2026-10-21 R36]` 行尾 R38 追记
- 日志：`memory/2026-10-21.md` R38
- 证据：`temp/sl_real2.log`（真源）/ `temp/sl_selftest3.log`（20 支）/ `temp/sl_M1-marker-drift.log` /
  `temp/sl_M2-col-drift.log` / `temp/sl_err-*.log`（4 支错误路径）
- FIST：`temp/fist-selfiter.db` T0r19 全生命周期回执

*AIGC 说明：本报告由 AI 辅助生成，数值全部出自本机实测日志。*
