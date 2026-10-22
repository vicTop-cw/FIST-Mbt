# 2026-10-20 汇报 —— `slave/fix/core-package-imports`（0071 core_package_not_imported 剩族清零）

## 结果摘要
- `moon check --target js --json`：**1895 warnings / 0 errors**（上一单 1899 → 本单 1895）；`error_code=71` 命中 16 条族里的最后 4 条 → **0**，`error_code=29` 保持 **0**。
- 零回归：`moon test --target js -j 1` → `Total tests: 1302, passed: 1302, failed: 0`。
- 改动面：`cmd/cli/moon.pkg`、`src/store/moon.pkg` 各 +1 条 `"moonbitlang/core/json"`；`.mbt` 源码一行未动。入账 **BUG-343**（medium，FIXED，R19）。
- 累计（本机可测面）：warning 1920 → 1895（−25），unused_package 与 core_package_not_imported 两族同时归零。

## 资源消耗
- `moon check --target js --json` ×2（前/后）、`moon test --target js -j 1` ×1、`check_pkg_imports.py` + selftest、`gen_plugins.py` 重投影；core 库源码点查 1 次（`~/.moon/lib/core/json/parse.mbt`）。
- 回合预算：目标 20 回合内续段，未新开分支预算；时间轴累计 ~11,300s。

## 任务分配记录
- FIST 自我迭代轨：T0.2 用 `python scripts/fist.py call claim/execute/submit/verify`（源建 `cmd/cli` 产物）推进到「已完成」，deliverable 记本轮读数；DB 走 `FIST_DB_PATH=temp/fist-selfiter.db` 显式改道。根任务 T0 仍「拆分中」，T0.3 未做，不假装收口。
- 未派子代理：判据只有"补哪条 import、能不能不补"一格，实测更快。

## 遗留风险
1. **native 面一条理论性 0029**：`cmd/cli` 新加的 `moonbitlang/core/json` 只被 js-only 的 `upgrade_js.mbt` 用到，native 侧没人用；本机 native 不可量（core native bundle 缺件），CI native job 只判 error 不判 warning ⇒ 这条不会自动浮现，但也不会消失。已在账本写明，不用压制掩盖。
2. 本支仍 stacked 在 `slave/fix/unused-package-deps`(9dfd08a) → `slave/fix/moonc-0.10.16-result-api`(f72752d) 之上，MR diff 会带上前序两单；先合前序再 rebase 即收敛到 2 份文件 + 文档面。
3. 其余 1700+ 条 warning 未动，头部两族仍是 0020 deprecated(904) 与 0025 test_unqualified_package(803)。

## 后续建议
- 下一族建议 `0035 reserved_keyword`(13) 与 `0078 result_error_return`(13)：都是"改名/加显式返回"级别的低风险机械改，但要逐条看锚点是否跨包公开名。`0006 unused_constructor`(12) 需谨慎——变体没构造点往往是功能缺口而非死码，删之前要回读设计意图。
- 若要让 native 面也可量，先补本机 `~/.moon/lib/core/_build/native/release/bundle`（与 BUG-329 的 js 侧合成同理，用 `moonc bundle-core` + native target），否则两族的 native 对照永远只能靠 CI。

## 超额内容
- 把 0071 整族（含 BUG-342 顺带的白盒 5 条）一次收干净，而不是只补这 4 条 import；并给出"为什么没有免 import 替代写法"的 core 库真源证据。

## 来源
- `moon check --target js --json`：`temp/chk7.json`（1899）/ `temp/chk8.json`（1895）。
- `moon test --target js -j 1`：`temp/pt6.log` → `Total tests: 1302, passed: 1302, failed: 0`。
- core 库真源：`~/.moon/lib/core/json/parse.mbt:82`（`pub fn parse`）；`from_string` 仅存在于 `BigInt`。
- 仓内证据：`cmd/cli/moon.pkg` 的 `options(targets: ...)`、`cmd/cli/upgrade_js.mbt:75/280`、`cmd/cli/upgrade_native.mbt`（`@json.` 0 处）、`src/store/store_sqlite.mbt:309/636`。
- 账本：`memory/bugs.md` BUG-343（detail + note + `### FIXED(R19)`）；`memory/2026-10-20.md` R19 段。
