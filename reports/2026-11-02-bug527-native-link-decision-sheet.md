# BUG-527 决策单 · native 库包 link 的两代 moon 语义分歧

- status: 提案中
- decided: （待 owner 裁决②的执行时机；③已按本单建议否决）
- date: 2026-11-02
- author: lead（beta 子代理失败无回执，按「单一上下文持续到结论」判例由统帅接手）
- ledger: `memory/bugs.md:14559` BUG-527 [medium] OPEN（追记2 改判后）

## 结果摘要

BUG-527 的本质：**同一个 `options(link:{native:{cc-link-flags}})` 写法，CI nightly moon（≈0.1.20261012）与本地新版 moon（WSL 0.1.20261021）语义相反**——前者把它当「库包向下游 native 测试链传播 `-lsqlite3`」的正确机制（摘掉反而红：runs 41305804775/41305804754 `undefined reference to sqlite3_*`），后者把带 link 的库包当可执行目标去链（全项目 `moon build --target native` 必崩 `undefined reference to 'main'`）。出路①（库包摘 link）已被 CI A/B 实证证伪并回滚（`e0ef45c5e` 状态）；现状=CI 两条 native 臂绿、本地全项目 native 不可用。

## 事实核查（本轮新验，不抄账本）

| 事实 | 读数 | 出处 |
|---|---|---|
| Windows 本机 moon | `0.1.20261016 (1af328f)`（钉版） | `moon version` 实测 |
| 「0.1.20261021 必崩」的复现机 | **WSL 侧**的 moon，非 Windows 本机 | 账本追记 detail |
| CI native 臂的构建面 | `moon test --target native`（**全项目**，`ci.yml:500`、`fist-ci.yml:132`） | workflow 实测 |
| 该臂现状 | **绿**（带 link，runs 41284830056/41284830060） | 账本追记2 |
| 仓库工作树 | **零真实 WIP**——38 项「脏」全是 CRLF 行尾幻影（`git diff --ignore-cr-at-eol` 为空） | 本轮实测 |

⇒ 无车道冲突；出路③若执行，删掉的是**当前在绿**、且恰好验证 link 传播机制（native 测试 exe 链 `-lsqlite3`）的那格覆盖。

## 三条出路的终审评估

**出路①（库包摘 link）— 已死。** CI 证伪在案（追记2），回滚完毕，不再讨论。

**出路③（native 观测臂降级为只建可执行包）— 建议否决。** 理由：该出路写于「CI native 臂一直红」的旧前提；A/B 实证后 CI 侧根本不是故障侧——故障侧是**本地新版 moon 的开发体验**。给 CI 降级=删除一格在绿的真覆盖（全项目 native 测试链），换不来故障侧任何改善。release 臂本就 scoped（BUG-527 首轮绕行），已无再降的面。

**出路②（上游 issue + 本仓 standards 写死）— 建议采纳为主行动。** 唯一能通到已改判关闭条件（「语义分歧有裁决且两侧同时可用」）的路：裁决只能来自上游。成本≈一次 issue + 一条规则；对两侧零风险（flags 不动、CI 不动）。

**出路④（本轮新增，本地缓解）— 顺手采纳。** 本机钉版 moon 0.1.20261016 是否同样崩、**未测**（WSL 只测过 0.1.20261021）。缓解口径：本地做 native 全项目构建/测试时，先用**钉版** moon 试（Windows 侧还需 `scripts/native-env.ps1` 的 MSVC 环境）；若钉版不崩，「本地 native」的口径就是钉版工具链，崩的只有升级后的 WSL——分歧面收窄为「单一代版本」。此为缓解不是裁决，不改变 ② 的主行动地位。

## 给上游 issue 的证据包（出路②执行件，拟稿就绪）

1. 最小形状：库包 `src/foo/moon.pkg` 含 `options(link: { native: { cc-link-flags: "-lsqlite3" } })`、无 `pkgtype(kind:"executable")` → `moon build --target native`（全项目）报 `failed to make executable …/src/foo: … undefined reference to 'main'`；scoped `moon build --target native cmd/cli` 正常。
2. 反面（为何 flags 在库包）：native 测试 exe 链接依赖库包传播 `-lsqlite3`（stub.c 调 `sqlite3_*`）；摘掉即 `undefined reference to sqlite3_*`。
3. A/B：带 link `8da9f920b` 两 native 臂绿（runs 41284830056/41284830060）；摘 link `d43a06a28` 红（runs 41305804775/41305804754）。
4. 版本对照：nightly ≈0.1.20261012 行为=传播；0.1.20261021 行为=当可执行链。请上游裁定哪个是规范语义（若「库包不得带 link」为规范，则 nightly 是偏差方，本仓整改需另寻传播机制——届时再开新单）。
5. 次要：错误行只有包名无 file:line（`Error: failed to make executable vicTop-cw/fist-mbt/src/core`），易被误读成源码错误。

发布渠道：上游 moon 仓 issue。**按金条四（发布类操作留确认），issue 文本已备、一行 `gh` 命令即可发，发不发、署名谁等 owner 一句话。**

## 关闭条件映射（对齐追记2 的改判）

- 「有裁决」= 上游 issue 得到 maintainers 结论（任一方向都算）。
- 「两侧同时可用」= 裁决为「link 合法」⇒ 本地随 moon 修复升级即愈；裁决为「非法」⇒ 本仓开新单按新机制整改 CI 侧传播，期间 AGENTS.md 记边界。
- 本单在裁决前保持 OPEN；出路①/③ 两栏不再重开。

## 遗留风险与后续建议

- 若上游长期不应答：BUG-527 以「裁决未至」挂 OPEN 是诚实态，不建议为关单而降级 CI（③的否决不因时间推移翻案）。
- CRLF 幻影（38 项假脏）建议另开小单：给 `.gitattributes` 补 `* text=auto eol=lf` 之类收敛——**本单不夹带**。

## 资源消耗 / 任务分配 / 超额

- 分配：beta 子代理两次（1c062778-… 失败无回执）→ 统帅亲查（账本 60 行 + workflow + moon version + 工作树核查 ≈ 4 次工具调用）。
- 超额：发现 CRLF 幻影与「0.1.20261021 是 WSL 侧版本」两个事实，均已入表。
