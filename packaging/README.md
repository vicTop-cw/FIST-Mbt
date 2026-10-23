# packaging/ — 发布到 DSH 社区的那一层（npm 包 + 插件市场）

本目录是**发布面**，不是另一个宿主投影：`plugins/` 是给各宿主的技能投影，这里是把
FIST-Mbt 装进任意 DeepSeek Harness 的 npm 包骨架。

## 目录

| 文件 | 作用 |
|---|---|
| `../package.json` | npm 包清单：`dsh.bundle.patch` 指到本目录的 patch，`files` 只放发布所需文件，`engines.node >= 24`（`node:sqlite`） |
| `dsh/cordis.patch.yml` | 社区安装的 bundle 层：用 `!!js` 在加载时解析自身路径，**不含任何机器绝对路径** |
| `dsh/launch-mcp.mjs` | 启动器：源码 checkout 里取 `_build/js/*/build/cmd/cli/cli.js` 最新构建；npm 包里跑 `dist/fist-mbt.js` |
| `dsh/locale/{en,zh}.json` | 插件市场的标题与描述（`meta.title` / `meta.description`） |
| `dsh/icon.svg` | 插件卡片图标 |

## 两条安装通道

1. **npm（推荐）**：`dsh plugin --profile web add fist-mbt`。包内自带 `dist/fist-mbt.js`
   预构建产物，安装不触发构建脚本（`allowBuilds` 那一步直接跳过）。
2. **本机源码**：`.dsh/fist-mbt-plugin/` 走 `link:` 安装，启动器优先 `_build` 最新构建，
   适合边改边试（构建变化会触发 MCP 重连）。

## 发版清单

1. `moon.mod` 的 `version` 递增。
2. 用 release 工作流重新生成 `dist/fist-mbt.js`（`scripts/check_dist_snapshot.py` 会校验
   快照内嵌版本 == `moon.mod`）。
3. **同步 `package.json` 的 `version`**（与 `moon.mod` 一致；npm 不允许重发同版本）。
4. `npm pack --dry-run` 核对文件清单 → `npm publish`（scoped 包才需要 `--access public`，
   本包已写 `publishConfig.access`）。
5. 首次收录：向 [awesome-dsh-plugin](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin)
   提 PR，新增 `data/plugins/<owner>__<repo>.yml`（格式见其 `contributing.md`），
   并在 GitHub 仓库加 `dsh-plugin` topic。

## 版本兼容

- `engines.node >= 24.0.0` 是硬要求：CLI 的 SQLite 后端直接用 `node:sqlite`。
- patch 里 `command: !!js process.execPath` + `ELECTRON_RUN_AS_NODE=1`：桌面端用 Electron
  自带的 Node 24 跑，网页端用宿主自己的 node 跑，避免"用户没装 Node / 装了旧 Node"。
- patch 里 `args` 用 `createRequire(baseUrl).resolve('fist-mbt/launch-mcp.mjs')` 解析：
  `baseUrl` 是 profile 的解析基准，因此同一份 patch 在任何机器上都指向已安装的包。
