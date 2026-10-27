# BUG-430 · S1 公告边界落地 · Lane AT · 2026-10-27

> **⚠️ S1 做完后，系统仍然不安全 —— 只是「不安全」变得可见。**
> **不要以为 S1 做完就安全了。** BUG-430 **保持 OPEN**，关闭条件是「存在至少一条
> 『调用方无法自报』的路径」，而那只有 **S3（身份锚点）** 能提供。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 改了 | **3 处**（`rsv_set` 回执 + `rsv_try_set` 回执 + AGENTS.md 已知边界）|
| 未改（受保护，出 patch）| **`server.mbt` 的 4 处 `agent` 参数描述** |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | 全量 **1576/1576/0**；`src/engine` **254/254/0** |
| 新增锁 | **3 格**，变异实测**全红** |
| BUG-430 状态 | **保持 OPEN**（`[arch] 边界已公告 / 认证未接入`）|

### 一处对 Alpha 报告的事实修正

Alpha 说「`role_source` 已经在回执里，S1 只需改拼串处（2 处）」——**部分成立**：
- `rsv_set` 回执确有 `role_source`（`engine_rsv.mbt:89`）✅
- **但 `rsv_try_set` 回执没有** —— 它走 `action` 标签（`+role_inferred`），**不是字段**。
  原因是 `RsvOutcome` 是 store 侧结构体、本层不能加字段。
  ⇒ 我的做法：给两个回执都补 `agent_source` 语义，`rsv_set` 走字符串、`rsv_try_set` 走 `action` 后缀。

---

## 二、证据

### 2.1 三处改动

**① `rsv_set` 回执（`src/engine/engine_rsv.mbt`）**
```diff
-        Ok(o) => Ok(o + " [role_source=" + role_source + "]")
+        Ok(o) =>
+          Ok(
+            o +
+            " [role_source=" + role_source +
+            "; agent_source=self-reported - agent is caller-asserted, unverifiable by the server; " +
+            "this does NOT prevent impersonation and will not be closed before BUG-430 S3]",
+          )
```

**② `rsv_try_set` 回执**：加 `+agent_self_reported` 后缀（两条返回路径都加）
```diff
+  let src_tag = "+agent_self_reported"
   ...
-              o.relabel(o.action + "+role_inferred")
+              o.relabel(o.action + (if role_source == "inferred" { "+role_inferred" } else { "" }) + src_tag)
```

**③ `AGENTS.md`**：新增「已知边界」整节（含分级表：S1/S2 都不改变安全属性，只有 S3 是）。

### 2.2 措辞：必须写「不安全」，不是「有说明」

| ✅ 用了 | ❌ 没用 |
|---|---|
| `unverifiable by the server` | ~~「本参数仅为登记用」~~ |
| `does NOT prevent impersonation` | ~~「仅供审计」~~ |
| `will not be closed before BUG-430 S3` | ~~「有一定风险」~~ |
| AGENTS.md：**「这是安全性公告，不是安全措施」** | ~~「已加说明」~~ |

### 2.3 未改的 4 处（`server.mbt` 受保护，出 patch）

| # | 工具 | 位置 | 现状 | 建议改成 |
|---|---|---|---|---|
| 1 | `reserve_scope` | `server.mbt:5563` | `"预订者（如 exec_1，必填）"` | `"预订者（必填）。⚠️ 自报值，服务端无法验证 ⇒ 不能防有意的冒充"` |
| 2 | `lock_acquire` | `server.mbt:5687` 附近 | `"持有者（必填）"` | 同上 |
| 3 | `claim` | `server.mbt:1947` | `"可选：ACL 判定身份的显式声明（缺省=assignee）…"` | 追加 `。⚠️ 自报值，不可验证` |
| 4 | `execute` | `server.mbt:2012` | `"可选：ACL 判定身份的显式声明（缺省=任务 assignee…）"` | 同上 |

**`assignee`（`server.mbt:1946`）与 `executor`（`server.mbt:2009`）同样自报**，建议一并加。

### 2.4 三格锁 + 变异实测

新文件 `src/engine/engine_bug430_s1_wbtest.mbt`：

| 锁 | 断言 |
|---|---|
| **锁 1** | `rsv_set` 回执含 `agent_source=self-reported` **且**含否定措辞（`unverifiable`/`冒充`）**且**点名 `S3` |
| **锁 2** | `rsv_try_set` 的 `action` 含 `+agent_self_reported` |
| **锁 3** | **措辞锁定格**：只写字段名、不写「挡不住冒充」⇒ **判不合格**（对应 Alpha 的核心警告）|

**变异实测（真跑）**：
```
# 删掉 rsv_set 的 agent_source 公告 + 删掉 rsv_try_set 的 src_tag
$ python scripts/moon_test_env.py --target js src/engine
汇总：Total tests 254 / passed 251 / failed 3
F| bug430_s1_rsv_set_receipt_declares_agent_source        failed
F| bug430_s1_rsv_try_set_action_declares_agent_source     failed
F| bug430_s1_receipt_must_say_insecure_not_merely_documented  failed
# 恢复后 254/254/0
```
**⇒ 三格都有判别力。**

---

## 三、分析（为什么措辞必须是「不安全」）

**「写了说明」≠「安全了」，而写了说明可能让人更放心。**
一个只说「本参数用于登记」的描述，读者会读成「已知，应该有处理」——
**它把一个未修复的漏洞，变成了一条让人安心的注释。**

**⇒ 公告的正确形态是「否定句」**：
不是「这个参数是干什么的」，而是「**这个参数挡不住什么**」。
所以回执/文档里必须出现：**「无法验证」「不能防冒充」「S3 前不会消除」** 三类否定表述。
锁 3 就是钉这件事：**只写字段名不写否定句 = 不合格的公告。**

---

## 四、缺口与风险

1. **4~6 处工具描述未改**（`server.mbt` 受保护）。**S1 因此只完成了一部分** ——
   回执和 AGENTS.md 已公告，但**工具描述（调用方最先看到的地方）还是旧的**。
   建议统帅把 §2.3 的 patch 应用后再宣告 S1 完成。
2. **BUG-430 保持 OPEN**。S1/S2 **都不改变安全属性**；只有 S3（签名挑战/验签/会话绑定）能改变。
3. **回执公告可被后来者「清理」**：文案是最容易被当作冗余删掉的东西。
   ⇒ 三格锁的作用就是让删它的人**立刻看到红**。
4. AGENTS.md 加长后已触发工作区指令上限截断（实测 88KB → 截到 65KB）。**不阻碍功能**，
   但若继续加内容，需考虑拆分到独立文档。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S1 落地 | BUG-430 挂 `- s1: reports/2026-10-27-bug430-s1-landing-report.md`，**状态保持 OPEN** |
| **「写了说明 ≠ 安全了」** | 判例集（Alpha 的警告，本单用锁 3 钉住）|
| 回执措辞否定句规则 | `scripts/README.md` 或 AGENTS 的「已知边界」旁 |
| 4 处工具描述 patch | BUG-430 正文，待统帅应用 |
