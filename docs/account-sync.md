# 四端账号同步契约

更新日期：2026-10-27。下文描述本次代码实现；不代表四端安装包已发布或线上后端已经联调。

## 链路与范围

Mac、Android、Windows、Linux 登录同一账号后，先 pull/apply，再 project/push；运行期间约每 45 秒兜底同步，Mac/Android 另有 WebSocket 唤醒。载荷由密码和用户 ID 经 PBKDF2-SHA256（210,000 次）派生密钥，以 AES-256-GCM 加密；同步元数据（集合、记录 ID、版本等）不在密文内。

四端共有范围：会话与笔记、会话标签定义、RSS 订阅源、邮箱服务器配置、用户技能包、人格、用户基本偏好、AI 连接定义及 API Key，以及 memory_l0 / memory_l0_spans / memory_l1 / memory_l2 / memory_l2_nodes / memory_l3 / memory_l4_entities / memory_l4_relations。Mac 额外保留 macos_runtime 设置；它不属于四端共有设置。

邮箱密码、OAuth 访问/刷新令牌、客户端 secret 不进入邮箱配置同步；各端独立授权。AI 连接中的普通 API Key 在 E2EE 信封内同步，Codex/Copilot OAuth 凭据不同步。邮件正文、日历事件、RSS 文章及阅读状态、附件文件、工作区文件、浏览器状态、定时/事件任务不进入通用账号同步；真人 IM 走独立链路。Base 的导入导出/同步格式尚未接入通用账号同步。

## 笔记

统一使用 `sessions` 集合、`kind=note`；正文是会话中的 user 消息，保留消息 ID 以支持正文编辑后的合并。缺少 kind 的旧会话按 chat 兼容，已有本地笔记类型应保留。

Android 独立笔记使用笔记 ID 作为会话 ID，已关联的笔记使用既有 sessionId；收到笔记会话后维护本地 Note 投影。新数据不再发布独立 notes 记录。四端仍接收历史 `notes` 记录并迁移到规范会话；历史记录含 sessionId 时优先使用该关联。会话 tombstone 防止普通旧笔记记录恢复已删除内容。

## 邮箱配置

集合为 `mail_accounts`。共享字段：id、displayName、address、username、imapHost、imapPort、imapSecurity、smtpHost、smtpPort、smtpSecurity、createdAt、updatedAt。时间戳为 epoch 毫秒，安全模式为 `ssl`、`starttls`、`none`。STARTTLS 必须升级成功后才发送凭据。

配置按 updatedAt 合并，保留本机凭据和认证状态；历史同地址不同 ID 的账户按较新记录合并。删除最后一个邮箱也传播；Windows/Linux 使用持久化删除队列，Mac/Android 从已同步基线与可用邮箱存储的差异生成 tombstone。单纯刷新本机 OAuth 凭据不应让共享服务器配置变新。

## 超大会话传输 v1

普通会话继续使用内联载荷。规范会话 JSON 的 UTF-8 字节数超过 512 KiB 时，拆为每块最多 256 KiB 的字节块；单条巨大消息也可以跨块，禁止按字符截断正文。

仍使用 sessions 集合和既有 push/pull/snapshot 路由，不新增服务端集合。根记录 ID 是真实会话 ID，载荷为 `{id,_connorSessionChunks:{v:1,sha256,semanticHash,byteLength,parts:[...]}}`。分块记录载荷为 `{_connorSessionChunk:{v:1,sessionId,sha256,index,data}}`，data 为 Base64。块 ID 是 `csp_` 加 SHA-256(`sessionId + NUL + sha256 + NUL + 十进制 index`) 的前 48 位小写十六进制。

每条分块和清单分别使用其自身记录 ID 作为 E2EE AAD。批量上传同时受 200 条和约 900 KiB 的序列化大小约束。分块不是可见会话，接收端将其持久化；只有清单所列分块全部收齐、总字节数与 SHA-256 均通过校验后，才合并完整会话。缺块清单进入既有重试队列，保存分块和重试状态后才推进游标，因此允许乱序、分页及重启。

semanticHash 用于避免各端 JSON 编码和 Mac 存储时间精度差异导致反复回推，不代替原始字节完整性校验。字段使用 UTF-8 编码并加 4 字节无符号大端长度前缀，依次为：id、title、createdAt、updatedAt、kind、status、archived（1/0）、标签数量及排序去重后的标签、消息数量，以及每条消息的 id、role、content、createdAt。整数用十进制；仅该比较哈希中的时间戳向下取整到秒，原始传输数据保持毫秒。消息保留 user/assistant，按取整后的 createdAt、id 排序。已完整接收的相同内容不会因本地重新编码生成另一套分块；本地独有或修改的消息仍会上传。

当前单会话最多 512 块，即 128 MiB 原始 JSON；超过上限会保持未同步状态，其他正常记录仍可继续同步。旧分块记录暂不做服务端回收，频繁编辑超大会话会增加服务端占用；后续应以根清单可达性和并发版本为依据增加回收机制。

## 升级与验证

四端需一起升级：旧客户端无法解码分块清单，可能显示接收重试。升级修复版本为 2，会重新请求历史快照，补收此前被过滤的邮箱和独立笔记记录；后端不支持快照时仍可增量同步，但历史补偿不可用。上线前需确认后端允许 sessions 中的透明加密载荷及上述记录 ID，并进行四端安装包联调。

共享测试向量为 `session-chunks-v1.json`，覆盖中文、emoji、转义字符和毫秒时间；四仓副本应一致。各端测试另覆盖大消息、缺块、乱序、状态序列化恢复及校验失败。运行结果以本次实际测试报告为准，不将静态检查视为真机验证。

## 持续增量接收修复

后端 main/c6632fb 的同账号不同记录可乱序提交：自增 cursor=3 先提交并被客户端消费，cursor=2 后提交后将被 cursor>3 永久跳过。后端本次修复在分配游标前取得账号级事务锁，保持至提交；所有服务实例需更新。修复前并发回归稳定失败，修复后通过；四端各有本地对话、三轮新增及单条分页的持续拉取也有回归覆盖。

客户端接收不再依赖本地投影/上传成功：投影失败仍尝试接收，已接收记录先持久化并刷新界面，上传失败保留错误和重试状态。Linux 后台接收新增 watch 通知到 GTK 会话列表；Windows 发出 Changed；Mac 通过 onReceived 刷新；Android 在上传前运行接收后的刷新。快照修复版本 2 用于补回此前已被跳过的记录，不清空本地独有对话。

## 真实后端协议与本次验证（2026-10-27）

后端 UserDTO.id 是 JSON 整数，Windows 已兼容整数及旧字符串响应，统一为相同用户 ID 文本再派生密钥。Windows/Linux 账号客户端会为服务器根地址补全 /api/v1；已经带此前缀的地址不会重复追加。回归夹具已使用真实数字 ID 和真实路由。

历史 notes 的 sessionId 与笔记 ID 不同时，保留到规范会话的映射；编辑复用正文消息 ID，删除会继续传播到规范 sessions 记录。邮箱配置保留设备凭据；Windows 本地 SSL 开关可继续编辑同步配置，Linux 旧 SMTP 587 配置导出为其实际使用的 STARTTLS。

| 范围 | 本机验证结果 |
| --- | --- |
| 后端 | 隔离 PostgreSQL 17：16 项顶层同步/接口/租约/WebSocket 测试通过，旧版并发漏收测试失败、修复后通过 |
| Windows | 54 项同步相关测试通过，包含真实登录协议、历史笔记编辑/删除、缺块/乱序分页、离线消息合并和重新上传 |
| Android | app 模块 161 项单元测试通过，无跳过；包含笔记适配、共享向量和分块恢复 |
| Linux | 15 项协调器、3 项分块、2 项邮箱测试通过；GTK 桌面 cargo check 通过 |
| Mac | 6 个变更 Swift 文件语法解析通过；共享向量副本一致；新增原生测试尚未在 macOS 执行 |

这些结果不等同于四端真机联调或线上修复已经生效。改动尚未部署/发布，Mac 仍需原生编译验收。分块格式需要四端一起升级，服务端各实例需同时更新提交顺序修复；客户端升级后以修复版本 2 重新读取快照补偿历史漏收。
