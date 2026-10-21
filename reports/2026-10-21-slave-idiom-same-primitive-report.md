# 2026-10-21 · R33 · slave/fix/idiom-same-primitive-renames（PR #20）

## 结果摘要
- 目标：清掉 0020 弃用面剩余机械族里**唯一能用硬证据判等价**的一类——「同一原语改名族」。准入判据不是名字新旧，而是 core 里弃用声明与现行声明绑定同一条后端 primitive，因而 codegen 逐字节不变。
- 范围：`UInt64::to_int64` → `UInt64::reinterpret_as_int64` 11 处（`src/server/server.mbt` 6、`src/server/mcpcf_embed.mbt` 3、`src/server/model_router_ops.mbt` 2）+ `Char::from_int` → `Int32::unsafe_to_char` 1 处（`src/router/router_caf_ext.mbt:116`）+ 1 处注释事实修正（`src/server/mcp_config_scaffold.mbt:149`）。
- 净效果：判据面 **501 → 489 warnings / 0 errors**，0020 命中 **460 → 448**（这两族 11+1 → 0），其余族一格未动；测试面 **1302/1302/0**；发布入口 `cmd/cli` 构建 rc=0；零 `.mbti` 变更、零接口变更。
- 超额：普查 `String::to_bytes` 三处弃用点的过程中，用临时探针实测出当前工具链的 `String::to_bytes()` 是 UTF-16LE，与 `attest.yml` 的 UTF-8 签名面不兼容 ⇒ star-gate 对真 attestation 必然验签失败。按金条四只入账（BUG-360 OPEN / medium），三条出路写清代价，不自决开修。

## 资源消耗
- 主代理轮次：1 个目标轮内完成（primitive 同一性取证 → 改写设计与边界判定 → 批量落盘 → moonfmt 正字法回合 → 判据/测试/构建三面实测 → 探针取证 → 守卫全套 → FIST 生命周期 → 记账与投影）。
- 实跑：`moon check --target js --json` 3 次（中间一次用于确认 `.mbti` 与 error_code 分布）、`moon test --target js -j 1` 2 次（改前基线 + 改后 `temp/pt20b.log`）、`moon build cmd/cli --target js` 1 次、只读 `moonfmt.exe` 逐文件 D0/D1 对比 5×2 次、白盒探针 `moon test` 2 次（首版 `abort` 只吐栈不吐读数，改用 `inspect` 强制快照 diff 才拿到测量值）、守卫/自检 20 支。
- FIST 记账：execute 记录 tokens-in 196,000 / tokens-out 18,400 / cost 0.52 / duration 780,000 ms（模型 qoder-agent）。

## 任务分配记录
- T0r14（根任务，第 16 次连续完整生命周期）：publish → claim → execute → submit → verify 全通过，状态 已完成。
- 子代理：无。本单元的核心风险在「哪 12 处可以改、哪 11 处绝不能顺手改」，判据是 core 的 primitive 绑定关系，交子代理容易把重载名 `to_int64` 一起扫掉。
- 批量工具：`temp/fix33.py`（13 处替换：dry-run 先行 + 逐站点断言命中次数 + `FORBIDDEN` 禁串自检 + CRLF 按原文件判定回写）、`temp/fmt30.py`（复用上一轮的 D0/D1 分歧尺，自 `git diff --name-only` 取文件集）、`temp/t14_drive.py`（FIST 生命周期）。

## 遗留风险
1. **BUG-360（OPEN，medium）**：`src/router/star_gate.mbt:302` 用 `canonical.to_bytes()` 当验签消息，而工具链的 `String` 内部是 UTF-16LE（探针：本轮 canonical 样例 57 字符 → 114 字节；`abc` → 6 字节、b0=97、b1=0）；生产侧 `.github/workflows/attest.yml:105-107` 与 `:168-172` 都按 UTF-8 签。两侧字节序列不可能相等 ⇒ 配了期望公钥的 star-gate 对真 attestation 必然判 BadSignature。方向是 fail-closed（不会伪造通过），所以是功能洞不是安全洞；但**这条门禁在真实数据面上从未成立过**。仓内 wbtest 与产品共用同一 `to_bytes`，签名/验签两侧同错 ⇒ 1302 条测试测不穿（测试镜像实现型盲区）。三条出路连同代价已入账，首选 (a)：验签侧改 `@encoding/utf8.encode` + 用 Node/Python 生成跨实现 KAT 钉住 UTF-8 已知答案。本单未复核 Pages 上是否已有真签名、也未复核该门在流水线里是否真被调用。
2. **0020 主体未动**：余 448 里 `Json::value` 占 430（82%），包内私有辅助 vs 逐点模式匹配属 owner 决策（先例：PR #15 的 `mcpcf_embed.mbt` 私有辅助形态）。
3. **`Int`/`Int32` 拼写漂移（BUG-330）仍在**：本轮亲历一次——照仓内先例写 `Int::unsafe_to_char` 被 moonfmt 规范化回 `Int32::` 并判为新增分歧。任何手写 `Int::` 的调用点都可能重演，建议单独一轮普查统一正字法。
4. **本机工具链限制不变**：`moon fmt` / `moon info` / `moonc` 仍 ICE，格式化与 `.mbti` 只能走只读 `moonfmt.exe` 与 `moon check/test/build`；因此本仓的「零新增分歧」是按 D0==D1 的只读尺定义的。
5. `check_host_installable` 的结构性红（BUG-358）本单未触碰；`cleanup_artifacts --check` 仍按既往裁决故意 DIRTY。

## 后续建议
1. 下一单元优先按 BUG-360 出路 (a) 收 star-gate：一次改动同时清掉 0020 的 3 处 `String::to_bytes` 与这条功能洞，并补一支不镜像实现的跨实现 KAT。
2. 然后回到 0020 主障碍：`Json::value` 430 条的**决策稿**（包内私有辅助 vs 逐点模式匹配，含 diff 体量对比），请指挥官二选一后铺开——这是通往「零 WARNING」的唯一大件。
3. 0020 零散族按「一处一判」继续：Show→Debug 8+3（快照承载，需 `moon test --update` 决策）、FFI `Array`→`FixedArray` 3、隐式提升 1（`src/executor/mcp_delegate.mbt:71`）。
4. owner 决策清单继续挂：BUG-354 的 10 条 `~`/`?` 参数、0078 残 3、0027 残 1（`StarVerdict`）、死码族 0001/0006/0007/0009、BUG-330 `Int`/`Int32`、`docs/agent-map.md:12` 的「工具数 104」vs 真源 170。

## 超额内容
- 交出本会话最重要的一条产品级缺陷取证（BUG-360）：探针实测 + core 源码背书 + 生产/消费两侧行号，并说明为什么现有测试必然看不见它。
- 把一条「判据不红、但会教错下一个读者」的注释失真（`mcp_config_scaffold.mbt:149` 对 core API 面的错描述）就地修正。
- 把 moonfmt 正字法与仓内旧先例的冲突固化成一条判据：新增分歧尺（D0/D1）优先于「照抄仓内写法」。

## 来源
- 等价性真源：`~/.moon/lib/core/builtin/int64.mbt:1199-1201` vs `:1222`（同为 `%u64.to_i64_reinterpret`）、`~/.moon/lib/core/builtin/intrinsics.mbt:1353-1354` vs `:1625-1626`（同为 `%char_from_int`）、`~/.moon/lib/core/builtin/char.mbt:436-438`（core 自家 `unsafe_to_char` 惯用法）、`~/.moon/lib/core/builtin/string.mbt:364-366`（UTF-16 code units little endian）
- 改动面：`src/server/server.mbt`（6 处）、`src/server/mcpcf_embed.mbt`（3 处）、`src/server/model_router_ops.mbt`（2 处）、`src/router/router_caf_ext.mbt:116`、`src/server/mcp_config_scaffold.mbt:149`；仓内先例 `src/omega/spec.mbt:316`
- 取证面：`temp/chk37.json`（501/0 改前基线）、`temp/chk39.json`（489/0 改后，error_code 分布）、`temp/pt20b.log`（1302/1302/0）、`temp/build20.log`（rc=0）、`temp/probe_enc.log` + `temp/probe_enc2.log`（UTF-16LE 测量：`str_len=57 bytes_len=114 abc_len=6 abc_b0=97 abc_b1=0`）、`temp/g33/*.log`（20 支守卫输出）
- 编码不一致的另一侧：`src/router/star_gate.mbt:78, 264, 302`、`.github/workflows/attest.yml:105-107, 168-172`
- 上一轮伏笔：`memory/bugs.md` BUG-358「后续建议」（CI 面最后一条真红，本单未动）、BUG-330（`Int`/`Int32` 漂移）
- FIST：`temp/fist-selfiter.db` 任务 T0r14
