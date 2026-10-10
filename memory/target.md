[principle] assets 单一真源投影：仓库根 assets/ 由 gen_plugins.py 的 copy_assets()（generate() 第⑤步）按字节 copytree 到 plugins/<host>/assets/，插在 generate() 内而非 main() 主流程——因为 generate() 是真跑与 --check 临时区两条路共用的唯一生成入口，插里面 cl7 判据态与生成态自动拿到同一套资产，否则两面漂移。新增宿主用单一常量 HOSTS 元组，禁止在各函数里硬编码宿主列表。
[lesson] check_publish_payload 对「未跟踪且未 ignore」的资产必报 P1（打包面=工作树−.gitignore）。修法 = git add 提交入库，不是加 .gitignore——ignore 会把真源挡出发布包让产物缺资产。判定顺序：先加资产 → gen_plugins 投影 → 提交入库。
[lesson] 本轮实测补齐 AI-DEVELOPMENT-STANDARD §7 已知边界「cl7 只保证等于投影，不保证宿主可用」的实证格：fist-mbt 插件在 DSH 宿主侧真装上（3 resources + 129 tools + 真库 2011 任务）。上一版 patch 失败根因：dsh-mcp-client Config 无 timeout_ms 字段（真名 toolCallTimeoutMs）+ 相对 _build 路径按 Host cwd 解析。修法：绝对路径 + 钉 cwd + 删宿主面重复 agent-instructions 行。
[principle] star gate (P1-a) 已完成并入库（commit 75d77a7）：`src/router/star_gate.mbt`（217 行）+ `star_gate_wbtest.mbt`（156 行），六判定 Unreadable→BadFormat→BadSignature→Stale→NoSuchUser→Valid，真 Ed25519 RFC 向量验签，`moon test --target js src/router` 34/34 通过。依赖 `"cc06b/mooncry/lib" @mooncry`（mooncry 0.13.1）。canonical = `{"issued_at":<n>,"list":[...],"ttl_seconds":<n>}`（与 attest.yml 的 json.dumps(sort_keys=True) 逐字节一致）。

[lesson] 多子代理并行跑同一工作树，任一代理执行 `git clean -fd` 会静默抹掉所有子代理的未跟踪成果（本会话 star_gate.mbt + wbtest 三次被抹，最终靠 git 对象库的 dangling blob 找回 + 上下文重写）。防法：① 任何新建文件**立即 `git add`**（暂存即入对象库，clean 不删）；② 关键成果**立即 commit**（防 `git reset --hard` / `checkout -- .`）；③ 子代理提示词**硬禁止** git clean/stash/reset --hard/checkout --/restore；④ 发现竞态**立即 interrupt_agent**，不要只发消息。

[lesson] mooncry 0.13.1 的 `"cc06b/mooncry"` 解析到**空根** `moon.pkg`，真实代码在 `"cc06b/mooncry/lib"`（其 moon.pkg 无 name ⇒ 模块名 = lib）。正确导入 `"cc06b/mooncry/lib" @mooncry`，代码里写 `@mooncry.hex_to_bytes_or` / `@mooncry.bytes_to_hex` / `@mooncry.ed25519_verify`（别名必须带 `@` 前缀）。API：`hex_to_bytes_or(s)->Result[Bytes,String]`、`bytes_to_hex(b)->Bytes`、`ed25519_sign(seed,msg)->Bytes`、`ed25519_verify(pk,msg,sig)->Bool`。

[lesson] MoonBit `inspect(x, content=...)` 的 `content` 参数类型是 **String**（快照对比），不是原始值：`content="Valid"` 而非 `content=Valid`；且被 inspect 的类型必须 `derive(Show)`（否则报 `does not implement trait Show`）。枚举构造子在 **value 位置**需 `StarVerdict::Valid` 限定，**pattern 位置**可裸用。

[lesson] PowerShell 里正则/字面量含 `\"`（反斜杠转义引号）或管道符 `|` 包在双引号字符串内会解析失败，浪费多次调用；诊断用 `-SimpleMatch` 或把正则放单引号且避开 `|`/`\"`。相对路径 `[System.IO.File]::ReadAllText` 按进程 cwd 解析不可靠，文件操作一律用绝对路径。
