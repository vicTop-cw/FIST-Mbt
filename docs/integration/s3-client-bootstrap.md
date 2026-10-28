# S3 客户端自举 —— 让你的调用方 20 行接入认证

> 适用：任何要调 `claim` / `reserve_scope` / `lock_acquire` 的客户端。
> 本文所有示例**已在本机实跑**，回执均为真实读数。

---

## ① 30 秒快速开始

```python
import json, os, subprocess, sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

def call(tool, **kw):                      # 换成你的 MCP 客户端即可
    cmd = [sys.executable, "scripts/fist.py", "call", tool]
    for k, v in kw.items(): cmd += ["--" + k, str(v)]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    # fist.py 会在 stdout 打构建日志（如入口产物过期时自动重建），
    # JSON 回执是**最后一个 `{` 开头的块**；解析失败说明服务侧有问题，不要静默吞掉。
    out = "\n".join(x for x in (r.stdout or "").splitlines() if x.startswith("{"))
    if not out:
        raise RuntimeError("fist.py 没返回 JSON（检查：仓能否 moon check / FIST_DB_PATH 是否一致）")
    return json.loads(out)

KEY = os.path.expanduser("~/.fist/s3.key")
os.makedirs(os.path.dirname(KEY), exist_ok=True)
if os.path.exists(KEY):
    priv = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
else:
    priv = Ed25519PrivateKey.generate()
    open(KEY, "wb").write(priv.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())); os.chmod(KEY, 0o600)

pub = priv.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()
AGENT, NS = "my-agent", "default"

r = call("agent_register_key", agent_id=AGENT, namespace=NS, pubkey_hex=pub)
if r.get("mode") == "challenge_issued":          # 首次 ⇒ 两步登记
    call("agent_register_key", agent_id=AGENT, namespace=NS, pubkey_hex=pub,
         challenge=r["challenge"], proof_sig=priv.sign(r["challenge"].encode()).hex())

ch  = call("agent_issue_challenge", agent_id=AGENT, namespace=NS)["challenge"]
sig = priv.sign(ch.encode()).hex()
print("就绪：challenge =", ch)
print("      challenge_sig =", sig[:16], "...（128 字符 hex）")
# 之后每次调用把 ch + sig 带上即可
```

**实跑读数**：`① 公钥: 7f76e6277bda235e ...` ｜ `② 首登完成` ｜
`③ 取票: fist-s3-challenge:v1:de-bootstrap-demo:1` ｜ `④ 签名长度: 128`

---

## ② 完整流程（4 步）

| 步 | 动作 | 关键点 |
|---|---|---|
| **1** | **生成密钥对** | 私钥本地存（`~/.fist/s3.key`，`chmod 600`）；公钥 = 32 字节 raw → 64 字符 hex |
| **2** | `agent_register_key(pubkey_hex)` | **两步**：先不带 `challenge` 拿挑战 → 用**新私钥**签 `proof_sig` 再调一次 |
| **3** | `agent_issue_challenge()` | 返回 `challenge`；**每个只能消费一次** |
| **4** | `claim(challenge=…, challenge_sig=…)` | `challenge_sig` = 私钥对 **challenge 原文**的 Ed25519 签名，hex（128 字符）|

**⚠️ 同名参数**：`agent_register_key` 用 `proof_sig`（首登证明），
`claim`/`reserve_scope`/`lock_acquire` 用 `challenge_sig`（用票证明）——**两者不是同一个字段**。

---

## ③ 私钥保管（**最重要的一段**）

**放哪**：本地文件 `~/.fist/s3.key`（`chmod 600`）或系统 keychain。
**不要**放环境变量（会进 `ps`/日志）。

**绝不能**：
- ❌ 提交到 git（`~/.fist/` 不在 repo 内，但别把它复制进来）
- ❌ 发给服务端 —— **服务端只收公钥**
- ❌ 写进日志/回执

**丢了怎么办**：私钥丢了 ⇒ 无法轮换（轮换要**旧私钥**签名）⇒ 只能：
```
1. agent_revoke_key(agent_id=…)      # 清空公钥（⚠️ 身份自报，非安全措施）
2. 重新走第 1~2 步                    # 生成新密钥对 + 首登
```

**⚠️ 实测坑**：公钥**按 ns 隔离** —— 在 `ns-a` 登记的公钥，`ns-b` 里不算「有钥匙」。
`reserve_scope` / `lock_acquire` **不接受 `namespace` 参数**（只走默认引擎），
而 `agent_issue_challenge` 接受 ⇒ **两者 ns 不同则验签永远失败**。统一用同一个 ns。

---

## ④ 三种失败模式（**真实回执**）

| `action` 里的后缀 | 含义 | 怎么办 |
|---|---|---|
| `+challenge_required` | **有钥匙但没出示** | 取票 → 签名 → 带上 `challenge`+`challenge_sig` |
| `+challenge_failed` | 传了票但**验签失败** | 检查是否用**对的私钥**签、签的是 **challenge 原文**（不是别的串）|
| `+challenge_missing` | `strict` 模式下**完全没传** | 同上，取票+签名（⚠️ 见下「strict 尚未真正拒绝」）|

**实测回执**（`reserve_scope`，同一 server 进程）：

```
成功（带 challenge + 真签名）  action = unregistered+challenge_verified+identity_verified
有钥匙但不传                  action = unregistered+challenge_required+identity_self_reported
传了但签名错                  action = unregistered+challenge_failed+identity_unverified
```

**附加标签**：`+challenge_replayed` = 同一张票用了第二次。
⚠️ **实测**：`claim` 会拦（走 `judged_role_with_nonce`，消费 nonce）；
**`reserve_scope` / `lock_acquire` 目前不拦**（走 `judged_role_gated`，只验签不消费）。

---

## ⑤ 常见误区

| 误区 | 事实 |
|---|---|
| 「服务端会帮我签名」 | ❌ **永远不会**。服务端代签 = 自己给自己发通行证 = 绕过整个认证。私钥只有你手里那一份 |
| 「公钥可以随时改」 | ❌ 已登记的公钥**不可静默覆盖**。要换必须走**轮换**：带 `rotate_sig`（用**旧私钥**签服务端签发的 `rotate_challenge`）+ `rotate_challenge` |
| 「ns 之间公钥互通」 | ❌ **按 ns 隔离**。在哪个 ns 登记就在哪个 ns 用 |
| 「`strict` 现在就能严格」 | ❌ **本版尚未真正拒绝**：它只返回 `challenge_missing` 标签并降权，各门还没据此硬拒 ⇒ 效果接近 `soft` |
| 「不传 challenge 也没事」 | ⚠️ 取决于 `FIST_AUTH_MODE`：`off`（默认）下无钥匙者自报放行；`soft` 下降权到 `Executor` |

---

**相关**：`AGENTS.md`「已知边界」段 ｜ `docs/plans/2026-10-28-bug470-owner-decision.md`（开关决策单）
