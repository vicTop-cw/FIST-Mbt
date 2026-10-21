# `Json::value` 430 处：三案量尺实测与请指挥官定夺

- 日期：2026-10-21
- 现状指针：本文件是**决策稿**（只出量尺、不动实现），属历史/计划面快照，不参与现状面对表
- 基线 commit：`e209e51`（分支 `slave/fix/idiom-same-primitive-renames`，PR #20）
- 证据脚本（全部可复跑，本机 `moon check --target js`）：`temp/analyze_jsonvalue.py`、`temp/gap_census.py`、`temp/gap_census2.py`、`temp/probe_dup_helper.py`、`temp/probe_dup_helper2.py`、`temp/pilot_a.py`、`temp/pilot_abc2.py`、`temp/pilot_b_only.py`、`temp/fmt30.py`
- 读数字物：`temp/chk39.json`（基线）、`temp/chk_cold.json`（`moon clean` 后）、`temp/chk_pilot2.json`、`temp/pt_pilotA.log`

---

## 1. 为什么这一族要单独出决策稿

0020 弃用面现存 448 条，其中 `Json::value` 一族占 430 条（95%）。前三次清弃用族（`not(x)` 203、切片 42、布尔/字符串访问器 22、同一原语改名 12）都能**逐字机械改名**，判据面直接掉数、测试面不动。这一族不行：

- core 的弃用文案 prescribed 的是**一个表达式形态**，不是一个可替换的方法名；
- 落地形态至少有三种，三者的 diff 体量、格式化后果、能否机械批处理完全不同；
- 站点 430/441 处跨 53 个文件、9 个包，其中 300 处在黑盒测试文件里 —— 黑盒作用域看不到包私有件，这是结构性约束而不是口味问题。

按金条四，动的是全仓惯用法基线（要不要引入一个私有辅助件、放哪、叫什么），属架构决策 ⇒ 本单元只做量尺与摊牌，选择权留指挥官。

---

## 2. 真源语义（实测）

`~/.moon/lib/core/json/json.mbt:79-86`：

```
#deprecated("Suggestion: `if json is Object(obj) { obj.get(key) } else { None }`")
pub fn Json::value(self : Json, key : String) -> Json? {
  if self is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}
```

三条要点：

1. **没有任何语义可换**：弃用体的实现就是 prescribed 表达式本身，`Json::value` 与 `if j is Object(obj) { obj.get(k) } else { None }` 逐字等价（同 `is` 模式、同返回类型 `Json?`、非对象即 `None`）。所以本族的收口判据只能是「判据面不再报」，不存在「改成另一语义」的风险面 —— 这点与 BUG-359 那两族（`to_int64`/`from_int` 落到同一条 primitive）同型。
2. **core 不提供现行替代品**：`json.mbt` 里没有 `Json::get_key` 之类的现行键访问器；`Object(Map[String,Json])` 上的 `Map::get` 是唯一现行原语。⇒ 清这一族必然要么每处展开、要么自建辅助件，没有第三条零成本路。
3. **房内先例是自建私有辅助件**：`src/server/mcpcf_embed.mbt:108/121/134` 的 `arg_str` / `arg_str_opt` / `arg_bool` 就是「文件私有、内部嵌套 `match args { Object(m) => match m.get(key) … }`」的形态，已在生产面运行、已被 1302 条测试覆盖。C 案就是把这个先例铺到全部 441 处，A 案是它的辅助件版。

---

## 3. 站点普查（实测，判据面 `temp/chk39.json`）

`moon check --target js` = **489 warnings / 0 errors**；`moon clean` 后重跑读数逐格相同（`temp/chk_cold.json`：489 / 0 / 0020=448 / value 族=430），排除缓存截断解释。

### 3.1 按包 × 按作用域

| 包 | 生产 `.mbt` | 白盒 `_wbtest.mbt` | 黑盒 `_test.mbt` | 合计 | 文件数 |
|---|---|---|---|---|---|
| `src/engine` | 20 | 2 | 189 | **211** | 23 |
| `src/server` | 18 | 31 | 39 | **88** | 12 |
| `src/omega` | 42 | 0 | 35 | **77** | 7 |
| `src/executor` | 2 | 0 | 16 | **18** | 2 |
| `src/ops` | 2 | 3 | 10 | **15** | 4 |
| `src/evolve` | 0 | 0 | 10 | **10** | 1 |
| `src/router` | 7 | 0 | 0 | **7** | 1 |
| `src/decompose` | 2 | 0 | 0 | **2** | 1 |
| `src/store` | 0 | 1 | 1 | **2** | 2 |
| 合计 | **93** | **37** | **300** | **430** | 53 |

> 注：先前草稿把 130 记作「生产站点」，实为 **非黑盒站点 = 生产 93 + 白盒 37**。普查脚本按 `endswith("_test.mbt")` 分桶，而 `_wbtest.mbt` 同样命中该后缀 —— 已在此修正，白盒与生产在**同一个编译作用域**（见 §4）。

### 3.2 用法形状（每行只出现一处 `.value(`，430 站点 = 430 行）

| 形状 | 处数 | 可机械批处理？ |
|---|---|---|
| `match j.value(k) {`（match-head） | **410** | A/B 可；C 需逐处补兜底分支 |
| `let x = j.value(k)` | 11 | 全部可 |
| `if j.value(k) is …` | 7 | 全部可 |
| `f(j.value(k))`（实参位） | 2 | 全部可 |

### 3.3 键

- 字面键 **166 个 distinct**，Top：`verdict` 25、`action` 9、`ok` 9、`tests` 9、`plan` 9、`suggestion` 7、`admit` 7、`value` 7。
- **动态键 37 处**（`j.value(key)`，key 是变量）⇒ 这些处不能按键名归类替换，只能按接收者改写；A 案对它们同样机械（`jget(j, key)`）。

### 3.4 判据盲区（本单元的新发现）

文本普查 `.value(` = **441**，判据面只报 **430** ⇒ **11 处编译器沉默**，分布在 8 个文件：

| 文件 | 文本 | 判据 | 差 |
|---|---|---|---|
| `src/engine/engine_contract_test.mbt` | 6 | 3 | 3 |
| `src/engine/engine_triage_test.mbt` | 15 | 13 | 2 |
| `src/engine/engine_circuit_test.mbt` | 4 | 3 | 1 |
| `src/engine/engine_dispatch_test.mbt` | 8 | 7 | 1 |
| `src/engine/engine_eval_test.mbt` | 4 | 3 | 1 |
| `src/engine/engine_phi_test.mbt` | 20 | 19 | 1 |
| `src/engine/engine_triage_skill_test.mbt` | 6 | 5 | 1 |
| `src/server/supervisor_tools_wbtest.mbt` | 1 | 0 | 1 |

复现路径：`engine_dispatch_test.mbt:47` 是一处真实 `.value("…")`，在干净树（暖缓存、`moon clean` 后冷跑、touch 单文件）三种跑法里都不被报；只有把它改成新形态再跑，它才在诊断面现形。反向哨兵已加：不存在「判据报了但文本没有」的文件（0 处）。

> **441 这个数只在「git 跟踪面」上成立**（`git ls-files "*.mbt"` = 290 个文件）。改用文件系统 walk 会把 `.mooncakes/moonbitlang/x/time/weekday.mbt` 里那个**同名不同物**的 `Weekday::Monday.value()` 一起数进来，得到 **448**——而 448 恰是本族 0020 判据的**总条数**，两个 448 撞在一起，很容易把人引向「盲区 18 处」这个假结论。所以：本稿全部差额数字的分母是跟踪面 441，盲区是 **11 处**不是 18 处。这一格已在 `scripts/check_deprecated_text_census.py` 里做成硬门（跟踪 .mbt 文件数 < 100 直接 FATAL 拒绝读数），宇宙被换掉时它不会静默给出另一种数字。

后果（要请指挥官一并定，见 §7 ⑤）：BUG-344 那条「以 `error_code` 命中数作为收口口径」的铁律在这一族上给出的是**下界**。若按判据面收口，清完 430 处后仍有 11 处 `Json::value` 留在源码里 —— 形态已经「绿」，真源还有一处弃用调用。

---

## 4. 作用域定律（实测，4 组探针）

A 案要落辅助件，第一件事是问「同名私有件能不能一个文件写一份」。四组探针（`temp/probe_dup_helper.py` / `probe_dup_helper2.py`，每组都完整回退、判据面复测）：

| 探针 | 两份同名 `fn jget` 写在 | 结果 |
|---|---|---|
| R1 | `src/omega/gate.mbt` + `src/omega/spec.mbt`（同包两份生产文件） | **rc=1**：`The toplevel identifier jget is declared twice` |
| R2 | `src/omega/gate.mbt`（生产）+ `src/omega/omega_test.mbt`（黑盒） | **rc=0 / 0 errors**（互不可见） |
| R3 | `src/omega/omega_test.mbt` + `src/omega/scoring_test.mbt`（同目录两份黑盒） | **rc=1**：declared twice |
| R4 | `src/server/server.mbt`（生产）+ `src/server/github_gitcode_wbtest.mbt`（白盒） | **rc=1**：declared twice |

三条定律，直接决定 A 案的形态：

1. **辅助件按「作用域」计数，不按文件计数** —— 一个包的生产+白盒共享一个作用域，只能有一份；一个目录的黑盒测试共享另一个作用域，也只能有一份。
2. **黑盒测试看不到包私有件**（R2 反证 + 房内常识），所以黑盒作用域**必须自带一份**，不能复用生产那份。
3. ⇒ 全仓 A 案的辅助件总数 = 需要包作用域件的 8 个包 + 需要黑盒作用域的 7 个目录 = **15 份**，覆盖 53 个文件。不是「53 个文件各 10 行」，而是「15 个辅助件 + 441 行调用点」。

（这条是本单元对上一轮草稿的实质纠正：草稿按「每文件一个辅助件」外推体量与冲突面，实测表明真正的约束是作用域。）

---

## 5. 三案量尺

对等实验用**同一批 25 处站点**（`src/omega/gate.mbt`，该文件恰有 25 处，覆盖 match-head / binding / 动态键三种形状）。判据面读数每案都实跑 `moon check --target js`；格式化面用 `moonfmt` 只读差分（D0 = `fmt(HEAD)` vs `HEAD`，D1 = `fmt(现状)` vs `现状`；新增分歧 = D1−D0，口径同 `temp/fmt30.py`）。

| | A：每作用域一个私有 `jget` | B：就地内联 `if … is Object(obj)` | C：按房内先例展开嵌套 `match` |
|---|---|---|---|
| 25 处实测 numstat | **+35 / −25** | **+26 / −25** | 1 处手写：4 行 → 8 行 |
| 判据面（25 处） | 464 warnings / **0 errors**，value 族 430→405 | 464 / **0 errors**，value 族 430→405 | 该站点清零、编译通过 |
| moonfmt 新增分歧 | **0**（D0=5 → D1=5） | **128**（D0=5 → D1=133） | 未测（形态即多行，预期不新增） |
| 全量外推（441 处） | 站点 +441/−441，辅助件 15×10=+150 ⇒ **≈ +591 / −441** | **≈ +470 / −441**，但 `moonfmt` 会再改动 **≈ 2260 行** | **≈ +1764 行** + **410 次**人工兜底判断 |
| 可否机械批处理 | 可（`temp/pilot_a.py` 已实现并通过 1302 条测试） | 可（正则一条） | **不可**（每个 match-head 要判「原 arms 有无兜底」） |
| 公开 API / `.mbti` | 不变（私有件） | 不变（无新标识符） | 不变 |
| 失败模式 | 15 份重复件，名字漂移风险（BUG-330 同族） | 表达式变长 → 折行、可读性下降、与房内风格背离 | 逐处新增 `_ => None` 之类的兜底臂会**改变失败路径**，需逐处审 |
| 主要代价 | 重复件计数 | **撞「零新增格式化分歧」锁** | 人工判断量 |

A 案的额外实测背书（3 文件 54 处的试点树，`temp/pt_pilotA.log`）：`moon test --target js -j 1` = **Total tests: 1302, passed: 1302, failed: 0**；`temp/fmt30.py` 报「新增分歧文件数 = 0」；`.mbti` 无变化。

**B 案的格式化代价要说准**（这决定它到底能不能选）：格式门确实存在于两条 CI 轨 —— 权威轨 `.github/workflows/ci.yml:80` 与狗食轨 `.github/workflows/fist-ci.yml:49` 都跑 `moon fmt --check`，但**两步当前都是 `continue-on-error: true`**（ci.yml:77 / fist-ci.yml:56，2026-10-13 定因后按「A′ 第 1 条」降门不阻断，根修等 owner 裁决）。所以选 B 的真实后果不是「CI 直接判死」，而是：

- 让一个本来就红的步骤**红得更彻底**（现存分歧是工具链版本差造成、全仓一致，B 案再叠 ≈2260 行**本仓自己造成**的新分歧，从此两者混在一个读数里，升门裁决更难）；
- 用户给的「提交之前一定不能有任何 WARNING 和 ERROR」这条硬要求，在格式面上从「不新增」变成「大面积新增」；
- 想收干净就得先做一次全仓 `moon fmt`（≈2260 行不可逆形态重排，且必须先有 owner 对 A′ 根修的裁决）。

⇒ B 案技术上可行、代价面上不划算；若指挥官恰好打算批「nightly 全仓 fmt」那次根修，B 案的这条代价会被一并吸收，那时它反而比 A 少 15 份重复件。这是 B 唯一的翻盘路径，写在这里供那条裁决与本案一起看。

### 5.1 放置问题（不是第四案，是 A 案的一个岔口）

把 15 份重复件收成 1 份公开件（放 `src/core`）：

- 实测依赖面：`src/core` 只 import `moonbitlang/core/{debug,quickcheck}`，是叶子包 ⇒ 新增件**不会成环**；
- 已依赖 core 的站点点包：`engine`、`server`、`executor`、`ops`、`store`（5 个，免费）；
- **未依赖 core** 的：`omega`、`evolve`、`router`、`decompose`（4 个）⇒ 要新增 4 条直接依赖，且黑盒测试作用域还要 `for "test"` 面，`check_pkg_imports` / `check_mbti_sync` 都要重跑；
- 净效果：15 份私有件 → 1 份跨包公开 API（core 的 `pkg.generated.mbti` 面 +1 个 `pub`）。

这是一次真实的架构取舍（重复 vs 新增跨包公开面 + 4 条依赖），按金条四不由副机代选。

### 5.2 方法注脚（两条自己的坑，写下来防下一轮重踩）

1. B 案首轮量尺被写入器污染成 `+461 / −451` —— 原因是读文件时未先归一 CRLF，回写时又叠加一次 `\n → \r\n`，产 `\r\r\n` 使整文件判变。修正写入器（先归一到 LF、按原文件判 EOL 回写）后重测得 `+26 / −25`。**教训：量 diff 之前先验 EOL，不先验 EOL 的 numstat 不可信。**
2. `temp/chk_pilotB.json` / `chk_pilotC.json` 与 `chk_pilot2.json` 读数逐格相同（436 / 0 / 0020=395），无法支撑三个独立结论 ⇒ 上一轮 B/C 的数字**不取**，本文件 §5 全部以同站点重测数为准。

---

## 6. 建议（仅供定夺，未实施）

**推荐 A 案 + 每包新建一个辅助件文件**（`src/<pkg>/json_get.mbt` 放包作用域件、`src/<pkg>/json_get_test.mbt` 放黑盒作用域件），理由：

- 唯一同时保住「0 errors」「零新增格式化分歧」「可机械批处理」三条的形态；
- 独立文件便于「收完这一族后若要收编成公开件，只动 15 个文件而不是 53 个」；
- 与房内先例 `mcpcf_embed.mbt` 的 `arg_*` 系列一脉（私有、贴近使用面、不进公开 API）。

分批（每批一个 PR，按判据面掉数验收；单批控制在 ≤60 站点以便终审）：

| 批次 | 范围 | 站点 | 判据面预期 |
|---|---|---|---|
| 1 | `store` 2 + `decompose` 2 + `router` 7 | 11 | 489 → 478（打通形态，含「仅包作用域」与「两种作用域都有」两类样本） |
| 2 | `ops` 15 + `executor` 18 + `evolve` 10 | 43 | → 435 |
| 3 | `omega` 42（生产+白盒面） | 42 | → 393 |
| 4 | `omega` 35（黑盒面） | 35 | → 358 |
| 5 | `server` 49（生产+白盒） | 49 | → 309 |
| 6 | `server` 39（黑盒） | 39 | → 270 |
| 7 | `engine` 22（生产+白盒） | 22 | → 248 |
| 8 | `engine` 73（`dag_ext_test.mbt` 单文件，最大单文件） | 73 | → 175 |
| 9 | `engine` 其余 116 | 116 | → 59（拆两批更稳） |

收口后 0020 面 448 → **18**（Show 8 + Show-collect 3 + utf8.encode 3 + FFI Array 3 + 隐式提升 1），总 warnings 预期 **489 → 48**；再往下就是这几族，各自另案。

---

## 7. 请指挥官定夺的 5 件事

1. **选哪案**：A（推荐）/ B / C。B 需要额外授权「一次性全量 `moon fmt`」（≈2260 行形态变更，不可逆面大）；C 需要接受 410 次逐处语义审。
2. **若 A：辅助件叫什么**。草稿用 `jget`（与 core 的 `Json::get` 无冲突，实测可编译）。也可选 `obj_field` / `json_get` / 房内 `arg_*` 风格的 `jval`。名字要一次定，跨 15 份件改名是本仓已记过的漂移面（BUG-330）。
3. **若 A：放置**。每包新建 2 个小文件（推荐）vs 附加在各包某个既有文件尾部（少 15 个文件、但「哪个文件持有辅助件」会变成新的口口相传）。
4. **黑盒测试作用域自带一份私有件是否可接受**（15 份里有 7 份是这个形态，且它们不参与发布产物、不进 `.mbti`）。若不可接受，唯一替代是 §5.1 的公开件方案。
5. **收口口径认哪个数**：判据面 430（编译器说的），还是文本普查 441（真源说的）。选 441 需给 BUG-344 那条铁律加限定语「`error_code` 命中数是下界，须配文本普查」；选 430 则要接受 11 处弃用调用在绿门上留存。

## 8. 本单元的边界与遗留

- **零 `.mbt` 改动**：三案的试点全部当场回退，工作树在写本文件前复验为 CLEAN；`.mbti` 已 `git restore`。判据面维持 489 warnings / 0 errors，测试面维持 1302/1302/0。
- 未复核：native 后端 `moon check --target native` 本机不可用，未测；三案的量尺只在 js 后端上取。
- 已复核并就地更正本稿一处：初稿写「未复核 CI 是否存在 `moon fmt --check` 门」，实为**两条轨都有该步、但都是 `continue-on-error: true`**（见 §5 「B 案的格式化代价要说准」一段）—— 这条差别对 B 案是决定性的，不能留作猜测。
- 另一格现状：gitcode 侧无镜像流水线（仓内无 `.gitcode/`、`.workflow/`），所以本决策稿与后续各批的守卫实际都在 GitHub Actions 上执行；MR 若开在 gitcode，门禁读数要到镜像/手工复跑处看。
- 顺带入账：判据盲区（§3.4）单独挂 BUG-361，与三案选择解耦 —— 即便选了 B/C，这 11 处沉默仍然存在。
