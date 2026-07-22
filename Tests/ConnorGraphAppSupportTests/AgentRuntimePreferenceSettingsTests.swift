import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Agent Runtime Preference Settings Tests")
struct AgentRuntimePreferenceSettingsTests {
    @Test func inputSettingsDefaultSessionSpeechTranscriptionDisabled() {
        let input = AgentRuntimeInputSettings()

        #expect(!input.sessionSpeechTranscriptionEnabled)
    }

    @Test func decodesLegacyInputSettingsWithSessionSpeechTranscriptionDisabledByDefault() throws {
        let data = Data("""
        {
          "composerSendShortcut": "cmd-return",
          "spellCheckEnabled": false,
          "autoSaveDraftsEnabled": false
        }
        """.utf8)

        let input = try JSONDecoder().decode(AgentRuntimeInputSettings.self, from: data)

        #expect(input.composerSendShortcut == "cmd-return")
        #expect(!input.spellCheckEnabled)
        #expect(!input.autoSaveDraftsEnabled)
        #expect(!input.sessionSpeechTranscriptionEnabled)
    }

    @Test func decodesExplicitlyDisabledSessionSpeechTranscription() throws {
        let data = Data("""
        {
          "composerSendShortcut": "return",
          "spellCheckEnabled": true,
          "autoSaveDraftsEnabled": true,
          "sessionSpeechTranscriptionEnabled": false
        }
        """.utf8)

        let input = try JSONDecoder().decode(AgentRuntimeInputSettings.self, from: data)

        #expect(!input.sessionSpeechTranscriptionEnabled)
    }

    @Test func defaultsAreEmptyUntilSystemOrUserFillsThem() {
        let preferences = AgentRuntimePreferenceSettings()

        #expect(preferences.displayName.isEmpty)
        #expect(preferences.timezone.isEmpty)
        #expect(preferences.preferredLanguage.isEmpty)
        #expect(preferences.city.isEmpty)
        #expect(preferences.country.isEmpty)
        #expect(preferences.genderIdentity.isEmpty)
        #expect(preferences.birthDate.isEmpty)
        #expect(preferences.notes.isEmpty)
        #expect(preferences.defaultSearchEngine == .bing)
        #expect(preferences.connorPersonality.isEmpty)
    }

    @Test func decodesLegacyPreferencesWithoutDefaultSearchEngineAsBing() throws {
        let data = Data("""
        {
          "displayName": "Alex",
          "timezone": "Europe/London",
          "preferredLanguage": "English",
          "city": "London",
          "country": "United Kingdom",
          "notes": "Prefers concise answers."
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(preferences.defaultSearchEngine == .bing)
        #expect(preferences.connorPersonality.isEmpty)
    }

    @Test func personalitySettingsRoundTripAndNormalizeGeneratedValues() throws {
        let personality = try ConnorPersonalitySettings(
            summary: "  温和但直接，重视事实。  ",
            traits: ["可靠", "", "可靠", "有耐心"],
            communicationStyle: "  先给结论， 再说明依据。 ",
            boundaries: ["不为了迎合用户而编造事实"]
        ).validated()
        let preferences = AgentRuntimePreferenceSettings(connorPersonality: personality)

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(decoded.connorPersonality.summary == "温和但直接，重视事实。")
        #expect(decoded.connorPersonality.traits == ["可靠", "有耐心"])
        #expect(decoded.connorPersonality.communicationStyle == "先给结论， 再说明依据。")
    }

    @Test func personalityGeneratorRejectsIdentityAndUnknownFields() throws {
        let json = """
        {
          "summary": "沉稳",
          "traits": ["可靠"],
          "communicationStyle": "简洁",
          "reasoningStyle": "严谨",
          "initiativeStyle": "主动",
          "emotionalTone": "温和",
          "boundaries": [],
          "name": "别的名字"
        }
        """

        #expect(throws: ConnorPersonalityError.unexpectedField("name")) {
            try ConnorPersonalityGenerator().decode(json)
        }
    }

    @Test func personalityPromptLocksNameAndGuidesConversationStyle() throws {
        let personality = ConnorPersonalitySettings(
            summary: "温和、直接并关注行动",
            traits: ["可靠", "坦诚"],
            communicationStyle: "先给结论，再给依据"
        )

        let prompt = ConnorPersonalityPromptBuilder(personality: personality).promptSection

        #expect(prompt.contains("## 康纳同学性格设置"))
        #expect(prompt.contains("姓名固定为“康纳同学”"))
        #expect(prompt.contains("持续以以下人格与用户对话"))
        #expect(prompt.contains("用户最新明确任务"))
        #expect(prompt.contains("- 沟通方式：先给结论，再给依据"))
    }

    @Test func emptyPersonalityDoesNotAddRuntimePrompt() {
        #expect(ConnorPersonalityPromptBuilder(personality: .empty).promptSection.isEmpty)
    }

    @Test func personalityGenerationPromptIsDedicatedAndLocksIdentity() {
        let prompt = ConnorPersonalityGenerationPrompt.systemInstruction

        #expect(prompt.contains("性格配置生成器"))
        #expect(prompt.contains("必须始终严格保持为“康纳同学”"))
        #expect(prompt.contains("只输出一个 JSON 对象"))
        #expect(prompt.contains("不能压过用户当前明确任务"))
    }

    @Test func decodesExplicitDefaultSearchEngine() throws {
        let data = Data("""
        {
          "defaultSearchEngine": "duckDuckGo"
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(preferences.defaultSearchEngine == .duckDuckGo)
    }

    @Test func decodesLegacyPreferencesWithoutLanguage() throws {
        let data = Data("""
        {
          "displayName": "Alex",
          "timezone": "Europe/London",
          "city": "London",
          "country": "United Kingdom",
          "notes": "Prefers concise answers."
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(preferences.displayName == "Alex")
        #expect(preferences.timezone == "Europe/London")
        #expect(preferences.preferredLanguage == "")
        #expect(preferences.city == "London")
        #expect(preferences.country == "United Kingdom")
        #expect(preferences.genderIdentity == "")
        #expect(preferences.birthDate == "")
        #expect(preferences.notes == "Prefers concise answers.")
    }

    @Test func decodesGenderIdentityAndBirthDateWhenPresent() throws {
        let data = Data("""
        {
          "displayName": "Alex",
          "timezone": "Europe/London",
          "preferredLanguage": "English",
          "city": "London",
          "country": "United Kingdom",
          "genderIdentity": "非二元",
          "birthDate": "1990-01-01",
          "notes": "Prefers concise answers."
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(preferences.genderIdentity == "非二元")
        #expect(preferences.birthDate == "1990-01-01")
    }

    @Test func fillsEmptyPreferenceFieldsFromSystemDefaultsWithoutOverwritingUserValues() {
        var preferences = AgentRuntimePreferenceSettings(
            displayName: "Alex",
            timezone: "",
            preferredLanguage: "",
            city: "London",
            country: "",
            birthDate: "1990-01-01",
            notes: "Prefers concise answers."
        )

        let didChange = preferences.fillEmptyFields(from: AgentRuntimePreferenceSystemDefaults(
            displayName: "System User",
            timezone: "Europe/London",
            preferredLanguage: "English",
            country: "United Kingdom"
        ))

        #expect(didChange)
        #expect(preferences.displayName == "Alex")
        #expect(preferences.timezone == "Europe/London")
        #expect(preferences.preferredLanguage == "English")
        #expect(preferences.city == "London")
        #expect(preferences.country == "United Kingdom")
        #expect(preferences.birthDate == "1990-01-01")
        #expect(preferences.notes == "Prefers concise answers.")
    }

    @Test func fillEmptyPreferenceFieldsReportsNoChangeWhenEverythingRelevantExists() {
        var preferences = AgentRuntimePreferenceSettings(
            displayName: "Alex",
            timezone: "Europe/London",
            preferredLanguage: "English",
            city: "London",
            country: "United Kingdom",
            birthDate: "1990-01-01",
            notes: "Prefers concise answers."
        )

        let didChange = preferences.fillEmptyFields(from: AgentRuntimePreferenceSystemDefaults(
            displayName: "System User",
            timezone: "Asia/Shanghai",
            preferredLanguage: "简体中文",
            country: "中国"
        ))

        #expect(!didChange)
        #expect(preferences.displayName == "Alex")
        #expect(preferences.timezone == "Europe/London")
        #expect(preferences.preferredLanguage == "English")
        #expect(preferences.country == "United Kingdom")
        #expect(preferences.birthDate == "1990-01-01")
    }

    @Test func promptBuilderIncludesOnlyFilledUserBasicInfo() {
        let preferences = AgentRuntimePreferenceSettings(
            displayName: "诗闻",
            timezone: "Asia/Shanghai",
            preferredLanguage: "简体中文",
            city: "杭州",
            country: "中国",
            genderIdentity: "非二元",
            birthDate: "1990-01-01",
            notes: "数学公式使用块级 LaTeX。"
        )

        let prompt = UserBasicInfoPromptBuilder(preferences: preferences).promptSection

        #expect(prompt.contains("## 用户基本信息"))
        #expect(prompt.contains("- 称呼：诗闻"))
        #expect(prompt.contains("- 时区：Asia/Shanghai"))
        #expect(prompt.contains("- 语言偏好：简体中文"))
        #expect(prompt.contains("- 性别：非二元"))
        #expect(prompt.contains("- 出生日期：1990-01-01"))
        #expect(prompt.range(of: "- 性别：非二元")!.lowerBound < prompt.range(of: "- 出生日期：1990-01-01")!.lowerBound)
        #expect(prompt.contains("- 城市：杭州"))
        #expect(prompt.contains("- 国家/地区：中国"))
        #expect(prompt.contains("- 备注：数学公式使用块级 LaTeX。"))
    }

    @Test func promptBuilderOmitsEmptyGenderAndBirthDate() {
        let preferences = AgentRuntimePreferenceSettings(displayName: "诗闻")

        let prompt = UserBasicInfoPromptBuilder(preferences: preferences).promptSection

        #expect(prompt.contains("- 称呼：诗闻"))
        #expect(!prompt.contains("性别"))
        #expect(!prompt.contains("出生日期"))
    }

    @Test func promptBuilderIncludesPreferNotToSayGenderWhenExplicitlyChosen() {
        let preferences = AgentRuntimePreferenceSettings(genderIdentity: "不愿透露")

        let prompt = UserBasicInfoPromptBuilder(preferences: preferences).promptSection

        #expect(prompt.contains("- 性别：不愿透露"))
    }
}
