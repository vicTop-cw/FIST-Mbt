# FIST-Mbt plugin patch — **模板态**（跟踪真源，禁止出现任何本机绝对路径）。
#
# 为什么是模板：`@deepseek-ai/dsh-mcp-client` 的 stdio 通道把 `args`/`cwd` 当**字面
# argv** 直接交给 `child_process.spawn`，DSH 宿主侧**不做美元花括号变量插值**（实测：
# app.asar 内 mcp-client 的 stdio 分支只读 `command`/`args`/`cwd`/`env` 四个键）。
# 所以任何写进这里的绝对路径都只对「写它的那台机器」成立——把本机盘符路径提交进
# 跟踪面，等于给每个克隆者埋一发 `server is disconnected`。
#
# 本文件由 `render_dsh_patch.py` 渲染成同目录的 `cordis.patch.yml`（本地产物、已
# gitignore）。占位符只有两个，值都由渲染器从「本仓自身位置」推导，零硬编码：
#
#   {{FIST_MBT_CLI}}   JS 可执行产物的绝对路径（正斜杠形态）
#   {{FIST_MBT_ROOT}}  本仓根的绝对路径（正斜杠形态）——CLI 以此为 cwd，
#                      相对 args 与 SQLite 台账引导都按它解析
#
# 形状对齐本仓跟踪真源 `.mcp.dev.json`，字段名对齐 dsh-mcp-client Config schema
# （`toolCallTimeoutMs`，不是 `timeout_ms`；reconnect 只认 enabled/initialDelayMs/
# maxDelayMs/maxAttempts）。

- insert:
    - id: fist-mbt-mcp
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: 'fist-mbt'
        transport: 'stdio'
        command: 'node'
        args:
          - '{{FIST_MBT_CLI}}'
          - 'serve'
        cwd: '{{FIST_MBT_ROOT}}'
        toolCallTimeoutMs: 30000
        failOnStartupError: false
        reconnect:
          enabled: true
          initialDelayMs: 500
          maxDelayMs: 30000
          maxAttempts: 10
