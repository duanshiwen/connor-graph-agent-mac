import Foundation
import CoreGraphics

struct ComposerTextInputConfiguration {
    var sendShortcut: String
    var isSkillPickerPresented: Bool
    var isPersonMentionPickerPresented: Bool = false
    var onSubmit: () -> Void
    var onImportFiles: ([URL]) -> Void
    var onSlashCommand: ((CGRect, NSRange) -> Void)?
    var onSkillPickerKeyCommand: ((SkillPickerKeyCommand) -> Void)?
    var onPersonMentionPickerKeyCommand: ((SkillPickerKeyCommand) -> Void)? = nil
    var onAttachmentImportError: ((String) -> Void)?
    var onTextFileDropped: ((String) -> Void)?
    var isNoteMode: Bool = false

    static func empty() -> ComposerTextInputConfiguration {
        ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            isPersonMentionPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: nil,
            onPersonMentionPickerKeyCommand: nil,
            onAttachmentImportError: nil,
            onTextFileDropped: nil,
            isNoteMode: false
        )
    }
}
