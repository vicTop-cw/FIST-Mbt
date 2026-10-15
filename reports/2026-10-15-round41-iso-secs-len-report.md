# Goal-2 Round 41 报告：iso_to_secs 长度与分隔符边界契约锁（issue_scan 寻虫产出）

- **日期**：2026-10-15
- **提交**：R41 code（`src/router/model_router_ts_len_test.mbt`，1 文件 +62，HEAD `050f73d`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9），本轮用 fist-mbt 自身能力寻虫

## 结果摘要

### 寻虫工具双轨实测（善用 fist-mbt 能力）

| 工具 | 结果 | 结论 |
|---|---|---|
| `issue_scan src/router` | 13 文件扫出 **673 findings**（`possible-overflow` 7 / `string-index` 3 / 数组下标 58 等，全 low/info） | 正则近似**无上下文分析**，高假阳性 |
| `ocr_scan src/router` | `reviewable_count=0`，32 文件全 `exclude_reason: unsupported_ext` | OCR CLI 不支持 `.mbt`，**不可用** |

### 复核最高价值 finding：`model_router.mbt` L487-492

`issue_scan` 命中 `dig[0]*1000 + ... + dig[18]`（`string-index` + `possible-overflow`）。
**复核真源**：
- L455 `if cs.length() < 19 { return -1 }` → **长度已防御**
- L464-472 `digit_idx` 检查所有关键下标非负 → **非负已防御**
- L500 `y∈[1970,2037]` → **BUG-218 已修**

**结论**：该 finding 是**假阳性**（dig 值 ≤9，`dig[0]*1000` 最大 9000，乘积不溢出 Int）。

### 但防御本身缺锁 → 补锁（寻虫实质产出）

现有锁 `rt_2b`（Y2038 边界）只测**合法输入**与 2038 溢出，**未测「长度 <19」防御**。若未来有人删掉 L455 守卫，`dig[18]` 会越界 panic，而现有锁**不会红**（都喂合法输入）。补 6 条边界锁：

| 锁 | 钉死的契约 |
|---|---|
| `caf_ts_1_空串返回-1` | `iso_to_secs("") == -1` |
| `caf_ts_2_长度不足19返回-1` | `iso_to_secs("2037-12-31T00:00:0") == -1`（真 18 字符） |
| `caf_ts_3_非时间戳返回-1` | `iso_to_secs("not-a-timestamp") == -1` |
| `caf_ts_4_合法时间戳返回正数` | `iso_to_secs("2037-12-31T00:00:00Z") > 0` |
| `caf_ts_5_分隔符错返回-1` | `iso_to_secs("2037 12-31T00:00:00Z") == -1` |
| `caf_ts_6_19字符无Z后缀合法` | `iso_to_secs("2037-12-31T00:00:00") > 0` |

### 一轮测试先红后绿（有价值教训）

初次 `caf_ts_2` 用 `"2037-12-31T00:00:00"` **红**——它不是 18 字符，而是 **19 字符**（`YYYY-MM-DDTHH:MM:SS` 精确 19），
是**合法完整格式（无 Z 后缀）**。`L455 length()<19` 放过 19，继续解析 → 返回正数。
这是**我的测试预期错，非源码 bug**。修正为真 18 字符 `"2037-12-31T00:00:0"`，并把 19 字符场景保留为
`caf_ts_6`（补 rt_2b 只测 20 字符带 Z 的盲区）。

### 验证

router **189/189**（R40 基线 183 + 6 锁）；全仓 **1196/1196**，0 failed。`.mbti` **无变化**。

## 资源消耗

`issue_scan` / `ocr_scan`（扫 src/router）/ `moon fmt` / `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新测试文件独占。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，工作树 94 文件）。
- **`ocr_scan` 对 MoonBit 仓库不可用**：CLI 只识别常见扩展（`.rs/.ts/.go` 等），`.mbt` 全部 `unsupported_ext`。
  → 寻虫面只剩 `issue_scan`（正则近似）+ `boundary_probe`（边界输入）+ 人工复核。**建议后续考虑为 `.mbt` 补 OCR 支持**
  （属并发 agent 的 ocr_scan 域）。
- **`issue_scan` 假阳性率高**：673 findings 全 low/info，实际复核最高价值候选为假阳性。**建议把 finding 当线索而非结论**，
  必须复核真源上下文。

## 后续建议

1. **R42 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。
2. **R42 备选**：用 `boundary_probe` 对 `issue_scan` 的 `string-index` finding 生成边界输入，
   喂 `run_check` 真实验证（三段闭环「扫描 → 边界构造 → 真实验证」）——本轮已复核为假阳性，
   但**流程**值得走一遍以验证探测链可用。
3. **R42 备选 2**：CAF 记忆容量淘汰不变量锁——现有锁只钉 `all()≤max_size`，未钉「淘汰后 FIFO 连续」。
4. **R42 备选 3**：`caf_feature_hash` 归一化——接线时 trim + lowercase 再 hash，避免 "python" vs "python " 碎片化。

## 超额内容

**时间戳格式的隐性契约**：`YYYY-MM-DDTHH:MM:SS` 无 Z 后缀时正好 **19 字符**，`L455 length()<19` 的语义是
「**允许 19（无 Z）和 20（带 Z）两种合法形状**，拒绝 18 及以下」。这解释了为何 `iso_to_secs("2037-12-31T00:00:00")`
返回正数——它不是"漏了 Z 的残缺"，而是合法完整格式。此契约此前**无锁**（rt_2b 只测 20 字符带 Z），R41 补上。

## 来源

- `issue_scan` findings（`model_router.mbt` L487-492）
- 真源复核：`src/router/model_router.mbt` L455-504
- 新增：`src/router/model_router_ts_len_test.mbt`
- 参考：`src/router/model_router_wbtest.mbt` L58-60（`rt_2b` Y2038 边界）
