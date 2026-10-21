# R34 · 修复 ocr_scan dry_run 契约（待应用）+ 发现仓库阻断：router_state 重复字段

- 日期：2026-10-21
- 性质：修复（fix_and_merge）+ 发现阻断
- 结论：**（A）确认 `ocr_scan --dry_run` 的 `ocr_available` 硬编码 bug，已写出最小修复补丁——但**（B）**发现 `src/router/router_state.mbt:211-212` 有重复字段 `use_caf_memory`（并发 agent 意外复制），Error 4043 使整个 src/router+src/server 包无法编译，全仓测试门当前是红的**。因无法满足 `moon test --target js` 全绿的提交门禁，**修复已回滚为待应用补丁**（见 §一），并报告阻断（见 §二）。

---

## 一、`ocr_scan` dry_run 契约修复（待应用，R33 发现的落地）

### 根因（已在 `src/server/ocr_scan.mbt` L269-294 精确定位）

dry_run 分支（先审后跑）**探测了**二进制（L272 `ocr_probe_binary`），却**硬编码** `ocr_available:true`（L278），探测结果被丢弃：

```moonbit
// L269-294 dry_run 分支（bug 在 L278）
if dry_run {
  let bin_hint = match ocr_probe_binary(project_dir) {
    Some(b) => b
    None => ""
  }
  return ocr_obj([
    ("ok", Json::boolean(true)),
    ("ocr_available", Json::boolean(true)),   // ← BUG：硬编码 true，探测结果丢弃
    ...
```

**实跑对比（本机无 opencodereview.exe）**：
| 调用 | `ok` | `ocr_available` |
|---|---|---|
| `dry_run=true` | true | **true**（误导） |
| `dry_run=false` | false | false（诚实） |

### 修复补丁（精确到行）

`src/server/ocr_scan.mbt`，把 L278 的 `Json::boolean(true)` 改为：

```moonbit
    // dry_run 仍按"先审后跑"回显 argv（ok=true），但 ocr_available 必须诚实反映探测结果：
    // 二进制不存在时回 false（与真跑路径 ocr_fail 一致），否则"先审后跑"的调用方会
    // 被 dry_run 的 ocr_available=true 误导、放心去掉 dry_run 真跑却直接失败。
    return ocr_obj([
      ("ok", Json::boolean(true)),
      ("ocr_available", Json::boolean(not(bin_hint.is_empty()))),
```

**已实跑验证**：
- `moon fmt src/server/ocr_scan.mbt` **exit 0**（语法/格式通过）
- diff 干净（1 文件 +4/-1）
- 类型正确：`bin_hint: String` → `.is_empty(): Bool` → `not(Bool): Bool` → `Json::boolean(Bool)`，无歧义

### 未提交的原因（诚实）

- **提交门禁要求 `moon test --target js` 全绿**（AGENTS.md）。当前因 §二 的 router_state 编译错，该门**不可满足**。
- 提交一个自己无法验证的改动会破坏提交门禁 + 让 CI 红。故**回滚为待应用补丁**（`git checkout -- src/server/ocr_scan.mbt`，已确认回滚干净）。
- **owner / 并发 agent 在 repo 恢复编译后，可直接按上方补丁应用**（文件是 clean，冲突风险低）。

### 为何 wbtest 没拦住

`ocr_scan_wbtest.mbt` L131-156 锁的是 `ocr_fail` **失败路径**（非法 project_dir/subcmd → `ok:false, ocr_available:false`），与该 bug 不同路径。**dry_run 成功路径的 `ocr_available` 无测试锁定**——这正是它悄悄错到现在的根因。

---

## 二、仓库阻断发现：`router_state.mbt` 重复字段（并发 agent 的脏文件）

### 现象

`moon test --target js src/server` → **exit 1**，Error 4043：

```
Error: [4043]
     ╭─[ E:\IDEProjects\AI\FIST-Mbt\src\router\router_state.mbt:212:5 ]
     │
 212 │     use_caf_memory: cfg.use_caf_memory,
     │     ───────┬──────
     │            ╰──────── The record field use_caf_memory is defined several times.
```

### 根因（L211-212 逐行核对）

```moonbit
211:     use_caf_memory: cfg.use_caf_memory,   ← 第 1 次
212:     use_caf_memory: cfg.use_caf_memory,   ← 第 2 次（重复，Error 4043）
```

**同一行被意外复制一次**，导致 record 字段重复定义 → 整个 src/router 编译失败 → src/server（依赖 router）连锁失败 → **全仓测试门红**。

### 性质

- `git status --porcelain -- src/router/router_state.mbt` = **` M`（脏，并发 agent 在改）**
- 因此**我不能修**（standing constraint：只改 git-clean 文件）
- 这是**当前仓库处于 broken 状态**的直接原因，会阻断所有 agent（包括编辑它的并发 agent 自己）的测试验证

### 修复建议（留给并发 agent / owner）

删掉 L211 或 L212 其中一行即可（两行完全相同）。这是显而易见的复制粘贴事故，无歧义。

---

## 资源消耗

- 1 次 `src/server` 状态查 + `ocr_scan.mbt` 定位（Select-String + read 精读 L255-324）
- 1 次 wbtest 查（确认无测试锁定 dry_run 成功路径）
- 1 次应用修复 + `moon fmt`（exit 0）
- 2 次 `moon test --target js src/server`（暴露 router_state 编译错）
- 1 次错误上下文反解（Error 4043 定位到 L212 重复字段）
- 1 次回滚（守提交门禁）

## 任务分配记录

- 无新派单。src/server 36 脏（R21 第二十一轮）；src/router 14 脏（其中 `router_state.mbt` 正阻断全仓编译）。

## 遗留风险

1. **【当前最高优】`src/router/router_state.mbt:211-212` 重复字段 → 全仓编译红**：阻断所有 agent 的测试验证。并发 agent 修掉该重复行前，`moon test` 无法全绿。
2. **`ocr_scan --dry_run` 契约 bug**：修复补丁已就绪（§一），等 repo 编译恢复后应用 + `moon test` 验证。
3. **`check_test_sync.py --help` 崩溃**（真 bug，脏文件）：R33 已记录，等文件清空后与 `patch_esm_main` 同法修。
4. src/server 36 脏（二十一轮）：issue_scan 家族 6 条 + BUG-339 仍压脏区。
5. 本机无 OCR 二进制：`bugfind` 模式 `require_ocr=true` 不可满足（`ocr_scan` 真跑诚实降级是对的）。

## 后续建议

1. **立即**：通知并发 agent / owner——`router_state.mbt:211-212` 重复字段是当前全仓编译红的根因，删任一行即恢复。这是协作最高优先。
2. 恢复编译后：应用 §一 的 ocr_scan 补丁 + `moon test --target js` 全绿验证 + 提交。
3. **经验**：`src/router` 是并发 agent 密集区（14 脏），其编译错误会传染到 src/server。本轮实证——依赖图的编译错误是"并发 agent 互踩"的直接表现。**owner 应协调 src/router 的编辑者尽快收口，否则所有 agent 的测试门都被卡住。**

## 来源

- `ocr_scan.mbt` L269-294 dry_run 分支精读（read 工具）
- `ocr_scan_wbtest.mbt` L125-174（确认 L131-156 锁失败路径、L159 锁 dry_run argv 但**未**锁 ocr_available）
- `moon test --target js src/server` 实跑 exit 1 + Error 4043
- `src/router/router_state.mbt` L205-216 逐行核对（L211-212 重复字段）
- `git status`：`src/server/ocr_scan.mbt` clean、`src/router/router_state.mbt` dirty
- 本会话 R22/R24/R26/R29/R31/R32/R33 提交：`c7934f3` / `b4665e2` / `a15ab01` / `8ab683e` / `167ac5c` / `c6d1816` / `37be862` / `75e42e7`