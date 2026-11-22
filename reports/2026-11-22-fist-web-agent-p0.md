# P0 阶段报告：.fist.md 打包器升级

- 日期：2026-11-22
- 命名空间：marvis-webagent
- 任务：T0.1 / T0.1.1 / T0.1.2（P0 .fist.md 规范定稿 + 打包器升级）
- 状态：已完成

## 交付物

1. `scripts/pack_exe_to_md.py`（升级版通用打包器，12572 字节）

## 能力

- 任意 Linux 静态二进制 → 单 `.fist.md` 交付态自建包
- YAML frontmatter：`fist-md: 1.0` / name / version / os / exposure / port / auth / payload / sha256 / tunnel
- payload = base64(gzip(tar(exe)))，标记 `<!--PAYLOAD:BEGIN-->` / `<!--PAYLOAD:END-->`
- 内嵌 UNPACK_PY（python3 优先）与 UNPACK_BASH（bash + base64/gzip/coreutils 兜底）
- 三档启动模板：local（127.0.0.1）/ lan（0.0.0.0 + 防火墙提示）/ global（cloudflared quick tunnel）
- 体积预算参数 `--budget`（超限告警）
- `--split` 分片模式（`<!--PAYLOAD:PART:n-->`）
- SHA256 校验链（frontmatter 与解压脚本双重校验）

## 验证记录

- frontmatter 解析：OK（fist-md: 1.0, sha256 存在, tunnel 字段存在）
- SHA256：匹配（3f63570cfd99ffb806e090598444821a93bfb83797c0271d02281e7d478d9902）
- payload 还原：python3 unpack 脚本还原 1048576 字节，exit 0，`OK: 还原 ...`
- 三档模板：local / lan / global 均存在
- 分片模式：1 片，SHA256 匹配，tar 成员正确
- 测试包：`temp/fist-web-agent-test.fist.md`（预算 8.0 MB，实际 1.34 MB）

## 修复记录

- UNPACK_PY 的 `text.find(BEGIN)` 会误匹配脚本自身字符串字面量导致 payload 提取为空、SHA256 失败 → 修复为 `rfind(BEGIN)` + `rfind(END)` + `j <= i` 守卫
- UNPACK_BASH 同步改为 `grep ... | tail -1`
- edit_file 曾出现"报告成功但文件未变更"问题，二次修复后生效

## 待办

- P1（T0.2）：核心服务 /health + OpenAI 兼容 /v1/chat/completions + /mcp + api-key 双通道鉴权
