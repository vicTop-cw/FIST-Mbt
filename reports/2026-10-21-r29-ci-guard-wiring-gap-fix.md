# R29 · 修复 CI 守卫接线缺口：2 个死重守卫接入门禁（19→21）

- 日期：2026-10-21
- 性质：清整/修复（tidy/fix）
- 结论：**发现并修复 CI 守卫接线缺口**——`check_desc_enum_sync` 与 `check_upgrade_installer` 两个 PASS 守卫**不在 CI**（死重不门禁），已接入 `.github/workflows/ci.yml`。CI 守卫 19→21，真跑 19/19 全绿零回归。

---

## 缺口发现（真实、干净文件可修）

对守卫族做**接线审计**：磁盘上 22 个 `check_*.py` 与 CI 引用逐一比对。

| 守卫 | selftest | 真库 | 原 CI | 判断 |
|---|---|---|---|---|
| check_desc_enum_sync | OK | PASS | ❌ 未接 | **缺口：真守卫应门禁** |
| check_upgrade_installer | OK(G1×5+G2×5+G3×8) | PASS | ❌ 未接 | **缺口：真守卫应门禁** |
| check_plan_landing | OK | exit=1 | ❌ 未接 | **正确**：刻意非门禁诊断（exit=1 会砸 CI） |
| 其余 19 | — | — | ✓ | 已接 |

根因：并发 agent 新增了这些守卫并保证 `--selftest` 可红可绿，但**忘了接 CI**。守卫 PASS 而不在 CI = 死重——它今天能过，不代表它拦得住将来的回归。

## 修复（commit `8ab683e`）

在 `.github/workflows/ci.yml` `check-and-test-js` job 的 skill-inject guard 之后，按同款样式接入两个守卫（`--selftest` + 真跑）：

```yaml
- name: Desc-enum-sync guard (report_bug.severity 等描述侧枚举 ↔ 闭集一致)
  shell: bash
  run: |
    python3 scripts/check_desc_enum_sync.py --selftest
    python3 scripts/check_desc_enum_sync.py

- name: Upgrade-installer guard (升级安装器可红可绿，自证不误红)
  shell: bash
  run: |
    python3 scripts/check_upgrade_installer.py --selftest
    python3 scripts/check_upgrade_installer.py
```

`check_plan_landing` **刻意不接**——它的 exit=1 是诊断读数（"有落点未落地"），接进 CI 会把正常状态判红。

## 验证

- YAML 合法：`yaml.safe_load` OK，jobs = `[check-and-test-js, check-native, check-windows-js]`
- CI 守卫引用 19→**21**；两守卫已确认接入
- 真跑 21 接线守卫（排除需 `moon_test_log` 参数的 `check_badge`/`check_test_sync`）：**PASS=19 RED=0**
- 零回归：`check_publish_payload` / `check_plugin_sync` / `check_tools_sync` 全 exit 0

## 资源消耗

- 1 次守卫↔CI 接线比对
- 1 次 ci.yml YAML 解析 + 编辑
- 1 次 21 守卫真跑模拟

## 任务分配记录

- 无新派单。src/server 仍 36 脏（R16 第十六轮）。

## 遗留风险

1. **src/server 36 脏（十六轮）**：issue_scan 家族 6 条（327/333/345/346/347/348）+ BUG-339 仍压在脏区。
2. **BUG-339 仍 OPEN**：`bug335_ns_route_wbtest.mbt` tracked=0、HEAD server.mbt 无 `publish_parallel_route`（R27 复核，未变）。成对提交须同一 commit。
3. `check_plan_landing` 的 63 条"计划点名但不存在"路径是历史文档腐烂读数，属并发收尾范围。
4. 全仓 .mbt 子系统全部在并发脏区（src/store 6 / engine 33 / ops 18 / router 14 / display 4 / diff 2 / evolve 6），无法安全扫描寻虫。

## 后续建议

1. 并发收口后跑一次全守卫族，确认无新增红。
2. src/server 清空后按 R23 六顶帽工件单批落地（347→345→346→348）。
3. 守卫族接线审计可推广到 `fist-ci.yml`（native 臂），确认关键守卫双 CI 都门禁。

## 超额内容

- 首次对守卫族做 **CI 接线审计**（此前只查"判据红不红"，没查"判据接没接 CI"）。
- 发现并修掉 2 个死重守卫；同时确认 `check_plan_landing` 不接是**正确的**（避免误接一个 exit=1 诊断把 CI 砸红）。

## 来源

- `.github/workflows/ci.yml` 接线实跑比对（2026-10-21 10:00）
- `scripts/check_*.py` 22 个判据 selftest + 真库实跑
- 本会话 R22/R24/R26/R27/R28 提交：`c7934f3` / `b4665e2` / `a15ab01` / `d5464bb` / `0b9c649`