# macOS 事件驱动同步（2026-11-24）

增加可选 heartbeat.syncCursor 门控、完整检查点精确比较与单轮解析缓存，以及邮件直接类型解码。保留原本地变更代次、WebSocket 唤醒和失败重试。新增策略与兼容测试；本机缺少 Apple SDK，未运行原生编译/测试。

统一协议、六端实现、测试与上线边界见工作区 [同步设计](../../connor-agent-backend/docs/sync-energy-event-driven.md)。

正常空闲状态跳过数据同步校验；保留原约 45 秒在线心跳/L1 租约及轻量远端水位比较，补偿漏通知。启动、重连、本地变更、远端提示、待处理失败及旧后端仍会进入同步。接收游标仅在相应数据/分片持久化后前进，冲突、删除传播、完整邮件正文/附件清单与必要后台任务保持原行为。

通知只作为提示的设计参考：[Google Drive push](https://developers.google.com/workspace/drive/api/guides/push)、[增量游标](https://developers.google.com/workspace/drive/api/guides/manage-changes)、[Apple 后台投递限制](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)。本次复用在线 WebSocket，没有接入新的系统推送通道。

代码提交与推送不代表已经部署；先更新后端能力，再发布客户端。缺少水位或监控失败会回退原检查，因此不能把测试结果等同于线上功耗改善。实际变更轮次仍可能扫描完整投影；未宣称全部改为逐记录 outbox 或事务检查点。未做同负载 Release 真机功耗 A/B。

