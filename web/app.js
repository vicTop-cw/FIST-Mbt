/* fist-mbt Dashboard · app.js
   零依赖原生 SPA 逻辑。所有函数均为浏览器环境；纯函数（不碰 DOM）放在
   `Pure` 命名空间下，供 node 冒烟测试直接 require 验证。
*/
"use strict";

/* =====================================================================
 * 全局状态
 * ===================================================================== */
var STATE = {
  ns: "default",            // 当前命名空间
  tasks: [],                // 扁平任务数组（扁平化缓存）
  byStatus: {},             // status -> count
  flatCount: 0,             // 任务总数
  updatedAt: null,          // 数据源更新时间
  autoRefreshMs: 5000,      // 自动刷新间隔
  autoRefreshTimer: null,   // setInterval 句柄
  sse: null,                // EventSource 实例
  sseOpen: false,           // SSE 状态
  selectedId: null,         // 当前选中任务
  expanded: {}              // 任务 id -> true（展开态）
};

/* =====================================================================
 * Pure 纯函数（无 DOM 依赖，可被 node require）
 * ===================================================================== */
var Pure = {};

/** HTML 转义（防注入） */
Pure.esc = function (s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
};

/** 状态 → 颜色 CSS 类。中文为主，英文兜底，未知态统一灰色。 */
Pure.statusColor = function (status) {
  var map = {
    // 中文
    "待领取": "st-待领取",
    "已领取": "st-已领取",
    "执行中": "st-RUNNING",   // 中文未在 fist-config 中覆盖，走英文兜底色
    "待验收": "st-待验收",
    "已完成": "st-已完成",
    "已归档": "st-已归档",
    "已暂停": "st-已暂停",
    "已打回": "st-已打回",
    "拆分中": "st-拆分中",
    // 英文
    "PENDING":   "st-PENDING",
    "CLAIMED":   "st-CLAIMED",
    "RUNNING":   "st-RUNNING",
    "SPLITTING": "st-SPLITTING",
    "REVIEW":    "st-REVIEW",
    "COMPLETED": "st-COMPLETED",
    "FAILED":    "st-FAILED",
    "ARCHIVED":  "st-ARCHIVED"
  };
  if (status == null) return "st-unknown";
  return map[String(status)] || "st-unknown";
};

/** 状态显示名（未知态直接回显原值） */
Pure.statusLabel = function (status) {
  return status == null ? "未知" : String(status);
};

/** 渲染单个状态徽章 HTML */
Pure.badgeHTML = function (status) {
  return '<span class="badge ' + Pure.statusColor(status) + '">'
    + Pure.esc(Pure.statusLabel(status)) + "</span>";
};

/** 渲染状态计数条 HTML（byStatus + flatCount 兜底 total） */
Pure.renderStatusBarHTML = function (byStatus, flatCount) {
  var ORDER = ["待领取", "已领取", "拆分中", "待验收", "已完成", "已打回", "已暂停", "已归档"];
  var html = "";
  // 先按固定顺序，再补未知状态
  var keys = ORDER.filter(function (k) {
    return byStatus && Object.prototype.hasOwnProperty.call(byStatus, k) && byStatus[k] > 0;
  });
  var extra = Object.keys(byStatus || {}).filter(function (k) { return ORDER.indexOf(k) < 0; });
  keys = keys.concat(extra);
  if (!keys.length) {
    html = '<span class="muted">暂无任务</span>';
  } else {
    keys.forEach(function (st) {
      var n = byStatus[st] || 0;
      html += '<span class="stat">' + Pure.badgeHTML(st) + " <b>" + n + "</b></span>";
    });
  }
  var total = flatCount != null ? flatCount : (function () {
    var s = 0;
    for (var k in (byStatus || {})) { s += (byStatus[k] || 0); }
    return s;
  })();
  html += '<span class="stat total">总计 <b>' + total + "</b></span>";
  return html;
};

/** 渲染单行任务 HTML（不递归子节点；children 由外层递归处理） */
Pure.taskRowHTML = function (t, depth, isExpanded, isSelected) {
  var id = Pure.esc(t.id == null ? "" : String(t.id));
  var status = t.status;
  var updated = Pure.fmtTime(t.updated_at);
  var indentStyle = depth > 0 ? ' style="margin-left:' + (depth * 20) + 'px"' : "";
  var leafTag = t.is_leaf ? '<span class="leaf-tag">叶</span>' : "";
  var depthTag = (t.depth != null ? '<span class="depth-tag">d' + t.depth + "</span>" : "");
  var childCount = Array.isArray(t.children) ? t.children.length : 0;
  var twist = childCount > 0 ? '<span class="twist">' + (isExpanded ? "▾" : "▸") + "</span>" : '<span class="twist">·</span>';
  var active = isSelected ? " active" : "";
  return '<div class="node">'
    + '<div class="node-row' + active + '" data-id="' + id + '"' + indentStyle + ">"
    + twist
    + Pure.badgeHTML(status)
    + '<span class="id">' + id + "</span>"
    + depthTag
    + leafTag
    + '<span class="desc" title="' + Pure.esc(Pure.shortText(t.description, 180)) + '">'
    + Pure.esc(Pure.shortText(t.description, 70)) + "</span>"
    + '<span class="meta">' + updated + "</span>"
    + "</div>";
};

/** 扁平化嵌套树（DFS，稳定：children 已按 id 升序，按数组顺序遍历） */
Pure.flatten = function (tasks) {
  var out = [];
  function walk(arr, depth) {
    (arr || []).forEach(function (n) {
      if (n == null) return;
      out.push(n);
      if (Array.isArray(n.children)) walk(n.children, (n.depth != null ? n.depth : depth) + 1);
    });
  }
  walk(tasks, 0);
  return out;
};

/** 递归渲染任务树 HTML */
Pure.renderTaskTreeHTML = function (tasks, expanded, selectedId) {
  var expandedMap = expanded || {};
  function walk(arr, depth) {
    var html = "";
    (arr || []).forEach(function (n) {
      if (n == null) return;
      var id = n.id == null ? "" : String(n.id);
      html += Pure.taskRowHTML(n, depth, !!expandedMap[id], id === selectedId);
      if (Array.isArray(n.children) && n.children.length && expandedMap[id]) {
        html += walk(n.children, depth + 1);
      }
    });
    return html;
  }
  var h = walk(tasks, 0);
  if (!h) return '<div class="empty">暂无任务</div>';
  return h;
};

/** 时间格式化 */
Pure.fmtTime = function (s) {
  if (!s) return "-";
  var d = new Date(s);
  return isNaN(d.getTime()) ? String(s) : d.toLocaleString("zh-CN", { hour12: false });
};

/** 截断长文本 */
Pure.shortText = function (s, n) {
  s = String(s || "").replace(/\s+/g, " ").trim();
  return s.length > (n || 60) ? s.slice(0, n || 60) + "…" : s;
};

/* =====================================================================
 * 浏览器侧：DOM 快捷
 * ===================================================================== */
function $(id) { return document.getElementById(id); }

/** 显示错误条（5s 自动隐藏） */
function showError(msg) {
  var bar = $("error-bar");
  var el = $("error-msg");
  if (!bar || !el) return;
  el.textContent = String(msg || "请求失败");
  bar.classList.remove("hidden");
  clearTimeout(showError._timer);
  showError._timer = setTimeout(hideError, 5000);
}

/** 隐藏错误条 */
function hideError() {
  var bar = $("error-bar");
  if (bar) bar.classList.add("hidden");
}

/** Toast 轻提示（详情加载失败用） */
function toast(msg) {
  var el = document.getElementById("toast");
  if (!el) return;
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toast._timer);
  toast._timer = setTimeout(function () { el.classList.remove("show"); }, 2200);
}

/** 更新 SSE 状态灯（open/error/closed） */
function setSSEState(state) {
  STATE.sseOpen = state === "open";
  var lamp = $("sse-lamp");
  var label = $("sse-label");
  if (!lamp || !label) return;
  lamp.className = "lamp lamp-" + (state === "open" ? "open" : state === "error" ? "err" : "off");
  label.textContent = state === "open" ? "SSE 已连接"
    : state === "error" ? "SSE 错误"
    : "SSE 未连接";
}

/* =====================================================================
 * 数据加载
 * ===================================================================== */

/** 通用 JSON GET，非 200 或 ok=false 抛错 */
async function jget(url) {
  var r = await fetch(url, { headers: { "Accept": "application/json" } });
  if (!r.ok) {
    var body = null;
    try { body = await r.json(); } catch (e) { body = null; }
    var msg = (body && (body.error || body.message)) || ("HTTP " + r.status);
    var err = new Error(msg);
    err.status = r.status;
    throw err;
  }
  return r.json();
}

/** 从 /api/status 提取 status_summary（防御式，多种字段形态） */
function extractSummary(statusPayload) {
  if (!statusPayload) return null;
  if (statusPayload.status && typeof statusPayload.status === "object") return statusPayload.status;
  if (statusPayload.summary && typeof statusPayload.summary === "object") return statusPayload.summary;
  return null;
}

/** 拉取 /api/status：填充 ns 下拉 + 状态计数条 */
async function fetchStatus() {
  try {
    var payload = await jget("/api/status");
    var summary = extractSummary(payload) || payload;
    var byStatus = summary.by_status || summary.byStatus || {};
    var total = (summary.total_tasks != null ? summary.total_tasks : summary.total) || null;
    STATE.byStatus = byStatus;
    STATE.flatCount = total != null ? total : STATE.flatCount;
    populateNsSelect(summary.active_namespaces);
    renderStatusBar(STATE.byStatus, STATE.flatCount);
    return payload;
  } catch (e) {
    showError("获取状态失败: " + e.message);
    return null;
  }
}

/** 拉取 /api/tasks，扁平化后统一渲染 */
async function fetchTasks(ns) {
  var target = ns || STATE.ns;
  STATE.ns = target;
  try {
    var url = "/api/tasks?ns=" + encodeURIComponent(target);
    var payload = await jget(url);
    if (payload == null || payload.ok === false) {
      throw new Error((payload && payload.error) || "接口返回异常");
    }
    var tasks = payload.tasks;
    if (!Array.isArray(tasks)) tasks = [];

    STATE.tasks = Pure.flatten(tasks);
    STATE.byStatus = payload.by_status || payload.byStatus || STATE.byStatus;
    STATE.flatCount = payload.flat_count != null ? payload.flat_count
      : (payload.total_tasks != null ? payload.total_tasks
      : (payload.total != null ? payload.total : STATE.tasks.length));
    STATE.updatedAt = payload.updated_at || payload.updatedAt || new Date().toISOString();

    renderStatusBar(STATE.byStatus, STATE.flatCount);
    renderTaskTree(tasks, $("task-tree"));
    renderUpdatedAt();
    return tasks;
  } catch (e) {
    showError("获取任务失败: " + e.message);
    return null;
  }
}

/** 拉取单任务详情，渲染右侧面板 */
async function fetchTaskDetail(id) {
  if (id == null || id === "") return;
  var panel = $("detail-panel");
  if (panel) panel.innerHTML = '<div class="empty">加载中…</div>';
  try {
    var url = "/api/tasks/" + encodeURIComponent(String(id));
    var payload = await jget(url);
    if (payload == null || payload.ok === false) {
      throw new Error((payload && payload.error) || "任务不存在");
    }
    var task = payload.task || payload;   // 兼容 {task:{...}} 与扁平两种形态
    renderDetailPanel(task);
  } catch (e) {
    if (panel) panel.innerHTML = '<div class="empty">加载失败: ' + Pure.esc(e.message) + "</div>";
    toast("加载详情失败: " + e.message);
  }
}

/* =====================================================================
 * 渲染
 * ===================================================================== */

/** 渲染状态计数条 */
function renderStatusBar(byStatus, flatCount) {
  var el = $("status-bar");
  if (!el) return;
  el.innerHTML = Pure.renderStatusBarHTML(byStatus || {}, flatCount);
}

/** 渲染任务树（递归） */
function renderTaskTree(tasks, container) {
  if (!container) return;
  container.innerHTML = Pure.renderTaskTreeHTML(tasks || [], STATE.expanded, STATE.selectedId);
}

/** 更新页脚更新时间 + 高亮当前选中行 */
function renderUpdatedAt() {
  var el = $("updated-at");
  if (el) el.textContent = "更新于 " + new Date().toLocaleTimeString("zh-CN", { hour12: false });
}

/** 渲染详情面板 */
function renderDetailPanel(task) {
  var panel = $("detail-panel");
  var title = $("detail-title");
  if (!panel) return;
  var id = task.id == null ? "" : String(task.id);
  if (title) title.innerHTML = "任务详情 · <code>" + Pure.esc(id) + "</code> " + Pure.badgeHTML(task.status);

  var deps = (task.depends_on || []).map(function (d) {
    return '<span class="chip" data-goto="' + Pure.esc(String(d)) + '">⛓ ' + Pure.esc(String(d)) + "</span>";
  }).join("");
  var down = (task.downstream || []).map(function (d) {
    return '<span class="chip" data-goto="' + Pure.esc(String(d)) + '">→ ' + Pure.esc(String(d)) + "</span>";
  }).join("");

  var meta = [
    ["父任务", task.parent_id ? '<span class="chip" data-goto="' + Pure.esc(String(task.parent_id)) + '">' + Pure.esc(String(task.parent_id)) + "</span>" : "—"],
    ["命名空间 ns", Pure.esc(task.ns || "—")],
    ["优先级 / 重要度", Pure.esc(String(task.priority || "—")) + " / " + Pure.esc(String(task.importance || "—"))],
    ["深度 / 拆分份数", Pure.esc(String(task.depth != null ? task.depth : "—")) + " / " + Pure.esc(String(task.split_n != null ? task.split_n : "—"))],
    ["负责人 assignee", Pure.esc(task.assignee || "—")],
    ["创建时间", Pure.fmtTime(task.created_at)],
    ["更新时间", Pure.fmtTime(task.updated_at)],
    ["完成人", Pure.esc(task.completed_by || "—")],
    ["清理模式", Pure.esc(task.cleanup_mode || "—")]
  ].map(function (r) { return "<tr><th>" + r[0] + "</th><td>" + r[1] + "</td></tr>"; }).join("");

  var logs = task.logs || [];
  var logRows = logs.map(function (l) {
    var fail = l.failure_reason ? '<span class="logfail">' + Pure.esc(Pure.shortText(l.failure_reason, 90)) + "</span>" : "—";
    return "<tr><td>" + Pure.fmtTime(l.created_at) + "</td><td>" + Pure.esc(l.executor || "—") + "</td>"
      + "<td>" + Pure.esc(l.model || "—") + "</td><td>" + (l.tokens_in || 0) + "/" + (l.tokens_out || 0) + "</td>"
      + "<td>" + Pure.esc(l.cost || "0") + "</td><td>" + (l.duration_ms || 0) + " ms</td><td>" + fail + "</td></tr>";
  }).join("");

  panel.innerHTML = ""
    + '<h3>描述</h3><pre class="desc">' + Pure.esc(task.description || "（无描述）") + "</pre>"
    + '<h3>元信息</h3><table>' + meta + "</table>"
    + '<h3>DAG 依赖</h3>'
    + '<div class="muted">上游 depends_on：' + (deps || "（无）") + "<br>下游 downstream：" + (down || "（无）") + "</div>"
    + '<h3>执行日志（executions ' + logs.length + "）</h3>"
    + '<div class="log-table"><table><tr><th>时间</th><th>执行器</th><th>模型</th><th>in/out</th><th>费用</th><th>耗时</th><th>失败原因</th></tr>'
    + (logRows || '<tr><td colspan="7" class="muted">暂无执行日志</td></tr>') + "</table></div>";

  // 绑定 chip 跳转（事件委托）
  panel.querySelectorAll(".chip[data-goto]").forEach(function (chip) {
    chip.onclick = function () {
      var gid = chip.getAttribute("data-goto");
      if (gid) selectTask(gid);
    };
  });
}

/* =====================================================================
 * 交互
 * ===================================================================== */

/** 选中一个任务：高亮 + 展开父链 + 拉详情 */
function selectTask(id) {
  STATE.selectedId = id == null ? null : String(id);
  // 确保该任务所在父链可见（展开所有祖先）
  expandAncestors(STATE.selectedId);
  renderTaskTree(STATE.tasks, $("task-tree"));
  fetchTaskDetail(STATE.selectedId);
}

/** 依据 parent_id 展开祖先链 */
function expandAncestors(id) {
  var byId = {};
  STATE.tasks.forEach(function (t) { byId[String(t.id)] = t; });
  var cur = byId[String(id)];
  var guard = 0;
  while (cur && cur.parent_id && guard++ < 100) {
    var pid = String(cur.parent_id);
    STATE.expanded[pid] = true;
    cur = byId[pid];
  }
}

/** 初始化 ns 下拉 */
function populateNsSelect(activeNamespaces) {
  var sel = $("ns-select");
  if (!sel) return;
  var list = Array.isArray(activeNamespaces) && activeNamespaces.length
    ? activeNamespaces
    : ["default", "fist-mbt-web"];
  // 避免重复
  var seen = {};
  var cur = sel.value || STATE.ns;
  sel.innerHTML = "";
  list.forEach(function (n) {
    if (seen[n]) return;
    seen[n] = true;
    var o = document.createElement("option");
    o.value = n;
    o.textContent = n;
    if (n === cur) o.selected = true;
    sel.appendChild(o);
  });
}

/** 切换 ns：持久化 + 重新拉任务 */
function switchNs(ns) {
  STATE.ns = ns || "default";
  STATE.tasks = [];
  STATE.selectedId = null;
  STATE.expanded = {};
  try { localStorage.setItem("fist-mbt-dashboard-ns", STATE.ns); } catch (e) { /* ignore */ }
  fetchTasks(STATE.ns);
  fetchStatus();
}

/* =====================================================================
 * SSE
 * ===================================================================== */

function connectSSE() {
  if (STATE.sse) {
    try { STATE.sse.close(); } catch (e) { /* ignore */ }
    STATE.sse = null;
  }
  if (typeof EventSource === "undefined") {
    setSSEState("off");
    return;
  }
  try {
    var es = new EventSource("/api/events");
    STATE.sse = es;
    es.onopen = function () { setSSEState("open"); };
    es.onerror = function () { setSSEState("error"); };  // EventSource 会自动重连
    es.onmessage = function (ev) { handleSSEMessage(null, ev.data); };
    es.addEventListener("snapshot", function (ev) { handleSSEMessage("snapshot", ev.data); });
    es.addEventListener("heartbeat", function (ev) { handleSSEMessage("heartbeat", ev.data); });
  } catch (e) {
    setSSEState("off");
  }
}

/** SSE 消息分发 */
function handleSSEMessage(type, data) {
  var payload = null;
  if (data) { try { payload = JSON.parse(data); } catch (e) { payload = null; } }
  if (type === "snapshot" || (payload && payload.type === "snapshot")) {
    // snapshot 触发数据刷新
    fetchTasks(STATE.ns);
    fetchStatus();
  }
  // heartbeat 仅用于保持连接，不做刷新（避免风暴）
}

/* =====================================================================
 * 自动刷新
 * ===================================================================== */

function startAutoRefresh() {
  stopAutoRefresh();
  STATE.autoRefreshTimer = setInterval(function () {
    fetchTasks(STATE.ns);
  }, STATE.autoRefreshMs);
}

function stopAutoRefresh() {
  if (STATE.autoRefreshTimer) {
    clearInterval(STATE.autoRefreshTimer);
    STATE.autoRefreshTimer = null;
  }
}

/* =====================================================================
 * 初始化
 * ===================================================================== */

function init() {
  // 读上次 ns
  try {
    var saved = localStorage.getItem("fist-mbt-dashboard-ns");
    if (saved) STATE.ns = saved;
  } catch (e) { /* ignore */ }

  // 绑定事件
  $("ns-select").onchange = function () { switchNs(this.value); };
  $("refresh").onclick = function () {
    fetchTasks(STATE.ns);
    fetchStatus();
  };
  $("auto-refresh").onchange = function () {
    if (this.checked) startAutoRefresh(); else stopAutoRefresh();
  };
  var closeBtn = $("error-close");
  if (closeBtn) closeBtn.onclick = hideError;

  // 任务树点击委托
  $("task-tree").onclick = function (ev) {
    var row = ev.target.closest ? ev.target.closest(".node-row") : null;
    if (!row) return;
    var id = row.getAttribute("data-id");
    if (!id) return;
    if (STATE.selectedId === id && STATE.expanded[id]) {
      // 再次点击收起
      STATE.expanded[id] = false;
    } else {
      STATE.expanded[id] = true;
    }
    selectTask(id);
  };

  // 初始填充下拉兜底
  populateNsSelect(null);

  // 启动
  fetchStatus();
  fetchTasks(STATE.ns);
  connectSSE();
  startAutoRefresh();
}

if (typeof document !== "undefined" && document.readyState) {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
}

/* =====================================================================
 * Node 导出（仅供冒烟测试）
 * ===================================================================== */
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    Pure: Pure,
    STATE: STATE,
    extractSummary: extractSummary
  };
}
