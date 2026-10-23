# 排查记录 · `X is not defined`（本地服务 ReferenceError）

> **定位方法可复用**。本案是 2026-10-12 追查 OFM 上游 500 `atomcode is not defined` 的完整路径。
> 任何"调用本地/远端服务时报 JS `X is not defined`"的同类问题，按下面 1→2→3 照方抓药即可。

## 0. 症状（本案）

- 端到端：fist-mbt `executor_run(executor="ofm", model=…)` 真跑 → 回 `http_status=500`、
  `error_type=server_error`、`error="atomcode is not defined"`、`failure_kind=UPSTREAM_DOWN`。
- 直接探上游：`POST {ofm_endpoint}/chat/completions` 对**全部 8 个模型**都回 500，体为
  `{"error":{"message":"atomcode is not defined","type":"server_error",...}}`。
- **反直觉的对照项**：同刻 `GET {ofm_endpoint}/models` 回 **200** ⇒ 排除"密钥无效 / 请求形状错 /
  鉴权错 / 个别模型坏"。这条对照几乎总是第一个要做的，能立刻把搜索面从"全链路"收到"chat 这一支"。

## 1. 先定位监听者，再定性"上游故障"

看到 `500 X is not defined`，**不要直接判"上游黑盒故障"**。先问：这个端口是谁在服务？

```powershell
# 谁在监听 18899？拿 PID
netstat -ano | Select-String "18899"
Get-NetTCPConnection -LocalPort 18899 -State Listen | Select-Object LocalPort,OwningProcess

# PID → 进程（拿命令行，确认它到底是哪个服务）
Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" | Select-Object Name,CommandLine
```

本案结论：监听 18899 的 PID 就是 **DSH web 进程本身**（`dsh/lib/bin.js web --port 3099`）。
⇒ "上游"其实**就在本机、可本地修**，不是等别人修的外部服务。

> 教训：`X is not defined` 是**调用方进程自己**抛的 ReferenceError。只要端口监听者在本机，
> 源码一定在这台机器上，追得到。

## 2. 找到引用 `X` 的那份源码（快，别用慢的递归管线）

关键：**先按进程找加载来源**，而不是全盘乱搜。

```powershell
# ① 进程入口包的源码树（DSH 装在哪）——本机用户态插件通常在 profiles 下
$dshHome = "C:\Users/<user>\.dsh"

# ② 用 findstr，别用 Get-ChildItem -Recurse + Select-String（在 node_modules 上慢到超时）
cmd /c "findstr /s /m /i /c:atomcode `"$dshHome\*.js`" `"$dshHome\*.mjs`" `"$dshHome\*.ts`" `"$dshHome\*.json`""
# /s 递归、/m 只打文件名、/i 忽略大小写 —— 立刻定位到：profiles/web/node_modules/dsh-our-free-model/*
```

> 坑：对同一个插件目录，`Get-ChildItem -Recurse` **枚举为空**，但 `Get-Item` / `Get-Content` /
> `findstr` 直读都正常。别被 PS 管线的空结果骗了，交叉验证用 `findstr` + 直读。

## 3. 判定"用了没声明"（ReferenceError 的唯一成因）

裸标识符 `atomcode` 抛 ReferenceError，只可能是：**在这个作用域里没有 `const/let/var/function/import`
绑定它**。把出现处全列出来，逐处看是否在作用域内。

```powershell
$f = "...\dsh-our-free-model\src\adapter.js"
Select-String -Path $f -Pattern '\batomcode\b' | ForEach-Object {
  "L$($_.LineNumber): " + $_.Line.Trim()
}
```

本案命中（节选）：

```
L25:  import { postAtomcodeStreamed, resolveAtomcodeToken } from './atomcode.js'   # 有 import，但没导入名叫 atomcode 的绑定
L30:  import { isAtomcodeEntry, isEacEntry, isKiloEntry } from './catalog.js'     # isAtomcodeEntry 已导入
L216: const sealed = isEacEntry(entry)        # 声明了 sealed
L217: const kilo   = isKiloEntry(entry)        # 声明了 kilo
L282: const renameMap = sealed || kilo || atomcode ? ...   # ← 用了 atomcode，但上面没声明它
L299: : atomcode ? postAtomcodeTurn(...)                    # ← 又用了 atomcode
```

**对照同文件的 lane 写法就露馅了**：`sealed` / `kilo` 都是
`const <lane> = is<Lane>Entry(entry)` 一行声明的，唯独 `atomcode` 少这一行。
而 `isAtomcodeEntry` 早已在 L30 导入、在 `catalog.js` L565 导出（`entry?.channel === ATOMCODE_CHANNEL`）。

⇒ **根因：漏写 `const atomcode = isAtomcodeEntry(entry)`**。由于 L282 在 turn 循环里**无条件执行**，
所以与"哪条 lane"无关，**每个请求都抛 ReferenceError** —— 这正好解释"8 个模型全 500"，
而 `/v1/models` 不走这段所以仍 200。

## 4. 修复（最小改动 + 同源对齐）

```js
const sealed = isEacEntry(entry)
const kilo   = isKiloEntry(entry)
const atomcode = isAtomcodeEntry(entry)                          // ← 补上这行
const wire = sealed || kilo || atomcode ? 'chat' : wireFor(entry.id)   // wire 判定同步含 atomcode
```

纪律：
1. **改前先备份**（`Copy-Item` 成 `.bak-<日期>-<关键词>`）。
2. **只修缺的那一行**，别顺手重构；本案唯一行为变化 = free lane 不再抛错（`isAtomcodeEntry` 对
   free-lane 条目返回 false，路径逐字不变）。
3. **确认改的是运行态加载的那份**：`index.js` 若是 `import ... from './src/adapter.js'`
   （非自包含 bundle），改 `src/adapter.js` 就有效。

## 5. 验证（分层）

| 层 | 手段 | 本案结果 |
|---|---|---|
| 语法 | `node --check adapter.js` | `rc=0` 通过 |
| 绑定 | 重列所有 `atomcode` 引用，确认全部落在新 `const` 作用域内 | L225/L287/L304 全解析 |
| 行为 | 逐 lane 走一遍 `sealed/kilo/atomcode` 真值 → 确认分支不越界 | free lane 零变化 |
| **运行时** | **重启承载进程**，再打一发真请求 | ⚠️ 见 §6 |

⚠️ **Node 会把已加载的 ESM 模块缓存在内存**。改盘上文件**不会热重载**（本案改完立刻重探仍 500）。
必须**重启承载该插件的进程**才生效。若该进程就是宿主会话本身（本案 DSH 承载了排查会话），
重启会断会话 ⇒ 这一步交使用方。

## 6. 善后与坑清单

- **生效依赖重启**：改完 ≠ 生效，务必写明"重启 <进程> 后生效"。
- **会被覆盖**：改在 `node_modules` 里的修复会被插件升级冲掉。**回上游源码补同一行**，本地这份当
  应急补丁（留备份 + 在文档/记忆里点名路径，防止升级后复发还查不到）。
- **工具选型**：搜 node_modules 用 `findstr /s /m`，PS `-Recurse` 管线在这类目录上慢到被 kill；
  且个别目录 PS 枚举为空、直读正常，别被空结果误导。
- **对照项先行**：`/v1/models` 200 + `/chat/completions` 500 这一对，比"反复改请求体"高效得多，
  直接锁定问题在 chat 这一支、且不是鉴权/形状问题。

## 来源

- 案发代码：`C:\Users/<user>\.dsh\profiles\web\node_modules\dsh-our-free-model\src\adapter.js`
- 修复备份：同目录 `adapter.js.bak-20261012-atomcode`
- 上游真源建议落点：`dsh-our-free-model` 插件源码仓库（本地这份为应急补丁）
- 关联记录：`memory/2026-10-12.md`「P0.3 上游 500 根因定位与修复」、
  `docs/2026-10-11-fist-mbt-upgrade-plan-v2.md` §8 P0.3 行、
  `reports/2026-10-12-ofm-fusion-p0-report.md` 遗留风险①/超额内容

*（内容由AI生成，仅供参考）*
