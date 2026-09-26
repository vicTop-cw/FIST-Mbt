/// project_standards.mbt —— AI 项目开发规范（默认内置 + FIST 专项）
///
/// 纯计算、零依赖，给 agent 一套"应该怎么开发"的基线规范。

///|
/// 通用 AI 项目开发规范（5 条）。
fn default_rules() -> Array[Json] {
  [
    Json::object({
      "id": Json::string("r1-doc-as-impl"),
      "title": Json::string("文档即实现"),
      "body": Json::string(
        "每个交付物必须有对应文档且同步。接口签名、参数说明、返回 schema 在代码里写 doc 注释，在 README 里有速查表。验收时先过文档再验功能。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "见 AI-DEVELOPMENT-STANDARD.md「目标项目必备文档集」（README/AGENTS/CHANGELOG/docs skill/memory bugs.md/reports/templates 各自的必填段与门禁）；output_validate 查存在性 + contains 关键字",
      ),
    }),
    Json::object({
      "id": Json::string("r2-single-source"),
      "title": Json::string("一源四态，单真源优先"),
      "body": Json::string(
        "核心逻辑写在单一语言/运行时，CLI/Skill/Plugin 都是薄封装。禁止在 CLI 里重写业务逻辑。插件态必须是真源的**生成投影**（scripts/gen_plugins.py），手写副本必然腐烂（外部 skill 曾长期写「41 工具」而真源已 100+）。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "代码审查：CLI 脚本有无业务逻辑？MoonBit 端才是单真源。插件目录漂移由 scripts/check_plugin_sync.py(cl7) 拦。",
      ),
    }),
    Json::object({
      "id": Json::string("r3-deterministic-first"),
      "title": Json::string("确定性优先于语义性"),
      "body": Json::string(
        "能用文件检查、正则匹配、状态机判定的地方，不要让 LLM 自评。issue_scan/output_validate/phi_accrual 全部确定性实现。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "grep 代码里 LLM 调用与纯计算模块的比例；确定性模块有无单元测试覆盖。",
      ),
    }),
    Json::object({
      "id": Json::string("r4-zero-regression"),
      "title": Json::string("增量零回归"),
      "body": Json::string(
        "每加一个功能或改一行代码，全量测试必须通过。临时脚本任务完必须清理。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "run_check full；output_validate 查 moon test 通过；git diff 检查临时文件。",
      ),
    }),
    Json::object({
      "id": Json::string("r5-self-evolve"),
      "title": Json::string("自我迭代优于一次性构建"),
      "body": Json::string(
        "先做最小可用，再用自身能力迭代打磨。FIST 的 evolve 体系就是给边做边学、失败回流用的。",
      ),
      "severity": Json::string("medium"),
      "how_to_check": Json::string(
        "evolve_snapshot 看档案库是否有 principle/lesson 条目。",
      ),
    }),
  ]
}

///|
/// FIST-Mbt 专项规范（5 条，强制遵守）。
fn fist_rules() -> Array[Json] {
  [
    Json::object({
      "id": Json::string("f1-use-fist-self"),
      "title": Json::string("必须使用 FIST 自身能力迭代开发"),
      "body": Json::string(
        "新功能/重构/打磨都要用 FIST 自身发布的工具（publish/plan/verify/output_validate）推进——dogfooding，自我验证。不用自身能力的 PR 打回重做。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "git log 是否有 FIST 任务记录（task_id/root_task_id）；报告必须列出用了哪些 FIST 工具。",
      ),
    }),
    Json::object({
      "id": Json::string("f2-four-forms-aligned"),
      "title": Json::string("四态必须对齐：MCP CLI Skill Plugin"),
      "body": Json::string(
        "每个新 MCP 工具上线时，必须同步：1 薄 CLI 封装；2 skill 文档说明何时用/怎么用/怎么闭环；3 四宿主插件态（atomcode/codearts/deepseek-harness/claude）重新生成。MCP 是单真源，插件目录禁止手改。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "tools 数 vs CLI 脚本数 vs skill 文档数 vs 插件投影文件数；新工具上线 checklist 必含这三项；gen_plugins.py --check 与 check_plugin_sync.py 必须绿。",
      ),
    }),
    Json::object({
      "id": Json::string("f3-evidence-ladder"),
      "title": Json::string("证据梯至少爬 L4"),
      "body": Json::string(
        "验收时不能只看报告(L1)/tool 消息(L2)/测试退出码(L3)——必须用 output_validate 到文件系统查实际产物(L4)。有条件就过 Omega 复验(L5)。",
      ),
      "severity": Json::string("hard"),
      "how_to_check": Json::string(
        "verify 前必须 output_validate verdict=pass；evidence_layer 至少 l4-pass。",
      ),
    }),
    Json::object({
      "id": Json::string("f4-task-dag"),
      "title": Json::string("重任务先拆 DAG 再动手"),
      "body": Json::string(
        "跨 3 文件/5 人日以上的工作，必须先 publish 根任务 + task_plan_deep 递归出 DAG，再按 dag_ready 顺序执行。禁止想到哪写到哪。",
      ),
      "severity": Json::string("medium"),
      "how_to_check": Json::string(
        "git diff 前有没有 FIST 任务发布记录；board_ascii 看项目是否有活跃根任务。",
      ),
    }),
    Json::object({
      "id": Json::string("f5-naming-clarity"),
      "title": Json::string("工具命名即文档"),
      "body": Json::string(
        "MCP 工具名必须动宾结构、明确做什么。参数名必须 snake_case、语义化。",
      ),
      "severity": Json::string("medium"),
      "how_to_check": Json::string(
        "新工具 code review 首审命名；aggressive rename 也接受。",
      ),
    }),
  ]
}

///|
/// 四态验收 checklist（7 项）。
fn checklist() -> Array[Json] {
  [
    Json::object({
      "id": Json::string("cl1-mcp-exists"),
      "question": Json::string("MCP 工具注册了？"),
      "gate": Json::string("hard"),
    }),
    Json::object({
      "id": Json::string("cl2-cli-exists"),
      "question": Json::string("CLI 封装到位？"),
      "gate": Json::string("hard"),
    }),
    Json::object({
      "id": Json::string("cl3-skill-doc"),
      "question": Json::string("skill 文档写了？"),
      "gate": Json::string("hard"),
    }),
    Json::object({
      "id": Json::string("cl4-tests-pass"),
      "question": Json::string("moon test 全绿？"),
      "gate": Json::string("hard"),
    }),
    Json::object({
      "id": Json::string("cl5-ov-pass"),
      "question": Json::string("output_validate L4 硬门 pass？"),
      "gate": Json::string("hard"),
    }),
    Json::object({
      "id": Json::string("cl6-doc-sync"),
      "question": Json::string("README/AGENTS 计数同步？"),
      "gate": Json::string("medium"),
    }),
    Json::object({
      "id": Json::string("cl7-plugin-forms-sync"),
      "question": Json::string(
        "四宿主插件态（atomcode/codearts/deepseek-harness/claude）已重生成且与真源一致？",
      ),
      "gate": Json::string("hard"),
    }),
  ]
}

///|
/// 完整规范清单（通用 + FIST 专项 + 可选 checklist）。
pub fn project_standards(
  project_type : String,
  include_checklist : Bool,
) -> Json {
  let gen = default_rules()
  let fist = fist_rules()
  let gen_cnt = gen.length().to_double()
  let fist_cnt = fist.length().to_double()
  let total = gen_cnt + fist_cnt
  // 规范性正文单真源 = AI-DEVELOPMENT-STANDARD.md；本函数是它的机器投影。
  // 一致性由 scripts/check_doc_surface.py 的 J6 拦（缺任一 id 或版本不符即红）。
  if include_checklist {
    Json::object({
      "project_type": Json::string(project_type),
      "generated_at": Json::string(
        "project_standards.mbt (pure, deterministic)",
      ),
      "version": Json::string("R116"),
      "canonical_doc": Json::string("AI-DEVELOPMENT-STANDARD.md"),
      "general_rules": Json::array(gen),
      "fist_specific_rules": Json::array(fist),
      "count_general": Json::number(gen_cnt),
      "count_fist": Json::number(fist_cnt),
      "count_total": Json::number(total),
      "checklist": Json::array(checklist()),
    })
  } else {
    Json::object({
      "project_type": Json::string(project_type),
      "generated_at": Json::string(
        "project_standards.mbt (pure, deterministic)",
      ),
      "version": Json::string("R116"),
      "canonical_doc": Json::string("AI-DEVELOPMENT-STANDARD.md"),
      "general_rules": Json::array(gen),
      "fist_specific_rules": Json::array(fist),
      "count_general": Json::number(gen_cnt),
      "count_fist": Json::number(fist_cnt),
      "count_total": Json::number(total),
    })
  }
}
