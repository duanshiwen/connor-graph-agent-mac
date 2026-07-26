import ConnorGraphAgentMac
import ConnorGraphCore
import Testing

@Suite("Person profile editor presentation tests")
struct PersonProfileEditorPresentationTests {
    @Test("new drafts use relationship-aware person profile copy")
    func newDraftUsesRelationshipAwarePersonProfileCopy() {
        let presentation = PersonProfileEditorPresentation(draft: PersonProfileDraft(displayName: ""))

        #expect(presentation.title == "新建人物档案")
        #expect(presentation.saveButtonTitle == "保存人物档案")
        #expect(presentation.subtitle.contains("人际关系"))
        #expect(presentation.subtitle.contains("@人物"))
        #expect(presentation.subtitle.contains("联系方式后补充"))
    }

    @Test("existing drafts use edit title")
    func existingDraftsUseEditTitle() {
        let presentation = PersonProfileEditorPresentation(
            draft: PersonProfileDraft(id: ContactID(rawValue: "person-1"), displayName: "诗闻")
        )

        #expect(presentation.title == "编辑人物档案")
    }

    @Test("display name controls save availability")
    func displayNameControlsSaveAvailability() {
        #expect(!PersonProfileEditorPresentation(draft: PersonProfileDraft(displayName: "")).canSave)
        #expect(!PersonProfileEditorPresentation(draft: PersonProfileDraft(displayName: "   \n  ")).canSave)
        #expect(PersonProfileEditorPresentation(draft: PersonProfileDraft(displayName: "诗闻")).canSave)
    }

    @Test("required display name hint explains mention usage")
    func requiredDisplayNameHintExplainsMentionUsage() {
        let presentation = PersonProfileEditorPresentation(draft: PersonProfileDraft(displayName: ""))

        #expect(presentation.displayNameHint.contains("必填"))
        #expect(presentation.displayNameHint.contains("@人物提及"))
    }
}
