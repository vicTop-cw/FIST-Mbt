# R15 组合模式 · 高风险持久层扫描 + 发现规则级真缺陷 BUG-346（pattern 与意图相反）

- 日期：2026-10-20
- 模式：寻虫（bugfind）
- 轮次：R15 / 256（目标 ACTIVE，未关闭）
- 结论：**扫 `src/store`（SQLite 持久层，7 文件 / 954 命中 / high=0 medium=0）→ 发现规则级真缺陷 BUG-346**：`moonbit-json-injection` 的 `pattern: ["Json::string("]` 匹配的恰是安全构造器，与 `why`/`hint` 描述的"拼接注入"完全相反，全 MoonBit 命中恒假阳；且 L2209 白盒锁把该规则锁定为常驻暴露。已上报 OPEN。
- 来源：R14 蓝本 `reports/2026-10-20-r14-bug345-fix-blueprint.md`

## 1. 并发状态复查（R15）
- 工作树脏 **205**；`src/server` 脏 **37**，与 R14 逐字节一致（无并发 commit 落地，`git log` 顶部仍全是我自己的报告 commit）⇒ BUG-327/333/345 三项修复**继续阻塞**。
- 归我的 OPEN：BUG-327 / 333 / 345（均 server 层）+ 本轮新增 **BUG-346**。

## 2. `src/store` 扫描（SQLite 持久层，最高风险面）
| 指标 | 值 |
|---|---|
| scanned_files | 7 |
| total_findings | 954 |
| high / medium | **0 / 0** |
| low | 954 |
| by_rule 前五 | result-discard 236、long-function 203(info)、match-exhaustive 204、unused-variable 195(info)、json-injection **45** |

high/medium 再次为 0 ⇒ 再次印证：**issue_scan 的内建+外部 low/info 规则对 MoonBit 近似无精度**（R11 复扫 430 命中、R13 复扫 364 命中、本轮 954 命中，均 high/medium=0）。可判读信号必须依赖 BUG-345（四桶分档）+ BUG-333（规则精度）修复。

## 3. **BUG-346 · 规则 pattern 与意图完全相反**（本轮真发现）

### 3.1 三处自相矛盾（`src/server/issue_scan.mbt:257-262` 逐字）
```moonbit
{
  id: "moonbit-json-injection",
  severity: "low",
  pattern: ["Json::string("],                 // ← 匹配的是安全 JSON 构造器
  why: "JSON 字符串由拼接构造，可破坏 JSON 结构", // ← 描述的是字符串拼接
  hint: "用 Json::object 构造或转义特殊字符",     // ← 叫用户用 Json::string/Json::object 构造
},
```

- **pattern 所匹配的 `Json::string(...)` 恰恰就是 `hint` 推荐的安全做法** —— MoonBit 惯用法是 `Json::object({...})` + `Json::string(...)` 构造，无裸字符串拼接。
- 真正的注入向量（`"..." + x` 裸拼接）在 pattern 里**根本不存在**。
- 因此该规则对 MoonBit 代码命中率 **100% 假阳** —— 结构上不可能命中真注入。

### 3.2 实测证据（release v0.3.9，`issue_scan src/store`）
json-injection 计 **45 条**，逐条抽查全部是安全构造，无一为拼接注入：
- `multi_store.mbt:179` `item.set("ns", Json::string(ns))`
- `store.mbt:113/120/164/165/167/168/169/208` `Json::string(self.lock_id / batch_id / scope / agent / mode / registered_at / heartbeat_at / status / ts)` …

由于 pattern 是字面量 `Json::string(`，**每条命中必然就是该构造器** ⇒ 45/45 假阳，数学上不可能有例外。

### 3.3 叠加风险：白盒锁把坏规则钉死
`src/server/issue_scan.mbt:2209`：
```moonbit
assert_false(scan_denoise_default_skip("moonbit-json-injection"))
```
断言该规则**不在**默认降噪跳过集 ⇒ 视为"应当常驻暴露的真规则"。这把一个 100% 假阳规则结构性锁定在结果里。L1876 注释自述该类高频命中文件需反复读盘（json-injection ~1334 条），放大 BUG-333 的量噪（72.7%）。

### 3.4 已上报
`report_bug` → **BUG-346**（OPEN，medium，reported_by=polish-lead），detail 含修复方向：
- ① 把 pattern 改成真正的拼接注入形状（裸 `+ x +` / `\" +` 拼接），或
- ② 把 `moonbit-json-injection` 加入默认降噪跳过集 + 同步改 L2209 白盒锁断言为 `assert_true`
- ①② 与 BUG-345（四桶）**独立可并行**；修完用 A/B（src/store）验证：走②则 json-injection 命中 45→0，走①则从假阳命中转为真命中。

## 4. 修复队列全景（归我，全部待 `src/server` 清空）
| BUG | 性质 | 修复点 | 状态 |
|---|---|---|---|
| BUG-346 | 规则 pattern 反转（100% 假阳 + 白盒锁钉死） | issue_scan.mbt:257-262 + :2209 | 蓝本已定（本轮） |
| BUG-345 | by_severity info→low 四桶 | issue_scan.mbt:1962-2011 | **蓝本 drop-in 就绪**（R14） |
| BUG-333①③ | --min-severity 过滤 / 默认降噪锁 | issue_scan.mbt + wbtest | 蓝本 §3.2-3.4（R14） |
| BUG-327 p2 | ocr_scan unsupported_ext | ocr_scan.mbt | 待定 |

落地顺序建议：**BUG-346 ② + BUG-345 + BUG-333①③ 同一批收口**（都动 issue_scan 聚合/规则表，一次 `moon test --target js` 全量验证），避免反复改同一文件。

## 5. 资源消耗
- 调用：`pwsh`（git 状态）、`issue_scan(src/store)` ×1、`grep`（json-injection）、`read`（规则定义）、《`report_bug`（BUG-346）
- 新增 commit：本轮报告（未改任何 `src/*`，未 `git add -A`）

## 6. 遗留风险
1. 4 项修复全阻塞于 `src/server` 37 脏（含 `issue_scan.mbt`、`issue_scan_wbtest.mbt`）。
2. `moonbit-json-injection` 在修 BUG-346 前会持续注入 ~1334 条假阳，污染 by_rule/总量读数，任何基于 issue_scan 的定量结论都应剔除该规则。
3. `git status -- src/server`（目录 pathspec）计数不可靠，判据须用全量 porcelain 过滤（R14 §1）。

## 7. 后续建议
- 窗口一开：按 §4 顺序一次落地 BUG-346② + BUG-345 + BUG-333①③；`moon fmt` → `moon test --target js`（权威门槛 1347/1347，看 `Total tests: N, passed: N, failed: 0`，不看 exit 0——BUG-142）→ 回填账本。
- 修完跑 A/B 三连：`src/store`（BUG-346 靶）、`src/ltl` + `rules_file=memory/bug333_denoise_rules.json`（BUG-345/333 靶），断言 low 下降 + info 键出现 + json-injection 命中归零。

## 来源
- `src/server/issue_scan.mbt` L255-262（规则定义）、L1876、L2209（白盒锁）—— 读源逐字
- `issue_scan src/store` 回执（954 命中，by_rule json-injection=45）
- R14 蓝本报告（BUG-345 四桶补丁）
