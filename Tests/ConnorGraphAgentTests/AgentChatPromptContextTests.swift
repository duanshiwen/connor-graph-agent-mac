import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentChatPromptContextIncludesExplicitPersonContextForMentionedPeople() {
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-wang"),
        displayName: "小王",
        aliases: ["王同学"],
        organizationName: "Connor Labs",
        notes: "杭州朋友",
        memoryEntityID: "person:person-profile:person-wang",
        memoryStableKey: "person-profile:person-wang"
    )
    let context = AgentChatPromptContext(
        userPrompt: "@小王 喜欢咖啡吗？",
        explicitPersonContexts: [PersonContextSnapshot(profile: profile, memorySummary: "小王偏好手冲咖啡。")]
    )

    let rendered = context.renderedPrompt

    #expect(rendered.contains("Explicit Relationship Context"))
    #expect(rendered.contains("relationship identity anchor"))
    #expect(rendered.contains("person_id: person-wang"))
    #expect(rendered.contains("aliases: 王同学"))
    #expect(rendered.contains("memory: 小王偏好手冲咖啡。"))
    #expect(rendered.contains("Current user request:"))
}

@Test func agentChatPromptContextRendersContactMethodsForMentionedPeople() {
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-duan-fuqiang"),
        displayName: "段福强",
        emails: [ContactEmailAddress(label: "primary", email: "oisin.duan@apecho.com")],
        phones: [PersonPhoneNumber(label: "mobile", number: "13800000000")],
        addresses: [PersonPostalAddress(label: "office", value: "杭州西湖区")],
        organizationName: "杭州康纳快跑科技有限公司",
        jobTitle: "CEO",
        memoryStableKey: "person-profile:person-duan-fuqiang"
    )
    let context = AgentChatPromptContext(
        userPrompt: "@段福强 帮我给他发封邮件",
        explicitPersonContexts: [PersonContextSnapshot(profile: profile)]
    )

    let rendered = context.renderedPrompt

    #expect(rendered.contains("Person Registry active profile contact methods are authoritative"))
    #expect(rendered.contains("emails: oisin.duan@apecho.com"))
    #expect(rendered.contains("phones: 13800000000"))
    #expect(rendered.contains("addresses: 杭州西湖区"))
    #expect(rendered.contains("person_id: person-duan-fuqiang"))
}

@Test func agentChatPromptContextRendersActivePersonMemoryItemsForMentionedPeople() {
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-chen"),
        displayName: "小陈",
        memoryEntityID: "person:person-profile:person-chen",
        memoryStableKey: "person-profile:person-chen"
    )
    let context = AgentChatPromptContext(
        userPrompt: "@小陈 最近在做什么？",
        explicitPersonContexts: [
            PersonContextSnapshot(
                profile: profile,
                activeMemoryItems: [
                    "小陈负责产品策略。",
                    "小陈喜欢冲浪。"
                ]
            )
        ]
    )

    let rendered = context.renderedPrompt

    #expect(rendered.contains("active person memory"))
    #expect(rendered.contains("archived/deleted/moved person memories are not active default context"))
    #expect(rendered.contains("- 小陈负责产品策略。"))
    #expect(rendered.contains("- 小陈喜欢冲浪。"))
}

@Test func agentChatPromptContextReturnsRawPromptWithoutSummaryOrRecentMessages() {
    let context = AgentChatPromptContext(userPrompt: "What next?")

    #expect(context.renderedPrompt == "What next?")
}

@Test func agentChatPromptContextRendersSessionSummary() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "We planned the next implementation phase.",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(userPrompt: "What next?", sessionSummary: summary)

    #expect(context.renderedPrompt.contains("Previous session summary:"))
    #expect(context.renderedPrompt.contains("We planned the next implementation phase."))
    #expect(context.renderedPrompt.contains("Current user request:"))
    #expect(context.renderedPrompt.contains("What next?"))
}

@Test func agentChatPromptContextRendersRecentConversation() {
    let context = AgentChatPromptContext(
        userPrompt: "What next?",
        recentMessages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer")
        ]
    )

    #expect(context.renderedPrompt.contains("Recent conversation:"))
    #expect(context.renderedPrompt.contains("User: Earlier question"))
    #expect(context.renderedPrompt.contains("Assistant: Earlier answer"))
    #expect(context.renderedPrompt.contains("Current user request:"))
    #expect(context.renderedPrompt.contains("What next?"))
}

@Test func agentChatPromptContextOrdersSummaryBeforeRecentConversationBeforeCurrentRequest() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Summary content",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(
        userPrompt: "What next?",
        sessionSummary: summary,
        recentMessages: [AgentMessage(id: "message-1", role: .user, content: "Earlier question")]
    )

    let rendered = context.renderedPrompt
    let summaryRange = rendered.range(of: "Previous session summary:")
    let recentRange = rendered.range(of: "Recent conversation:")
    let currentRange = rendered.range(of: "Current user request:")

    #expect(summaryRange != nil)
    #expect(recentRange != nil)
    #expect(currentRange != nil)
    #expect(summaryRange!.lowerBound < recentRange!.lowerBound)
    #expect(recentRange!.lowerBound < currentRange!.lowerBound)
}

@Test func agentChatPromptContextSkipsEmptySummaryContent() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "   \n  ",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(userPrompt: "What next?", sessionSummary: summary)

    #expect(!context.renderedPrompt.contains("Previous session summary:"))
    #expect(context.renderedPrompt == "What next?")
}
