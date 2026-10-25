# `render_dsh_patch.py` 单摘增量（从 `fix/render-release-priority-master` 保全）

> **来源分支**：`origin/fix/render-release-priority-master`
> **单摘原因**：该分支是**真基线倒退**（删了 main 有的 `sync-from-gitcode.simulate.sh`
> + 把判例-9 修复整条退回旧写法），**绝不能整支合**（判例-1）。
> 但它自己有一个真增量：`scripts/render_dsh_patch.py`。**只摘这一份。**
> **单摘时间**：2026-10-25 · 司令-γ

---

## 1. 单摘命令

```bash
git diff main...origin/fix/render-release-priority-master -- scripts/render_dsh_patch.py \
  > reports/salvage-2026-10-25/render-dsh-patch-increment.diff
```

- **保存路径**：`reports/salvage-2026-10-25/render-dsh-patch-increment.diff`（**跟踪面**，判例-55）
- **行数**：75 行（`35 insertions / 16 deletions`）
- **范围**：**只含 `scripts/render_dsh_patch.py` 一个文件**，不含被倒退的 sync 文件

---

## 2. ⚠️ 这份增量的方向需要复核（重要）

**分支把 main 的「按 mtime 取新」退回了「release 优先硬编码」。**

| 位置 | main（现在） | 分支 |
|---|---|---|
| `known = []` | 有 | **无** |
| `st_mtime` 比较 | 有（`known.append((p.stat().st_mtime, p, rel))` + `max(…, key=st_mtime)`） | 仍出现 6 次但用法不同 |
| 选择策略 | **两形态并存时按 mtime 取新** | **release 优先、debug 兜底（硬编码顺序）** |

**main 的注释明确记录了为什么要按 mtime**：
```
# debug 与 release 是两个独立构建目录，谁新谁旧取决于最近一次 `moon build`
# 用什么 flag；硬编码 debug 优先会在「release 已重建、debug 还是旧件」时把渲染件
# 指回旧产物（2026-10-24 实测：release 10:19 最新、debug 07:42 旧，渲染器仍选 debug）
# ⇒ 两形态并存时按 mtime 取新，与下方 glob 兜底同一律。
```

**⇒ 分支的做法有它的理由**（「DSH 插件安装面面对最终用户，装的是正式发布态」），
**但它等于把一个「已实测踩过坑」的策略换回来。**

**结论：这份增量不是无脑可合的。** 若要采用，必须先回答：
- **mtime 那个坑还在吗？**（release 新、debug 旧时渲染件指回旧产物 —— 2026-10-24 实测过）
- 若还在，就得**两者结合**：release 优先**且**在同一形态内按 mtime 取新（而非全局 release 优先）。

---

## 3. 使用方式

```bash
git apply --check reports/salvage-2026-10-25/render-dsh-patch-increment.diff   # 先验可应用
git apply reports/salvage-2026-10-25/render-dsh-patch-increment.diff           # 再应用
```

**应用后必须跑**：`python scripts/render_dsh_patch.py --selftest`（若有）。
**并按上节复核 mtime 策略。**

---

## 4. 来源

- 分支：`origin/fix/render-release-priority-master`
- 倒退详情：`reports/2026-10-25-render-release-priority-regression.md`
- 判例：1（基线倒退只取增量）· 9（静默失败守卫抓住倒退）· 55（保全必须落跟踪面）
