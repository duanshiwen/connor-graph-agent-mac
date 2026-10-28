# 四端账号同步契约

更新日期：2026-10-28。本文描述源代码契约；不代表安装包已发布或线上后端已部署。

## 链路与共同范围

四端登录同一 Connor 账号后执行 pull → apply → project → push，约每 45 秒兜底同步；部分平台另有 WebSocket 唤醒。载荷以密码和用户 ID 经 PBKDF2-SHA256（210,000 次）派生密钥，通过 AES-256-GCM 加密。集合、记录 ID 和版本属于同步元数据，不在密文内。

| 项目 | 共同范围 |
| --- | --- |
| 会话与笔记 | sessions；笔记使用 kind=note；保留历史 notes 接收和迁移 |
| 标签 | governance_labels：id/name/colorName/systemImage/updatedAt |
| RSS | rss_subscriptions：id/feedURL/title/createdAt/updatedAt；兼容旧 feedUrl，不同步文章和阅读状态 |
| 邮件内容 | mail_messages：邮件列表、纯文本正文、已读状态和附件清单；详见 [邮件内容同步](mail-content-sync.md) |
| 技能 | skills：用户技能包的身份、指令、模板、分类、启用状态及时间；内置技能不参与 |
| 设置 | settings 只投影 personality、user_preferences、ai_connections |
| Memory OS | memory_l0 / memory_l0_spans / memory_l1 / memory_l2 / memory_l2_nodes / memory_l3 / memory_l4_entities / memory_l4_relations |

邮箱登录与服务器配置 mail_accounts 已退出同步：不再投影、推送、应用或回推其删除；后端拒绝新写入，并从 pull/snapshot 过滤历史配置。客户端清理旧配置的同步重试状态，但不会删除本机邮箱账户、凭据或已有邮件缓存；历史云端行不在本次改动中物理擦除。

邮箱密码、OAuth 访问/刷新令牌、客户端 secret、附件文件不参与邮件内容同步。AI 普通 API Key 仍遵循原有 E2EE 连接同步规则，本次仅调整邮件范围。日历事件、工作区文件、浏览器状态、定时/事件任务、Base 数据不进入通用同步；真人 IM 使用独立链路。主题、代理、权限等设备运行时设置留在本机，Mac 不再投影或应用 macos_runtime。

## 笔记与合并

笔记统一为 sessions、kind=note，正文为 user 消息，复用消息 ID。Android 未关联笔记使用笔记 ID，已关联笔记使用 sessionId。四端仍接收历史 notes，保留到规范会话的映射，编辑和删除继续落到规范 sessions。缺少 kind 的历史载荷兼容原有会话类型。

会话保留 user/assistant 消息并集和标签并集；共享元数据按更新时间合并。status 使用 in_progress、needs_review 等规范值，archived 独立保存，不能因“已完成”状态丢失归档。会话 tombstone 阻止旧副本恢复，显式恢复走恢复版本协议。

标签定义保留原始颜色、图标和版本；RSS 配置时间独立于抓取时间，已有源同样更新。用户偏好允许用空串清空 city/country；缺失历史字段不覆盖本机值，Mac 的共享偏好时钟独立于主题等本机设置。已设置后的空人格参与同步。

AI 连接整条记录按 updatedAt 合并，保留完整 models/defaultModel；正版本的空列表可清空普通连接。none/空 API Key 清理旧普通密钥。OAuth 凭据留在本机，各端保留本机已授权而远端未列出的订阅连接；Android 加密保留不支持的协议定义。清空共享列表不等于撤销其他设备的 OAuth 授权。

Windows/Mac/Linux 技能使用本机 sidecar 保留远端不透明 ID 和本机 Markdown 无法表达的模板、分类、时间；收到技能后重新编码不能生成一个新的共享身份。

## 大记录传输 v1

会话 JSON 超过 512 KiB 时，按最多 256 KiB 的 UTF-8 字节块拆分，单条消息可跨块。仍使用 sessions 集合，不增加服务端会话格式；每条块和根清单分别以自身记录 ID 作为 E2EE AAD。

根为 `{id,_connorSessionChunks:{v:1,sha256,semanticHash,byteLength,parts:[...]}}`；块为 `{_connorSessionChunk:{v:1,sessionId,sha256,index,data}}`，data 是 Base64，块 ID 为 csp_ 加 SHA-256(`根ID + NUL + sha256 + NUL + 十进制index`) 的前 48 位小写十六进制。

分块不是可见内容。四端持久化块和未完成清单，支持乱序、分页及重启；收齐并验证字节长度、SHA-256、记录 ID 和语义哈希后才应用完整内容。批次同时受 200 条和约 900 KiB 序列化大小限制。当前最多 512 块，即 128 MiB 原始 JSON；超限保持未完成状态，其他正常记录继续同步。旧块暂不做服务端垃圾回收。

会话 semanticHash 对规范字段使用 4 字节大端长度前缀的 UTF-8 字符串，字段顺序为 id/title/createdAt/updatedAt/kind/status/archived、排序去重后的标签及 user/assistant 消息的 id/role/content/createdAt。仅比较哈希中的时间向下取整到秒；原始传输保留毫秒。

邮件在 mail_messages 集合复用同一分块信封，旧的 _connorSession* 键名只是传输格式，不表示邮件变成会话。邮件使用自己的完整内容语义哈希，不能套用会话字段归一化；其定义见邮件协议文档。已确认根内容相同时，不再重复上送另一套编码分块。

## 删除、增量与升级

会话、RSS、标签、用户技能使用显式持久化删除意图，确认后清理，删除最后一条也传播；重新添加/导入会取消相应待删除意图。历史差异检测仍保留空集合防护，不能把缓存丢失视为全局删除。

邮件内容是只读副本：清理缓存、删除本机邮箱配置不会生成邮件删除，后端也拒绝 mail_messages 的删除 mutation。收件端打开邮件不会代替用户向邮箱服务器发出已读、删除或发送命令。

后端对同一账号在分配变更游标前取得事务锁，持有至提交，避免较大游标先提交导致较小游标永久漏收。客户端接收独立于本地投影和上传成功；先持久化接收结果并通知界面，再尝试上传。版本 4 快照用于补收邮件内容及历史漏收记录，不清空本机独有会话。

后端与四端需要配套升级。旧客户端仍推送 mail_accounts 时会收到集合不支持的错误；旧客户端也不能接收邮件内容或分块。上线前仍需安装包联调；本工作不包含生产部署。

## 验证

四端共享 account-sync-config-v1.json、session-chunks-v1.json、mail-content-v1.json，副本必须逐字一致。邮件样例验证身份、跨端语义哈希、跨 UTF-8 边界分块、凭据与附件实体剔除、两端无重复回推、完整正文不被不完整副本覆盖。

本次自动验证结果以任务报告为准。Mac 新增了原生测试；当前 Windows 环境只能进行语法解析对比，未执行 macOS 原生编译或四端真机联调。
