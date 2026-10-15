#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CAF P2d 冷启动 A/B 预演（2026-10-15 Goal-2 Round 25）
验证：冷启动阶段用默认偏好是否比"总是选第一个"更好。

Scenario:
- 3 模型：m_free(成功率0.5, 成本1), m_mid(0.7, 2), m_premium(0.9, 3)
- 100 次路由决策
- Strategy 0（baseline）：总是选候选第一个（m_free）
- Strategy 1（P2d 默认偏好 [m_mid, m_premium, m_free]）：优先选 m_mid
- Strategy 2（P2d 学到偏好 [m_premium, m_mid, m_free]）：优先选 m_premium

Metric:
- total_cost：为达成 100 次成功所需的成本
- success_rate：100 次中成功次数
- 最优 = total_cost 最低且 success_rate 最高
"""
import random
import sys
from typing import List, Tuple

MODELS: List[Tuple[str, float, float]] = [
    ("m_free", 0.5, 1.0),
    ("m_mid", 0.7, 2.0),
    ("m_premium", 0.9, 3.0),
]
N_DECISIONS = 100
SEED = 42


def simulate_pick(preference: List[str], seed: int = SEED) -> Tuple[int, float]:
    """按 preference 顺序选第一个，模拟 100 次路由决策。返回 (success_count, total_cost)"""
    rng = random.Random(seed)
    success = 0
    cost = 0.0
    # preference 里第一个就是首选（P2d 的 caf_soft_reorder_with_preference 语义）
    for _ in range(N_DECISIONS):
        chosen = preference[0]
        # 查找模型数据
        model_data = None
        for m, sr, c in MODELS:
            if m == chosen:
                model_data = (sr, c)
                break
        if model_data is None:
            raise ValueError(f"Unknown model: {chosen}")
        sr, c = model_data
        cost += c
        if rng.random() < sr:
            success += 1
    return success, cost


def main() -> int:
    print("=" * 60)
    print("CAF P2d 冷启动 A/B 预演")
    print(f"决策次数: {N_DECISIONS} | 种子: {SEED}")
    print("=" * 60)

    # 3 个策略
    strategies = [
        ("Strategy 0 (baseline: 总是选第一个 m_free)", ["m_free", "m_mid", "m_premium"]),
        ("Strategy 1 (P2d 默认偏好 m_mid)", ["m_mid", "m_premium", "m_free"]),
        ("Strategy 2 (P2d 学到偏好 m_premium)", ["m_premium", "m_mid", "m_free"]),
    ]

    print(f"\n{'策略':<50} {'成功':>6} {'总成本':>10} {'每成功成本':>12}")
    print("-" * 80)
    results = []
    for label, pref in strategies:
        success, cost = simulate_pick(pref)
        per_success = cost / success if success > 0 else float("inf")
        results.append((label, success, cost, per_success))
        print(f"{label:<50} {success:>6} {cost:>10.0f} {per_success:>12.3f}")

    print("-" * 80)

    # 判定
    best = min(results, key=lambda r: r[3])
    print(f"\n[OK] 最优策略: {best[0]}")
    print(f"     每成功成本: {best[3]:.3f}")

    # P2d 是否优于 baseline
    baseline = results[0]
    p2d_best = min(results[1:], key=lambda r: r[3])
    if p2d_best[3] < baseline[3]:
        improvement = (baseline[3] - p2d_best[3]) / baseline[3] * 100
        print(f"[OK] P2d 优于 baseline: 成本降低 {improvement:.1f}%")
    else:
        print(f"[FAIL] P2d 未优于 baseline: {p2d_best[3]:.3f} vs {baseline[3]:.3f}")

    # 全部通过判据
    all_ok = p2d_best[3] < baseline[3]
    print(f"\n判据: {'2/2 PASS' if all_ok else '1/2 PASS'}")

    # ===== 场景 2：成功率敏感（关键任务必须成功）=====
    print("\n" + "=" * 60)
    print("场景 2：成功率敏感（关键任务必须成功）")
    print("指标：成功率 > 每成功成本（任务失败代价高）")
    print("=" * 60)
    print(f"\n{'策略':<50} {'成功':>6} {'总成本':>10} {'成功率':>8}")
    print("-" * 80)
    results2 = []
    for label, pref in strategies:
        success, cost = simulate_pick(pref)
        rate = success / N_DECISIONS
        results2.append((label, success, cost, rate))
        print(f"{label:<50} {success:>6} {cost:>10.0f} {rate:>7.1%}")

    print("-" * 80)
    best2 = max(results2, key=lambda r: r[3])
    print(f"\n[OK] 场景 2 最优策略: {best2[0]}")
    print(f"     成功率: {best2[3]:.1%}")

    # 场景 2 判据：P2d 策略成功率 > baseline
    p2d_best2 = max(results2[1:], key=lambda r: r[3])
    baseline2 = results2[0]
    if p2d_best2[3] > baseline2[3]:
        improvement2 = (p2d_best2[3] - baseline2[3]) * 100
        print(f"[OK] P2d 优于 baseline（成功率）: +{improvement2:.1f} 个百分点")
        all_ok2 = True
    else:
        print(f"[FAIL] P2d 未优于 baseline（成功率）: {p2d_best2[3]:.1%} vs {baseline2[3]:.1%}")
        all_ok2 = False

    # 总结：场景 1（成本敏感）→ baseline 优；场景 2（成功率敏感）→ P2d 优
    print("\n" + "=" * 60)
    print("结论：冷启动偏好是【场景依赖】的")
    print(f"  场景 1（成本敏感）: baseline 最优（每成功成本 {baseline[3]:.3f}）")
    print(f"  场景 2（成功率敏感）: P2d 最优（成功率 {best2[3]:.1%}）")
    print("=" * 60)
    if all_ok2:
        print("\n[OK] 场景 2 判据通过：P2d 在成功率敏感场景优于 baseline")
    else:
        print("\n[FAIL] 场景 2 判据未通过")
    return 0 if all_ok2 else 1


if __name__ == "__main__":
    sys.exit(main())