# 项目助理选举 Skill（assistant_* 五工具）

## 何时用

当多 agent 并发协作需要单一"项目助理"主节点时，用本组五工具完成选举、续命、清僵尸、退位与状态查询。适用场景：

- 多 agent 并发编辑同一项目，需一个主助理协调文件锁与心跳
- 无人值守流水线需要一个可选举、可接管、可退位的项目助理角色
- 需要查看当前助理全景（现任主助理、全部登记、锁违例统计）
- 需要定期清扫过期文件锁与僵尸助理（心跳陈旧超阈值）

## 怎么调

### 1. `assistant_claim`

项目助理选举。裁决单一真源 `store.assistant_claim_action`。

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `agent` | string | **是** | 调用方 agent 标识 |
| `heartbeat_ttl_sec` | number | 否 | 心跳 TTL 秒数，默认 `300` |

返回裁决四态：

- `elected` — 无 active 主助理，本人当选
- `renewed` — 本人重复调用，续任
- `taken_over` — 主助理心跳陈旧，接管（旧主记 `lock_violations` force_takeover）
- `conflict` — 主助理心跳新鲜，拒绝

### 2. `assistant_status`

助理全景查询（纯读不写）。

无参数。返回：现任主助理 + 全部登记 + 锁违例统计。

### 3. `assistant_sweep`

清扫拍：释放 TTL 过期文件锁（复用 `locks_sweep`）+ 心跳陈旧超 `stale_secs` 的助理标 `dead`。

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `stale_secs` | number | 否 | 心跳陈旧阈值秒数，默认 `600` |

### 4. `assistant_resign`

助理主动退位。`status=resigned`；锁不阻塞，靠 TTL + 清扫拍兜底释放。

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `agent` | string | **是** | 退位的 agent 标识 |

### 5. `assistant_heartbeat`

刷新自己的 `heartbeat_at`（未注册者显式报错）。

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `agent` | string | **是** | 心跳上报的 agent 标识 |

## 已知边界

- 锁不阻塞：`assistant_resign` 退位后不立即释放锁，靠 TTL 过期 + `assistant_sweep` 清扫拍兜底释放。
- `assistant_heartbeat` 对未注册 agent 显式报错（非静默忽略）。
- `assistant_sweep` 的 `stale_secs`（默认 600s）与 `assistant_claim` 的 `heartbeat_ttl_sec`（默认 300s）是两个独立参数，语义不同：前者是"陈旧判 dead"阈值，后者是"心跳新鲜"判定窗口。
- `assistant_claim` 的 `taken_over` 接管会把旧主记入 `lock_violations`（force_takeover），这是审计痕迹，不影响新主正常工作。
- 本组工具真源 `src/store/store_assistant.mbt`（multi-agent-lock v3 阶段 2 精简版）。

## 五工具协同

五工具构成助理生命周期闭环：

```
assistant_claim（选举）
      │
      ▼
  主助理在任
      │
      ├── assistant_heartbeat（续命，刷新 heartbeat_at）
      │
      ├── assistant_status（全景查询，纯读）
      │
      └── assistant_resign（主动退位）
                    │
                    ▼
              锁靠 TTL + 清扫拍兜底释放

assistant_sweep（清扫拍）
  ├── 释放 TTL 过期文件锁
  └── 心跳陈旧超 stale_secs 的助理标 dead
```

闭环路径：**claim 选举 → heartbeat 续命 → sweep 清僵尸**，三拍一循环，确保多 agent 环境下始终有且只有一个活跃主助理。
