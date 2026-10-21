# marvis 组合模式第6轮 · 扩展模块边界寻虫

## 时间
2026-10-16 16:32Z – 16:34Z

## 阶段：寻虫 bugfind

## 扫描结果

### src/store（7 文件）
- **0 high / 0 medium** / 943 low
- multi_store.mbt safe_ns/data_dir_ok 边界已有完整守卫

### src/evolve（7 文件）
- **0 high / 0 medium** / 317 low
- critic.mbt float-equality 为语义设计（score 精确比较）

### src/router（13 文件）
- **0 high / 0 medium** / 687 low
- model_router.mbt iso_to_secs 有 length>=19 前置守卫
- dig[18] 访问在 length>=19 时安全
- noop-assignment 为 struct 字段构造误报（reason:/tier: 只是字段名匹配）

### src/hat（7 文件）
- **0 high / 0 medium** / 152 low

## 结论
- 4 个扩展模块均无 high/medium 级缺陷
- 全部 low 为 OCR 启发式噪声（match-exhaustive/result-discard/long-function 等）
- 需重启 MCP server 才能关闭 BUG-185/186/217（e2e irm + claimguard 已修但未现网生效）

## 剩余 OPEN 缺陷分析
- BUG-185/186/217：**已修复待重启生效**（e2e_irm + claimguard）
- BUG-242/244/245：Pentad 子项目（.p5 语言 demo），不在此 MoonBit FIST-Mbt 主仓内