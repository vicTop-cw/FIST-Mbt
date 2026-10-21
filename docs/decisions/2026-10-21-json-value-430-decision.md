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

### 3.5 其余 0020 子族没有可证的文本代理（R36 实测）

§3.4 的差额只有在「弃用点在源码里就长得和弃用件同名」时才可测。把 0020 剩下的子族按**名称级**
与**站点级**两种口径各普查一遍（宇宙 `git ls-files "*.mbt"` = 290 文件，判据面 `temp/chk41.json`）：

| 子族 | 判据面 | 名称级文本 | 站点级文本 | 结论 |
|---|---|---|---|---|
| `Json::value` | 430 | `.value(` 441 | 同一处 | 代理成立，盲区 **11** |
| `Check @encoding/utf8.encode` | 3 | `utf8.encode(` **1**（且在注释里） | `.to_bytes(` 3 | 代理成立，盲区 **0** |
| `Show`（debugging 8 / collections 3） | 8 行发 11 条（3 行双发） | `\bShow\b` **2** | `.to_string()` 435 + `inspect(` 39 + 插值 `\{` 859 ⇒ 并集 **1333** | **无代理** |
| FFI `Array` | 3 | `\bArray\b` 1463 | `: Array[` 953 | **无代理** |
| 隐式提升 `run` | 1 | `\brun\b` 32 | `.run(` 7 | **无代理** |

三条非显然读数，都直接影响 §6 的收口表能覆盖谁：

1. **`Show` 族的名称级普查会给出负缺口**：文本 2 处 < 判据 8 处，而那 2 处文本本身不是弃用站点——
   `src/router/star_gate.mbt:33` 是 0027 的 `derive(Eq, Debug, Show)`，`:42` 是一条
   `pub extend StarVerdict with Show::{to_string, output}`，与 8 个判据行**无一重合**。真正的站点分散在
   三种写法里（方法调用 `.to_string()`、`inspect(...)`、字符串插值 `\{x}`），把它们并起来是 1333 处对判据 11 条：
   上限要写到 **1322** 才不红，这样的棘轮等于没有。
2. **`utf8.encode` 族反过来证明站点级代理可行**：判据 3 处与 `.to_bytes(` 文本 3 处逐行重合（盲区 0），
   三处即 `src/router/star_gate.mbt:302` / `src/router/star_gate_wbtest.mbt:22,350`——**正是 BUG-360 那条
   「String 内部 UTF-16LE、签名侧 UTF-8」验签洞的本体**。所以这一族的上限 0 顺带把 BUG-360 的修复进度也钉住了：
   谁新写一处不发判据的 `.to_bytes(`，R3 就红；BUG-360 修完后两面归 0，R4 会要求把这条整条删掉。
3. **FFI `Array` 的判别事实是跨行的**：3 处全在 `extern "js" fn` 的形参/字段上（`github_js.mbt:63` /
   `laya_js.mbt:18` / `run_check_js.mbt:26`），而 `: Array[` 在跟踪面有 953 处合法非 FFI 用法；建议替代件
   `FixedArray` 全仓 0 处。行级正则表达不了「这一处是否处在 extern 声明里」，隐式提升那一处同理（`.run(` 7 处对判据 1 处，
   建议形态 `Executor::run` 全仓 0 处）。

把 Show 族真按两种口径各写一条表项喂进守卫，实测读数：**名称级 ⇒ rc=2**（R2「判据命中未被本族文本正则覆盖」，
尺子拒绝代读，不会静默放过）；**站点并集 ⇒ rc=1、缺口 1322**。结论写进 `scripts/check_deprecated_text_census.py`
的 docstring：这张表只收**语法族**；语义族（`Show`/FFI `Array`/隐式提升）与缺席型族（0001/0002/0006/0007/0009 的
unused 系、0078 契约面 437 处对判据 3 处）只能按 `error_code` 逐条清，判据面自己就是清单。

> 一条口径提醒：0027 那 1 处若照字面写 `derive(Show)` 普查会读 **0**（真身是 `derive(Eq, Debug, Show)`），
> 要 `derive\([^)]*\bShow\b` 才对得上。BUG-359 说的「逐字命中、无差额」只就 0020 的两个改名子族成立，
> 不能当成对所有弃用族的默认假设。

### 3.6 本节的拆族读数已经做成守卫的一个模式（R37）

§3.5 那张表是拿 8 份临时探针（`temp/probe42.py`–`probe49.py`）手工拆出来的，其中一支还先错判过 `level`
（真值是小写的 `warning`）和 `loc`（`L1:C1-L2:C2` 的前两个数字是行号与**起始列**，
不是起止行）。这类读数一旦只活在临时探针里，下一单就会重犯同样的解析错、或干脆凭印象把两个族并成一个。
现在 `scripts/check_deprecated_text_census.py --dump-distribution <dump>` 直接给同一批数：8 个 code / 15 种形状 /
489 处，0020 拆成 **430 / 8 / 3 / 3 / 3 / 1**，与 §3.5 逐格相同；未入表的 13 种形状（判据 56 处）当场列成一张队列，
每条带文件数与首个站点。

三条口径值得单独记：① 形状归一只抹引号字面量与数字，**不**抹裸标识符——于是 0009 的三处（`WorldState` /
`ActiveReservation` / `PlannedAction`）各占一行而不是并成一行，宁可读数啰嗦，也不让某个族在汇总里隐身；
② 认领（marker 命中）一律对原始 message 测，因为归一把 `utf8` 写成 `utf<n>`，对形状测会让表里那条
`utf8.encode` 一条也命中不了；③ 本模式**不挂 CI**，只可能返回 0 或 2——「读到了什么」和「这算不算缺陷」
分开写，才不能让一次工具链升级用红门的形式说出「大概没事」。

### 3.7 不可入表族的「站点清单」也做成守卫（R38）

§3.5 只能给「这几族进不了表」的结论，给不出「那这几族到底在哪、该怎么改」。上一单为拿这两问的答案临时写了
`temp/probe50.py`/`temp/probe51.py`，本单把答案固化成 `scripts/check_deprecated_site_list.py`：判据行 ⇒
`file:line:col` ⇒ 按 loc 起止列切出源码片段 ⇒ 结构归属（回溯顶层条目抬头 / 反解判据文本里的 impl /
判 derive 列表是否已含 Debug / 判 0078 站点所在函数的可见性）。**只读数，退出码只可能 0 或 2，不挂 CI**。

一条实测纠正了本单自己沿用的口径：Show 族不是 11 处，是 **11 条判据行 / 8 个站点**。`cmd/cli/main.mbt:458`、
`src/router/router_caf_replay_distinct_test.mbt:288`、`src/router/router_state_wbtest.mbt:85` 三处同时被
`Use Debug instead of Show…` 与 ``Use `@debug.Debug` instead of `Show` for collections`` 两条文本命中，
后者**新增 0 个站点**。按行派工就会多算 3 处——这是行级普查的第二种失真（第一种是 §3.4 的静默少报）。

三族的结构归属实测（`temp/chk44.json` 表头读数：六族合计判据行 19 / 站点 16 / 文件 11）：

- FFI `Array` 3 处（`src/server/github_js.mbt:63` / `src/server/laya_js.mbt:18` / `src/server/run_check_js.mbt:26`）：
  extern "js" 抬头分别在其上 **1、2、2 行** ⇒ §3.5 说的「跨行事实」不是推测，行级判据在这三行上读 0；
  工具把这格直接印成 `行级正则能否单独判定 = 不能（本行无 extern token，归属在上方 N 行）`。
- 隐式提升 1 处：判据文本自述 `impl Executor for McpDelegateExecutor`，本文件内该 impl 有两条（第 50、57 行），
  按「下一个顶层条目起始行」取粗界得段 50–56 / 57–68，站点第 71 行**落在两段体之外**（在 `fn delegate_execute` 里）
  ⇒ 标准形状是「方法只存在于 impl 而按点号调用」，改法即判据点名的显式限定 `Executor::run`。
- 0027 那 1 处真身是 `} derive(Eq, Debug, Show)`，**Debug 已在列表里** ⇒ 改法是删一个 token，不用补实现。
- 0078 的 3 处全在**私有**转换辅助（`fn to_result` 第 795 行 / `fn to_ids_result` 第 850 行 / 同型第三处）的返回类型上
  ⇒ 对外契约面为 0，这正是 §3.5 里「437 处对判据 3 处」那三处的真身。

两支真数据变异对照（各 489 条，不是合成件）：M1 把六族 marker 各改一个字母（命中 19 条）⇒ rc 仍 0，但打出
「大概率是判据文本漂移而不是族已清空」并指回 `--dump-distribution` 对 code 面；M2 把表内族 loc 起止列整体 +3
⇒ rc=2 并点名 S5。一条不对称值得记下：只有判据**点名符号**的族能自证列口径（Array / 0027 的 Show / Result），
Show 的 0020 判据不点名 token，同一份变异里它 8 个站点全读成「未分类」——数字不会自拒，但小结一片「未分类」
就是进料信号。另有一条本轮新踩的坑：本单第一版探针按 `messages` 键读 dump，读到 0 条而不自知（489 条在
`diagnostics`），这把尺因此把「`diagnostics` 是非空数组」钉成 S1 硬前置（与 §3.6 那批一次性探针同型教训）。

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
