import Foundation
import ConnorGraphCore

public struct MediaTranscriptionPromptBuilder: Sendable {
    public init() {}

    public func completionMessage(job: BrowserMediaTranscriptionJob, attachmentID: String) -> String {
        let title = job.source.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? job.source.pageTitle! : "当前网页媒体"
        return """
        已完成《\(title)》的本地媒体转写，并作为附件添加到本会话。

        附件 ID：\(attachmentID)
        来源页面：\(job.source.pageURLString)

        \(completionInstruction(for: job))
        """
    }

    public func analysisPrompt(job: BrowserMediaTranscriptionJob, attachmentID: String) -> String {
        """
        你刚收到一个由 Connor 内置浏览器本地转写生成的媒体全文附件。请只基于附件内容完成以下任务：

        附件 ID：\(attachmentID)
        来源页面：\(job.source.pageURLString)

        \(analysisTasks(for: job))

        请不要臆测附件之外的信息；如果转写中有明显噪声、不确定片段、低置信度片段或说话人识别错误，请显式标注。
        """
    }

    private func completionInstruction(for job: BrowserMediaTranscriptionJob) -> String {
        if job.request.outputPurpose == .discussion, !job.request.shouldGenerateChapters {
            return "用户选择了“只转写”。请先确认附件已可用，不要主动展开总结；如用户继续提问，再基于附件回答。"
        }
        if job.request.shouldGenerateChapters {
            return "请基于附件内容完成：总结主旨、提炼价值知识、生成章节/时间线、标注待核实内容、给出知识库沉淀建议，并提出高质量追问。"
        }
        return "请基于附件内容完成：总结主旨、提炼价值知识、标注待核实内容、给出知识库沉淀建议，并提出高质量追问。"
    }

    private func analysisTasks(for job: BrowserMediaTranscriptionJob) -> String {
        if job.request.outputPurpose == .discussion, !job.request.shouldGenerateChapters {
            return """
            用户本次只要求转写，不要求自动提炼。
            1. 简短确认转写附件已生成，并说明可以继续基于附件提问。
            2. 不要主动总结全文，不要生成章节，不要扩展知识库建议。
            """
        }

        var tasks = [
            "1. 用 5-8 个要点概括这个视频/音频的主要内容。",
            "2. 提取其中最有价值的知识、观点、方法、案例或数据，并说明为什么有价值。",
            "3. 标出值得进一步核实的事实、数据、引用或时间点。"
        ]
        if job.request.shouldGenerateChapters {
            tasks.append("4. 按内容结构生成章节、主题段落或时间线；如果附件中没有可靠时间戳，请用主题章节替代，不要编造时间点。")
            tasks.append("5. 如果内容适合沉淀为知识库，请给出建议的知识条目标题、标签和可复用摘要。")
            tasks.append("6. 最后向我提出 3 个高质量追问，帮助我决定下一步是深入讨论、保存知识，还是转化为行动。")
        } else {
            tasks.append("4. 如果内容适合沉淀为知识库，请给出建议的知识条目标题、标签和可复用摘要。")
            tasks.append("5. 最后向我提出 3 个高质量追问，帮助我决定下一步是深入讨论、保存知识，还是转化为行动。")
        }
        return tasks.joined(separator: "\n")
    }
}
