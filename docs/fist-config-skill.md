# fist-config-skill.md · 目标项目连接配置（fist-mbt）

> **真源**：`src/server/mcp_config_scaffold_impl.mbt` + `fist-config.html`（纯静态前端）
> **对应计划**：`docs/improvement-plan-20261010.md` §2 方向一 P0-b
> **单源纪律**：MCP 连接参数的 JSON schema 只通过 `mcp_config_scaffold` 服务端校验，fist-config.html / CLI / 文档三态都不得另写一套参数规则。

---

## 1. 这是什么

**fist-config.html** 是一个纯静态单文件（无 CDN、无外部依赖），在**目标项目**目录下用浏览器打开即可使用。它帮助用户在图形界面中生成两份产物：

1. **`fist.mcp.json`** — 供 MCP 客户端读取的连接配置（command/args/env 等字段，不进凭据）；
2. **`fist-runtime.json`** — 运行时策略预设（覆盖模式/拆解开关/看门狗/六顶帽/模型路由预设），由 agent 把每个开关对应到工具调用的参数上。

两份产物都由用户复制 JSON 正文后，由 agent/安装器落盘到目标项目根。

### 为什么需要它

- MCP 配置（command、args、env 映射）对新手有门槛。图形界面一次性填完所有字段，避免手写 JSON 出错。
- 运行时策略（Gradient 是否开启、Phi Accrual 阈值、六顶帽默认帽数等）不是 MCP 配置字段，但影响 fist-mbt 的行为。把它们单独归到 `fist-runtime.json`，防止与 `fist.mcp.json` 的 schema 纠缠。

---

## 2. 配置项

### 2.1 MCP 连接字段（写入 `fist.mcp.json`）

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `command` | 可执行文件路径 | `fist-mbt`（黑盒路径，安装器 shim 优先）；可选切换到 `node <absolute>` 源码模式 |
| `args` | 命令行参数，固定 `["serve"]` | `["serve"]` |
| `cwd` | 工作目录 | 目标项目根 `.` |
| `toolCallTimeoutMs` | 单次工具调用超时 | `30000`（30 秒） |
| `failOnStartupError` | 启动失败是否阻止连接 | `false`（推荐，允许部分工具可用） |
| `reconnect.intervalMs` | 重连间隔 | `500` ms |
| `reconnect.maxRetries` | 最大重连次数 | `30` |
| `reconnect.delayMs` | 重连延迟 | `30000` (30 秒) |
| `env` | 环境变量（只填变量名，不填真值；凭据不走配置文件） | 见下方 |

#### 环境变量（`env` 部分）

| 变量名 | 说明 | 填写规则 |
|--------|------|----------|
| `FIST_PROJECT_DIR` | 目标项目目录（相对/绝对） | 默认 `.` |
| `FIST_OFM_ENDPOINT` | OFM 兼容端点 URL | 可选，留空即禁用 OFM 通道 |
| `FIST_OFM_KEY` | OFM 密钥占位符 | 可选；真值通过 server 进程环境变量注入，**不进配置文件** |

### 2.2 运行时策略（写入 `fist-runtime.json`）

| 策略 | 说明 | 选项 | 默认 |
|------|------|------|------|
| gradient | 子任务难度梯度 | `true` / `false` | `true` |
| phi_gate | Phi Accrual 概率式判活 | `true` / `false` | `true` |
| autodispatch | 自动派单 | `true` / `false` | `true` |
| hats | 六顶帽讨论帽数 | `white,black,yellow` / 自定义 | 默认三帽 |
| hatsThreshold | 帽子收敛阈值 | 0.0 - 1.0 | 0.6 |
| thresholdPct | 付费切换阈值（百分比） | 0 - 100 | 95 |
| freePool | 免费池名称 | 字符串，多池逗号分隔 | 空串（使用默认池） |
| watchdog.ttlSeconds | 看门狗 TTL | 正整数 | 300 |
| watchdog.reviewEvery | 审视频次（每 N 轮） | 整数，0=禁用 | 0 |
| omegaSplitN | Omega 强验证拆分数 | 正整数 | 2 |
| phiThreshold | Phi Accrual 阈值 | 正整数 | 8 |

---

## 3. 使用流程

```
1. 在目标项目目录中打开 docs/fist-config.html（浏览器即可）
   → 或把 fist-config.html 复制到目标项目根后打开

2. 填写 MCP 连接字段（command / timeout / env 等）

3. 勾选/填写运行时策略（梯度 / 自动派单 / 六顶帽 / 看门狗等）

4. 点击「生成配置」
   → 页面上方显示 fist.mcp.json 与 fist-runtime.json 两份 JSON

5. 分别复制 JSON，由 agent/安装器落盘到目标项目根：
   - fist.mcp.json → MCP 客户端读取
   - fist-runtime.json → agent 读取各开关对应到工具参数

6. （可选）点击「加载默认值」恢复出厂设置
```

---

## 4. 凭据纪律

- **本页面不涉及凭据**。`env` 区只填环境变量名，不填真值。
- 密钥（如 OFM key、Star 门公钥）只通过 server 进程环境变量注入，**不进配置文件、不进 `fist.mcp.json`、不写在 HTML 内**。
- `mcp_config_scaffold` 服务端有 `mcp_env_whitelist` 硬门：不在白名单的凭据形状值会直接被拒绝。

对应的工具：`mcp_config_scaffold` — 对 `form_json` 做服务端校验并返回可落盘的 `fist.mcp.json` 正文。CLI 路由：`python scripts/fist.py call mcp_config_scaffold ...`。

---

## 5. 已知边界

- `fist.mcp.json` 已在 `.gitignore` 中（条目 `/fist.mcp.json`），不会意外进仓库；`default-fist.mcp.json`（模板）是跟踪文件，进发布包。
- HTML 页是纯前端——它只有浏览器权限，不写文件。落盘由 agent/安装器做。
- 运行时策略（fist-runtime.json）是**预设契约**，不是强约束——agent 可以按需覆盖。它只是减少每轮手动传参的负担。
- `mcp_config_scaffold` 白盒锁：`src/server/mcp_config_scaffold_wbtest.mbt`。
