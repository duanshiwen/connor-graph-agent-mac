# 日历重复与参与人复核

ICS 与 CalDAV 同步改为先展开配置时间窗口内的实际实例，保留 RRULE、RDATE、EXDATE、改期、取消及 VTIMEZONE；不再只按首次 DTSTART 过滤整个系列。实例 ID 包含重复标识。EventKit 保留参与人和组织者，同一个系列的多次实例使用不同本地 ID，原始远端标识继续用于系统写入。

CalDAV 整系列编辑以远端 master 为基准，保留排除日、分离例外和未变的来源时区，防止用所选实例的日期重写系列起点。条件写继续绑定审批时版本；系列确认后替换全部缓存实例，删除后清除系列缓存。系统日历写入后刷新实例，整系列范围映射到 master 起的 futureEvents。展示完整 EventKit 规则；简单写入器对无法表示的额外部分明确报错，避免静默改变日程。

新增 `CalendarOccurrenceParityTests`，并修正 `EventKitCalendarMutationAdapterTests` 对整系列范围的断言。当前 Windows 机器没有 Swift/macOS SDK，这些 Swift 测试和原生应用构建**未运行**。

可在仓库根目录执行 `node Scripts/test-calendar-occurrences.cjs`；离线生产解析桥的9项检查已在 Windows Node 通过。此结果不代替 Swift/JavaScriptCore 原生集成验收。

## 第三方源码

使用官方 npm `ical.js` **2.2.1**，来源：https://registry.npmjs.org/ical.js/-/ical.js-2.2.1.tgz ，项目：https://github.com/kewisch/ical.js 。依照包内 MPL-2.0 许可证分发，许可证全文、未修改的21个源文件和原包元数据一起放在 `Sources/ConnorGraphAppSupport/Resources/Calendar`，随资源包分发。`ical.es5.min.cjs` 未修改，SHA-256：`74B6AA16936DAA102CA216A29C8C25B53468762DD793BD9B106074AAA7961C65`。

`occurrences.js` 是本项目的独立桥接代码。每次解析使用隔离的 JavaScriptCore VM，ICS 通过函数参数作为数据传入，不拼接进代码；解析过程不访问网络。IANA 时区偏移由 Foundation 提供，内嵌时区按各自日历定义处理。
