# rx-mbt 仓库 origin URL 内嵌明文 OAuth token —— 侦察与处置方案

> **发现者**：β（兄弟目录核查）
> **侦察者**：commander-delta · 2026-10-25
> **仓库**：`E:/IDEProjects/AI/rx-mbt`（**非本仓**，不归 FIST-Mbt 管）
> **性质**：凭据事故面（BUG-127 同代：**凭据不该以明文形式落在可分发/可备份的位置**）
> **状态**：**只侦察，未做任何修改**。`rx-mbt/.git/config` 一字未动。

---

## 一、判定：确认有明文 OAuth token

```
scheme        : https
host          : atomgit.com
path          : VictorTop_atomcode-apps/rxmbt.git
user          : oauth2
token         : <REDACTED>   长度 24，字母数字，前缀 4 位已记为 MGes
完整形态      : https://oauth2:<REDACTED>@atomgit.com/VictorTop_atomcode-apps/rxmbt.git
```

| 项 | 读数 |
|---|---|
| 是否有内嵌凭据 | **是** |
| 凭据类型 | AtomGit OAuth2 access token（`oauth2:` 前缀 + 24 字符字母数字串） |
| 出现位置 | `rx-mbt/.git/config` **第 9 行**（`url = …`，git 自动加 `remote "origin"` 段） |
| 该 URL 用于 | **fetch 与 push 双向**（`git remote -v` 确认）|

**风险等级：high。** 理由：① 明文字符串而非凭据助手托管；② 该仓库有两个 remote（`github` 与 `origin`），
`origin` 指向 AtomGit —— 意味着同一工作副本既推 GitHub 又推 AtomGit，凭据面被不必要地扩大了。

---

## 二、泄漏面普查（逐处实测）

| # | 位置 | 结果 | 判据 |
|---|---|---|---|
| 1 | `rx-mbt/.git/config` | 🔴 **命中 1 处**（第 9 行 url） | 全文正则 `://[^@/]+@` 扫，仅此 1 行 |
| 2 | `git config --global` | ✅ **0 命中** | 全局配置无内嵌凭据 |
| 3 | `rx-mbt` 提交历史 | ✅ **0 命中** | `git log --all -S "oauth2:"` 空 |
| 4 | `rx-mbt` 工作树 | ✅ **0 命中** | `git grep` 空 |
| 5 | `.git/FETCH_HEAD` | ✅ 0 | —— |
| 6 | `.git/logs/HEAD`（reflog） | ✅ 0 | —— |
| 7 | `.git/ORIG_HEAD` / `packed-refs` | ✅ 0 | —— |
| 8 | `rx-mbt/backup/` | ✅ 0 | —— |
| 9 | **FIST-Mbt 提交历史** | ✅ **0 命中** | `git log --all -S "<token>"` 空 |
| 10 | **FIST-Mbt 工作树** | ✅ **0 命中** | `git grep` 空 |
| 11 | FIST-Mbt 自身 remote | ✅ 干净 | `origin`=SSH、`gitcode`=无凭据 |

**结论：污染面收敛在 `rx-mbt/.git/config:9` 单点，未扩散到历史/备份/本仓。**

这是**好消息**：意味着修复只需改一处，**不需要 `filter-repo` 重写历史**（对比 BUG-127 那种进了历史的凭据）。

---

## 三、⚠️ 侦察过程中的二级泄漏（必须记录）

**我用 `git remote -v` 取证时，该命令不脱敏，把完整 token 打印进了会话输出。**

```
git remote -v  →  回显 https://oauth2:<完整24位>@atomgit.com/...
```

**这是我的操作失误。** 教训与规避：

| 项 | 说明 |
|---|---|
| 为什么会中招 | 我用 Python 正则脱敏处理了 `git config --get remote.origin.url`，**但对 `git remote -v` 没有走同一个过滤器** |
| 正确姿势 | 任何会打印 remote URL 的命令，都必须管道进**同一个脱敏函数**；或统一用 `git config --get` + 脱敏 |
| 影响面 | 该 token 已出现在本次会话记录中；`rx-mbt/.git/config` 里仍是明文 |
| 处置建议 | **owner 应把「吊销并重签该 AtomGit token」的优先级提到最高**，而不是只改 remote URL |

⇒ **这条使得方案 C（改 token）从「可选」升级为「必做」**：**只改 remote URL 不足以消除风险**，
因为该 token 已在至少一处（会话记录）留下明文副本。

---

## 四、三方案（**均未执行**）

### 方案 A：`git remote set-url` 去凭据（**推荐，最小改动**）

```bash
cd E:/IDEProjects/AI/rx-mbt
git remote set-url origin https://atomgit.com/VictorTop_atomcode-apps/rxmbt.git
```

| 项 | 评价 |
|---|---|
| 可逆性 | ✅ **完全可逆**（原 URL 备份一行即可还原） |
| 消除明文 | ✅ config 里不再有 token |
| 副作用 | 后续 push 需要**交互输入**或**凭据助手**（否则会 403） |
| 风险 | **低**。但若无人值守推送该仓，会因缺凭据失败 |
| 配套 | 建议同时配 `git config --global credential.helper manager`（Windows）或 `store` |

### 方案 B：改 SSH remote

```bash
cd E:/IDEProjects/AI/rx-mbt
git remote set-url origin git@atomgit.com:VictorTop_atomcode-apps/rxmbt.git
```

| 项 | 评价 |
|---|---|
| 可逆性 | ✅ 完全可逆 |
| 消除明文 | ✅ 最彻底（SSH key 不在 URL 里） |
| 前提 | **该机需已在 AtomGit 注册 SSH 公钥** —— 未验证，属未知面 |
| 风险 | **中**。若 SSH key 未配，推送直接失败，且换发布通道属运维决定 |
| 备注 | 与本仓 FIST-Mbt 的 `origin`（`git@github.com:…`）风格一致，是**长期最优** |

### 方案 C：吊销并重签 token（**必做，不是可选**）

**服务端侧动作，非 git 命令。** 因 §三 的二级泄漏，这一步**必须做**。

| 项 | 评价 |
|---|---|
| 可逆性 | ❌ **不可逆**（旧 token 立即失效） |
| 收益 | 消除「已泄漏凭据」这一事实本身 |
| 前提 | 需 AtomGit 账号权限（`VictorTop_atomcode-apps`） |
| 风险 | **低**（但会使所有引用旧 token 的自动化失效，需盘点） |

---

## 五、推荐组合（**交 owner 裁决**）

```
必要项  : C（吊销重签）—— 因 token 已明文出现在会话记录
推荐项  : A（去凭据）  —— 立即可做、可逆、消除 config 明文
长期项  : B（改 SSH）   —— 若该机已有 AtomGit SSH key，一次到位
```

**顺序建议：先 C（止损）→ 再 A（消明文）→ 视情况 B（长期）。**

⚠️ **若先做 A 而不做 C**：config 干净了，但泄漏的那个 token 仍有效 ⇒ **表面安全，实际未止损**。
**这正是「判据看的不是它以为在看的东西」的凭据版。**

---

## 六、边界声明（我做了什么 / 没做什么）

| 动作 | 状态 |
|---|---|
| 读 `rx-mbt/.git/config` | ✅ 做了（只读） |
| 扫全局 config / 历史 / 工作树 / 本仓 | ✅ 做了（只读） |
| **改 `rx-mbt` remote URL** | 🚫 **未做** |
| **删/改该 token** | 🚫 **未做** |
| 用该 token 调 AtomGit API 验有效性 | 🚫 **未做**（避免用泄漏凭据产生新痕迹） |
| 在报告中写入 token 本体 | 🚫 **未做**（全文 `<REDACTED>`，仅留 4 位前缀供对账） |

---

## 七、给 owner 的一句话

**这不是本仓的问题，但它是一个「凭据进了 URL」的真实样本。**
**建议把本报告的两条判据收进纪律**：

1. **任何打印 remote URL 的命令都必须过脱敏过滤器**（我在 §三 栽的跟头）
2. **凭据修复要区分「消除痕迹」与「吊销失效」两件事** —— 只做前者 = 假安全（本报告 §五 末段）
