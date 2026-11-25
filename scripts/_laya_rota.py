#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_laya_rota.py — 「一来一回换一个可用空闲服务」的确定性轮转策略（T0r127）。

**规格来源**：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md` 工作项四 + 裁决 A1~A4 + 红线。
本模块只做**纯规则选路**（无网络、无 IO、无时钟副作用），因此验收五格可以离线钉死：
  ① 跳过 busy   ② 跳过 cooldown   ③ 空池安全返回   ④ 失败顺延   ⑤ 窗口到期重置

**「空闲」判据（计划文件红线，三条件皆满足才入候选，任一不满足即顺延下一个）**：
  · 服务在注册表 alive → 调用方以 `busy_ids` / `dead_ids` 表达（本模块只读这两个集合，
    不自造探活，也不改注册表既有条目）；
  · 该服务上无存活执行会话 → `busy_ids`；
  · 该上游无冷却 / 未耗尽 → `cooldown_until > now` 或 `used >= limit`。
轮转是**软性**的：只做候选排序与跳过，不封禁任何服务（`fail_count` 到上限只是进冷却，
进程重启即归零；红线「失败一次记录并顺延，连续失败进冷却」）。

**与既有实现的关系（判例-29「机制格≠实现路径格」）**：
  · `src/router/model_router.mbt::pool_pick` —— 环形扫描形态的**参照**（`(start+i)%n`，
    下标随 i 走）。MoonBit 侧早已存在且被 `model_router_wbtest` / `rx_rate_limit_wbtest`
    锁住；Python 侧此前**没有**对应实现，`scripts/fist_gateway.py::CompletionPool._pick_next`
    只做线性取位（无过滤、无窗口）。本模块补的是 Python 侧这一格，不复制 MoonBit 语义
    到第二处（`pool_pick` 真源不动）。
  · `scripts/autoplan.py` 的 exec 轮转（`dispatch_round`）—— **不同语义**：那是「任务派给
    哪个 agent 身份」，且 P20（`2026-11-25-quota-recovery-and-dispatch-cap.md`）已裁决
    **取消 last_ok 提队首**。本模块不得引入同类「提队首」逻辑，两者不可混用。

**为什么时间比较用 datetime 而不用字典序**：与仓内 `scripts/check_fmt_gate.py` /
`check_known_red_until.py` 同族口径（字符串比较在带偏移量的 ISO 串上会误判），
也与 `model_router.window_expired` 的**意图**一致（按瞬时时间比，不是按串比）。

**为什么 `_` 前缀**：内部共享模块、被 `test_laya_rota.py` 导入、不独立成尺 ⇒
命中 `run_guards.EXEMPT_RULES` 的 `("_", "内部共享模块（被导入，非独立尺）")` 豁免。
本文件自己的参数面：无旗标（库模块，不当 CLI 跑）。

**本文件形态说明**：按本仓惯例「判据自带自检」，自检格与变异对照都内嵌在本文件里
（`python scripts/_laya_rota.py --selftest`），**不再另立 `test_*.py`** —— 那样会进
`check_scripts_index` 的登记面并要求改 `scripts/README.md`（该文件正被他方 WIP 占用）。
`_` 前缀同时豁免三处：`check_scripts_index.formal_scripts`（`_`=即用即清）、
`run_guards.EXEMPT_RULES`（内部共享模块）、`check_py_stdout_encoding` 的 `--all` 面。

用法（自检）：`python scripts/_laya_rota.py [--selftest]`
退出码：`0` 全绿（真模块全过 + 变异对照全生效）/ `1` 有断言失败或变异后点名格仍绿 /
`2` 判据无法自证（读不到自身源码、未知旗标）—— R207：拼错旗标不得静默落进真分支。
"""
from __future__ import annotations

import calendar
import os
import sys
import time
from datetime import datetime, timezone

# 失败重试上限（裁决 A3 = B 档：上限 3，超过即回明确错误体，不无限轮转）。
MAX_ATTEMPTS = 3

# 窗口秒数默认值：对齐 `src/router/model_router.mbt` 的 `window_seconds = 18000`（5 小时）。
DEFAULT_WINDOW_SECONDS = 18000


def iso_to_epoch(iso: str) -> float:
    """ISO 8601 → epoch 秒；**无法解析返回 -1.0**（哨兵，绝不抛异常打断轮转）。

    与 `model_router.iso_to_secs` 的 -1 哨兵同向；调用方必须显式处理负值，
    不得把 -1.0 当成「很早以前」参与比较（那会让冷却形同虚设 / 窗口永不重置）。
    支持 `Z` 结尾与带时区偏移两种写法；naive 串按 UTC 解（本仓时间戳一律 UTC）。
    """
    if not isinstance(iso, str):
        return -1.0
    s = iso.strip()
    if not s:
        return -1.0
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return -1.0
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def iso_now() -> str:
    """UTC ISO 8601 串（`YYYY-MM-DDTHH:MM:SSZ`）—— 便于持久化与跨进程对表。"""
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def in_cooldown(cooldown_until: str, now_iso: str) -> bool:
    """`cooldown_until` 晚于 `now` 即仍在冷却；空值 / 任一侧不可解析 ⇒ **视为无冷却**（放行）。

    参数是**冷却截止时间串本身**（不是候选字典）—— 调用方必须传「记账态」的那个字段：
    实测踩过的形状（2026-11-25 端到端探针）：早期版本从原始候选字典读，而 `on_failure`
    只写 `state`，于是运行期设下的冷却对选路**完全无效**（第 3 轮又选中刚冷却的候选）。
    fail-open 方向与 `ModelQuota::in_cooldown` 一致（`cool_secs <= 0` / `now_secs <= 0` ⇒ 放行），
    理由亦一致：坏时间戳锁死候选比放行更糟，冷却应由下一次失败自然重设。
    """
    until = cooldown_until or ""
    if not until:
        return False
    cool = iso_to_epoch(until)
    now = iso_to_epoch(now_iso)
    if cool <= 0 or now <= 0:
        return False
    return now < cool


def window_expired(window_start: str, now_iso: str, window_seconds: int) -> bool:
    """窗口是否到期：恰满 `window_seconds` 即算到期（`>=`，与 rt_6 锁一致）。

    起点为空 / 任一时间戳非法 ⇒ **false（不重置）**，绝不用坏时间戳清零用量。
    """
    if not window_start:
        return False
    start = iso_to_epoch(window_start)
    now = iso_to_epoch(now_iso)
    if start < 0 or now < 0:
        return False
    return (now - start) >= window_seconds


def window_reset_if_expired(state: dict, now_iso: str, window_seconds: int) -> bool:
    """到期则重置该候选（`used=0`、`window_start=now`）；返回本次是否真的重置了一个窗口。

    与 `quota_window_reset_if_expired` 逐字同形；起点为空时不重置也不开窗口
    （开窗只由首次使用写，见 `quota_window_open`）。
    """
    if window_expired(state.get("window_start", ""), now_iso, window_seconds):
        state["used"] = 0
        state["window_start"] = now_iso
        return True
    return False


def from_complete_backends(backends: list[dict]) -> list[dict]:
    """把 `fist_gateway.parse_complete_backends` 的真源候选形状转成本策略的候选表。

    真源字段（2026-11-25 实测，见 `scripts/fist_gateway.py::parse_complete_backends`）：
    `{id, kind, url, key_env, models}`，其中 `models` 是 `[(选择器名, 上游名), ...]`。
    本函数只做**字段搬运**，不复制解析规则（判例「同一规则多份实现」）——
    缺 id/url 的条目在上游解析处已被丢弃，这里不再做第二份校验。

    `models` 的处置：轮转是 **model 级**的（条目三实测：同一 relay 端点内 607 个模型名里
    有 402 QUOTA / 502 UPSTREAM_DOWN 的差异）。多条 model ⇒ 展开成多个候选，
    id 用 `<id>:<选择器名>`；单条/空 ⇒ 原 id 原样。
    """
    out: list[dict] = []
    for b in backends or ():
        cid = b.get("id") or ""
        if not cid:
            continue
        models = b.get("models") or []
        if not models:
            out.append({"id": cid, "kind": b.get("kind", ""),
                        "endpoint": b.get("url", ""), "model": "",
                        "credential_ref": b.get("key_env", "")})
            continue
        for sel, up in models:
            out.append({"id": "%s:%s" % (cid, sel or up),
                        "kind": b.get("kind", ""),
                        "endpoint": b.get("url", ""), "model": up or sel,
                        "credential_ref": b.get("key_env", "")})
    return out


class CandidatePool:
    """跨协议候选表的确定性轮转（环形扫描 + 过滤 + 记账）。

    候选字段（条目三建议 + 实测补 `limit`/`window_start`/`alive`）：
      id            候选标识（必须非空）
      kind          openai_compatible / mcp_task / cdp（仅供状态面可读，不参与判据）
      endpoint      上游端点（状态面展示用）
      model         该候选上的模型名（relay 内部可用性差异是 model 级，见条目三 §五）
      credential_ref 凭据引用（状态面展示用；缺失判定由调用方或 busy/dead 集合表达）
      used           本地准入辅助计数（**不作计费真源**，裁决 A4）
      limit          额度上限；0 = 未知 ⇒ 不参与耗尽判定
      window_start   窗口起点 ISO；"" = 未开窗
      fail_count     连续失败次数
      cooldown_until 冷却截止 ISO；"" = 无冷却

    `cursor` = **下一次起始扫描位**（即上次被选中者的下一位），持久化由调用方负责
    （参考 `.fist-mbt/data/exec_rota_state.json`）。与 `model_router` 的
    `self.free_idx = (idx + 1) % free.length()` 同形 —— 若存成「被选中者本身」，
    同一候选会被连续选中，「一来一回换一个」就退化成了「一直用同一个」。
    """

    def __init__(self, candidates: list[dict], cursor: int = 0,
                 max_attempts: int = MAX_ATTEMPTS,
                 window_seconds: int = DEFAULT_WINDOW_SECONDS) -> None:
        self.candidates = [c for c in (candidates or []) if c.get("id")]
        self.cursor = cursor or 0
        self.max_attempts = max(1, max_attempts)
        self.window_seconds = window_seconds
        # 最近一次选路的上下文集合（alive/busy/unhealthy）。状态面 `describe()`
        # 必须与真实选路**同源**，否则会出现「说跳过却没跳」的两头空（V7 格）；
        # 未跑过 pick 时为空集。调用方仍可显式传参覆盖。
        self.context_ids: dict[str, set[str]] = {
            "busy": set(), "dead": set(), "unhealthy": set()}
        self.state: dict[str, dict] = {}
        for c in self.candidates:
            self.state[c["id"]] = {
                "id": c["id"],
                "used": int(c.get("used") or 0),
                "limit": int(c.get("limit") or 0),
                "window_start": c.get("window_start") or "",
                "fail_count": int(c.get("fail_count") or 0),
                "cooldown_until": c.get("cooldown_until") or "",
                "last_used": c.get("last_used") or "",
                "last_error": "",
                "skip_reason": "",
                "skip_count": int(c.get("skip_count") or 0),
            }

    # ── 单候选准入（四条硬约束的 Python 侧单一真源）──────────────────────────
    def admitted(self, candidate: dict, now_iso: str,
                 busy_ids: set[str], dead_ids: set[str],
                 unhealthy_ids: set[str]) -> tuple[bool, str]:
        """返回 `(是否准入, 跳过原因)`；原因为空即准入。

        短路顺序：alive(dead) → busy → unhealthy → cooldown → exhausted。
        """
        cid = candidate["id"]
        if cid in dead_ids:
            return False, "not_alive"
        if cid in busy_ids:
            return False, "busy"
        if cid in unhealthy_ids:
            return False, "unhealthy"
        st = self.state[cid]
        # 先做窗口到期重置：耗尽判定必须在重置后读 used，否则上一个窗口的用量会
        # 让候选永久跳过（「窗口到期重置」格的实现点就在这里）。
        window_reset_if_expired(st, now_iso, self.window_seconds)
        # 冷却读 **state**（不是候选字典）—— 运行期冷却由 on_failure 写入 state；
        # 读候选字典会让运行期冷却静默失效（端到端探针实测，见 in_cooldown docstring）。
        if in_cooldown(st["cooldown_until"], now_iso):
            return False, "cooldown"
        if st["limit"] > 0 and st["used"] >= st["limit"]:
            return False, "exhausted"
        return True, ""

    def pick(self, now_iso: str | None = None, busy_ids=None, dead_ids=None,
             unhealthy_ids=None) -> dict | None:
        """环形扫描取下一位可用候选；空池 / 全部不可用 ⇒ `None`（**绝不崩**）。

        `cursor` 推进为「被选中者的下一位」（`(idx+1)%n`），这就是「一来一回换一个」。
        全不可用时**不推进游标**：没有「取下一位」可推，推进只会让日志看起来在动。
        """
        now = now_iso or iso_now()
        busy = set(busy_ids or ())
        dead = set(dead_ids or ())
        unhealthy = set(unhealthy_ids or ())
        self.context_ids = {"busy": set(busy), "dead": set(dead),
                            "unhealthy": set(unhealthy)}
        n = len(self.candidates)
        if n == 0:
            return None
        # BUG-73 同族防线：下标必须随扫描步 `i` 走（`(cursor+i)%n`），
        # 不能把游标本身当固定起点重复测同一格。
        for i in range(n):
            idx = (self.cursor + i) % n
            cand = self.candidates[idx]
            ok, _reason = self.admitted(cand, now, busy, dead, unhealthy)
            if ok:
                self.cursor = (idx + 1) % n
                st = self.state[cand["id"]]
                st["last_used"] = now
                st["skip_reason"] = ""
                return cand
        return None

    def on_success(self, cid: str, now_iso: str | None = None,
                   tokens_in: int = 0, tokens_out: int = 0) -> None:
        """成功记账：清失败计数与冷却，开窗（若未开），`used += 1`。"""
        st = self.state.get(cid)
        if st is None:
            return
        now = now_iso or iso_now()
        st["used"] += 1
        st["fail_count"] = 0
        st["cooldown_until"] = ""
        st["last_error"] = ""
        st["last_used"] = now
        if not st["window_start"]:
            st["window_start"] = now

    def on_failure(self, cid: str, error: str = "", now_iso: str | None = None,
                   cooldown_secs: int = 0) -> dict:
        """失败记账：`fail_count += 1`；连续失败达上限则进冷却（软性，进程重启即归零）。

        返回 `{cooldown_until, exhausted}` 供调用方直接写错误体。
        """
        st = self.state.get(cid)
        if st is None:
            return {"cooldown_until": "", "exhausted": False}
        now = now_iso or iso_now()
        st["fail_count"] += 1
        st["last_error"] = error or ""
        st["last_used"] = now
        until = ""
        if cooldown_secs > 0:
            epoch = iso_to_epoch(now)
            if epoch > 0:
                until = time.strftime(
                    "%Y-%m-%dT%H:%M:%SZ",
                    time.gmtime(epoch + cooldown_secs))
                st["cooldown_until"] = until
        return {"cooldown_until": until, "exhausted": st["fail_count"] >= self.max_attempts}

    def skipped(self, now_iso: str | None = None, busy_ids=None, dead_ids=None,
                unhealthy_ids=None) -> list[dict]:
        """当前**会被跳过**的候选与原因（状态面用；实时判定，不依赖上一次调用）。

        三个集合省略时取**最近一次 `pick` 的上下文**（`context_ids`）——
        状态面与真实选路因此同源；不传就会退化成「只看冷却/耗尽」。
        """
        now = now_iso or iso_now()
        ctx = self.context_ids or {}
        out = []
        for c in self.candidates:
            ok, reason = self.admitted(c, now, set(busy_ids) if busy_ids is not None else set(ctx.get("busy") or ()),
                                       set(dead_ids) if dead_ids is not None else set(ctx.get("dead") or ()),
                                       set(unhealthy_ids) if unhealthy_ids is not None else set(ctx.get("unhealthy") or ()))
            if not ok:
                out.append({"candidate": c["id"], "reason": reason,
                            "kind": c.get("kind", ""),
                            "model": c.get("model", "")})
        return out

    def describe(self) -> dict:
        """状态面：当前游标 + 各候选成败/冷却/跳过原因（对齐 `model_router_status` 形态）。"""
        cands = []
        for c in self.candidates:
            st = dict(self.state[c["id"]])
            st["kind"] = c.get("kind", "")
            st["endpoint"] = c.get("endpoint", "")
            st["model"] = c.get("model", "")
            cands.append(st)
        return {
            "cursor": self.cursor,
            "max_attempts": self.max_attempts,
            "window_seconds": self.window_seconds,
            "stamped_at": iso_now(),
            "candidates": cands,
            "skipped": self.skipped(),
        }


# ══════════════════════════════════════════════════════════════════
# 自检（内嵌 · 判据自带）：验收五格 + 反向对照 + 变异对照
# ══════════════════════════════════════════════════════════════════

_SELFTEST_NOW = "2026-11-25T12:00:00Z"
_SELFTEST_OLD = "2026-11-25T00:00:00Z"


def _self_cand(cid, **kw):
    """造一个候选字典（字段口径见 `CandidatePool` docstring）。"""
    base = {"id": cid, "kind": "openai_compatible", "endpoint": "",
            "model": "", "credential_ref": "", "used": 0, "limit": 0,
            "window_start": "", "fail_count": 0, "cooldown_until": "",
            "last_used": "", "skip_count": 0}
    base.update(kw)
    return base


def _self_run_once(pool, attempt_fn, now=None):
    """模拟一次完整轮转周期：取候选 → 尝试 → 成功记账 / 失败顺延。

    「上限 3」是**循环界**（`pool.max_attempts`），不是池长：池里只有 1 个候选时
    也不会原地打转到天荒地老（裁决 A3：超过上限回明确错误体）。
    """
    now = now or iso_now()
    picked = []
    for _ in range(pool.max_attempts):
        c = pool.pick(now_iso=now)
        if c is None:
            break
        picked.append(c["id"])
        ok, note = attempt_fn(c)
        if ok:
            pool.on_success(c["id"], now)
            return {"ok": True, "candidate": c["id"], "attempts": picked}
        pool.on_failure(c["id"], note, now)
    return {"ok": False, "error": "所有候选均未返回正文", "attempts": picked}


_SELFTEST_MARKER = "# ══════════════════════════════════════════════════════════════════\n# 自检（内嵌 · 判据自带）"

def _selftest_cells(mod):
    """返回 [(名字, 是否通过, 说明)]；全部在内存里跑（被测对象无 IO）。"""
    out = []

    def ck(name, cond, detail):
        out.append((name, bool(cond), detail))

    # ── ① 跳过 busy ────────────────────────────────────────────────────────────
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW, busy_ids={"A"})
    ck("V1-skip-busy", got is not None and got["id"] == "B",
       "A 忙 ⇒ 必须跳过并选到 B")
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V1b-no-busy-normal-order", got is not None and got["id"] == "A",
       "无忙候选 ⇒ 按游标取 A（反向对照）")

    # ── ② 跳过 cooldown ───────────────────────────────────────────────────────
    p = mod.CandidatePool(
        [_self_cand("A", cooldown_until="2026-11-25T13:00:00Z"), _self_cand("B")],
        cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V2-skip-cooldown", got is not None and got["id"] == "B",
       "A 冷却至 13:00Z、现在 12:00Z ⇒ 必须跳过")
    p = mod.CandidatePool([_self_cand("A", cooldown_until=_SELFTEST_NOW)], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V2b-cooldown-boundary-exact-free", got is not None and got["id"] == "A",
       "冷却截止 == now ⇒ 不再算冷却（边界同 `ModelQuota::in_cooldown`）")
    p = mod.CandidatePool([_self_cand("A", cooldown_until="not-a-time")], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V2c-cooldown-invalid-fail-open", got is not None and got["id"] == "A",
       "非法冷却时间戳 ⇒ 视为无冷却（fail-open，BUG-584 同族口径）")

    # ── ③ 空池安全返回 ────────────────────────────────────────────────────────
    p = mod.CandidatePool([], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V3-empty-pool-returns-none", got is None,
       "空候选池 ⇒ 返回 None、**不抛异常**（`% len([])` 型崩溃是 T0r121 已治形状）")
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=1)
    before = p.cursor
    got = p.pick(now_iso=_SELFTEST_NOW, busy_ids={"A", "B"})
    ck("V3b-all-unavailable-returns-none", got is None and p.cursor == before,
       "全不可用 ⇒ None 且游标不动（没有「下一位」可推）")

    # ── ④ 失败顺延（上限 3）───────────────────────────────────────────────────
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    r = _self_run_once(p, lambda c: (False, "HTTP 402") if c["id"] == "A" else (True, ""))
    ck("V4a-failover-to-next", r.get("ok") and r["candidate"] == "B",
       "A 失败 ⇒ 顺延 B 并记成功（一来一回换一个的真义）")
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0, max_attempts=3)
    r = _self_run_once(p, lambda c: (False, "HTTP 402"))
    ck("V4b-attempts-capped-at-3",
       r["ok"] is False and len(r["attempts"]) <= 3 and "所有候选" in r["error"],
       "全部失败 ⇒ attempts ≤ 3 且回明确错误（裁决 A3：不无限轮转）")
    p = mod.CandidatePool([_self_cand("A")], cursor=0, max_attempts=3)
    r1 = p.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=300)
    r2 = p.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=300)
    r3 = p.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=300)
    ck("V4c-fail-count-and-cooldown",
       r1["exhausted"] is False and r2["exhausted"] is False and r3["exhausted"] is True
       and r3["cooldown_until"] != "",
       "连续失败第 3 次 ⇒ exhausted=True 且写下冷却截止")
    p = mod.CandidatePool([_self_cand("A")], cursor=0)
    p.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=300)
    p.on_success("A", _SELFTEST_NOW)
    ck("V4d-success-clears-failure-state",
       p.state["A"]["fail_count"] == 0 and p.state["A"]["cooldown_until"] == ""
       and p.state["A"]["used"] == 1,
       "成功 ⇒ 清失败计数与冷却并开窗计一次用量")
    # 运行期冷却必须对选路生效（端到端探针实测踩到的真缺陷：on_failure 只写 state，
    # 若 admitted 从原始候选字典读冷却 ⇒ 冷却静默失效，退化成原地打转）。
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    p.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=3600)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V4e-runtime-cooldown-blocks-repick",
       got is not None and got["id"] == "B" and p.state["A"]["cooldown_until"] != "",
       "A 已有运行期冷却 ⇒ 本轮跳过 A 选到 B（冷却对选路真的生效）")
    p2 = mod.CandidatePool([_self_cand("A")], cursor=0)
    p2.on_failure("A", "HTTP 402", _SELFTEST_NOW, cooldown_secs=3600)
    ck("V4f-state-cooldown-read-by-admitted",
       mod.in_cooldown(p2.state["A"]["cooldown_until"], _SELFTEST_NOW) is True
       and p2.pick(now_iso=_SELFTEST_NOW) is None,
       "state 里的冷却串被 admitted 读到 ⇒ 该候选当前不可选")

    # ── ⑤ 窗口到期重置 ────────────────────────────────────────────────────────
    p = mod.CandidatePool([_self_cand("A", used=2, limit=2, window_start=_SELFTEST_OLD)],
                          cursor=0, window_seconds=18000)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V5a-window-expired-resets-quota",
       got is not None and got["id"] == "A" and p.state["A"]["used"] == 0,
       "窗口满 5h ⇒ used 清零、候选恢复可用（否则耗尽候选永久跳过）")
    p = mod.CandidatePool([_self_cand("A", used=2, limit=2, window_start=_SELFTEST_NOW)],
                          cursor=0, window_seconds=18000)
    got = p.pick(now_iso=_SELFTEST_NOW)
    ck("V5b-window-not-expired-keeps-used", got is None and p.state["A"]["used"] == 2,
       "窗口刚开 ⇒ used 保留、耗尽候选继续被跳过（反向对照）")
    exp = mod.window_expired("2026-11-25T07:00:00Z", "2026-11-25T12:00:00Z", 18000)
    notexp = mod.window_expired("2026-11-25T07:00:01Z", "2026-11-25T12:00:00Z", 18000)
    ck("V5c-window-boundary-ge", exp is True and notexp is False,
       "恰满 5h ⇒ 到期；差 1s ⇒ 未到期（`>=` 边界，与 rt_6 锁一致）")
    ck("V5d-window-invalid-does-not-reset",
       mod.window_expired("", _SELFTEST_NOW, 18000) is False
       and mod.window_expired("not-a-time", _SELFTEST_NOW, 18000) is False
       and mod.window_expired(_SELFTEST_OLD, "not-a-time", 18000) is False,
       "起点空 / 任一非法 ⇒ 一律不重置（绝不用坏时间戳清零用量）")

    # ── ⑥ 轮转真的换人（「一来一回换一个」的本体）────────────────────────────
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    seq = []
    for _ in range(4):
        c = p.pick(now_iso=_SELFTEST_NOW)
        if c is None:
            seq.append(None)
            continue
        seq.append(c["id"])
        p.on_success(c["id"], _SELFTEST_NOW)
    ck("V6-alternates-between-candidates", seq == ["A", "B", "A", "B"],
       "连续四次 ⇒ A/B/A/B（游标存成「被选中者本身」会退化成 A/A/A/A）")

    # ── ⑦ 状态面对表（describe 与实际选路同源，不许「说跳过却没跳」）──────────
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B")], cursor=0)
    p.pick(now_iso=_SELFTEST_NOW, busy_ids={"B"})
    reasons = {e["candidate"]: e["reason"] for e in p.describe()["skipped"]}
    ck("V7-describe-matches-selection",
       reasons.get("B") == "busy" and "A" not in reasons,
       "describe 的 skipped 与 pick 的实际跳过原因对表")

    # ── ⑧ 环形扫描真的扫（BUG-73 同族：下标必须随 i 走）──────────────────────
    p = mod.CandidatePool([_self_cand("A"), _self_cand("B"), _self_cand("C")], cursor=0)
    got = p.pick(now_iso=_SELFTEST_NOW, busy_ids={"A"}, dead_ids={"B"})
    ck("V8-scan-crosses-skipped", got is not None and got["id"] == "C",
       "游标位 A 忙、B 死 ⇒ 必须扫到 C（固定起点重复测同一格永远选不到）")

    # ── ⑨ 真源形状接线（parse_complete_backends 字段搬运）────────────────────
    # 只验本模块的适配器（不 import 他方在飞文件）：真源字段 = {id,kind,url,key_env,models}。
    parsed = [{"id": "ofm-relay", "kind": "openai_compatible",
               "url": "http://127.0.0.1:18326/v1/chat/completions",
               "key_env": "FIST_OFM_KEY",
               "models": [("our-free-model/free", "our-free-model/free"),
                          ("trae/glm-5.3-flash", "glm-5.3-flash")]}]
    ck("V9a-real-shape-expands-to-model-level",
       [c["id"] for c in mod.from_complete_backends(parsed)]
       == ["ofm-relay:our-free-model/free", "ofm-relay:trae/glm-5.3-flash"],
       "同一端点的多条 model 展开为多个候选（条目三：可用性差异是 model 级）")
    ck("V9b-real-shape-single-and-empty-models",
       mod.from_complete_backends([{"id": "x", "url": "u", "models": []}])[0]["id"] == "x"
       and mod.from_complete_backends([{"id": "", "url": "u"}]) == [],
       "无 model ⇒ 原 id 原样；缺 id ⇒ 丢弃（不做第二份解析校验）")
    return out


# ══════════════════════════════════════════════════════════════════
# 变异对照（判例-29/30）：把代码改坏 ⇒ 点名格子必须转红
# ══════════════════════════════════════════════════════════════════

_MUTATIONS = (
    ("M1-scan-index-fixed-start",
     "            idx = (self.cursor + i) % n",
     "            idx = self.cursor % n",
     {"V8-scan-crosses-skipped", "V6-alternates-between-candidates"}),
    ("M2-window-boundary-strict-gt",
     "    return (now - start) >= window_seconds",
     "    return (now - start) > window_seconds",
     {"V5c-window-boundary-ge", "V5a-window-expired-resets-quota"}),
    ("M3-busy-filter-disabled",
     '        if cid in busy_ids:\n            return False, "busy"',
     '        if False:\n            return False, "busy"',
     {"V1-skip-busy", "V1b-no-busy-normal-order"}),
    # M4 = 端到端探针实测到的缺陷形状：冷却改回读原始候选字典 ⇒ 运行期冷却静默失效。
    ("M4-cooldown-reads-candidate-dict",
     '        if in_cooldown(st["cooldown_until"], now_iso):',
     '        if in_cooldown(candidate.get("cooldown_until") or "", now_iso):',
     {"V4e-runtime-cooldown-blocks-repick", "V4f-state-cooldown-read-by-admitted"}),
)


def _exec_variant(src_text, old, new, target):
    """把源码副本改坏后 exec 成新模块对象（**不改盘上的真文件**）。

    判例-30 的自指陷阱：变异锚文本本身写在 `_MUTATIONS` 表里 ⇒ 直接在全源码里数
    会出现 2 次（实现处 + 表项处），于是「唯一性」断言恒不成立。因此**只在自检段
    之前**的实现区里数与替换——`_MUTATIONS` 表不是被测实现，混进来就是拿注释当代码。
    """
    head, sep, tail = src_text.partition(_SELFTEST_MARKER)
    assert sep, "找不到自检段分界标记（判据无法自证）"
    assert old in head, "变异点不在实现区里（判例-30：不许只改注释/找不到锚点）"
    assert head.count(old) == 1, \
        "变异锚点在实现区出现 %d 次（必须唯一）" % head.count(old)
    code = head.replace(old, new, 1) + sep + tail
    assert code != src_text, "变异没落到代码行"
    ns = {"__name__": "laya_rota_variant", "__file__": target}
    exec(compile(code, "<laya-rota-variant>", "exec"), ns)   # noqa: S102 - 自造夹具
    mod = type(os)("laya_rota_variant")
    mod.__dict__.update(ns)
    return mod


def _run_cells(mod):
    res = {}
    for name, ok, _detail in _selftest_cells(mod):
        res[name] = ok
    return res


def selftest():
    """真模块全绿 + 变异对照全生效。rc 0/1/2。"""
    target = os.path.abspath(__file__)
    with open(target, encoding="utf-8") as f:
        src = f.read()
    real = _run_cells(sys.modules[__name__])
    bad = [k for k, v in real.items() if not v]
    print("=== 真模块 ===")
    for name, ok, detail in _selftest_cells(sys.modules[__name__]):
        print(("  OK   " if ok else "  FAIL ") + name + " — " + detail)
    if bad:
        print("SELFTEST FAIL 真模块就有 %d 格未过：%s" % (len(bad), ", ".join(bad)))
        return 1
    mut_bad = []
    print("\n=== 变异对照 ===")
    for name, old, new, expect_red in _MUTATIONS:
        try:
            vmod = _exec_variant(src, old, new, target)
        except AssertionError as e:
            mut_bad.append("%s（夹具不成立：%s）" % (name, e))
            print("  FAIL %s — 变异夹具不成立：%s" % (name, e))
            continue
        got = _run_cells(vmod)
        hit = sorted(c for c in expect_red if not got.get(c, False))
        if hit:
            print("  OK   %s — 变异后 %s 变红（锁真在看）" % (name, ", ".join(hit)))
        else:
            mut_bad.append("%s（变异后点名格仍全绿 ⇒ 锁没在看）" % name)
            print("  FAIL %s — 变异后点名格仍全绿（期望红：%s）"
                  % (name, ", ".join(sorted(expect_red))))
    if mut_bad:
        print("SELFTEST FAIL 变异对照 %d/%d 未过：%s"
              % (len(mut_bad), len(_MUTATIONS), "; ".join(mut_bad)))
        return 1
    print("\nSELFTEST PASS（真模块 %d 格全绿 + 变异对照 %d/%d 生效）"
          % (len(real), len(_MUTATIONS), len(_MUTATIONS)))
    return 0


def main(argv=None):
    """CLI：`--selftest` 之外一律拒绝（R207：拼错旗标不得静默落进真分支）。"""
    argv = list(sys.argv[1:] if argv is None else argv)
    known = {"--selftest"}
    unknown = [a for a in argv if a.startswith("-") and a not in known]
    if unknown:
        print("FATAL 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(known)))
        return 2
    if argv and argv != ["--selftest"]:
        print("FATAL 未知参数 %s —— 本尺只接受 --selftest（rc=2）" % " ".join(argv))
        return 2
    if "--selftest" in argv:
        return selftest()
    print("用法：python scripts/_laya_rota.py [--selftest]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
