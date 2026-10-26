# 提案 — 跨机器任务发布 / 查看（黑盒、非实时）

> **文件命名**：`2026-10-22-cross-machine-task-publish-proposal.md`
> **放置目录**：`docs/proposals/`
> **状态**：`draft`
> **替代**：`docs/archive/2026-10-16-future-plan.md` §一（内容整合进 `improvement-plan-20261010.md` §6）
> **来源**：用户口述「跨机器发布/查看任务」需求 + `scripts/fist-mbt-http.py` 已有基础

---

## 1. 背景与问题

FIST-Mbt 当前 MCP server 绑定 `127.0.0.1:3100`，只能本机调用。用户需要在机器 B 上向机器 A 的任务库发布任务、查看状态。硬约束：分钟级延迟可接受，不做 WebSocket / 长连接，黑盒交换。

## 2. 方案对比

| 方案 | 做法 | 改动量 | 适合 | 不适合 |
|---|---|---|---|---|
| A. 共享后端库 | SQLite 换远程库（Postgres/网络盘），多机桥连同一库 | 中 | 同内网、多机常驻 | 需运维数据库、跨网段复杂 |
| B. 快照文件同步 | 任务库定期导出 JSONL 快照；发布=写快照、查看=读快照；git/网盘/rsync 同步 | 低 | 完全黑盒、机器可离线 | 延迟分钟级、需外部同步通道 |
| C. HTTP 桥暴露 + token | 3100 桥绑定 LAN IP + 简单 token；机器 B 直接 POST/GET | 最低 | 只发布+查看、同内网 | 需机器 A 常驻 server |

## 3. 推荐路径

先做 C（最小改动，半天内）→ 按需做 B（完全黑盒形态）→ A 仅在需要多机同时活跃操作时启用。

## 4. 四态对齐

| cl | 判据 | 本功能动作 |
|---|---|---|
| cl1 | MCP 工具存在 | 扩展 `fist-mbt-http.py`：新增 `--bind <ip>` 与 `--token <secret>`（请求头校验，鉴权失败返回 401） |
| cl2 | CLI 封装 | `python scripts/fist.py call ...` 可路由到跨机器发布 |
| cl3 | skill 文档 | `docs/cross-machine-skill.md` |
| cl4 | 测试 | `scripts/blackbox/` 增加跨机器黑盒测试 |
| cl5 | L4 证据 | `output_validate` 验跨机器发布→查看端到端日志 |
| cl6 | 文档同步 | README 追加跨机器章节 |
| cl7 | 插件投影 | 无新增插件文件（纯 Python 脚本扩展） |

## 5. 待用户拍板的决策点

| 决策点 | 选项 | 建议 |
|---|---|---|
| D1 · 方案选型 | A) HTTP 桥 + token B) 快照文件同步 C) 共享远程库 | 默认 A 起步 |
| D2 · token 管理 | A) 固定 token（配置文件） B) 动态签发（需额外服务） | 默认 A |
| D3 · 是否纳入 MCP 工具 | A) 新增 `cross_machine_publish` 工具 B) 仅 CLI/HTTP 调用，不进 MCP | 默认 B（最小侵入） |

## 6. 落地顺序

| 阶段 | 内容 | 涉及文件 | 依赖 | 交付 |
|---|---|---|---|---|
| P0 | HTTP 桥 + token | `scripts/fist-mbt-http.py`、`docs/cross-machine-skill.md` | 无 | 机器 B 可发布+查看 |
| P1（可选） | 快照导入导出 | 新增 `export_snapshot`/`import_snapshot` 工具 | P0 | 完全黑盒形态 |
| P2（可选） | 共享远程库 | `src/store/store_sqlite.mbt` 扩展 | P1 | 多机同时活跃 |

## 7. 已知边界与风险

- 机器 A 必须常驻 server 进程（否则 HTTP 桥不可达）
- token 走 HTTP Header，明文传输需 HTTPS 前置（当前未做）
- 黑盒测试需两台机器或两台 VM，CI 上难以自动化
- 与既有 `SOP.md` 单轮节奏无冲突（跨机器是补充，不是替代）

## 8. 参考

- `improvement-plan-20261010.md` §6（方向五）
- `docs/archive/2026-10-16-future-plan.md` §一（已归档）
- `scripts/fist-mbt-http.py`（现有 HTTP 桥）
