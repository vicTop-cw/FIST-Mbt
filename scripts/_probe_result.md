# dry-run 探测结论（atomcode 3 家）

- 载体全为 `atomcode -p` headless，本机已登录可用（输出 stdout 纯文本）。
- AI2 LongCat：`--provider longcat --model "LongCat-2.0" --ephemeral` 可用。
- AI3 默认：`atomcode -p`（不指定模型）可用，输出 "OK"。
- AI4 Kimi：`--provider Kimi --model "kimi-k3" --ephemeral` 可用。
- `--model "provider/模型"` 形式返 400，须 `--provider`+裸模型名。
- 极简提示仅回 OK；喂完整 rubric 时 LongCat ≥120s 仍生成中（需放大 timeout）。
- 门禁脚本真实跑通 AI1+error 路径；SCORE_JSON 解析正则通过（含夹带叙述）。

缺口：真实模型评分慢（>120s），须按实放大 timeout。