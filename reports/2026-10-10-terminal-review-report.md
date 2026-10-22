# 终审报告 · 四项遗留（A/B/C/D）+ Star 门公钥钉死边界

**日期**：2026-10-10
**结论**：A、B、D 三项经终审判定「按设计保持，不改代码」；**C 发现并修掉一份会丢数据的旧备份**；Star 门补上计划此前没写的另一半诚实边界（公钥钉死）。
**终态**：7 守卫全绿（4 必需 + 3 P2），工作树干净，commit `8110609`。

---

## 结果摘要

用户授权「你自己审，我看不过来，然后继续」。对收口汇报里点名的四项遗留逐条终审，证据锚点全部落到守卫正文、真源代码或实测回执：

| 项 | 终审结论 | 依据 |
|---|---|---|
| **A · claude `.mcp.json` 相对 `_build/...` + `timeout_ms`** | **按设计保持，不改** | 守卫 `check_host_installable.py` 明写：宽松档「相对路径**不判**、`timeout_ms` 只打 **WARN 信息级不计 exit 1**」；**T4d 自检显式声明**「把默认模板带 Claude reconnect 误判红 → 三宿主 schema 不同名却逼通用模板改键名，是误伤」。真实可装路径是 `default-fist.mcp.json`（`command:"fist-mbt"` + `cwd:"."`，走 PATH），守卫 T4 已验绿。 |
| **B · `evolve_asset_register` score 默认 0** | **按设计保持，不改** | `src/evolve/evolve.mbt:146-149`：`score=0` 时采样权重走 `0.001` 下限，**不会永久封死**；且生态资产按 **D4** 走**显式 `inject`**（`check_skill_inject` S3 只查 id/goal/note/code、**不查 score**）。改默认值会把工具描述文本涟漪到 AGENTS/README/skill 十余面 + 插件重投影，零功能收益。正确杠杆是**调用方约定**：注册高价值资产时显式传 `score`。 |
| **C · `fist-mbt.db-wal` 备份能否恢复** | **能恢复，但旧备份缺 8 条 `[asset]` → 已补一份现势备份** | 实测（副本上，不改活库）：旧备份 `b141-3f648518` `integrity_check` 全 ok、14 表、tasks=2036、specs=829 可读；但对账发现 **evolve_artifacts total=16 / asset=0**，而活库 **total=24 / asset=8**（lesson=7、principle=9、max_score=94 两侧一致）——旧备份**恰好缺那 8 条 D4 生态注册**，恢复它会静默丢数据。 |
| **D · Star 门（D1=A）仪式化边界** | **定性维持「弱/仪式感门禁」，但补上 plan 没写的另一半** | `attest.yml` 是真 GitHub Actions + Pages：每 6h cron + star 触发，用 `ED25519_PRIVATE_KEY_HEX` 对 `{list, issued_at, ttl_seconds}` 做 canonical Ed25519 签名，发布到 Pages，`selfcheck` job 验回自己签的清单（反漂移）。 |

## 资源消耗

- 运行：`moon test --target js` **623/623 / exit 0**（终审前已跑一次，作为权威门槛复核）。
- 守卫：4 必需 + 3 P2 各跑一轮，**全部 rc=0**：
  - `check_plugin_sync` PASS：4 宿主 / 64 生成文件 / **134 工具** / v0.3.6
  - `check_doc_surface` PASS：134 工具逐个可查、J6–J14 全绿
  - `check_tools_sync` PASS：134 工具单真源
  - `check_publish_payload` PASS：将随包公开 596 件，未被 git 跟踪 **0 件**
  - `check_host_installable` PASS（严格档 + 宽松档 + 默认模板 + v0.3.6）
  - `check_model_auth_no_key` PASS（扫 40 份，无真凭据值形状）
  - `check_skill_inject` PASS：**已注册 8 条 `[asset]` 全部 asset_id 可反查且 note/code 非空可注入**（独立印证 C 的 8 条计数）
- 脚本：`temp/verify_backup_restore.py` / `temp/verify_backup_staleness.py` / `temp/take_fresh_backup.py`（均落 `temp/`，已被 `.gitignore:23 temp/` 覆盖，不随包公开）。

## 任务分配记录

- 终审与验证由指挥官（我）亲跑：这是「终审结果」职责，按 AGENTS.md 金条八「所有子任务结果由你终审」，不外包。
- 未发布新 FIST 根任务（四项遗留均为判读/结论类，无源码改动面）。

## 遗留风险（终审后剩余）

1. **Star 门公钥未离线钉死**（本次新写进 `docs/improvement-plan-20261010.md` §3.2 第 6 点）：`attest.yml` 把 `public_key_hex` 与 `signature_hex` 放在**同一个 payload**里一起发布，客户端没有离线钉死的期望公钥 → 该 Ed25519 签名只能自证「workflow 跑过 + 载荷自洽」，**对能改写 Pages/CI 产物的攻击者不构成认证**。要真正用上 Ed25519，须把期望 `public_key_hex` 在客户端离线钉死（源码常量或另一次独立签名发布）。与第 4 点的「本地改缓存绕过」是两条独立弱化面。
2. **Star 门 6h TTL + 6h cron**：CI 宕机 >6h 即 fail-closed 全员锁死；unstar 后最多 ttl 内仍可解锁（计划已写明，属模型性质）。
3. **8 条 `[asset]` score=0**：可注入但不参与多样性加权（`evolve_sample` 走 0.001 下限）。建议后续调用方约定显式传 score；不改框架默认。
4. **native 后端 BUG-133**（`mizchi/sqlite@0.3.1` FFI）仍在账，本轮**未**宣称 native 全绿；权威门槛=JS 后端。

## 后续建议

1. 若要给 Star 门加真正的签名强度：客户端钉死 `public_key_hex`（一行常量 + 一条「公钥不符即拒绝」白盒锁）。这会把弱门禁抬到「防 GitHub 侧篡改」的档位。
2. 备份纪律：保留现势备份 `temp/fist-mbt.db.backup-postreview-c635bcef`（已实测 total=24 / asset=8 / integrity ok），旧 `b141-3f648518` 降级为「更早时间点快照」；两目录均已附 README 自证。
3. 注册高价值生态资产时显式传 `score`（如 0.8），而非依赖默认 0。

## 超额内容

- **新增现势备份** `temp/fist-mbt.db.backup-postreview-c635bcef`（原不在计划内）：旧备份被证实缺 8 条 D4 资产后即时补一份，附 `README.md` 记录两侧差异与 integrity 复核方式。
- **终审探针** 3 个落 `temp/`：备份恢复验证、活库↔备份对账、现势备份取数与自证。

## 来源

- 守卫正文：`scripts/check_host_installable.py`（L7/25-39/411-419/429-450 T4d/T4e）、`src/evolve/evolve.mbt`（L146-149）
- Star 门实现：`.github/workflows/attest.yml`（L92-101 payload 含 self-carried `public_key_hex`；L114-138 selfcheck）
- 计划边界：`docs/improvement-plan-20261010.md` §3.2（原第 4 点本地改缓存绕过；本次新增第 6 点公钥钉死）
- 备份实测：`temp/verify_backup_restore.py`（RESTORE_VERDICT=OK）、`temp/verify_backup_staleness.py`（LIVE 24/8 vs BACKUP 16/0）、`temp/take_fresh_backup.py`（postreview-c635bcef，total=24/asset=8）
- commit：`8110609`（本报告对应的唯一源码树改动）
