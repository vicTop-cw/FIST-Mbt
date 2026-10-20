# SKILL: atgc-old — ATGC 双链虚拟机（atgc_old_compile / atgc_old_run / atgc_old_talk）

> 形态：skill（本文档，一源四态第三态）｜MCP 工具 `atgc_old_compile` / `atgc_old_run` / `atgc_old_talk`（衍生子项目 ATGC-old，3 工具）
> 真源：`atgc-old/talk.mbt`（`atgc_compile` / `atgc_run` / `atgc_talk` 三接口 + `valid_input` 输入契约 + `atgc_intro` 简介 + `atgc_explain` 叙事）
> + `atgc-old/transpile.mbt`（`compile_dna` 转录+翻译、`transcribe` T→U、`Compiled` 结构、三模式 A/B/C 与 `.ROLLBACK`）
> + `atgc-old/vm.mbt`（`run` 栈机执行 + 快照回滚、`RunResult` 结构、错误不崩溃）
> + MCP 注册面 `src/server/server.mbt`（三工具 schema + `instrumented_tool` 注册，参数名逐字对齐）
> 用途：给"同一段 DNA 程序"提供**编译 / 运行 / 叙事**三种视角——`atgc_old_compile` 只看不跑（DNA→mRNA→操作列表），`atgc_old_run` 跑起来（含快照回滚），`atgc_old_talk` 把整条流水线讲成生物故事并输出最终数值。

## 何时用

- **想把一段 DNA 序列"编译成什么"但不想跑**：拿到一段 `[ATGCU]` 碱基序列，`atgc_old_compile` 把它转录成 mRNA、翻译成操作列表，回 `transcription`（mRNA）/ `ops`（操作序列）/ `mode`（编译模式）/ `antisense`（反义链）/ `rollback`（是否启用快照回滚）——纯计算、不运行、不写库。
- **想真执行 DNA 程序并看结果**：`atgc_old_run` 把编译出的程序跑完，回 `output` / `stack_history`（栈轨迹）/ `final_stack`（最终栈）/ `result`（`ok` / `err: …` / `rolled_back: …`）/ `rolled_back`——除零、栈下溢等错误**不崩溃**，作为 `result` 返回；开启 `.ROLLBACK` / 模式 A 时出错自动回到最近 checkpoint。
- **想把整段程序"讲通"**：`atgc_old_talk` 把 compile + run 串成生物故事（转录→mRNA→核糖体翻译→酶逐条执行），输出最终数值；带 `question` 时再附一段叙事应答；不带 `seq` 时返回双链虚拟机简介。

## 怎么调

> 参数名 = MCP 注册面真名（`src/server/server.mbt`），逐字对齐真源接口，不是杜撰。`compile` / `run` 返回 **JSON 字符串**，`talk` 返回**纯文本**——消费方按工具分流解析。

### 编译（A）—— `atgc_old_compile`，DNA→mRNA→操作列表

| 参数 | 必填 | 说明 |
|---|---|---|
| `seq` | ✅ | DNA 序列：仅允许 `[ATGCU]` 碱基与空白 / `;;` 注释，大小写不敏感；非法字符直接拒（返回错误、不崩溃） |

返回键 `{transcription, ops, mode, antisense, rollback}`：

- `transcription` — 模式 B 时是 mRNA，否则回退 `antisense`（**不是恒等于 mRNA**）
- `ops` — 正向操作列表（空格分隔的操作名，如 `START SUB`）
- `mode` — 编译模式：`A` / `B` / `C` 或组合（如 `B+A`）
- `antisense` — 反义链（反向互补）
- `rollback` — 是否启用快照回滚（`.ROLLBACK` 指令或模式 A 时为 `true`）

```
tools/call atgc_old_compile
  { "seq": "ATGCCGTA" }
// → {"transcription":"AUGCCGUA","ops":"START SUB","mode":"B","antisense":"TACGGCAT","rollback":false}
```

### 运行（B）—— `atgc_old_run`，执行 DNA 程序（含快照回滚）

| 参数 | 必填 | 说明 |
|---|---|---|
| `seq` | ✅ | 同 `atgc_old_compile` 的 `seq`（同一套输入契约） |

返回键 `{output, stack_history, final_stack, result, rolled_back}`：

- `output` — 字符串输出（`OUT_NUM` / `OUT_CHAR` 累计）
- `stack_history` — 栈轨迹数组（每成功一步的栈快照文本）
- `final_stack` — 最终栈（Int 数组）
- `result` — `"ok"` / `"err: <原因>"` / `"rolled_back: <原因>"`
- `rolled_back` — 是否触发快照回滚

```
tools/call atgc_old_run
  { "seq": "ATGCCGTA" }
// → {"output":"","stack_history":["[]"],"final_stack":[],
//    "result":"err: 算术: 栈不足2","rolled_back":false}
// SUB 是栈运算需 2 操作数，栈空 → 栈下溢（预期错误，处理正常，不崩溃）
```

### 叙事（C）—— `atgc_old_talk`，把 DNA 程序讲成生物故事

| 参数 | 必填 | 说明 |
|---|---|---|
| `seq` | — | DNA 序列（可选）：**无（空串）则返回双链虚拟机简介** |
| `question` | — | 自由问题（可选）：以叙事方式回答 |

返回**纯文本**（非 JSON），分三档：

- 无 `seq` → `atgc_intro()` 双链虚拟机简介（**不回答 `question`**）
- 有 `seq`、无 `question` → `atgc_explain(seq)` 生物故事：`🧬 DNA 故事（模式 X）` → 有义链 DNA → mRNA → 核糖体翻译 → 酶执行栈轨迹 → 输出 → 结果（含最终数值）
- 有 `seq` + `question` → 故事后追加 `📌 关于你的问题「…」：…` 叙事应答

```
tools/call atgc_old_talk
  { "seq": "ATGCCGTA" }
// → 🧬 DNA 故事（模式 B）
//    · 有义链 DNA：ATGCCGTA
//    · 反义链模板已转录成 mRNA：AUGCCGUA
//    · 核糖体翻译（密码子→操作）：START SUB
//    · 酶执行（栈轨迹）：[]
//    · 输出：（空）
//    · 结果：err: 算术: 栈不足2

tools/call atgc_old_talk
  { "question": "这个 DNA 程序是怎么跑起来的？" }   // 无 seq
// → 仅返回双链虚拟机简介，不回答 question
```

## 已知边界

- **三工具都纯计算**：`compile` / `run` / `talk` 均**不 spawn、不写库、不发模型调用**——`compile` 只转录+翻译不运行，`run` 是进程内栈机执行，`talk` 内部就是 `compile_dna` + `run` 再包一层叙事。
- **输入契约是硬门**：仅允许 `[ATGCU]` 碱基与空白 / `;;` 注释，大小写不敏感；非法字符三入口都过 `valid_input` 直接拒（返回错误、不崩溃）——越界即回显边界，而不是猜。
- **错误处理不崩溃**：除零、栈下溢、`HALT_ERR`、占位操作（`LOAD` / `STORE` / `MOD` 未实现）都作为 `result="err: …"` 返回而非 panic。
- **`rollback` 只在 `.ROLLBACK` 或模式 A 时为 `true`**：此时出错自动恢复到最近 checkpoint 并置 `rolled_back=true`（`result="rolled_back: …"`）；否则错误直接 `result="err: …"`、`rolled_back=false`。
- **`transcription` 不是恒等于 mRNA**：`compile` 的 `transcription` 在模式 B 时是 mRNA，否则回退 `antisense`。
- **`talk` 无 `seq` 时只返回虚拟机简介、不回答 `question`**：自由问题只有在携带 DNA 序列（叙事对话围绕该程序展开）时才被应答——设计现状，非缺陷（与 `atgc_old_run` 返回 `err: 栈不足2` 的硬门行为同族：参数契约明确，越界即回显边界而不是猜）。
- **返回形态不一**：`compile` / `run` 返回 JSON 字符串，`talk` 返回纯文本——消费方要按"调的是哪个工具"分流解析。
- **三编译模式 + 组合指令**：`A` / `B` / `C` 三种模式与 `.DUAL` / `.OVERLAP` 组合指令；`mode` 字段可为组合（如 `B+A`），`rollback` 随模式 A 自动开启。
- 本次为**纯文档**：不编译 src、不跑 `moon test`。

## 三工具协同

三件正交、可串联，对**同一段 DNA 程序**给出三种视角：

1. **`atgc_old_compile` 编译视角（只看不跑）**：DNA → mRNA → 操作列表，回 `transcription` / `ops` / `mode` / `antisense` / `rollback`——回答"这 DNA 编译成什么"，不执行。
2. **`atgc_old_run` 运行视角（跑起来）**：执行 compile 编译出的程序，含快照回滚，回 `output` / `stack_history` / `final_stack` / `result` / `rolled_back`——回答"跑起来输出什么、栈怎么走、错在哪"。
3. **`atgc_old_talk` 叙事视角（讲通整条流水线）**：内部就是 compile + run（`atgc_explain` 调 `compile_dna` + `run`），把转录→mRNA→翻译→酶执行串成生物故事并输出最终数值；带 `question` 时再叠加叙事应答。

**典型串法**：`atgc_old_compile` 看"编译成什么" → `atgc_old_run` 看"跑起来结果/栈轨迹" → `atgc_old_talk` 看"用生物故事把整条流水线讲通"。因为 `talk` 与 `compile` / `run` 共享同一套 `compile_dna` + `run` 语义，三视角的口径天然一致（同一 DNA 在 compile 的 `ops` 与 talk 故事里的操作序列相同、run 的执行结果与 talk 里的"结果"行相同）。

> 一句话：`atgc_old_compile` 告诉你"这 DNA 编译成什么"，`atgc_old_run` 告诉你"跑起来输出什么"，`atgc_old_talk` 把两者讲成一个生物故事——三件一起，同一段 DNA 程序从编译、执行到叙事都看得明白。
