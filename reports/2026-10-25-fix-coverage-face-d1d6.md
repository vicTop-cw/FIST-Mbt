# 修复报告：把 D1–D6「单值写死型」并入 `check_coverage_face.py`

> **任务**：把侦察产出 D1–D6 落成常驻判据（「修」，非侦察）
> **日期**：2026-10-25 · **执行者**：audit-preservation
> **改动面**：`scripts/check_coverage_face.py`（+D1–D6 层）、`scripts/README.md`（同批登记）
> **未改**：`scripts/` 下其它任何文件；未新增 `scripts/*.py`（避判例-5）

---

## 一、结论

**D1–D6 已作为「单值写死型」正交补充并入，现有清单型逻辑一行未改。**

| 项 | 修前 | 修后 |
|---|---|---|
| `--selftest` | **20 格** rc=0 | **58 格** rc=0（默认形态）；`--strict` 形态 58 格也 rc=0 |
| 覆盖面 | 只有清单型（模块级常量序列） | 清单型 **+** 单值型（D1–D6） |
| 本仓实跑 | 可能窄 4 条 | 可能窄 4 条；**单值写死型 0 条**（与侦察结论一致） |
| 电池读数 | `rulers=120 ci=45 battery=79 missing=0 gate=87` | **完全一致**（未变） |
| 退出码签名 | `verdict_rc(n_guards, n_indexed)` | `verdict_rc(n_guards, n_indexed, n_hard)`（**默认行为不变**：非 strict 仍只出数） |

---

## 二、六道判据的落地形态

| # | 判据 | 实现 | selftest 格 |
|---|---|---|---|
| **D1** | 比较形态 `== / != / startswith / endswith / in (` | `extract_single_values()` | `d1-cmp-{eq,ne,starts,ends,in}` ×5 + 变异格 ×2 |
| **D2** | 像配置值（含 `- _ / .` 或长度 ≥6） | `_looks_like_config_literal()` | `d2-config-like` / `d2-short` |
| **D3** | 非协议字面量（扩展名/语言名/状态标签） | `D3_PROTOCOL` 表（**set**，为变异格留还原位） | `d3-{extension,status,protocol,regex-frag}` + 变异格 ×2 |
| **D4'** | 该值是**真源面的当前值**，且非枚举标签形状 | `_is_source_value()` + `_SOURCE_FACE_GLOBS` | `d4-*` ×7（含 2 个变异格） |
| **D5** | 反店：排除出现在 ≥30% 判据里的通用词 | `judge_single_values()` 内 | `d5-*` ×3（含变异格） |
| **D6** | **无自拒保护**（决定性） | `has_self_refusal()` + `_is_pure_predicate()` | `d6-*` ×6（含变异格 + 实现面锁） |

### D6 的两处实跑修正（这是本轮最重要的过程）

**首版实跑发现 35 条 🔴，逐条核查后全是假阳性。** 修了两次：

| 修正 | 假阳性根因 | 修法 |
|---|---|---|
| **一：纯谓词豁免** | `check_diff_scope.is_contract(path)` 是「路径是不是契约面」的**形状定义**（只做分支/返回、不碰 IO），被判成「写死 + 无自拒」 | 加 `_is_pure_predicate()`：无 IO 依赖 + 判定性函数名 ⇒ 豁免。**理由：形状定义的真源就是代码本身，没有外部真源可比对** |
| **二：D4' 收窄** | 首版 D4 只要「该值在任意其它文件出现过」就算真源，于是 `'comment'` / `'contract'` / `'MISSING'` / `'extern'` 这类**语义枚举标签**因出现在 `docs/` 里被当成真源值 | D4 改为 D4'：必须在**真源面**（`moon.mod` / `scripts/README.md` / `plugins/source/` 等）+ **不是枚举标签形状**（单小写词/驼峰/全大写常量名）+ 含分隔符或够长 |

**修正后 35 → 0 条**，与侦察报告「0 个真缺陷」一致。

---

## 三、判例-50 变异验真（DS 变异，每处改坏对应格必须红）

**复现命令**：`python temp/scout/mutation_verify.py`

```
基线：rc=0  FAIL 格=0

### MUT1 D6 自拒降级失效
  变异生效：True
  ✓ SELFTEST FAIL d6-with-refusal-is-ok-refused: got=[('shared-config-value','hard')]
                                              want=[('shared-config-value','ok-refused')]

### MUT2 D4' 真源面失效
  变异生效：True
  ✓ SELFTEST FAIL d4-no-elsewhere: got=1 want=0
  ✓ SELFTEST FAIL d4-mutation-no-source-face-no-report: got=[{…'verdict':'hard'…}] want=[]

### MUT3 D3 协议表失效
  变异生效：True
  ✓ SELFTEST FAIL d3-protocol: got=True want=False

还原后：rc=0  FAIL 格=0  ✓
变异验真总判定：全部通过 ✓
```

**判例-50 的三个要求都满足**：
1. **变异真的改变了被测行为** —— 每个变异都先打印「变异生效：True」再跑判据；
2. **改坏的是代码不是注释** —— 三处替换点都在实现函数体内（`has_self_refusal` 的 `if m:`、
   `_is_source_value` 的 `on_source_face` 判定、`_looks_like_config_literal` 的 D3 表查）；
3. **还原后核对** —— 还原后 selftest 恢复全绿，且 `git status` 该文件只剩我**已声明的 540 行新增**（见 §四）。

> **MUT2 第一次没抓对格**（我按「期望为 1」的格去找，但 D4' 改坏后变阳性的是「期望为 0」的负样本格）。
> 修正验证脚本后命中两格。**这是「机制格 ≠ 实现路径格」的又一实例**：验真脚本本身也要对齐。

---

## 四、验收六项

| # | 验收项 | 结果 |
|---|---|---|
| ① | `--selftest` rc=0 | ✅ **rc=0**（58 格） |
| ② | selftest 输出里 D1–D6 每条都有变异格 | ✅ D1×2 / D3×2 / D4'×2 / D5×1 / D6×3（含实现面锁及其变异） |
| ③ | 加完 D1–D6 后现有电池读数不变 | ✅ `rulers=120 ci=45 battery=79 missing=0 gate=87` **逐键一致** |
| ④ | `check_battery_count_doc.py` PASS | ✅ PASS rc=0 |
| ⑤ | `git show --stat` = 预期文件数 | 见提交回执（2 文件：判据 + README 登记） |
| ⑥ | 三端一致 | 见提交回执 |

**附加门禁**（我主动多跑的，防「改这个把别处弄红」）：

```
check_scripts_index.py          PASS rc=0
check_selftest_inventory_doc.py INVENTORY_SYNC=clean rc=0
check_doc_surface.py            PASS rc=0
```

---

## 五、缺口与风险

### 5.1 本判据仍「只报不判」

D1–D6 与清单型一样**默认 rc=0**（只出数），`--strict` 下才把 🔴 判红。
⇒ **它进了电池但不会自动拦住新引入的单值写死**，要拦得让电池那条 case 带 `--strict`。
**这是设计选择不是遗漏**：报「该不该反解」要人读语义，自动判红会重演「为了绿而放宽判据」。
**若要升档为硬门，需 owner 裁决**（会改变电池读数语义）。

### 5.2 D4' 的真源面是**清单**

`_SOURCE_FACE_GLOBS` 是 7 个具体文件的**清单** —— 按本判据自己的判例-16 标准，
**这是「元判据自己犯被判例-16 的病」**。

**诚实标注**：本轮没把它改成反解，因为「哪些文件算真源面」是**语义判断**（`docs/` 算不算？
`templates/` 算不算？），反解不出来。**这是本判据已知的窄面。**
缓解：清单一旦漏了某个真源文件，只会**漏报**（少抓），不会**误报**——方向是安全的。

### 5.3 未覆盖

- **`--selftest` 内部的单值写死**：那类写死是夹具本意（固定期望值），不该报。
- **跨文件常量**：判据 A 写死值、真源在判据 B 里 —— D4' 只用「真源面」判定，没做判据间溯源。
- **数值真源**：侦察已单独补测（0 命中），本判据**未**并入该面。

---

## 六、复现命令

```bash
# 判据自检（默认 / strict 两形态）
python scripts/check_coverage_face.py --selftest
python scripts/check_coverage_face.py --selftest --strict

# 实跑（清单型 + 单值型）
python scripts/check_coverage_face.py
python scripts/check_coverage_face.py --strict     # 有 indexed 或 🔴 则 rc=1
python scripts/check_coverage_face.py --json

# 判例-50 变异验真
python temp/scout/mutation_verify.py

# 反向对照：证明判据真能抓真阳性（不是「一律 0 条」）
python temp/scout/probe_guard.py
```

---

## 七、来源

| 角色 | 贡献 |
|---|---|
| 统帅 | 派单（把侦察产出落成常驻判据）、验收六项、「别新增 scripts/*.py」提醒 |
| `reports/2026-10-25-scout-audit-single-value-hardcode.md` | D1–D6 初始定义、11 条候选的降级依据 |
| 判例-29/30/50 | 变异对照必做、改代码不改注释、变异要验真生效 |
| 判例-16 | 本判据自身的存在理由（尺的覆盖面）—— §5.2 是它对本判据的自指 |
| 本执行组 | D4→D4' 与纯谓词豁免两次实跑修正（35 假阳性 → 0）、MUT1–MUT3 变异验真 |
