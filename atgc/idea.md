# ATGC 双链虚拟机设计文档

> 一套基于 DNA 双链结构的四进制编程语言与虚拟机模型
>
> | | |
> |---|---|
> | 版本 | 1.1 |
> | 日期 | 2026-09-24 |
> | 来源 | 由 `idea.txt` v1.0 整理 |
> | 修订 | 修复表格/标题格式；统一「指令语境 vs 数据语境」规则消除三表语义冲突；重写 §10 自洽示例并实证模式 A 的设计约束；新增 §2.4 词法约定、§4.4 rc 对合事实、§13 开放问题 |

核心思想：**底层 4 进制，3 个一组做 token，编译 = 转录，运行 = 酶加工，双链均可执行。**

---

## 目录

1. [概述](#1-概述)
2. [底层编码](#2-底层编码)
3. [64 密码子指令表](#3-64-密码子指令表)
4. [双链模型](#4-双链模型)
5. [编译指令（Pragma）](#5-编译指令pragma)
6. [三种编译模式](#6-三种编译模式)
7. [组合模式](#7-组合模式)
8. [编译器伪代码](#8-编译器伪代码)
9. [运行时执行模型](#9-运行时执行模型)
10. [完整示例](#10-完整示例)
11. [与生物学的对应关系](#11-与生物学的对应关系)
12. [总结](#12-总结)
13. [开放问题与后续工作](#13-开放问题与后续工作)
- [附录：ATGC 快速参考](#附录atgc-快速参考)

---

## 1. 概述

ATGC 是 DNA 的四种碱基：

| 碱基 | 全称 | 四进制 | 二进制 |
|------|------|--------|--------|
| A | 腺嘌呤（Adenine） | 0 | 00 |
| T | 胸腺嘧啶（Thymine） | 1 | 01 |
| G | 鸟嘌呤（Guanine） | 2 | 10 |
| C | 胞嘧啶（Cytosine） | 3 | 11 |

核心设计：

- **底层 4 进制**：4 种碱基 = 4 个符号，1 碱基 = 2 bit；
- **3 个一组 = 64 种 token**：对应生物学密码子（codon）；
- **编译 = 转录 + 翻译**：DNA → mRNA → 蛋白质；
- **运行 = 酶催化**：蛋白质执行功能；
- **双链均可执行**：有义链与反义链都有语义。

---

## 2. 底层编码

### 2.1 碱基到四进制

```text
A = 0    T = 1    G = 2    C = 3
```

### 2.2 组合数量

| 序列长度 | 组合数 | 生物学含义 |
|----------|--------|------------|
| 1 碱基 | 4^1 = 4 | 单个碱基 |
| 2 碱基 | 4^2 = 16 | — |
| 3 碱基 | 4^3 = 64 | 密码子 |
| 4 碱基 | 4^4 = 256 | — |
| n 碱基 | 4^n | — |

关键：**3 个碱基一组 = 64 种密码子 = 64 个操作码槽位**。

### 2.3 数字表示

十进制 2026 转四进制：

```text
2026 = 1×4^5 + 3×4^4 + 3×4^3 + 2×4^2 + 2×4^1 + 2×4^0
     = 133222₄
```

映射为 ATGC：

```text
1 3 3 2 2 2
T C C G G G
```

### 2.4 词法与语境约定（v1.1 新增）

1. **大小写**：源码大小写不敏感，编译器规范输出大写；
2. **分组**：密码子按每 3 个碱基一组切分，空白/换行仅为可读性，可有可无；
3. **语境二分（关键规则）**：同一个密码子在不同语境下语义不同——
   - **指令语境**：密码子按 §3 指令表译为操作码（默认）；
   - **数据语境**：仅当密码子作为 `PUSH_IMM` 的下一个密码子、或 `LOAD/STORE` 的地址操作数出现时，按四进制数值解释（0–63），**不做操作码解码**；
   - 该规则消除「AAT 既是 JUMP_IF_NEG 又是立即数 1」的表面冲突；
4. **U/T 兼容**：mRNA 层的 U 与 DNA 层的 T 视为同一符号，编译器输入统一为 T；
5. **注释**：以 `;;` 起始至行尾（仅存在于友好源码层，编译后不保留）。

---

## 3. 64 密码子指令表

设计原则：**生物学性质决定操作类别**。

| 生物学分类 | 氨基酸 | 密码子（DNA） | 操作码 | 说明 |
|------------|--------|---------------|--------|------|
| 起始 | Met (M) | ATG | START | 启动程序，确定阅读框 |
| 终止 | Stop | TAA | HALT | 终止程序，返回 0 |
| 终止 | Stop | TAG | HALT_ERR | 终止程序，返回非零 |
| 终止 | Stop | TGA | BREAK | 跳出当前循环 |
| 带电（正） | Lys (K) | AAA AAG | OUT_NUM | 栈顶弹出，数字输出 |
| 带电（正） | Arg (R) | AGA AGG CGT CGC CGA CGG | OUT_CHAR | 栈顶弹出，字符输出 |
| 带电（正） | His (H) | CAT CAC | PUSH_IMM | 下一个密码子作为立即数入栈 |
| 带电（负） | Asp (D) | GAT GAC | POP | 弹出栈顶 |
| 带电（负） | Glu (E) | GAA GAG | DUP | 复制栈顶 |
| 极性（不带电） | Ser (S) | TCT TCC TCA TCG AGT AGC | CALL | 调用子程序 |
| 极性（不带电） | Thr (T) | ACT ACC ACA ACG | RETURN | 从子程序返回 |
| 极性（不带电） | Cys (C) | TGT TGC | JUMP | 无条件跳转 |
| 极性（不带电） | Tyr (Y) | TAT TAC | JUMP_IF_ZERO | 栈顶为 0 则跳转 |
| 极性（不带电） | Asn (N) | AAT AAC | JUMP_IF_NEG | 栈顶为负则跳转 |
| 极性（不带电） | Gln (Q) | CAA CAG | JUMP_IF_POS | 栈顶为正则跳转 |
| 非极性 | Gly (G) | GGT GGC GGA GGG | NOP | 空操作 |
| 非极性 | Ala (A) | GCT GCC GCA GCG | SWAP | 交换栈顶两个元素 |
| 非极性 | Val (V) | GTT GTC GTA GTG | OVER | 复制栈顶第二个元素 |
| 非极性 | Leu (L) | TTA TTG CTT CTC CTA CTG | ROT | 旋转栈顶三个元素 |
| 非极性 | Ile (I) | ATT ATC ATA | ADD | 加法 |
| 非极性 | Pro (P) | CCT CCC CCA CCG | SUB | 减法 |
| 非极性 | Phe (F) | TTT TTC | MUL | 乘法 |
| 非极性 | Trp (W) | TGG | DIV | 除法 |
| — | — | — | LOAD | 从内存加载（**待分配，见 Q2**） |
| — | — | — | STORE | 存入内存（**待分配，见 Q2**） |
| — | — | — | MOD | 取模（**原稿挂在 ATG 上与 START 双义，见 Q2**） |

> **密码子账目（v1.1 审计）**：上表共占用 63 个唯一密码子；其中 ATG 被同时标为 START 与 MOD（双义冲突）；LOAD/STORE 未分到密码子。64 个槽位实际已满，需按 §13 Q2 的方案腾位。

### 3.1 简并性 → 操作数修饰（Wobble Position）

密码子第三位（wobble position）作为操作数修饰符：

| 第三位碱基 | 修饰含义 | 示例 |
|------------|----------|------|
| T | 操作数 = 立即数 | CTT → ROT 操作立即数 |
| C | 操作数 = 栈顶 | CTC → ROT 操作栈顶 |
| A | 操作数 = 内存地址 | CTA → ROT 操作内存值 |
| G | 操作数 = 寄存器 | CTG → ROT 操作寄存器 |

---

## 4. 双链模型

### 4.1 双链结构

```text
5' - ATG AAA AAT TAA - 3'   有义链（Sense）
3' - TAC TTT TTA ATT - 5'   反义链（Antisense）
```

### 4.2 反向互补

反义链按 5'→3' 方向读取：

```text
5' - TTA ATT TTT CAT - 3'
```

即：

**反义链 5'→3' 序列 = 有义链的反向互补（reverse complement）**

公式：

```text
rc(seq) = reverse(complement(seq))

complement: A↔T, G↔C
```

### 4.3 双链执行的两个方向

| 方向 | 读取链 | 程序 | 效果 |
|------|--------|------|------|
| 正向 | 有义链 5'→3' | P | 执行 |
| 反向 | 反义链 5'→3' | rc(P) | 撤销 / 独立程序 |

### 4.4 rc 的对合结构（v1.1 新增的数学事实）

rc 是 64 密码子集合上的**对合**（`rc(rc(c)) = c`），且由于**没有任何碱基等于自己的补**（A↔T、G↔C 均互换）：

- **不存在自反密码子**（rc(c) = c 无解）；
- 64 个密码子恰好划分为 **32 个 rc 互补对**，每对形如 `{c, rc(c)}`；
- 例：`ATG ↔ CAT`、`AAA ↔ TTT`、`AAG ↔ CTT`、`TAG ↔ CTA`、`TGA ↔ TCA`。

这一结构是模式 A 的地基：**每个 rc 对的两个成员天然适合分配为一对互逆操作 `{O, O⁻¹}`**（详见 §6.1 与 Q1）。

---

## 5. 编译指令（Pragma）

编译指令用 ATGC 编码，放在程序最前面。

### 5.1 指令区结构

```text
ATG TAA <指令1> <指令2> ... TAA TAA TAA <程序体>
```

- `ATG TAA`：指令区开始；
- `TAA TAA TAA`：指令区结束；
- 解析器**仅在文件头部固定偏移处匹配**这两个标记（`startswith("ATGTAA")` + `find("TAATAATAA")`），程序体中出现的同名序列不会被误判。

### 5.2 指令表

| 指令 | ATGC 编码 | 含义 |
|------|-----------|------|
| .MODE_A | ATG TAA ATG | 反链 = 逆程序 |
| .MODE_B | ATG TAA TAG | 反链 = 编译模板 |
| .MODE_C | ATG TAA TGA | 反链 = 独立程序 |
| .DUAL | ATG TAA CAT | 双链同时执行 |
| .ROLLBACK | ATG TAA CAA | 启用错误回滚 |
| .OVERLAP | ATG TAA CAG | 启用重叠基因 |
| .END | TAA TAA TAA | 指令区结束 |

### 5.3 组合示例

```text
ATG TAA TAG ATG TAA CAT CAA TAA TAA TAA
```

含义：模式 B + 模式 A + 双链执行 + 回滚支持。

---

## 6. 三种编译模式

### 6.1 模式 A：反链 = 逆程序

```text
.ATG TAA ATG ... TAA TAA TAA
```

编译规则：

1. 读有义链 5'→3'，翻译为程序 P；
2. 读反义链 5'→3'，翻译为程序 rc(P)；
3. 建立操作对：每个密码子 c 的操作 O，rc(c) 分配 O⁻¹。

**目标语义的逆操作配对（示意）**：

| 有义密码子 | 操作 | 反义密码子（rc） | 逆操作 |
|------------|------|------------------|--------|
| ATG | START | CAT | STOP |
| TAA | HALT | TTA | RESUME |
| AAA | OUT | TTT | IN |
| AAT | PUSH | ATT | POP |
| AAG | ADD | CTT | SUB |
| AAC | MUL | GTT | DIV |
| ATA | JUMP | TAT | JUMP_BACK |
| TAG | CALL | CTA | RETURN |
| TGA | LOOP | TCA | ENDLOOP |

> ⚠️ **设计约束（v1.1 明确）**：上表为「目标语义示意」，**尚未与 §3 主表对齐**。原因有二：
>
> 1. **rc 对合约束**：`rc(主表密码子)` 得到的操作，与上表要求的逆操作不一致（例：主表 `AAG = OUT_NUM`，而 `rc(AAG) = CTT` 在主表是 ROT，上表却要求它是 SUB）。要让「反链自动成为逆程序」，**指令表必须按 32 个 rc 对整体重排**：每个 rc 对的两个成员分别授予互逆操作 `{O, O⁻¹}`，同操作的多重简并必须与其逆操作的简并数量守恒（详见 §13 Q1）；
> 2. **实证**：§10.7 用当前主表对真实程序求 rc，得到的反链操作序列确实不是逆程序——约束未满足的直接证据。
>
> 在 Q1 落地前，`.ROLLBACK` 的可用实现是**状态快照回滚**（见 §7.1）。

示例（目标语义达成后的效果）：

```text
有义链：ATG AAT AAG AAA TAA
操作：  START PUSH1 ADD OUT HALT

反义链：TTA CTT ATT CAT
操作：  RESUME SUB POP STOP
```

### 6.2 模式 B：反链 = 编译模板

```text
.ATG TAA TAG ... TAA TAA TAA
```

编译规则：

1. 有义链是源代码；
2. 反义链是模板链；
3. 转录：读反义链 3'→5'，生成 mRNA（T→U）；
4. mRNA 序列 = 有义链的 T→U 版本；
5. 翻译 mRNA，每 3 个碱基一个操作；
6. 反链不独立执行，只作为编译中间产物。

流程：

```text
有义链 DNA： 5'-ATG AAT AAG AAA TAA-3'
反义链 DNA： 3'-TAC TTA TTC TTT ATT-5'
                    ↓ 转录（读反义链 3'→5'）
mRNA：        5'-AUG AAU AAG AAA UAA-3'
                    ↓ 翻译
蛋白质/指令：  START PUSH1 PUSH2 OUT HALT
```

> 注：该转录方向与分子生物学一致——RNA 聚合酶读模板链 3'→5'，产物 mRNA 与编码链（有义链）同序（T→U）。

### 6.3 模式 C：反链 = 独立程序

```text
.ATG TAA TGA ... TAA TAA TAA
```

编译规则：

1. 有义链翻译为程序 P1；
2. 反义链 5'→3' 翻译为程序 P2；
3. P1 和 P2 共享同一张密码子表，但语义独立；
4. 两个程序可分别运行，也可同时运行。

示例：

```text
有义链：ATG AAA TAA   -> START, OUT, HALT
反义链：TTA TTT CAT   -> RESUME, IN, STOP
```

对应生物学中的重叠基因：同一段 DNA，不同链编码不同蛋白质。

---

## 7. 组合模式

### 7.1 .DUAL + .ROLLBACK（B + A）

```text
.ATG TAA TAG ATG TAA TAA TAA
```

- 主模式 B：反链作为编译模板，生成 mRNA；
- 附加模式 A：同时生成逆程序，用于回滚。

编译输出：

```text
program:
  forward:  [START, PUSH1, PUSH2, ADD, OUT, HALT]
  backward: [RESUME, SUB, SUB, POP, STOP]
  rollback: enabled
```

运行时：

```text
正向：mRNA → 翻译 → 执行 → 产生结果
出错：反义链 → 逆程序 → 回滚状态
```

> **v1.1 过渡实现注**：Q1 落地前，`ROLLBACK` 以**状态快照回滚**实现——翻译后按密码子位置记录 checkpoint（栈深度、PC、内存脏页、输出游标），出错时回退到最后 checkpoint。快照回滚与「逆程序回滚」语义等价性由 Q1 完成后接管。

### 7.2 模式组合表

| 模式 | 反链角色 | 用途 |
|------|----------|------|
| A | 逆程序 | 回滚、错误恢复、可逆计算 |
| B | 编译模板 | 转录、翻译、标准生物流程 |
| C | 独立程序 | 重叠基因、双程序编码 |
| DUAL | 同时执行 | 并行计算 |
| ROLLBACK | A + 监控 | 容错执行 |
| OVERLAP | C + 共享 | 信息压缩 |

---

## 8. 编译器伪代码

```python
# 密码子表：64 个密码子 -> 操作
CODON_TABLE = { ... }

# 反向互补映射
def reverse_complement(seq):
    comp = {'A':'T', 'T':'A', 'G':'C', 'C':'G'}
    return ''.join(comp[b] for b in reversed(seq))

# 读取编译指令
def parse_directives(seq):
    if not seq.startswith("ATGTAA"):
        return {"mode": "B"}  # 默认模式
    end = seq.find("TAATAATAA")
    directive_region = seq[6:end]
    body = seq[end+9:]
    directives = []
    for i in range(0, len(directive_region), 3):
        codon = directive_region[i:i+3]
        directives.append(DIRECTIVE_MAP[codon])
    return {"directives": directives, "body": body}

# 模式 A 编译
def compile_mode_a(sense):
    forward = translate(sense)
    antisense = reverse_complement(sense)
    backward = translate(antisense)
    pairs = build_inverse_pairs(forward, backward)
    return {"forward": forward, "backward": backward, "pairs": pairs}

# 模式 B 编译
def compile_mode_b(sense):
    antisense = reverse_complement(sense)
    mrna = transcribe(antisense)   # T -> U
    protein = translate(mrna)
    return {"mrna": mrna, "protein": protein}

# 模式 C 编译
def compile_mode_c(sense):
    forward = translate(sense)
    antisense = reverse_complement(sense)
    backward = translate(antisense)
    return {"program1": forward, "program2": backward}

# 主编译入口
def compile_dna(seq):
    info = parse_directives(seq)
    body = info["body"]
    directives = info.get("directives", ["MODE_B"])

    result = {}
    if "MODE_A" in directives:
        result["A"] = compile_mode_a(body)
    if "MODE_B" in directives:
        result["B"] = compile_mode_b(body)
    if "MODE_C" in directives:
        result["C"] = compile_mode_c(body)
    if "DUAL" in directives:
        result["dual"] = True
    if "ROLLBACK" in directives:
        result["rollback"] = True
    if "OVERLAP" in directives:
        result["overlap"] = True
    return result
```

> 注：`translate` 按 §2.4 语境规则解码——默认指令语境，`PUSH_IMM`/`LOAD`/`STORE` 后一密码子切数据语境。

---

## 9. 运行时执行模型

```text
                    ┌──────────────┐
                    │  加载 mRNA   │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  核糖体翻译   │
                    │  密码子→操作  │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌───▼───┐ ┌─────▼─────┐
        │ 正向执行   │ │ 监控  │ │ 反向执行   │
        │ (有义链)  │ │ 错误  │ │ (反义链)  │
        └─────┬─────┘ └───┬───┘ └─────┬─────┘
              │            │            │
              │       ┌────▼────┐       │
              │       │ 出错？   │       │
              │       └────┬────┘       │
              │            │            │
              │       ┌────▼────┐       │
              │       │ 触发回滚 │───────┘
              │       └─────────┘
              │
        ┌─────▼─────┐
        │  输出结果  │
        └───────────┘
```

---

## 10. 完整示例

### 10.1 源文件（双链，v1.1 重写为与 §3 主表自洽）

程序目标：计算 `1 + 2 + 2 = 5` 并输出，模式 B + A，启用回滚。

程序体（有义链，按主表与语境规则编码）：

```text
ATG  CAT AAT  CAT AAG  CAT AAG  ATT  AAA  TAA
START  PUSH 1  PUSH 2  PUSH 2  ADD  OUT_NUM  HALT
```

完整有义链：

```text
5'-ATG TAA TAG ATG TAA CAA TAA TAA TAA ATG CAT AAT CAT AAG CAT AAG ATT AAA TAA-3'
```

互补反义链：

```text
3'-TAC ATT ATC TAC ATT GTT ATT ATT ATT TAC GTA TTA GTA TTC GTA TTC TAA TTT ATT-5'
```

### 10.2 指令解析

```text
ATG TAA          -> 指令区开始
TAG              -> MODE_B（反链=编译模板）
ATG              -> MODE_A（反链=逆程序）
CAA              -> ROLLBACK（启用回滚）
TAA TAA TAA      -> 指令区结束
ATG CAT AAT CAT AAG CAT AAG ATT AAA TAA  -> 程序体
```

### 10.3 程序体翻译（指令语境 + 数据语境）

```text
ATG       -> START
CAT AAT   -> PUSH_IMM 1     （AAT 在数据语境 = 0,0,1₄ = 1）
CAT AAG   -> PUSH_IMM 2     （AAG 在数据语境 = 0,0,2₄ = 2）
CAT AAG   -> PUSH_IMM 2
ATT       -> ADD
AAA       -> OUT_NUM
TAA       -> HALT
```

### 10.4 编译器输出

```text
mode:      B + A + ROLLBACK
forward:   [START, PUSH 1, PUSH 2, PUSH 2, ADD, OUT_NUM, HALT]
mrna:      5'-AUG CAU AAU CAU AAG CAU AAG AUU AAA UAA-3'
rollback:  enabled（Q1 前 = 状态快照；Q1 后 = 逆程序）
```

### 10.5 运行

```text
正向执行 -> 栈变化：[1] [1,2] [1,2,2] [5] -> 输出 5
若出错   -> 回退到最后 checkpoint（栈清空、输出游标归零）
```

### 10.6 简单示例：计算 (1+2)×3

```text
ATG          # START：启动程序
CAT AAT      # PUSH_IMM 1
CAT AAG      # PUSH_IMM 2
ATT          # ADD：1+2=3
CAT AAC      # PUSH_IMM 3
TTT          # MUL：3×3=9
AAA          # OUT_NUM：输出 9
TAA          # HALT：终止
```

连起来：

```text
ATGCATAATCATAAGATTGCATAACTTTAAATAA
```

运行输出 9。

### 10.7 模式 A 实证：rc 链的现状语义（v1.1 新增）

对 §10.1 程序体求反向互补（反义链 5'→3'）：

```text
rc 程序体 = ATT TTT TAA TTC GTA TTC GTA TTA GTA TAC
```

按当前 §3 主表翻译：

```text
ATT=ADD, TTT=MUL, TAA=HALT, TTC=MUL, GTA=OVER,
TTC=MUL, GTA=OVER, TTA=ROT, GTA=OVER, TAC=JUMP_IF_ZERO
```

结果不是 `START…HALT` 的逆——**这就是 Q1 所述「主表未按 rc 对重排」的直接证据**。Q1 完成后，同一操作的反链将自动翻译为 `[RESUME, POP, POP, POP, SUB, STOP, …]` 形态的逆程序。

---

## 11. 与生物学的对应关系

| 计算机概念 | 生物概念 | 说明 |
|------------|----------|------|
| 源代码 DNA | DNA | 存储程序 |
| 编译前端 | RNA 聚合酶 | 读取 DNA |
| 中间表示 IR | mRNA | 转录产物，T → U |
| 编译后端 | 核糖体 | 翻译成蛋白质 |
| 机器码 | 蛋白质 | 可执行功能分子 |
| 运行时 | 代谢网络 | 酶催化反应 |
| 函数调用 | 酶与底物结合 | 特异性识别 |
| 副作用 | 代谢产物 | 改变细胞状态 |
| 双链 | 双链 DNA | 两条链都携带信息 |
| 反向互补 | 碱基配对 | A-T, G-C |
| 重叠基因 | 重叠基因 | 同一段 DNA 编码不同蛋白质 |
| 错误回滚 | DNA 修复 | 逆程序恢复状态 |

### 11.1 生物与计算机的关键区别

| 维度 | 生物 | 计算机 |
|------|------|--------|
| 执行方式 | 并行、随机、化学 | 串行、确定、逻辑 |
| 密码子映射 | 64 → 20 氨基酸（简并） | 64 → 64 操作码（可一一对应） |
| 程序控制 | 浓度、扩散、反馈网络 | 程序计数器 |
| 错误处理 | DNA 修复机制 | 回滚、异常处理 |

---

## 12. 总结

### 12.1 核心设计

- 底层 4 进制：ATGC 四种碱基，2 bit；
- 3 个一组 = 64 密码子：对应 64 个操作码槽位；
- 双链均可执行：有义链与反义链都有语义；
- 编译 = 转录 + 翻译：DNA → mRNA → 蛋白质；
- 运行 = 酶催化：蛋白质执行功能。

### 12.2 三种模式

| 模式 | 反链角色 | 用途 |
|------|----------|------|
| A | 逆程序 | 回滚、错误恢复、可逆计算 |
| B | 编译模板 | 转录、翻译、标准生物流程 |
| C | 独立程序 | 重叠基因、双程序编码 |

### 12.3 编译指令

| 指令 | 编码 | 作用 |
|------|------|------|
| .MODE_A | ATG TAA ATG | 反链 = 逆程序 |
| .MODE_B | ATG TAA TAG | 反链 = 编译模板 |
| .MODE_C | ATG TAA TGA | 反链 = 独立程序 |
| .DUAL | ATG TAA CAT | 双链同时执行 |
| .ROLLBACK | ATG TAA CAA | 启用错误回滚 |
| .OVERLAP | ATG TAA CAG | 启用重叠基因 |
| .END | TAA TAA TAA | 指令区结束 |

### 12.4 一句话总结

ATGC 底层是 4 进制，3 个一组变成 64 个操作码。它不是只有 4 个操作，而是一套用 DNA 密码子写的双链虚拟机汇编指令集。有义链执行正向程序，反义链可执行逆程序、编译模板或独立程序，编译即转录，运行即酶催化。

---

## 13. 开放问题与后续工作（v1.1 新增）

| # | 问题 | 现状与建议 |
|---|------|------------|
| Q1 | **指令表按 rc 对重排**（模式 A 成立的前提） | rc 把 64 密码子划成 32 个互补对、无自反（§4.4）。需把互逆操作对 `{O, O⁻¹}` 逐对分配到 rc 对上，并保证简并守恒：操作 O 占 k 个密码子（跨 k 个 rc 对），其逆 O⁻¹ 必须占这 k 个 rc 对的另一半。可先按功能分四组（算术 / 栈 / 控制流 / IO-内存）再组内配对，产出 v2.0 指令表 |
| Q2 | **ATG 双义（START/MOD）与 LOAD/STORE 缺位** | 方案 a：压缩高简并操作——OUT_CHAR（Arg 6 个）与 CALL（Ser 6 个）各收缩到 4 个，腾出 4 个密码子给 LOAD/STORE/MOD；方案 b：MOD 走 wobble 修饰（如 `MUL` 第三位 = A 时语义取模）。倾向 a+b 混合 |
| Q3 | **立即数扩展** | 当前 PUSH_IMM 一次只能压 0–63。约定：连续 k 个数据密码子按 6k bit 拼接（小端或大端待定），或引入 `.DATA` pragma 段放字面量池；负数用二补码，位宽由首个数据密码子的高 2 位声明 |
| Q4 | **.DUAL 并发语义** | 双链同时执行时共享一个栈还是各持栈？建议：双栈 + 每 tick 一次同步屏障，共享内存区为唯一交换媒介 |
| Q5 | **.OVERLAP 执行语义与安全** | 重叠基因 = 同段 DNA 双程序，需要定义「共享窗口」的对齐规则与读写冲突仲裁 |
| Q6 | **落地实现（MoonBit / FIST-Mbt 生态）** | 建议模块切分：`atgc/lexer`（词法分组与语境标注）→ `atgc/codon`（指令表 + rc 对数据结构）→ `atgc/transpiler`（三模式编译）→ `atgc/vm`（栈机 + checkpoint 回滚）。先落 MODE_B + 快照回滚（最小自洽闭环），Q1 完成后补 MODE_A 逆程序 |

---

## 附录：ATGC 快速参考

### 碱基配对

```text
A ↔ T
G ↔ C
```

### 反向互补（成对出现，共 32 对，无自反）

```text
rc(ATG) = CAT      rc(TAA) = TTA      rc(AAA) = TTT
rc(AAT) = ATT      rc(AAG) = CTT      rc(AAC) = GTT
rc(ATA) = TAT      rc(TAG) = CTA      rc(TGA) = TCA
```

### 64 密码子速查

```text
AAA AAG AAT AAC  -> Lys, Asn
ATA ATG ATT ATC  -> Ile, Met
AGA AGG AGT AGC  -> Arg, Ser
ACA ACG ACT ACC  -> Thr
TAA TAG TAT TAC  -> Stop, Tyr
TTA TTG TTT TTC  -> Leu, Phe
TGA TGG TGT TGC  -> Stop, Trp, Cys
TCA TCG TCT TCC  -> Ser
GAA GAG GAT GAC  -> Glu, Asp
GTA GTG GTT GTC  -> Val
GGA GGG GGT GGC  -> Gly
GCA GCG GCT GCC  -> Ala
CAA CAG CAT CAC  -> Gln, His
CTA CTG CTT CTC  -> Leu
CGA CGG CGT CGC  -> Arg
CCA CCG CCT CCC  -> Pro
```

---

> 文档结束（v1.1，由 `idea.txt` 整理完善；设计原意未变，矛盾已标注为开放问题）
