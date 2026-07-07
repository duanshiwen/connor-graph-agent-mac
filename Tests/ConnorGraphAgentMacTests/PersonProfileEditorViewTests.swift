import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
struct PersonProfileEditorViewTests {
    @Test func presentationUsesCreateTitleForNewDraft() {
        let draft = PersonProfileDraft(displayName: "张霞")

        let presentation = PersonProfileEditorPresentation(draft: draft)

        #expect(presentation.isEditing == false)
        #expect(presentation.title == "新建人物")
        #expect(presentation.subtitle.contains("Person Registry"))
        #expect(presentation.canSave == true)
        #expect(presentation.footerHint == "按 ⏎ 保存，按 Esc 取消。")
        #expect(presentation.closeAccessibilityLabel == "关闭新建人物表单")
        #expect(presentation.cancelAccessibilityLabel == "取消新建人物")
        #expect(presentation.saveAccessibilityLabel == "保存新建人物")
        #expect(presentation.saveHelp == "保存人物档案")
    }

    @Test func presentationUsesEditTitleForExistingDraft() {
        let draft = PersonProfileDraft(
            id: ContactID(rawValue: "person-zhang-xia"),
            displayName: "张霞"
        )

        let presentation = PersonProfileEditorPresentation(draft: draft)

        #expect(presentation.isEditing == true)
        #expect(presentation.title == "编辑人物")
        #expect(presentation.closeAccessibilityLabel == "关闭编辑人物表单")
        #expect(presentation.cancelAccessibilityLabel == "取消编辑人物")
        #expect(presentation.saveAccessibilityLabel == "保存人物修改")
    }

    @Test func presentationDisablesSaveWhenDisplayNameIsBlank() {
        let draft = PersonProfileDraft(displayName: "  \n\t  ")

        let presentation = PersonProfileEditorPresentation(draft: draft)

        #expect(presentation.canSave == false)
        #expect(presentation.footerHint == "请输入显示名后保存。")
        #expect(presentation.saveHelp == "请输入显示名后才能保存")
    }

    @Test func aliasFormattingTrimsAndSkipsEmptyAliases() {
        let aliases = PersonProfileEditorDraftFormatting.parseAliases(" 妈妈, , 张阿姨,\n霞姐 ")

        #expect(aliases == ["妈妈", "张阿姨", "霞姐"])
    }

    @Test func aliasFormattingJoinsAliasesWithReadableSeparator() {
        let text = PersonProfileEditorDraftFormatting.aliasesText(["妈妈", "张阿姨"])

        #expect(text == "妈妈, 张阿姨")
    }
}
