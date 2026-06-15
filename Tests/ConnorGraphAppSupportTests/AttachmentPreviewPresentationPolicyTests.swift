import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

struct AttachmentPreviewPresentationPolicyTests {
    @Test func pdfUsesPDFKitNativeRendererForContinuousMultipagePreview() {
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .pdf, hasOriginalFileURL: true) == .pdfKit)
    }

    @Test func officeAndImagesUseQuickLookNativeRenderer() {
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .document, hasOriginalFileURL: true) == .quickLook)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .spreadsheet, hasOriginalFileURL: true) == .quickLook)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .presentation, hasOriginalFileURL: true) == .quickLook)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .image, hasOriginalFileURL: true) == .quickLook)
    }

    @Test func textKindsDoNotUseNativeOriginalFileRenderer() {
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .markdown, hasOriginalFileURL: true) == .none)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .text, hasOriginalFileURL: true) == .none)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .json, hasOriginalFileURL: true) == .none)
    }

    @Test func missingOriginalFileDisablesNativeRenderer() {
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .pdf, hasOriginalFileURL: false) == .none)
        #expect(AttachmentPreviewPresentationPolicy.nativeRenderer(for: .document, hasOriginalFileURL: false) == .none)
    }
}
