# docs/skills/

按 `docs/DOCS-STRUCTURE.md` 的约定，**新写的 skill 说明落在这里**；存量平铺在 `docs/` 下的
skill 文档（如 `executor-marketplace-skill.md`、`fist-config-skill.md`、`mcpcf-embed-skill.md`）
暂不迁移——迁移要同时改文档内互链与判据引用面，单独做一轮。

- 本目录只放**面向使用者的 skill 说明**；规范正文仍以 `AI-DEVELOPMENT-STANDARD.md` 为准。
- 新增文件请在首行写明「真源」路径（现读存在的文件），判据 `check_plan_landing.py` 会把
  文档里点名的路径与跟踪面比对。
