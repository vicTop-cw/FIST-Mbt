# 2026-10-21 · 拆族探针固化成守卫的进料口模式（R37 / T0r18）

## 1. 结果摘要

| 项 | 交付 | 状态 |
|---|---|---|
| 新模式 | `scripts/check_deprecated_text_census.py --dump-distribution <moon check --json dump>`：按 `error_code` × 归一化消息形状分组，逐形状给处数 / 文件数 / 首个站点 / 表内认领状态 | 实跑 rc=0 |
| 认领三态 | `claim()` 用表内 `judge_marker` 对**原始** message 测 ⇒ 已入表(k/n) / **部分入表(k/n)** / 未入表；部分入表 = marker 与真源形状脱钩的进料信号 | 两支真数据变异各自现形 |
| 探针归位 | 上一单为拆 0020 的 6 个子族临时写的 8 份 `temp/probe42.py`–`probe49.py`，其读数现由守卫常驻给出 | 与手工读数逐格相同 |
| 夹具补格 | `--selftest` 10→**17 支**（真判据 10 + 分布 7） | rc=0，每支命中自己指名的读数 |
| 文档口径 | `scripts/README.md`（新模式 + 不挂 CI 的理由 + 计数改 17）、决策稿 §3.6、账本 BUG-362 追记、日报 R37、本报告 | 已同步 |
| 零改动面 | `.mbt` 本体 0 处改动；CI 步骤 0 增加；真判据的判据与退出码语义未动 | 见 §5 |

一句话：上一单量出了「盲区在哪」，这一单把「怎么发现下一个盲区」变成一条命令——并且把它能咬人的那两格（形状被并族而隐身、marker 与真源脱钩）都事先考过。

## 2. 实测读数（全部当场跑，非引用旧数）

判据面来源：`moon check --target js --json` ⇒ `temp/chk44.json`（rc=0，489 条，`level` 全为小写 `warning`，error 0 条）。

| 读数 | 值 | 对照 |
|---|---|---|
| 分布形状总数 | 8 个 `error_code` / **15 种形状** / 489 处 | 与上一单手工探针分族逐格相同 |
| 0020 拆分 | 430 / 8 / 3 / 3 / 3 / 1 | 即决策稿 §3.5 那张表（`Json::value`、Show-debug、Show-collections、utf8、FFI `Array`、隐式提升） |
| 已入表 | 2 条（`Json::value` 430/430、`Check @encoding/utf8.encode` 3/3） | 真判据面对 `chk44` 仍 PASS |
| 未入表队列 | 13 种形状、覆盖 56 处判据 | 0001:9 / 0002:11 / 0006:12 / 0007:2 / 0009:3(三行) / 0020 余 15 / 0027:1 / 0078:3 |
| 真判据（回归） | `430 / 441 缺口 11 == 上限`；`3 / 3 缺口 0 == 上限` ⇒ PASS rc=0 | 基线 489 warnings / 0 errors 不变 |
| 测试面 | `Total tests: 1302, passed: 1302, failed: 0.`（`temp/pt24.log`） | 以计数行为准，不采信 rc |

变异对照两支（改 dump，不改源码）：

| 变异 | 真判据面 | 分布面 | 说明 |
|---|---|---|---|
| M1 抹掉 3 条 utf8 判据（`temp/chk44_mut_no_utf8_judge.json`） | **rc=1**：`R3 … 缺口 3 超上限 0`，点名 `src/router/star_gate.mbt +1`、`src/router/star_gate_wbtest.mbt +2` | 该形状读成「表内条目在本 dump 判据面 0 命中」 | 棘轮仍咬得住，不是恒绿装饰 |
| M2 只把 1 条 message 的 `utf8`→`utf16`（形状不变、marker 掉一格，`temp/chk44_mut_marker_drift.json`） | rc=1：判据面 2 / 文本面 3 ⇒ 缺口 1 超上限 0 | **部分入表(2/3)** + 结论行「marker 与这个形状对不齐，先修 marker 再谈代码」 | 同一处漂移在两把尺上的不同咬法：分布面直接说是尺子和表对不上，真判据面只能报缺口 |

错误路径 4 支（都是 rc=2，且话术分开）：无参（打 usage）、非 JSON（`Expecting value…`）、缺 `diagnostics` 数组、`diagnostics` 为空（附「分布读数也拒绝在空 dump 上印『没有别的族』」）。

`--selftest` 17 支全绿的分布 7 支分别是：同 code 多形状必须分列 / 只差引号字面量与数字的两条必须并形 / marker 全命中=已入表(1/1) / 同形状只命中一半=部分入表(1/2) / 空 dump 读 rc=2 / 表内条目 0 命中要点名 / 不同 code 不并块且报告永不给 1。

## 3. 非显然判定（四条，都是这一单里"不写下来就会重犯"的东西）

1. **报告与裁决分档，所以分布模式永不返回 1、也不挂 CI。** 红门的语义是「缺陷在场」；把一份读数报告接到红门上，等于允许一次工具链升级用红灯的形式说「大概没事」——而红灯被忽略一次，整把尺就废（同 R35 那条取舍的理由，方向相反）。因此本模式只可能 0 或 2，`2` 留给「dump 形状不对 / 诊断面为空」这类尺子无法自证的情况。
2. **形状归一不抹裸标识符，是刻意的「宁可啰嗦」。** 0009 的三处（`WorldState` / `ActiveReservation` / `PlannedAction`）各占一行而不是并成一行：并族等于其中一族在读数里隐身，那正是 BUG-362 立单的失效形态（判据面静默少报）。汇总行仍然给「几种形状 / 几处判据」，所以啰嗦不进结论。
3. **认领判断必须对原始 message 测，不能对归一形状测。** 归一把 `utf8` 写成 `utf<n>`，于是表里那条 `utf8.encode` 若去匹配形状会一条也命中不了 ⇒ 假「未入表」，把已经守着的族说成没人守。这条被 M2 实测钉住：形状相同、marker 掉一格时，读数给的是「部分入表(2/3)」而不是「未入表(0/3)」。
4. **分布模式不读源码，所以它不构成清零证据。** 一处判据 ≠ 一处源码调用（430 对 441 是上一单的实测）。docstring 与 README 都把这句话放在读数第一行，防止有人拿「分布里没有这个形状了」当「弃用调用清零了」。

## 4. 资源消耗

| 项 | 值 |
|---|---|
| 估算 tokens | in ≈ 118 000 / out ≈ 10 400 |
| 估算成本 | ≈ 0.31（按项目既有单价口径） |
| 墙钟时长 | ≈ 640 000 ms（含两次 `moon check` / 一次 `moon test -j 1`） |
| 执行模型 | qoder-agent（指挥官本机，未派子代理） |

## 5. 任务分配记录

- 指挥官（本机 agent）亲自执行：分布模式设计、`shape_key/claim/distribution` 实现、selftest 7 支新格、两支真数据变异、四处文档口径、FIST T0r18 生命周期（publish→claim→execute→submit→verify→get，全 rc=0，状态「已完成」）。
- 未派子代理的理由：单文件加读数模式 + 文档同步，边界清晰、验证成本低，分派反而增加终审负担（金条四）。
- 零 `.mbt` 改动；`.github/workflows/ci.yml` 未加步骤（§3 判定 1）。

## 6. CI 与预存红（如实标注，不代裁决）

- 本单元**不新增** CI 步骤：`--dump-distribution` 是报告，真判据两步（`--selftest` + 判据）仍挂在权威 `ci.yml` js-ubuntu 臂，未改动。
- 全套守卫复跑：`temp/run_guards14.py` 共 33 例，与期望不符者仅既有三条预存红——`check_py_stdout_encoding.py --selftest`（rc=2）、`check_py_stdout_encoding.py --all`（rc=1，6 份脚本缺 stdout 闸）、`cleanup_artifacts.py --check`（rc=1，DIRTY 547）。三者 owner 已有裁决（「交 CI 当门，PR 里如实标注」），本单元不动。
- 新增 3 例分布用例（chk44 正常读数 / marker 漂移读数 / 空 dump 期望 rc=2）均按期望退出。
- `check_publish_payload`、`check_scripts_index`、`check_doc_surface`、`check_mbti_sync`、`check_badge`、`check_test_sync` 全绿；基线 `moon check --target js` = 489 warnings / 0 errors。

## 7. 遗留风险

1. **BUG-362 仍 OPEN**：11 处 `Json::value` 本体待 BUG-361 定案；分布模式只让「下一个盲区怎么被发现」变便宜，不代替裁决。
2. **分布读数会被误用成清零证据**：已在读数首行、docstring、README 三处钉「只读 dump、不读源码」，但真正的防线是它不挂 CI、不返回 1。
3. **归一化量程的取舍不是免费午餐**：不抹裸标识符会让形状数随名字数量增长（0009 三行、`Json::value` 一行 430 处）。若将来某个族有上百个不同名字，这个模式会打出上百行——`top_shapes=40` 的截断只影响打印，不影响汇总计数，但那时需要再加一个「按形状前缀聚类」的选项，属于本模式的下一个迭代而不是这一单。
4. **数字仍随工具链版本浮动**：与 R35 同一风险面。形状数与处数都不进棘轮，只有表里的 `gap_ceiling` 进，所以升级最多让队列变长，不会让门变松。
5. `check_deprecated_site_list.py`（语义族：`Show` 8+3、FFI `Array` 3、隐式提升 1 的站点清单工具）仍挂待议——这三族按 §3.5 的实测不能进文本棘轮表。

## 8. 后续建议

1. 给分布模式加 `--by-file`（按文件 × 形状交叉表），把「哪个文件同时背着三族弃用」排出来——收口时按文件改比按族改省一半往返。
2. BUG-361 定案后，把 M1/M2 这两支变异写进 `--selftest` 的「真数据版」（现在用合成夹具），这样上游 marker 一改形状，夹具与真源会同时叫。
3. 决策稿 §7 那五项裁决若能落一项，就顺手把对应形状从「未入表」推进表内，`--dump-distribution` 的队列长度即该单的进度读数。
4. 预存红 6 份脚本的 stdout 闸仍待单独一小单收（不改行为，只加 `sys.stdout.reconfigure`）。

## 9. 超额内容（任务包之外做的）

- 任务包只要求「把探针读数固化成一个模式 + 文档同步」；额外做了两支**真数据**变异对照（M1/M2），因为它们才能证明认领三态不是夹具里的自嗨。
- 额外把 `main()` 里的读盘与形状校验抽成 `load_dump()`，两个模式共用同一句 FATAL 话术（原来各写各的，会漂移）。
- 额外纠正了一条凭印象的计数：docstring 初稿写「7 份探针」，`ls temp/probe*.py` 实测为 **8 份**（`probe42.py`–`probe49.py`），四份文档一并改回。
- `evaluate()` 的 R3 红行末尾加了一句「下一步：`--dump-distribution` 看这些落在哪些判据形状上」，把两个模式串成一条工作路径（不改判据、不改退出码）。

## 10. 来源

- 判据面：`temp/chk44.json`（本机 `moon check --target js --json`，rc=0）；对照 `temp/chk41.json`、`temp/chk43.json`（同分布）。
- 测试面：`temp/pt24.log`，`Total tests: 1302, passed: 1302, failed: 0.`
- 守卫：`scripts/check_deprecated_text_census.py`（`--selftest` 17 支、真判据、分布、变异与错误路径均为当场实跑）；全套 `temp/run_guards14.py`。
- 台账：`memory/bugs.md` BUG-362（R36 landed 行内 R37 追记）、`memory/2026-10-21.md` R37。
- 决策稿：`docs/decisions/2026-10-21-json-value-430-decision.md` §3.5（量程实测）、§3.6（本单固化）。
- 上游结论：BUG-362 建议②（R35 棘轮入 CI）、建议③（R36 三向普查）；BUG-360（utf8/`to_bytes` 验签洞，被族表第二条钉住进度）；BUG-361（`Json::value` 五案待裁决）。
- FIST：根任务 T0r18（`temp/t18_drive.py`，六格全 rc=0）。
