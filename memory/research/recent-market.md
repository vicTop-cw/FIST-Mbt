# 调研记档：近 3 个月市场证据底座（2026-06 至今）

> 蒸馏日期：2026-09-24
> 检索方式：WebSearch 真实检索（2026-09-24），结合竞赛报告 §二生态表（2026-09-24 mooncakes 实时数据）。
> 铁律：仅记录检索到的事实；查不到的一律写「未检索到」，不编造包名/下载量/排名。
> 说明：M1 标准下全文不出现盘符/用户主目录等绝对路径，项目内部引用一律相对路径或仅文件名。

## 一、近 3 个月相关新增/活跃项目（mooncakes + 官方 + 社区周报）

| 包/项目 | 一句话 | 与 fist-mbt 的关系 | 来源 link |
|---------|--------|--------------------|-----------|
| vectie/moonclaw 0.1.6 | MoonBit 原生 agent runtime + gateway + 记忆 + job 系统 + ACP 远程 agent 控制，约 2026-06~07 高活跃 | ⚠️ 潜在直接竞品：概念(agent 编排+job+memory+AOP 位)与 fist-mbt 高度重叠；定位平台非 MCP Server | https://mooncakes.io/docs/vectie/moonclaw |
| cogna-dev/mcp-sdk 0.1.0 | MoonBit 实现的完整 MCP 规范 SDK（Server/Tools/Resources/Prompts/Streamable HTTP/SSE） | 协议库层（类 colmugx/mcp）；非完整编排系统 | https://mooncakes.io/docs/cogna-dev/mcp-sdk |
| moonbit-mcp（Glenn Lewis） | 社区 MCP 简单抽象封装 | 协议库层；无任务编排 | https://moonbit.community/weekly |
| MCP Server SDK（MoonBit 官方 peter-jerry-ye） | 官方同学编写的 MCP Server SDK | 协议库层优先；官方背书值得关注 | https://moonbit.community/weekly |
| Golem 1.5：The Agent Runtime（2026-05-08 发布） | 外域 WASM 持久 agent 运行时，MoonBit 获一等支持（derive.agent 定义、HTTP 路由、RPC 客户端） | 跨生态背书：MoonBit 可写 agent；fist-mbt 为 MoonBit 内 MCP Server+编排，非同场 | https://golem.cloud/blog/golem-1-5-the-agent-runtime/ |
| SeekMoon（MoonBit 官方 ADE，2026-09-01） | MoonBit 团队自建智能体开发环境(IDE→ADE)，核心用 MoonBit 实现，代码理解/评审/沙箱 | 强信号：官方重投 agent/智能体方向；fist-mbt 是其下游可被编排对象 | https://www.moonbitlang.com/blog/tags/ai |
| Rz-coder8848/moon-neo4j 0.1.0 / HuLunTunTao/moon-ort / moonbitstack/moonasgi / GA-vim/bobzhang-office 等 | 生态丰富度类包（图库/ONNX/AI 推理/Web/办公） | 生态基数佐证，非直接竞品 | 竞赛报告 §2.2 表 |
| colmugx/posoco 0.18.5 / mizchi/llm 0.3.2 / mizchi/bitflow 0.4.1 | Agent 框架 / 纯 MoonBit LLM 客户端 / Starlark 工作流引擎 | 概念重叠但语言/定位不同；llm 可替代 Python sidecar | 竞赛报告 §2.2 表 |

> 结论：**近 3 个月 MoonBit/AI 方向显著升温**，官方(SeekMoon/Golem 支持) + 社区(moonclaw/mcp-sdk/moonbit-mcp) 均发力 agent/MCP。fist-mbt 的「完整 MCP Server + 任务编排 + 自进化」组合仍是 MoonBit 生态中稀缺位，但 **moonclaw 与 fist-mbt 概念重叠最高**，需差异化论述。

## 二、同类竞品与评审偏好

- **MCP 生态稀缺性（客观核实）**：检索 mooncakes 相关包——colmugx/mcp（已依赖）、cogna-dev/mcp-sdk、moonbit-mcp、官方 peter-jerry-ye 的 MCP SDK、vectie/moonclaw。前四者均为**协议库/抽象**，**完整 MCP Server + 编排 + 自进化的一体化系统仍只有 fist-mbt**。评审「生态贡献」维度优势成立。
- **评审偏好（风险侧）**：2026 SCC 作品墙 30 项中高可视项目居多（moon-bash 浏览器演示、MoonMarkMind 脑图可视化、Reisen 视觉小说引擎等）；CSDN/MoonBit 官方月报公开报道多为可视化/可直接体验项目。→ 黑客松评委存在「偏好可见效果」倾向，MCP Server 需 MCP 客户端才有直观呈现，是 fist-mbt 的演示门槛。
- **fist-mbt 相对差距（客观判断）**：完成度（61 工具/148 测试/双端/CI）与技术深度（九态状态机+Omega+DGM+递归拆解+自驱+看门狗）属同比领先；相对差距主要在「首次体验链路」（需客户端接线）与「申报书/英文说明」未落地，非技术差距。

## 三、对本项目概率评估的含义（≤3 条）

1. **支撑「一等奖(30~45%)/二等奖(45~60%)」**：官方(SeekMoon、Golem 支持 MoonBit agent)与社区(moonclaw 等)持续加码 agent/MCP 方向，方向热度上升，fist-mbt 的生态唯一一体化落点价值被放大。
2. **压力来自概念门槛与可视化偏好**：评审更易向可直览项目倾斜；fist-mbt 需靠「30 秒体验脚本 + 申报书 + WSL/Windows 一键运行」补足演示短板，否则概率被压缩。
3. **moonclaw 是新变量**：若评审查到 moonclaw，fist-mbt 需清晰区分「完整 MCP Server + 纯 MoonBit 任务编排 + 自进化闭环」vs「平台级运行时」，避免被误判为重复造轮子。

## 来源
WebSearch（2026-09-24）真实命中链接：mooncakes.io/docs/vectie/moonclaw、mooncakes.io/docs/cogna-dev/mcp-sdk、golem.cloud/blog/golem-1-5-the-agent-runtime、moonbitlang.com/blog/tags/ai、moonbit.community/weekly、moonbitlang.cn/2026-scc/showcase、moonbitlang.cn/updates/2026/06/08 + 竞赛报告 §二；未检索到：fist-mbt 的直接同定位竞品完整清单、各包 GitStar 数（诚实留白）。