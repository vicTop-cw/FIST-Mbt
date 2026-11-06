# BUG-577 批 · §4.1 运行时描述串面收口 + 统帅行尾事故自纠 · 汇报

- 批次：2026-11-06 统帅亲笔收口批（本地两笔 `0c057dcbd` 主件 · `9334713b6` 行尾修复；**未推送**，本地领先 `origin/main` 44 笔）
- 台账：`memory/bugs.md` BUG-577（medium，OPEN→FIXED 一步到位）；投影现读 `BUG-1~577 共 562 条：5 待修 / 516 已修 / 13 重复并入 / 28 误报`

## 1. 结果摘要

这一批收的是 **BUG-575 立账时自己点名「本单不收口」的两面**，它们的取数面与散文面不同，故单立一单：

1. **工具描述串（客户端可见面）**：`src/server/server.mbt` 里 `agent_register_key` 的描述仍写
   「已有公钥且与本次不同 ⇒ 拒绝（需走轮换，尚未实现）」，而**同一文件**的 `key_pin_reject_message`
   早已写明「S3 第八段已实现」⇒ 每个客户端经 `tools/list` 读到的都是「这个能力不存在」。
   现改为点名两步链（带 `rotate_sig` = 用旧私钥签服务端签发的 `rotate_challenge` 即换；
   私钥已丢先 `agent_revoke_key` 吊销再重登），并保留仍成立的半限制「吊销不验调用方（S1）」。
2. **函数搬家型文档滞后**：`docs/integration/s3-client-bootstrap.md` 写「`reserve_scope`/`lock_acquire`
   重放目前不拦（走 `judged_role_gated`，只验签不消费）」——BUG-477 后两处门都改走 `judged_role_with_nonce`。
   现点名**现读**消费点 `rsv_try_set`:816 / `locks_try_acquire`:962。

## 2. 资源消耗

- 工具面：`Bash`/`Read`/`Grep`/`Write`/`Edit`、`mcp_call`（fist-mbt：`claim` 后的 T0 主线）、`Task*`
- 子代理：**0**（本轮没有可用的车道执行面——worktree 切点被环境钉在 `0844a12d7`，
  上一批三条车道里两条因基线作废、一条 model interrupted；S3 车道停手前交的取证成为本批依据）
- 判据当跑：`check_tools_sync` rc=0 / `check_doc_surface` rc=0 / `check_arg_face_strict` rc=0（97 把）/
  `check_fmt_gate` rc=0（`moon fmt --check` rc=0）/ `moon_test_env --target js src/server` =
  `Total tests: 586, passed: 586, failed: 0` / `check_bug_ledger_shape` rc=0 /
  `check_plugin_sync`（cl7）rc=0 / `check_text_control_chars` rc=0 / `check_doc_dup` rc=0 /
  `check_hardcoded_paths` rc=0 / `check_publish_payload` rc=0（1956 件、未跟踪 0 件）

## 3. 任务分配记录

| 单位 | 归属 | 状态 |
|---|---|---|
| `server.mbt` 工具描述串取证 | lane-stale-S3（上一批） | 车道因基线自检停手，**取证可用**；落地由统帅亲笔完成 ⇒ 记 FIST `iterate-1106`/T0r3 已收 |
| `docs/integration` 重放行 | 同上 | 同上（断言修正后落笔） |
| BUG-577 记账 + 投影 + 行尾修复 | 统帅 | 本批完成 |
| §4.1 常驻门 `check_stale_self_claim` | FIST T0 / 任务 #41 | **未交付**（车道中断 + 车道切点环境态） |
| 门禁尺单一谓词同源 | FIST T0r2 / 任务 #43 | 未动工（同样受切点阻塞；要点已写在单里） |

> 分流裁决说明：本轮「忌亲力亲为」让位于「车道执行面当前不可用」——四条 worktree 全钉在同一个过期切点，
> 派单只会重复收获「停手」。亲笔的两处都是一行文本 + 现读取证，且取证已由车道做完。

## 4. 遗留风险

1. **`dist/fist-mbt.js` 仍烤旧描述串**：`.mbt` 改完，产物没刷 ⇒ 公网装出来的那份还在撒谎。
   刷新走 `scripts/refresh_dist.py`（需 moon build 产物并写盘），本轮未跑。
2. **§4.1 无常驻门**：本批两类形状（运行时串滞后、函数搬家后文档滞后）都靠人眼 + 现读 grep 发现；
   `check_stale_self_claim` 不落地就会复发。这是这条线真正的关闭条件缺口，不是「细节待补」。
3. **`engine_rsv.mbt:322`「nonce 表不落库、跨进程不共享」**同类滞后，本批未动（未先全量 grep 判定面，不猜）。
4. **统帅自造的行尾事故暴露一处判据盲区**：138 处 `\r\r\n` 落盘时，`check_text_control_chars`、
   `check_doc_surface`、`check_plugin_sync`、`check_hardcoded_paths` 全部 rc=0，
   **唯一暴露它的是 `git show --stat` 的行数**。⇒「diff 规模 == 预期改动面」目前没有尺在判。
5. **44 笔未推送**（owner 红线）；staleness 类判据只扫 `gitcode/main`，推送前本地红是预期态。

## 5. 后续建议

- 下一轮第一件事：把「diff 规模 vs 预期改动面」做成提交前的一行自检（或给 `commit_scoped.sh` 加一档
  「单文件改动行数 > 3× 申报行数即问一句」），本轮的形状已实测两次（车道 patch 合流 + 自写脚本）。
- `check_stale_self_claim` 的两条取数面必须分开判：**注释面**（可 grep 文本 + 调用点对表）与
  **运行时字符串面**（要扫 `server.mbt` 注册块里的字面量，并处理「工具描述长度上 wire」的约束）；
  合成一把会两边都判不准。
- 车道执行面的环境态：worktree 切点固定 `0844a12d7` ⇒ 派单前先确认能否从 HEAD 起树，
  不能就明说是统帅亲笔批，别让车道重复停手（这轮已收获两次同样的停手）。
- owner 侧待裁决清单不变：BUG-527 出路②、BUG-538 连接器重连、BUG-542 A/B、BUG-565 A 三案 + B 启动器、BUG-566 harness 侧。

## 6. 超额内容

- **探针自纠**：第一版脚本断言「nonce 调用点 ≥3」被现读（2 处）当场 fail-closed；复查发现
  claim 的预取**刻意**走 `judged_role_with_challenge`（只验签不消费，防双消费）⇒「2 处才是事实」。
  断言改为「`rsv_try_set` 与 `locks_try_acquire` 两个函数必须命中」后主张成立才落笔。
  上一轮我把这次否决记成「该行维持未改、待重测」——那是把**尺坏**当成**事实未定**，本批纠正并入账。
- **fail-closed 双闸**：`server.mbt` 内找不到同文件真源「S3 第八段已实现」即不写；锚点命中非恰 1 即不写。
- 申报面偏差如实写明：描述串字数 **+135**，超出我给自己写的「>120 必须收紧」线；
  保留理由是多出的半句承载仍成立的 S1 限制，删掉就是把低估翻成高估（不是静默越线）。

## 7. 来源

- `memory/bugs.md` BUG-577 条目与其 `### FIXED` 证据段（含读数、偏差申报与遗留面）
- `memory/2026-11-06.md` 续27（行尾事故与探针自纠的过程记账）
- 上一批 lane-stale-S3 回传原文（`main:server.mbt:7734` 与 `main:7853-7937` 的逐字对照）
- 本批 §2 所列判据当跑结果；全量电池读数见 `temp/battery-574.log`（BUG-575/576 批）与本批收口后的补跑
- FIST 连接器：ns `iterate-1106`（T0 已 claim 为 `commander`，T0r2/T0r3/T0r4 在册）
