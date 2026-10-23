# FIST-Mbt 开发层插件 patch — **模板态**（跟踪真源，禁止出现任何本机绝对路径）。
#
# 为什么是模板：`@deepseek-ai/dsh-mcp-client` 的 stdio 通道把 `args`/`cwd` 当**字面
# argv** 直接交给 `child_process.spawn`，DSH 宿主侧**不做美元花括号变量插值**（实测：
# app.asar 内 mcp-client 的 stdio 分支只读 `command`/`args`/`cwd`/`env` 四个键）。
# 所以任何写进这里的绝对路径都只对「写它的那台机器」成立——把本机盘符路径提交进
# 跟踪面，等于给每个克隆者埋一发 `server is disconnected`（BUG-389 同族教训）。
#
# 本文件由 `scripts/render_dsh_patch.py` 渲染成同目录的 `cordis.patch.yml`
# （本地产物、已 gitignore）。`package.json` 的 `dsh.bundle.patch` 指向渲染件，
# 安装面形状不变（DSH 照旧读一份 YAML），只是路径每台机器各自生成。占位符两个：
#
#   {{FIST_MBT_LAUNCHER}}  本仓 `packaging/dsh/launch-mcp.mjs` 的绝对路径（正斜杠形态）
#                          —— launcher 机器无关：内部经 import.meta.url 解析包根，
#                          优先挑 `_build/js/*` 最新产物、回退 `dist/fist-mbt.js`，
#                          并自带 Node>=24 / node:sqlite 检查与 ESM require shim。
#   {{FIST_MBT_ROOT}}      本仓根的绝对路径（正斜杠形态）——CLI 以此为 cwd，
#                          相对 args 与 SQLite 台账引导都按它解析；同时写进
#                          env.FIST_PROJECT_DIR（server 侧项目锚点）。
#
# 形状对齐同仓的社区层 `packaging/dsh/cordis.patch.yml`（那份零绝对路径、走 profile
# 模块解析，面向 npm 安装；本层面向「源码 checkout + DSH link 安装」）。字段名对齐
# dsh-mcp-client Config schema（`toolCallTimeoutMs`，不是 `timeout_ms`；reconnect 只认
# enabled/initialDelayMs/maxDelayMs/maxAttempts）。

- insert:
    - id: fist-mbt-mcp
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: 'fist-mbt'
        transport: 'stdio'
        command: 'node'
        args:
          - '{{FIST_MBT_LAUNCHER}}'
        cwd: '{{FIST_MBT_ROOT}}'
        toolCallTimeoutMs: 300000
        failOnStartupError: false
        env:
          FIST_PROJECT_DIR: '{{FIST_MBT_ROOT}}'
        reconnect:
          enabled: true
          initialDelayMs: 500
          maxDelayMs: 30000
          maxAttempts: 10
