# assets/

仓库根级静态资产（徽章、favicon、图标等）的**单一真源**。

| 文件 | 用途 |
|---|---|
| `fist-logo.svg` | FIST 拳头单色矢量 logo。纯 SVG、无外部引用（不引字体/图片/脚本/CDN），
  `viewBox="0 0 64 64"` 尺寸自适，`fill="currentColor"` 单色、适合 16px favicon 与 README 徽章。 |

这些文件由 `scripts/gen_plugins.py` 在投影流程末尾**按字节**复制到每个宿主目录的
`plugins/<host>/assets/`（投影可重跑，目标同名文件被覆盖为源字节）。手改
`plugins/<host>/assets/` 下的副本会在 `scripts/check_plugin_sync.py`（cl7）下红。
