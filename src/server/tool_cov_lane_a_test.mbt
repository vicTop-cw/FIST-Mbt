/// tool_cov_lane_a_test.mbt —— Lane A「纯计算族」工具的行为锁（第一批 3 个）。
///
/// 覆盖：`staff_label_of` / `text_diff` / `audit_permission`。
///
/// ## 为什么是这三个（`scripts/check_tool_coverage.py` 判据）
///
/// 判据报「外壳零覆盖」= 任何测试文本里都没出现过这些工具名。它们是纯计算族：
/// handler 内部只做「参数解析 → 调实现函数 → 拼 JSON」，没有 IO、没有引擎状态。
/// 本文件按工具 handler 的**真实调用链**逐段断言返回值：
///
/// | 工具 | handler 调的实现 | 本文件断言的返回值 |
/// |---|---|---|
/// | `staff_label_of` | `@display.staff_label / staff_duty / staff_hierarchy / staff_titles / staff_title_count` | 军职名、职责、挂靠体系、6 职表完整性 |
/// | `text_diff` | `@diff.diff_lines / render_unified / render_json / diff_stats` | 这三条正是工具三种 `format` 的**回执正文本身**（handler 原样透传） |
/// | `audit_permission` | `@ops.Role::from_string + @ops.enforce` | `allowed:true` 分支 / `message` 文案（handler 原样透传 msg） |
///
/// ## 诚实边界（不假装测过）
///
/// 上述三个 handler 的**函数体是 `run_server()` 内的匿名闭包**（`server.mbt` 内联），
/// 进程内无法从测试里取到句柄 ⇒ 本文件覆盖的是「实现语义 + 回执内容」，
/// **不含** `Json::object({...})` 那一行字段拼装。要补那一层，正解是把 handler 体
/// 抽成顶层 `pub fn`（如 `project_standards` 那样）再锁——那需要改 `server.mbt`，
/// 不在本任务边界内（只允许新增测试文件）。已写进报告「缺口与风险」。
///
/// 断言口径（防判例-30 自指假绿）：每条断言都落在**真实返回值**上，
/// 变异实现（改映射表 / 改 diff 回溯 / 改权限矩阵）会让本文件变红。

///|
/// 带诊断文案的断言（本仓 `assert` 的 msg 参数跨版本不稳，沿用 abort 传话的惯例）。
fn tla_must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
/// 角色字符串 → `@ops.Role`（解析失败直接炸，避免测试把 None 当通过）。
fn tla_role(s : String) -> @ops.Role {
  match @ops.Role::from_string(s) {
    Some(r) => r
    None =>
      abort("角色解析失败（本测试的前置条件不成立）: " + s)
  }
}

///|
/// 操作序列 → "equal,delete,insert,equal" 形态的 kind 串（便于一条断言看全序列）。
fn tla_kinds(ops : Array[@diff.DiffOp]) -> String {
  ops.map(fn(op) { op.kind() }).join(",")
}

// ─────────────────────────────────────────────────────────────────────────
// staff_label_of（参谋线展示层）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 正常路径：关键词 → 参谋军职，且**同一 title 的职责/挂靠体系自洽**。
///
/// `staff_label_of` 的回执 = {title, duty, hierarchy, count, titles}，
/// 前三个字段各由一次实现函数调用得到；任一映射表被改坏本格即红。
test "staff_label_of：正常路径——关键词映射到军职且职责/挂靠三件套自洽" {
  let title = @display.staff_label("searcher")
  tla_must(
    title == "侦察参谋",
    "role=searcher 应映射到侦察参谋，实际 " + title,
  )
  tla_must(
    @display.staff_duty(title) == "情报搜集、可行性调研",
    "侦察参谋 duty 应与 §8.1 表一致，实际 " +
    @display.staff_duty(title),
  )
  tla_must(
    @display.staff_hierarchy(title) == "Leader 体系 / Searcher 职能",
    "侦察参谋挂靠体系应为 Leader 体系 / Searcher 职能，实际 " +
    @display.staff_hierarchy(title),
  )
  // 工具 role 参数直接喂 staff_label ⇒ 中文关键词与大小写不敏感同为契约
  tla_must(
    @display.staff_label("情报") == "侦察参谋",
    "中文关键词『情报』应映射到侦察参谋",
  )
  tla_must(
    @display.staff_label("VERIFIER") == "验收宪兵",
    "role 匹配应大小写不敏感：VERIFIER 应映射到验收宪兵，实际 " +
    @display.staff_label("VERIFIER"),
  )
}

///|
/// 6 职表完整性：`count` 与 `titles` 长度一致，且**每个 title 都有职责与挂靠体系**。
///
/// 这条锁的是「注册表加了军职、duty/hierarchy 表漏加」那一类漂移
/// （与 mode_templates 文档里点名的 BUG-118 同族：表对不上就等于没人报）。
test "staff_label_of：count/titles 与 6 职职责表一一对应（新增军职漏表即红）" {
  let titles = @display.staff_titles()
  tla_must(
    titles.length() == 6,
    "参谋军职应恰 6 个，实际 " + titles.length().to_string(),
  )
  tla_must(
    @display.staff_title_count() == 6,
    "staff_title_count 应与 titles 长度一致（6），实际 " +
    @display.staff_title_count().to_string(),
  )
  for t in titles {
    tla_must(
      @display.staff_duty(t) != "未知参谋军职",
      "军职 " +
      t +
      " 在 duty 表里缺席（回执会出现『未知参谋军职』）",
    )
    tla_must(
      @display.staff_hierarchy(t) != "未知挂靠体系",
      "军职 " +
      t +
      " 在 hierarchy 表里缺席（回执会出现『未知挂靠体系』）",
    )
  }
  // 默认军职必须在表内（它是 role 缺省时的回退目标）
  tla_must(
    titles.contains("军务文书"),
    "默认军职『军务文书』必须在 6 职表内",
  )
}

///|
/// 边界/异常：空 role、未知词、**协议角色名 `leader`** 一律回退「军务文书」；
/// 显式 `title` 指定未知值时，回执落到「未知…」而非崩溃。
test "staff_label_of：边界——空/未知/协议角色名回退军务文书，未知 title 不崩" {
  tla_must(
    @display.staff_label("") == "军务文书",
    "空 role 应回退默认军职『军务文书』，实际 " +
    @display.staff_label(""),
  )
  tla_must(
    @display.staff_label("zzz-not-a-tag") == "军务文书",
    "未知关键词应回退『军务文书』，实际 " +
    @display.staff_label("zzz-not-a-tag"),
  )
  // 参谋军职不是协议角色：协议角色名 leader 在参谋表里无对应 ⇒ 回退默认
  // （这条同时锁住『别把协议角色名硬塞进参谋线』这一设计边界）
  tla_must(
    @display.staff_label("leader") == "军务文书",
    "协议角色名 leader 不在参谋表内，应回退『军务文书』，实际 " +
    @display.staff_label("leader"),
  )
  tla_must(
    @display.staff_duty("军务文书") == "记录、台账、日志归档",
    "默认军职职责文案应稳定（面板/汇报文案依赖它）",
  )
  tla_must(
    @display.staff_duty("不存在的军职") == "未知参谋军职",
    "未知 title 的 duty 应为『未知参谋军职』，不能返回空串或崩溃",
  )
  tla_must(
    @display.staff_hierarchy("不存在的军职") == "未知挂靠体系",
    "未知 title 的 hierarchy 应为『未知挂靠体系』",
  )
}

// ─────────────────────────────────────────────────────────────────────────
// text_diff（LCS 文本 diff）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 正常路径：旧 a/b/c → 新 a/x/c 的 LCS 序列 = equal,delete,insert,equal。
///
/// `format` 缺省（unified）时工具回执**就是** `render_unified` 的返回值；
/// `format=stats` 时**就是** `diff_stats` 三元组 ⇒ 断言这两者等于断言回执正文。
test "text_diff：正常路径——LCS 序列与 unified 渲染（format 缺省形态）" {
  let ops = @diff.diff_lines("a\nb\nc", "a\nx\nc")
  tla_must(
    ops.length() == 4,
    "a/b/c → a/x/c 应得 4 个操作，实际 " + ops.length().to_string(),
  )
  tla_must(
    tla_kinds(ops) == "equal,delete,insert,equal",
    "操作序列应为 equal,delete,insert,equal，实际 " + tla_kinds(ops),
  )
  tla_must(
    @diff.render_unified(ops) == " a\n-b\n+x\n c",
    "unified 正文应为『 a / -b / +x /  c』，实际:\n" +
    @diff.render_unified(ops),
  )
  let (eq, ins, del) = @diff.diff_stats(ops)
  tla_must(
    eq == 2 && ins == 1 && del == 1,
    "stats 应为 equal=2/insert=1/delete=1，实际 " +
    eq.to_string() +
    "/" +
    ins.to_string() +
    "/" +
    del.to_string(),
  )
}

///|
/// 边界：两段都空 ⇒ 零操作、`format=json` 回执恰为 `[]`；完全相同 ⇒ 全 equal、
/// 不产生假差异（diff 最常见的误报就是「无变化却报 delete/insert」）。
test "text_diff：边界——空文本零操作、相同文本不产生假差异" {
  let empty = @diff.diff_lines("", "")
  tla_must(
    empty.length() == 0,
    "空 vs 空应得 0 个操作，实际 " + empty.length().to_string(),
  )
  tla_must(
    @diff.render_json(empty) == "[]",
    "format=json 的空 diff 应为 []，实际 " + @diff.render_json(empty),
  )
  let same = @diff.diff_lines("a\nb", "a\nb")
  let (eq, ins, del) = @diff.diff_stats(same)
  tla_must(
    eq == 2 && ins == 0 && del == 0,
    "相同文本应全 equal（2/0/0），实际 " +
    eq.to_string() +
    "/" +
    ins.to_string() +
    "/" +
    del.to_string(),
  )
  tla_must(
    @diff.render_unified(same) == " a\n b",
    "相同文本的 unified 正文应全是空格前缀，实际:\n" +
    @diff.render_unified(same),
  )
}

///|
/// 边界：**尾部换行差异不能被静默丢掉**。
///
/// `split_lines` 的注释写明这是刻意修过的坑（丢尾部空行会让
/// `diff_lines("a\n", "a")` 判成无差异）。这条锁直指该语义。
test "text_diff：边界——尾部换行差异必须报出一条 delete" {
  let ops = @diff.diff_lines("a\n", "a")
  let (eq, ins, del) = @diff.diff_stats(ops)
  tla_must(
    del == 1,
    "『a\\n』vs『a』尾部空行差异应报 delete=1，实际 " +
    del.to_string() +
    "（漏报即回到修前的假无差异）",
  )
  tla_must(
    eq == 1 && ins == 0,
    "除尾部空行外其余行应 equal（1/0），实际 " +
    eq.to_string() +
    "/" +
    ins.to_string(),
  )
  tla_must(
    @diff.render_unified(ops) == " a\n-",
    "unified 应为『 a』+ 一条空删除行『-』，实际:\n" +
    @diff.render_unified(ops),
  )
}

///|
/// 边界/异常：`format=json` 的转义必须成立（引号/反斜杠进 JSON 文本后仍是合法 JSON）。
///
/// BUG-216 就是这条线：旧 `json_escape` 只转 5 个字符，控制字符原样拼进去 ⇒
/// `text_diff format=json` 产出非法 JSON。本格断言引号与结构骨架。
test "text_diff：json 格式——引号与结构骨架转义后才回执" {
  let ops = @diff.diff_lines("say \"hi\"", "")
  let j = @diff.render_json(ops)
  tla_must(
    tla_kinds(ops) == "delete",
    "右侧清空时左侧应整体 delete，实际 " + tla_kinds(ops),
  )
  tla_must(
    j.contains("\\\"hi\\\""),
    "JSON 正文里引号必须转义为 \\\"，实际 " + j,
  )
  tla_must(
    j.contains("{\"kind\":\"delete\",\"text\":"),
    "JSON 条目骨架应为 {kind,text}，实际 " + j,
  )
  tla_must(
    j.contains("say"),
    "转义不能吞掉正文：应保留 say，实际 " + j,
  )
}

// ─────────────────────────────────────────────────────────────────────────
// audit_permission（角色矩阵只读查询）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 正常路径：`human_steward` 可 publish（allowed:true 分支）；`agent`/`leader`
/// 可 claim（claim 面向三角色全放开）。这三条正是 `allowed` 位为 true 的格子。
test "audit_permission：正常路径——human_steward 可发布、agent/leader 可认领" {
  tla_must(
    @ops.enforce(action="publish", role=tla_role("human_steward")) is Ok(_),
    "human_steward 应可 publish（allowed 必须返回 true）",
  )
  tla_must(
    @ops.enforce(action="claim", role=tla_role("agent")) is Ok(_),
    "agent 应可 claim（claim 面向三角色全放开）",
  )
  tla_must(
    @ops.enforce(action="claim", role=tla_role("leader")) is Ok(_),
    "leader 应可 claim",
  )
  tla_must(
    @ops.enforce(action="claim", role=tla_role("human_steward")) is Ok(_),
    "human_steward 应可 claim",
  )
}

///|
/// 拒绝路径：**回执 message 是 `enforce` 的 Err 文案原样透传**
/// ⇒ 断言文案里的角色、操作、所需角色三个关键片段（不断言整串），
/// 调用方靠这段文案判断「该找谁授权」。
test "audit_permission：拒绝路径——agent 发布被拒且文案点名角色/操作/所需角色" {
  match @ops.enforce(action="publish", role=tla_role("agent")) {
    Ok(_) =>
      abort(
        "audit_permission: agent 可 publish ⇒ 人类主权矩阵被破坏",
      )
    Err(m) => {
      tla_must(
        m.contains("权限拒绝"),
        "拒绝文案应含『权限拒绝』，实际 " + m,
      )
      tla_must(
        m.contains("[agent]") && m.contains("[publish]"),
        "拒绝文案应点名角色与操作，实际 " + m,
      )
      tla_must(
        m.contains("该操作需 human_steward"),
        "拒绝文案应指明所需角色（human_steward），实际 " + m,
      )
    }
  }
  // leader 也不是「唯一指挥官」：archive/delete/publish 同样拒
  tla_must(
    @ops.enforce(action="archive", role=tla_role("leader")) is Err(_),
    "leader 不可 archive（仅 human_steward）",
  )
  tla_must(
    @ops.enforce(action="delete", role=tla_role("leader")) is Err(_),
    "leader 不可 delete（仅 human_steward）",
  )
  // 反向确认 human_steward 的 archive/delete 不被误伤
  tla_must(
    @ops.enforce(action="archive", role=tla_role("human_steward")) is Ok(_),
    "human_steward 应可 archive",
  )
}

///|
/// 边界/异常：未知角色解析失败（工具据此走 `未知角色: … 合法值…` 的 ToolError 分支），
/// 未知 action 一律拒绝（`enforce` 的 `_ => false` 兜底，绝不能静默放行）。
test "audit_permission：边界——未知角色解析失败、未知操作不静默放行" {
  match @ops.Role::from_string("root") {
    None => ()
    Some(_) =>
      abort(
        "audit_permission: 未知角色 root 必须解析失败，否则非法角色可越过角色矩阵",
      )
  }
  // 角色名大小写敏感：工具只接受 human_steward / leader / agent 三个字面值
  match @ops.Role::from_string("Human_Steward") {
    None => ()
    Some(_) =>
      abort(
        "audit_permission: 角色名应大小写敏感，Human_Steward 必须解析失败",
      )
  }
  tla_must(
    @ops.Role::from_string("leader") is Some(_),
    "合法角色 leader 必须可解析（否则工具对所有调用都报未知角色）",
  )
  match @ops.enforce(action="frobnicate", role=tla_role("human_steward")) {
    Ok(_) =>
      abort(
        "audit_permission: 未知 action 必须拒绝，不能落到允许分支",
      )
    Err(m) => {
      tla_must(
        m.contains("不可执行"),
        "未知 action 的拒绝文案应含『不可执行』，实际 " + m,
      )
      tla_must(
        m.contains("[frobnicate]"),
        "拒绝文案应点名该未知操作，实际 " + m,
      )
    }
  }
}
