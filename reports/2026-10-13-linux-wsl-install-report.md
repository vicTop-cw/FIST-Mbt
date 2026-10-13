# 2026-10-13 G5「Linux 同等实现（WSL2 实测）」端到端验证报告

## 结果摘要

SHIP-PLAN-BLACKBOX-v2 的 Gap 清单 G5（「WSL2 未实测——Linux 安装脚本理论有、WSL2 实际未知」）本轮**功能面实测通过**：Linux(WSL2) 侧走 `install.sh` 全流程装出的产物与 Windows 侧**逐字节相同**，且 server 真起、工具真回。

关键读数（`temp/final10_direct.txt`，脚本全程落盘不靠 stdout）：
- 装后 `fist-mbt.js` **md5 = `985f2209c51e1ae9afbdb7e1a507aebd`**，与 Windows 侧 `_release/js/fist-mbt.js`、`_build/.../cli.js`、本机已装 `AppData/Local/FIST-Mbt/fist-mbt.js` **三处全等** ⇒ 跨端同码。
- `fist version` / `fist-mbt version` = **FIST-Mbt v0.3.8**；ESM `createRequire` 注入 1 处；install.sh 自检两格 ✅。
- MCP 冒烟：`node fist-mbt.js serve` 在 Linux node v25.2.1 下**真起 server**，`tools/list` 回 **163 工具**（`SERVE_OK`）。
- 环境：WSL2 root、node v25.2.1、python3、curl/unzip 齐（`temp/wsl_pre.sh` 探针逐条 `command -v` 真值，非 pwsh 内联假读数）。

## 资源消耗
- 一次 WSL 端到端离线安装（解压/装/shim/自检/serve 冒烟）；三次前置探针与两次失败重跑（step7/step9，见「遗留风险」的方法教训）。全程不联网下载（走 `FIST_LOCAL_ZIP` 离线口子）。

## 任务分配记录
- 指挥官亲自：设计 step7→step10 的收敛路径（每步落盘读文件）、定位 CRLF 假警报的成因（工作树副本 vs git blob）、把 G5 拆成「网络面」与「功能面」分别定死。
- 未派子代理：跨 shell 验证强依赖实机 WSL 环境与逐字节对照，拆给子代理反而多一层终审。

## 遗留风险
1. **公网下载线未在此机 WSL 测通（环境限制，非产品缺陷）**：step9 A 段实测 WSL 直连 `github.com`（下载主机）**25s 超时**，而 `api.github.com`/`objects.githubusercontent.com` 都通（TLS 活着）——本机 WSL 不走 Windows 系统代理。故 G5 的「下载」这一发用 `FIST_LOCAL_ZIP` 离线口子验，功能全链路其余段（解压/shim/ESM/自检/serve）全走真码。**诚实边界：不能说「Linux 公网 curl|bash 端到端已实测」，只能说「Linux 安装器功能面已实测、公网下载面受本机网络限制未测」。**
2. **R6「200≠拿到文件」同族的又一格，Linux 侧也现形**：step8 走真下载线时，源1 `gitcode.com/.../releases/download/…zip` 回 **HTTP 403**（正文 `{"error…`），install.sh 正确识别「给的不是 zip」并换源——与 install_onecmd.ps1 那条「GitCode 主源第一档其实一直取不到、全靠 fallback GitHub」的假主源发现同形，且证明**换源逻辑在 Linux bash 下确实执行**。
3. **`.gitattributes` 缺失是潜在坑（本轮没踩到产品，但踩到自己的测试）**：`install.sh` 的 git blob 实测**纯 LF（CR=0）** ⇒ 用户 `curl|bash` 拿到的没问题；但本机 `core.autocrlf=true` 下 Windows 工作树副本是 **CRLF（CR=260）**，step7/step9 我误跑工作树副本 ⇒ `line 15: $'\r': command not found` + `set: pipefail: invalid option`。任何人**从 Windows 工作树直接跑**（非 curl|bash）`.sh` 都会炸。补 `.gitattributes` 强制 `*.sh text eol=lf` 可消除，但该文件是否加属仓库级约定，留 owner。
4. **initialize 非标那格 Linux 同现**：`Method not found: initialize — this server speaks MCP 2026-07-28` 在 Linux 也复现（与 Windows 八发记录的找 bug 线索 2 同形），非 Linux 特有，`tools/list` 仍正常应答。

## 后续建议
1. 若要坐实「Linux 公网 curl|bash 端到端」：在能直连 github.com 的 Linux（或配了代理的 WSL）上跑 `install.sh` 不带 `FIST_LOCAL_ZIP`；本机受网络限制只能测功能面。
2. 加 `.gitattributes`（`*.sh text eol=lf`、`*.ps1 text eol=crlf`）——同时消掉「工作树 CRLF 的 .sh 在 Linux 炸」这一类环境相关假警报，且与本仓已有的 `check_ps_encoding`（BUG-88）互补。
3. G5 之后，SHIP-PLAN 剩余 Gap 只有 **G7「CI 自动发布接 GitCode」**（本轮已探：GitCode v5 只认 `/user`，项目/releases 端点 404，且不可逆发布步需 owner 拍板 + 可用 API 事实，见 memory 2026-10-13 G7 段）。

## 超额内容
- 顺带把「测试脚本跨 shell 复跑要先确认工具链在 PATH + 字节形状（LF/CRLF）」这条方法教训写进 memory（step7/9 的两次假警报根因），避免后续再来一回。
- 复用 step10 的一次运行同时验到 R6 换源逻辑在 Linux 侧执行、以及 initialize 非标格跨端一致。

## 来源
- 实测日志：`temp/final10_direct.txt`（功能面全链路 + md5 + serve 冒烟）、`temp/final9_direct.txt`（网络面 curl 逐源超时/403/404 读数）、`temp/final8_direct.txt`（首次 LF 化尝试 + R6 换源现形）、`temp/wsl_pre.sh` 探针输出。
- 被验对象：`scripts/blackbox/install.sh`（git blob CR=0 实测）、`_release/fist-mbt-js-v0.3.8.zip`。
- 台账：`docs/SHIP-PLAN-BLACKBOX-v2.md` §需求④ + Gap G5（本轮翻账）。`memory/2026-10-13.md` 的 G5 段**本轮刻意不写**——该文件并发会话有未提交的 R13 段（HEAD 止于 107 行、工作树 136 行），整份 add 会代提交他们的账，而只提交自己段又会被他们后续整份 add 抹掉；待该文件腾清再补，故本报告即 G5 的一手记录。
- 跨端 md5 对照：`Get-FileHash`（Windows 三处）vs `md5sum`（WSL 一处），同值 `985f2209…`。
