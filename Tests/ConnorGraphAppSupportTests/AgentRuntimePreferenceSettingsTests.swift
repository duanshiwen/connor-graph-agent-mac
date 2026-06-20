import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Agent Runtime Preference Settings Tests")
struct AgentRuntimePreferenceSettingsTests {
    @Test func inputSettingsDefaultSessionSpeechTranscriptionEnabled() {
        let input = AgentRuntimeInputSettings()

        #expect(input.sessionSpeechTranscriptionEnabled)
    }

    @Test func decodesLegacyInputSettingsWithSessionSpeechTranscriptionEnabledByDefault() throws {
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
        #expect(input.sessionSpeechTranscriptionEnabled)
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
        #expect(preferences.notes.isEmpty)
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
        #expect(preferences.notes == "Prefers concise answers.")
    }

    @Test func fillsEmptyPreferenceFieldsFromSystemDefaultsWithoutOverwritingUserValues() {
        var preferences = AgentRuntimePreferenceSettings(
            displayName: "Alex",
            timezone: "",
            preferredLanguage: "",
            city: "London",
            country: "",
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
        #expect(preferences.notes == "Prefers concise answers.")
    }

    @Test func fillEmptyPreferenceFieldsReportsNoChangeWhenEverythingRelevantExists() {
        var preferences = AgentRuntimePreferenceSettings(
            displayName: "Alex",
            timezone: "Europe/London",
            preferredLanguage: "English",
            city: "London",
            country: "United Kingdom",
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
    }

    @Test func promptBuilderIncludesOnlyFilledUserBasicInfo() {
        let preferences = AgentRuntimePreferenceSettings(
            displayName: "诗闻",
            timezone: "Asia/Shanghai",
            preferredLanguage: "简体中文",
            city: "杭州",
            country: "中国",
            notes: "数学公式使用块级 LaTeX。"
        )

        let prompt = UserBasicInfoPromptBuilder(preferences: preferences).promptSection

        #expect(prompt.contains("## 用户基本信息"))
        #expect(prompt.contains("- 称呼：诗闻"))
        #expect(prompt.contains("- 时区：Asia/Shanghai"))
        #expect(prompt.contains("- 语言偏好：简体中文"))
        #expect(prompt.contains("- 城市：杭州"))
        #expect(prompt.contains("- 国家/地区：中国"))
        #expect(prompt.contains("- 备注：数学公式使用块级 LaTeX。"))
    }
}
