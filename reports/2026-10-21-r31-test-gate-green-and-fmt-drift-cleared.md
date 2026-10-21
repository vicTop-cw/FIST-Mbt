# R31 · 权威测试门 1347/1347 零回归 + fmt 漂移技术前置已消（owner 可加速恢复门强度）

- 日期：2026-10-21
- 性质：验证（verify）
- 结论：**权威测试门 1347/1347 exit 0（195 脏下零回归）+ 工作树 `moon fmt --check` exit 0 全绿 + 本地 moon 已升 0.1.20261016（> CI nightly 0.1.20261012）** ⇒ AGENTS.md 记载的 fmt 版本漂移**已消**，fmt 门 `continue-on-error` 的**技术前置已满足**，剩余仅流程阻塞（WIP 收口）。已在 ci.yml 注释中记录该结论，owner 裁决时可直接引用。

---

## 一、权威测试门（moon test --target js）

```
moon 0.1.20261016 (1af328f 2026-10-16)
Total tests: 1347, passed: 1347, failed: 0.
exit=0
```

**并发 agent 195 脏工作树下零回归**——测试门仍是 1347/1347 基线，与 AGENTS.md 记载一致。

## 二、moon fmt --check（含并发 WIP 的工作树）

```
exit=0（全绿，工作树已按本地 moon 0.1.20261016 格式化）
```

此前 AGENTS.md 记载 "工作树 93 个 .mbt 未提交 WIP 未收口" 时 fmt 门 `continue-on-error` 是为了保护守卫族。现在 **fmt --check 在工作树上 exit 0**——并发 WIP 已被格式化到当前 moon 风格。

## 三、fmt 漂移已消（技术前置已满足）

| 项 | AGENTS.md 记载（诊断时） | 本轮实测（2026-10-21） |
|---|---|---|
| 本地 moon | 0.1.20260920 | **0.1.20261016** |
| CI nightly | 0.1.20261012 | 0.1.20261012（latest） |
| 版本关系 | 本地 < CI（不同代） | **本地 > CI**（更新） |
| `moon fmt --check` | rc=255 | **exit=0** |

AGENTS.md 记载的根因是 "本地钉版 0.1.20260920 与 CI nightly 0.1.20261012 两代 moon fmt 规则不同（新版把 Int 改写 Int32）"。**本地 moon 已升级到 0.1.20261016（比 CI nightly 更新）**，两代规则差异不复存在，fmt --check 全绿。

## 四、ci.yml 注释更新（commit `167ac5c`）

在 fmt 门注释追加 R31 复核结论：

```
# 2026-10-21 复核（R31）：本地 moon 已升 0.1.20261016（> CI nightly 0.1.20261012），
# 含并发 WIP 的工作树上 `moon fmt --check` exit=0 全绿 ⇒ 上面所述"两代 fmt 版本漂移"已消，
# 底层技术阻塞已清除。剩余仅流程阻塞（WIP 收口 + 一次 nightly 重排统一风格）；
# 在此之前 continue-on-error 仍保留（防 CI 侧 moon 版本波动 skip 守卫族），
# 但 owner 裁决时可直接以本条为"技术前置已满足"的证据，不再需要重新诊断漂移。
```

**故意不撤 `continue-on-error`**：AGENTS.md 明确要求 "并发 WIP 收口后跑一次 nightly 全仓重排，统一风格后即可撤销"。CI 侧 moon 仍是 latest，若版本再波动会 skip 守卫族（CI #275 实证）。技术阻塞已消但流程阻塞未到，撤门是 owner 的 WIP 收口后裁决项。

## 验证

- YAML 合法：`yaml.safe_load` OK，jobs = `[check-and-test-js, check-native, check-windows-js]`（注释改动不影响结构）
- `moon test --target js` 1347/1347 exit 0（新鲜重跑）
- `moon fmt --check` exit 0（含并发 WIP 工作树）

## 资源消耗

- 1 次权威测试门全量重跑（1347 测试）
- 1 次 `moon fmt --check` 全仓
- 1 次 ci.yml 注释编辑 + YAML 校验

## 任务分配记录

- 无新派单。src/server 仍 36 脏（R18 第十八轮）。

## 遗留风险

1. **src/server 36 脏（十八轮）**：issue_scan 家族 6 条（327/333/345/346/347/348）+ BUG-339 仍压在脏区。
2. **BUG-339 仍 OPEN**：并发 agent `f6e4019` 独立复核确认 commit-pairing 死锁未解。需 owner 协调一揽子提交。
3. **fmt 门强度未恢复**：技术前置已消，但撤 `continue-on-error` 须等 WIP 收口 + 一次 nightly 全仓重排确认。本轮注释已把"技术前置已满足"写入 ci.yml，owner 可直接引用。
4. 全仓 .mbt 子系统仍在并发脏区，无法安全扫描寻虫（R30 已用干净子系统确认 issue_scan FP 噪音淹没真告警）。

## 后续建议

1. **owner 裁决 fmt 门恢复**：技术前置已消（本轮实测），建议 WIP 收口后直接跑一次 `moon fmt --check`（本地 0.1.20261016）+ nightly 重排确认，然后撤 `continue-on-error` 恢复门强度。本轮 ci.yml 注释已记录证据，无需重新诊断。
2. **规则层批次优先级**（R30 实证 264 条 100% FP 后再次强调）：src/server 清空后第一批落地 BUG-345/346/347/348。
3. BUG-339 成对提交（server.mbt + bug335 锁）须同一 commit，需 owner 协调。

## 来源

- `moon test --target js` 新鲜重跑回执（1347/1347 exit 0，2026-10-21 10:16）
- `moon fmt --check` 新鲜重跑回执（exit 0，2026-10-21 10:16）
- `moon version` 回执（0.1.20261016）
- AGENTS.md「Commit gate」节（fmt 门 policy）
- 本会话 R22/R24/R26/R27/R28/R29/R30 提交：`c7934f3` / `b4665e2` / `a15ab01` / `d5464bb` / `0b9c649` / `8ab683e` / `2b385ad`