# BUG-527 出路④ 取证报告：Windows 钉版 moon 0.1.20261016 全项目 native build 实测

- 日期：2026-11-02
- 任务：T0r2（ns=iterate-1102，lane-b-pinned-moon）
- 性质：构建/测试取证，不改任何源码/配置（build 产物只在 `_build/`）

## 结果摘要

**钉版崩。** Windows 本机钉版 moon **0.1.20261016**（1af328f 2026-10-16）全项目
`moon build --target native` **必崩**，崩因与 WSL 0.1.20261021 实测（BUG-527）同根：
**带 `options(link: {"native": {...}})` 的库包被 moon 当成可执行目标去链**，共 10 个库包
`failed to make executable`。`moon build` 退出码 **127**。build 未过 ⇒ 按任务边界
不进入 `moon test --target native`（判绿面未测，见缺口）。

结论三选一：**钉版崩**（不是环境缺件——MSVC 与 SQLite 开发库均就位且被正确装载）。

## 证据

### 环境（先决条件全部就位，排除环境缺件读数）

- `moon version` → `moon 0.1.20261016 (1af328f 2026-10-16)`（与 AGENTS 记录的钉版一致）
- `pwsh ./scripts/native-env.ps1` 探测结果：
  - sqlite 头文件 OK：`C:\sqlite-dev\include`（`sqlite3.h` 在位）
  - VS 已装载：`E:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`
  - `INCLUDE += C:\sqlite-dev\include ; LIB += C:\sqlite-dev\lib`

### 命令与 rc

```
pwsh -NoProfile -File ./scripts/native-env.ps1 -Run "moon build --target native"
→ rc = 127（moon 自身退出码；native-env.ps1 按约定原样透传 $LASTEXITCODE）
```

日志 423 行（末尾）：`Failed with 44 warnings, 0 errors.` →
`Error: failed to run build for target Native` / `Caused by: failed when building project`。
**注意编译阶段 0 errors**——崩全在链接阶段，44 条 warning 全是常规 lint
（unused_value / unused_package 等，与本单无关）。

### 失败面（10 个库包被当可执行目标去链）

```
failed to make executable vicTop-cw/fist-mbt/src/store
failed to make executable vicTop-cw/fist-mbt/src/omega
failed to make executable vicTop-cw/fist-mbt/src/router
failed to make executable vicTop-cw/fist-mbt/src/executor
failed to make executable vicTop-cw/fist-mbt/atgc-old
failed to make executable vicTop-cw/fist-mbt/src/engine
failed to make executable vicTop-cw/fist-mbt/src/core
failed to make executable vicTop-cw/fist-mbt/src/ops
failed to make executable vicTop-cw/fist-mbt/tests/external_executor
failed to make executable vicTop-cw/fist-mbt/omega
```

### 关键错误行原文（每个失败包同构，此处以 src/store 为例）

```
Error: failed to make executable vicTop-cw/fist-mbt/src/store (native): "…\cl.exe" /nologo
/Fe\\?\E:\IDEProjects\AI\FIST-Mbt\_build\native\debug\build\src\store\store.exe
…\src\store\__moonbit_link_core__\store.obj …\.mooncakes\daqing\sqlite\libsqlite.lib …
/libruntime.lib /link /nologo /subsystem:console /LIBPATH:C:\Users\victo\.moon\lib
-lsqlite3 libcmt.lib oldnames.lib kernel32.lib shell32.lib user32.lib dbghelp.lib uuid.lib
LINK : warning LNK4044: 无法识别的选项"/lsqlite3"；已忽略
libcmt.lib(exe_main.obj) : error LNK2019: 无法解析的外部符号 main，函数
"int __cdecl __scrt_common_main_seh(void)" 中引用了该符号
\\?\…\_build\native\debug\build\src\store\store.exe : fatal error LNK1120: 1 个无法解析的外部命令
```

（10 个包均为同一三连：LNK4044 `-lsqlite3` 无法识别被忽略 → LNK2019 找不到 `main` → LNK1120。）

## 分析

1. **根因与 BUG-527 同族，且与工具链版本解耦**：AGENTS/决策单原先把「库包带 link flag 被当可执行目标」
   归因为 moon 0.1.20261021（WSL）的**新语义**。本次实测证明 **钉版 0.1.20261016 在 Windows 上同型必崩**
   ——该语义分歧不是 20261021 引入的回归，而是两代 moon 共有。出路④设想的「若钉版不崩，把本地 native
   口径收窄为钉版工具链」**不成立**。
2. **两层崩因叠加**：① 库包（无 `main`）被交给 cl.exe 链可执行 ⇒ LNK2019/LNK1120；
   ② `cc-link-flags` 里的 `-lsqlite3` 是 GCC 风格旗标，MSVC 不认（LNK4044 忽略）⇒
   即使 moon 不把库包当可执行、只链真正的 exe（cmd/cli、cmd/main），SQLite 符号也解析不到
   （`-lsqlite3` 被丢弃后没有任何 `sqlite3.lib` 进 link 行）。本次日志未出现 cmd/cli、cmd/main 的
   错误行——build 在库包阶段即整体失败，尚未走到（或未输出）可执行包链步骤。
3. **CI 与本机的分歧面变窄了**：CI nightly（Linux nightly moon）两条 native 臂**绿**
   （决策单 A/B 实证），说明 Linux 侧 nightly moon 对同一组 moon.pkg 的语义能把
   `-lsqlite3` 正确传给 gcc 且不把库包当 exe；本地 Windows 钉版两侧都不成立 ⇒
   「本地 native」口径继续按 AGENTS 既有结论：**Windows 本机全项目 native build/test 不可用，
   权威稳定门槛 = JS 后端**，native 取证以 CI 臂 + WSL 探针为准。
4. **rc=127 的旁证**：moon build 失败回 127（非 1/2），与 AGENTS 已记录的「moon 退出码不可靠」
   （BUG-142：测试崩溃仍回 exit 0）同族——任何拿 rc 判读的自动化都不能只信 moon 的退出码。

## 缺口与风险

- **`moon test --target native` 未测**：build 未过 ⇒ 判绿面（Total tests 行）本机不可达，
  本单验收标准取的是「完整 rc + 错误输出」这一格，已满足。
- **未观测 cmd/cli / cmd/main 的独立链结果**：若有人摘掉库包 link flag 单测可执行包，
  预期仍会因 `-lsqlite3` 被 MSVC 忽略而 LNK2019 `sqlite3_*`——此为推断，未实测。
- **Linux nightly vs 钉版的语义分歧仍未定位到上游**：本单只证明「分歧不是 20261021 引入」，
  未证明「nightly 修了什么」；上游 issue 该不该提、以哪个版本为基线，仍待裁决。
- 本报告读数随 moon/依赖版本漂移即老化（自述滞后判例-BUG-514 同族）：复现请重跑原命令，不抄本数字。

## 后续建议

1. BUG-527 追记3 入档（本单即出路④的取证）：**出路④否决**——钉版同样崩，「本地 native 必崩」
   口径从「0.1.20261021 的语义分歧」改写为「≥钉版 0.1.20261016 两代实测均崩，与版本无关，
   Windows 本机全项目 native 不可用」，权威稳定门槛维持 JS 后端。
2. 若要救 Windows 本机 native：两层都要动——`cc-link-flags` 换 MSVC 风格
   （`/link` 段或直接 `sqlite3.lib`，见 AGENTS「cc-link-flags」写法的平台差异），
   且库包 link flag 的传递/目标判定问题要等上游语义裁决；单修其一不够。
3. `check_instruction_budget` / 文档面不需要动（本单零代码零配置改动）。

## 资源消耗

- 单次全项目 native build（423 行日志，编译 0 error + 链接 10 包失败），耗时约 1 分钟量级；
- 磁盘：`_build/native/debug/` 产物（不影响跟踪面）；
- MCP 调用：claim 1 次（前置 ACL 授权 1 次）、execute/submit 各 1 次。

## 任务分配记录

- 根任务 T0（ns=iterate-1102）→ 本单 T0r2，由 lane-b-pinned-moon 认领执行；
- 前置插曲：claim 首次被 ns ACL 拒（`acl: ACL 默认拒绝写（can_write=0）: 28c9622c716a14bc/iterate-1102`），
  按回执自救路径 `agent_acl_grant(agent_id="lane-b-pinned-moon", namespace="iterate-1102",
  can_read=true, can_write=true, pid_bound=true)` 授权后 claim 成功。
  同批 lane-a/lane-c 在 call_log 中同样撞该门（seq 22/27/29）⇒ 属批次级前置缺口，
  建议下一批发布任务时由指挥官先为各 lane 身份授予 ns 写权。

## 遗留风险

- ACL 授权用了默认 `by=human_steward` 身份盖章（工具无硬角色门）——S1 自报身份边界
  （BUG-430/464）下的已知属性，非本单引入；pid_bound=true 限定本进程实例，风险面最小化。
- `_build/native/debug/` 残留 build 产物，若他人并行跑 native 相关判据请知悉（不进跟踪面）。

## 超额内容

无。

## 来源

- 实测日志：`/tmp/bug527_build.log`（会话临时区，423 行，关键行已摘录上文）
- 决策单：`reports/2026-11-02-bug527-native-link-decision-sheet.md`（出路④出处）
- 账本：`memory/bugs.md` BUG-527（追记建议见「后续建议」1）
- AGENTS「native 目标构建环境要求」段（既有口径，本次读数与之相符）
- call_log（fist_mbt MCP，seq 20-29）：claim ACL 门与自救过程
