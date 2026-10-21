# 2026-10-21 · R32 · slave/fix/docs-surface-current-state-sync（PR #19）

## 结果摘要
- 目标：把「现状面自述滞后真源」这一类 CI 预存红一次收口，并普查出同类未收口项入账。
- 范围与性质：测试总数面 21 处（AGENTS / ARCHITECTURE / README.mbt / README / README_EN / docs-SOP / agent-map / deliverable / scoring_rubric，漂在 1058 / 1112 / 1108 / 1260 四个数上）、豁免与夹具面（`check_test_sync.py` 新登记 3 条 EXEMPT + 补 8 条夹具声明）、入口面 1 处（SOP 部署路径指退役 `cmd/main`）、版本面 2 处（USAGE 自述 0.3.8、README 资产名 v0.3.8.zip）、索引面 1 处（`run_check_t0r21.py` 未登记）。
- 净效果：**7 个 CI 步骤由红转绿**（Badge consistency / Test-count single-source / Test-count guard selftest / Doc-surface / Scripts-index / Entry-list / Release asset-name）。其中 `check_test_sync --selftest` 此前直接判红，意味着它的 8 支判据对照在 CI 上从未真跑过——本单把它恢复成可执行判据。
- 零代码面改动：无 `.mbt` 变更、`.mbti` 未动，判据面 501 warnings / 0 errors 与测试面 1302/1302/0 不变。

## 资源消耗
- 主代理轮次：1 个目标轮内完成（性质分流 → 真源实测 → 批量对表 → 判据夹具修复 → 三格版本/入口/索引 → 守卫全量复跑 → FIST 生命周期 → 记账与投影）。
- 实跑：`moon test --target js -j 1` 1 次（产出本轮真源读数）、`moon build cmd/cli --target js` 1 次（rc=0）、守卫/自检 20+ 次（含 4 支由红转绿后的复跑与 12 支无回归复跑）。
- FIST 记账：execute 记录 tokens-in 148,000 / tokens-out 15,200 / cost 0.39 / duration 660,000 ms（模型 qoder-agent）。

## 任务分配记录
- T0r13（根任务，第 15 次连续完整生命周期）：publish → claim → execute → submit → verify 全通过，状态 已完成。
- 子代理：无。本单元的核心工作量是**逐格判性质**（改文档 / 走豁免 / 修夹具 / 登记历史脚本），不是搜索或批处理，交子代理会把判据语义做丢。
- 批量工具：`temp/fix32.py`（21 处替换，逐条断言命中数 + CRLF 保真 + dry-run 先行）、`temp/t13_drive.py`（FIST 生命周期）。

## 遗留风险
1. **BUG-358（OPEN，medium）**：`check_host_installable.py` 把未跟踪件 `.mcp.json` 列为「缺件即自拒」的关键输入（`LENIENT_JSON` → `missing_key_files()`），而 `.gitignore:65` 明写它不跟踪 ⇒ 干净检出上这一步必 `FATAL` rc=2，**deepseek-harness / Claude 宿主安装门在权威 CI 面上从未执行过一次真判定**。三条出路已写进账本（首选 (a)：候选序列跟踪面优先，与 BUG-131 同口径）；动的是判据输入面语义，按金条四留指挥官定夺，本单只入账不自决开修。
2. **散文数字仍会漂**：`docs/agent-map.md:12` 写「工具数 104」而真源 170，`check_tools_sync` 的注册面判据抓不到这句；现状面共 121 份文档由人写数字，判据只能覆盖窄口径命中的那些。根治要把数字改成投影生成，动 README/AGENTS 结构，属 owner 决策。
3. `EXEMPT` 表与 selftest 夹具是**两份手写清单**，天然会再漂（本轮修的就是上一轮的漂移）。若下一轮再登记豁免，必须同步写夹具声明，否则 `baseline-clean` 又被 R4 判红——这条已写进夹具注释。
4. `cleanup_artifacts --check` 仍 DIRTY：`_build` 生成物按既往裁决故意保留（不是本轮引入）。
5. 本机工具链限制不变：`moon fmt` / `moon info` / `moonc` 仍 ICE，格式化与判据只能走只读 `moonfmt.exe` 与 `moon check/test/build`。

## 后续建议
1. 下一单元优先按 BUG-358 出路 (a) 修 `check_host_installable` 的输入面（并顺手普查其余 `check_*.py` 有没有同类「未跟踪件当关键输入」形状），目标是把 CI 面最后一条真红清零。
2. 然后回到 0020 主障碍：`Json::value` 430 条的**决策稿**（包内私有辅助 vs 逐点模式匹配，含 diff 体量对比），请指挥官二选一后铺开——这是通往「零 WARNING」的唯一大件。
3. 0020 零散族按「一处一判」继续：`reinterpret_as_int64` 11 / Show→Debug 8+3 / `utf8.encode` 3 / FFI `Array`→`FixedArray` 3 / `Int::unsafe_to_char` 1 / 隐式提升 1。
4. owner 决策清单继续挂：BUG-354 的 10 条 `~`/`?` 参数、0078 残 3、0027 残 1、死码族 0001/0006/0007/0009、BUG-330 的 `Int`/`Int32` 拼写漂移。

## 超额内容
- 顺手普查出并入账一条**新的 CI 真红**（BUG-358），它不在本单目标里、也不是本轮引入。
- 把 3 处「判据抓不到但用户在读」的散文数字（EN 徽章、`the 1112-test JS suite`、`check_test_sync (1112 aligned`）一起对表——判据不红不等于文档不谎。

## 来源
- 真源读数：`temp/pt19.log`（本轮 HEAD 上 `moon test --target js -j 1` 实跑，`Total tests: 1302, passed: 1302, failed: 0`）、`moon.mod:14`（`version = "0.3.9"`）、`README.md:110`（入口 `cmd/cli … serve`，裸跑只打印 help）
- 判据面：`scripts/check_test_sync.py`（R1~R4 与窄口径正则、EXEMPT  prescribed 用法）、`scripts/check_host_installable.py:91,324-328`（`LENIENT_JSON` 与 `missing_key_files`）、`.gitignore:62-65`（根 `.mcp.json` 不跟踪的裁决注释）
- CI 面：`.github/workflows/ci.yml` 第 85 / 93 / 97 / 101 / 105 / 112 / 152 / 179 / 191 行（各守卫步骤的调用形态与是否 continue-on-error）
- 上一轮伏笔：`memory/bugs.md` BUG-356「后续建议」②（预言本单要做的 5 份文档同步）
- FIST：`temp/fist-selfiter.db` 任务 T0r13
