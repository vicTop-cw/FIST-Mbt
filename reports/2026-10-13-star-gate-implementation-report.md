# 2026-10-13 Star 门端到端实装报告

## 结果摘要

Star 门（星门）从「代码就绪、CI 从没跑通过」推进到**端到端实跑跑通并全链路验签 PASS**：

- 授权链落地：repo secrets `ED25519_PRIVATE_KEY_HEX`（签名私钥）+ `STAR_GATE_PAT`（拉 stargazer 名单）已设；GitHub Pages 已启用（`build_type=workflow`）。
- 线上清单就位：`https://victop-cw.github.io/FIST-Mbt/_attest/attestation.json` **HTTP 200**，内容 = `{list:["vicTop-cw"], issued_at, ttl:21600, public_key_hex, signature_hex, algorithm:ed25519, format:fist-star-gate-attestation/v1}`。
- 端到端验签：**钉死公钥一致 / Ed25519 验签通过 / TTL 剩余 21547s / 名单含 vicTop-cw**（金条八：真拉线上产物本地复算，不据 CI 绿灯自证）。
- 自动刷新：`cron 0 */6 * * *` + `watch: started`（star/unstar 即时重签）。
- 门禁语义按 owner 裁决维持：未 star 用户走自动路由需先 star 再等名单刷新（≤6h 或即时），否则免费池 fail-closed 锁定。

`attest.yml` run#9（head=`03460b1`）**attest + selfcheck 双 job success**——这是该 workflow 历史上第一次真跑通（此前 secret/Pages 从未配齐，从没跑到构建步）。

## 资源消耗

- 5 轮 CI 实跑红→修（run#4/#5/#6/#8 各定位一格真 bug，run#9 绿），每轮 setup-python + pip + python 签名 + Pages deploy。
- 4 次 GitHub API 写操作（2 个 secret PUT、1 次 Pages 启用、1 次 workflow_dispatch ×3）。
- 本地临时脚本 3 支（temp/，gitignored），零密钥落盘、零密钥回显。
- 一次 git merge 收外部 force-update（见「遗留风险」）。

## 任务分配记录

- 指挥官亲自：密码学一致门校验（私钥派生公钥 ↔ 源码常量 ↔ 发布模板三方对表）、secrets 设置、Pages 启用、attest.yml 五连修、served URL 对齐、端到端验签、拓扑处置（origin force-update 后先核对再 merge，绝不强推）。
- 未做子代理分派：本任务每一步都依赖真实 CI 读数与密钥操作，属不可拆的串行验证链。

## 遗留风险

1. **origin 曾被外部 force-update**（`bce150b...4f96ef5 (forced update)`，GitHub→gitcode 的 add-only sync 链所为）：它把分步提交重打包成一个合并提交。本轮已核对「其内容 == 我的修复」才 merge；**但它同时带进了重复的 `upload-artifact`（同名 `star-gate-attestation` 两条）导致 run#8 红**——同步链合并不是无风险，后续每次 merge 后必须重验 CI 面。
2. **Pages 站点根 404**：bundle 里只有 `_attest/attestation.json`，没有 `index.html`，站点根回 404（清单文件本身 200）。目前无害，若以后要 Pages 展示更多文件需补 index。
3. **`STAR_GATE_PAT` 是 owner 个人 classic PAT**（scopes 极宽，admin 级）：它进的是 repo secret、只在 attest.yml 里用。纪律上更该用最小权限的细粒度 token（只读 members/user）——owner 侧决定，本仓已留换法（换 secret 值即可，workflow 不用改）。
4. **弱门禁定性不变**（attest.yml 头注 + improvement-plan §3.2）：清单在客户端本地校验，改本地缓存可绕过；信任根 = GitHub Pages HTTPS + 仓库完整性，Ed25519 只自证「CI 跑过且载荷没被改坏」。
5. GitHub Release v0.3.8 仍未产出（release.yml `MOON_VERSION: latest` 那格，独立问题，见 2026-10-12 三发记录）。

## 后续建议

1. 把 `STAR_GATE_PAT` 换成最小权限细粒度 token。
2. release.yml 钉 moon 版本，让公网 Release 与本地命令同码。
3. 若要对外宣称"star 才能用"，建议在 README 安装段加一句解锁指引（指向 `/_attest/attestation.json` 与三个 env），否则新用户只会看到 fail-closed 而不知何故。

## 超额内容

- 顺手定位并修复 **5 个从没现形的 attest.yml 真 bug**（该 workflow 因 secrets/Pages 长期缺位从未跑到过，所有错误都是首次实跑才暴露）：
  1. 缺 PyNaCl 依赖（ubuntu runner 不自带）；
  2. 默认 `github.token` 拉 `/stargazers` 恒 403（实测，需 PAT）；
  3. `verify_key.encode(hex=True)` 在当前 PyNaCl 不存在（TypeError）；
  4. selfcheck 误拿 `github-pages` bundle 当数据源（那是 artifact.tar 外壳，文件必然不存在）；
  5. Pages served URL 与文档承诺路径不一致（`upload-pages-artifact` 把 path 的**内容**当站点根，`path: _attest` 会让清单落站点根，照文档写 `_attest/` 去拉的人 404）——加 staging 一步对齐。
- 另记两格工具链教训（已入 memory）：pwsh 里 curl 内联 JSON 转义失败会让 dispatch 静默不生效（`Invoke-WebRequest -InFile` 可靠）；Windows 下 python 打印非 GBK 字符需 `sys.stdout.reconfigure`。

## 来源

- `.github/workflows/attest.yml`（修复链 `550d3f1` → `b4e93ba` → `0ceeb69` → `bce150b` → `2693554` → `03460b1`，均已推 origin + gitcode）
- 真源：`src/router/star_gate.mbt`（`star_release_default_pubkey_hex` / `star_gate_policy` / `star_gate_verify_pinned`）、`src/server/model_router_ops.mbt`（env 读取 + 硬门短路）
- 线上原件：`https://victop-cw.github.io/FIST-Mbt/_attest/attestation.json`（本地留档 `temp/att_final.json`）
- 记录：`memory/2026-10-13.md`「Star 门实装端到端跑通」段；前序 `memory/2026-10-12.md` 二发（默认开启裁决）、`docs/improvement-plan-20261010.md` §3.2（设计与诚实边界）
