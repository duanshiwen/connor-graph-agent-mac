import Foundation
import CoreGraphics

struct ComposerTextInputConfiguration {
    var sendShortcut: String
    var isSkillPickerPresented: Bool
    var onSubmit: () -> Void
    var onImportFiles: ([URL]) -> Void
    var onSlashCommand: ((CGRect, NSRange) -> Void)?
    var onSkillPickerKeyCommand: ((SkillPickerKeyCommand) -> Void)?
    var onAttachmentImportError: ((String) -> Void)?
    var onTextFileDropped: ((String) -> Void)?
    var isNoteMode: Bool = false

    static func empty() -> ComposerTextInputConfiguration {
        ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: nil,
            onAttachmentImportError: nil,
            onTextFileDropped: nil,
            isNoteMode: false
        )
    }
}
