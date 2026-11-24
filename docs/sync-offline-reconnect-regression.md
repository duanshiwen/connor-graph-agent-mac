# macOS 离线重连回归（2026-11-24）

新增 reconnectReceivesCommittedChangesEvenAfterSenderLeaves，参数 true/false 分别覆盖 A 仍在线和已离线。通过 Combine 网络恢复事件自动进入协调器，不调用手动同步；检查 SQLite 会话修改/删除和持久化游标。已完成语法检查，当前 Windows 主机无 Apple SDK，未运行原生测试。

运行：`swift test --filter AccountSyncRecoveryTests`。

共同前提：A 已成功上传，B 离线期间没有收到变更通知。B 恢复时没有本地编辑，没有新的 sync_changed/peer_online，不依赖 A 再上线或发请求。受控小数据测试的 5 秒截止时间用于检测误等 45 秒轮询，不是生产网络或移动端系统挂起状态下的时延保证。

[后端与六端验收记录](../../connor-agent-backend/docs/sync-offline-reconnect-regression.md)。后端另有隔离 PostgreSQL 的六种平台 × 两种在线顺序，共 12 组已通过，包含修改、新增、删除与游标幂等。提交推送不代表部署，也不代表已完成六台真机互通。

