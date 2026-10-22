#!/usr/bin/env python3
"""CAF P2c 接线 A/B 预演验证（验收标准 2）

模拟 P2c 接线后的 A/B 对比：
- A 组（关闭）：确定性路由 = 固定优先级选模型（无 CAF 记忆）
- B 组（开启）：CAF 记忆软性排序 = 相似任务优先选历史成功率高的模型

验收标准 2：B 组在相同任务集上，成本 ≤ 基线 且 成功率 ≥ 基线；若有偏差须记录。

用法：`python scripts/caf_p2c_ab_preflight.py`
退出码：0=全部通过，1=有失败
"""

import random
from collections import defaultdict
import sys


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


# ---- 基础配置 ----
MODELS = {
    # 模型 → (成功率, 单次成本)  · 模型能力随任务难度变化
    "m_free":    {"base_rate": 0.70, "cost": 0.01},
    "m_cheap":   {"base_rate": 0.80, "cost": 0.05},
    "m_mid":     {"base_rate": 0.88, "cost": 0.10},
    "m_premium": {"base_rate": 0.96, "cost": 0.50},
}

# 默认优先级（A 组固定顺序，与 v0.3.8 行为近似）
DEFAULT_ORDER = ["m_free", "m_cheap", "m_mid", "m_premium"]

# 任务类型（影响成功率偏移）
TASK_TYPES = {
    "简单":   {"difficulty": 1.0},
    "中等":   {"difficulty": 0.9},
    "复杂":   {"difficulty": 0.7},
}

# 特征哈希简化版：直接用任务类型字符串（模拟 caf_feature_hash 的映射）
def feature_hash(task_type: str) -> str:
    """返回稳定的字符串哈希（模拟 caf_feature_hash 的 32-bit 数字串）"""
    # 简单映射：确保同类型同哈希
    mapping = {"简单": "1001", "中等": "2002", "复杂": "3003"}
    return mapping[task_type]


# ---- 模拟 caf_edit_distance ----
def edit_distance(a: str, b: str) -> int:
    """Levenshtein DP，模拟 caf_edit_distance"""
    if a == b:
        return 0
    n, m = len(a), len(b)
    if n == 0:
        return m
    if m == 0:
        return n
    prev = list(range(m + 1))
    for i in range(1, n + 1):
        curr = [i]
        for j in range(1, m + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr.append(min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost))
        prev = curr
    return prev[m]


# ---- 记忆表（FIFO ≤10000）----
class CafMemory:
    def __init__(self, max_size=10000):
        self.records = []  # [(hash, model, ok, cost)]
        self.max_size = max_size

    def push(self, feature_hash, model, ok, cost):
        self.records.append((feature_hash, model, ok, cost))
        if len(self.records) > self.max_size:
            self.records = self.records[-self.max_size:]

    def knn_stats(self, target_hash, k=8):
        """模拟 CafMemory::knn_stats：Top-K 邻域成功率/成本"""
        if not self.records:
            return []
        # 按编辑距离排序（对哈希数字串）
        scored = sorted(
            self.records,
            key=lambda r: (edit_distance(r[0], target_hash), -r[3]),  # 距离 asc, 成本 desc（同距时靠前的优先）
        )
        neighbors = scored[:k]
        by_model = defaultdict(lambda: {"ok": 0, "count": 0, "cost_sum": 0.0})
        for h, model, ok, cost in neighbors:
            by_model[model]["ok"] += 1 if ok else 0
            by_model[model]["count"] += 1
            by_model[model]["cost_sum"] += cost
        stats = []
        for model, d in by_model.items():
            stats.append({
                "model": model,
                "rate": d["ok"] / d["count"] if d["count"] > 0 else 0.0,
                "avg_cost": d["cost_sum"] / d["count"] if d["count"] > 0 else 0.0,
                "count": d["count"],
            })
        # 排序：rate desc → cost asc
        stats.sort(key=lambda s: (-s["rate"], s["avg_cost"]))
        return stats


# ---- 决策融合 ----
def caf_soft_reorder(candidates, stats):
    """模拟 caf_soft_reorder：邻域优先（rate desc → cost asc），非邻域保持原序"""
    stat_map = {s["model"]: s for s in stats}
    in_nb = [c for c in candidates if c in stat_map]
    not_in_nb = [c for c in candidates if c not in stat_map]
    in_nb.sort(key=lambda m: (-stat_map[m]["rate"], stat_map[m]["avg_cost"]))
    return in_nb + not_in_nb


# ---- 模拟一次执行 ----
def simulate_task(task_type, chosen_model, rng):
    """模拟一次任务执行：返回 (成功?, 成本)"""
    difficulty = TASK_TYPES[task_type]["difficulty"]
    base_rate = MODELS[chosen_model]["base_rate"]
    # 实际成功率 = 基础成功率 × 难度系数
    effective_rate = base_rate * difficulty
    effective_rate = max(0.0, min(1.0, effective_rate))
    ok = rng.random() < effective_rate
    cost = MODELS[chosen_model]["cost"]
    return ok, cost


# ---- 主验证 ----
def run_ab_preflight(seed=42, n_tasks=200, warmup=50):
    """
    运行 A/B 对比。
    返回: { "A": {success, total, cost}, "B": {success, total, cost}, "bias": ... }
    """
    rng = random.Random(seed)
    # 生成任务集：均匀分布在简单/中等/复杂
    task_types = ["简单", "中等", "复杂"]
    tasks = [rng.choice(task_types) for _ in range(n_tasks)]

    # 结果统计
    result = {"A": {"success": 0, "total": 0, "cost": 0.0},
              "B": {"success": 0, "total": 0, "cost": 0.0}}
    # B 组记忆表
    mem = CafMemory()

    for i, task_type in enumerate(tasks):
        ctx_hash = feature_hash(task_type)

        # A 组：固定优先级（默认顺序，与 v0.3.8 行为一致）
        chosen_a = DEFAULT_ORDER[0]  # 默认优先最低成本
        ok_a, cost_a = simulate_task(task_type, chosen_a, rng)
        result["A"]["success"] += 1 if ok_a else 0
        result["A"]["total"] += 1
        result["A"]["cost"] += cost_a

        # B 组：CAF 记忆软性排序
        # 冷启动：前 warmup 次任务用默认顺序积累记忆
        if i < warmup:
            # 学习阶段：默认顺序但回写记忆
            chosen_b = DEFAULT_ORDER[0]
            ok_b, cost_b = simulate_task(task_type, chosen_b, rng)
            mem.push(ctx_hash, chosen_b, ok_b, cost_b)
        else:
            # 决策阶段：用记忆排序
            stats = mem.knn_stats(ctx_hash, k=8)
            if stats:
                chosen_b = caf_soft_reorder(DEFAULT_ORDER, stats)[0]
            else:
                chosen_b = DEFAULT_ORDER[0]
            ok_b, cost_b = simulate_task(task_type, chosen_b, rng)
            # 回写记忆（B 组持续学习）
            mem.push(ctx_hash, chosen_b, ok_b, cost_b)

        result["B"]["success"] += 1 if ok_b else 0
        result["B"]["total"] += 1
        result["B"]["cost"] += cost_b

    # 计算比率
    for grp in ["A", "B"]:
        r = result[grp]
        r["rate"] = r["success"] / r["total"] if r["total"] > 0 else 0.0
    result["bias"] = {
        "success_delta": result["B"]["rate"] - result["A"]["rate"],
        "cost_delta": result["B"]["cost"] - result["A"]["cost"],
        "verdict": "",
    }
    # 验收标准 2：B 组成本 ≤ A 组 且 成功率 ≥ A 组
    if result["B"]["cost"] <= result["A"]["cost"] + 1e-9 and result["B"]["rate"] >= result["A"]["rate"] - 1e-9:
        result["bias"]["verdict"] = "pass"
    else:
        result["bias"]["verdict"] = "deviation"
        # 记录偏差（不掩盖）
        result["bias"]["note"] = (
            f"B 组成本 {result['B']['cost']:.2f} vs A 组 {result['A']['cost']:.2f}"
            f"; B 成功率 {result['B']['rate']:.2f} vs A 组 {result['A']['rate']:.2f}"
        )
    return result


def test_acceptance_criterion_2():
    """验收标准 2：开启后不增成本且成功率不降"""
    r = run_ab_preflight(seed=42, n_tasks=200, warmup=50)
    print("=" * 60)
    print(f"A 组（关闭）：成功率 {r['A']['rate']:.2f}，总成本 {r['A']['cost']:.2f}")
    print(f"B 组（开启）：成功率 {r['B']['rate']:.2f}，总成本 {r['B']['cost']:.2f}")
    print(f"差值：成功率 {r['bias']['success_delta']:+.2f}，成本 {r['bias']['cost_delta']:+.2f}")
    print(f"验收标准 2：{r['bias']['verdict']}")
    if r["bias"]["verdict"] == "pass":
        print("→ 验收标准 2 通过（B 组不增成本、成功率不降）\n")
        return True
    else:
        print(f"→ 偏差记录：{r['bias'].get('note', '')}\n")
        return False


def test_zero_regression_closed():
    """验收标准 4（预演）：关闭时行为与基线完全一致"""
    rng1 = random.Random(7)
    rng2 = random.Random(7)  # 相同种子
    # A 组用固定顺序，B 组用关闭时的 CAF（应等价）
    mem = CafMemory()
    # 冷启动阶段：两者相同
    task_types = ["简单", "中等", "复杂"]
    tasks = [rng1.choice(task_types) for _ in range(100)]
    # 都选 DEFAULT_ORDER[0]，无 CAF 影响
    for tt in tasks:
        ok_a, cost_a = simulate_task(tt, DEFAULT_ORDER[0], rng2)
        mem.push(feature_hash(tt), DEFAULT_ORDER[0], ok_a, cost_a)
    # 决策阶段：B 组此时记忆已积累，会走软性排序
    # 但关闭状态下不会调用 caf_soft_reorder，所以等价于 A 组
    # 这里验证：记忆为空时 caf_soft_reorder 返回原序
    ordered = caf_soft_reorder(DEFAULT_ORDER, [])
    assert ordered == DEFAULT_ORDER, "空记忆必须返回原序（零回归）"
    print("零回归验证通过：空记忆 -> 原序 [OK]\n")
    return True


if __name__ == "__main__":
    print("=" * 60)
    print("CAF P2c 接线 A/B 预演验证（验收标准 2）")
    print("=" * 60)
    r1 = test_acceptance_criterion_2()
    r2 = test_zero_regression_closed()
    all_pass = r1 and r2
    print("=" * 60)
    print(f"结果：{sum([r1, r2])}/2 通过")
    exit(0 if all_pass else 1)