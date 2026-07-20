import AppKit
import PDFKit
import QuickLookUI
import SwiftUI

struct NativeFilePDFPreview: NSViewRepresentable {
    var fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: fileURL)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != fileURL {
            nsView.document = PDFDocument(url: fileURL)
        }
        nsView.autoScales = true
        nsView.displayMode = .singlePageContinuous
        nsView.displayDirection = .vertical
    }
}

struct NativeFileQuickLookPreview: NSViewRepresentable {
    var fileURL: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        if let previewView = QLPreviewView(frame: .zero, style: .normal) {
            previewView.autostarts = true
            previewView.shouldCloseWithWindow = false
            previewView.previewItem = fileURL as NSURL
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)
            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            let fallbackLabel = NSTextField(labelWithString: "当前无法使用 Quick Look 预览这个文件。")
            fallbackLabel.textColor = .secondaryLabelColor
            fallbackLabel.alignment = .center
            fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(fallbackLabel)
            NSLayoutConstraint.activate([
                fallbackLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                fallbackLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                fallbackLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
                fallbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
            ])
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewView = nsView.subviews.compactMap({ $0 as? QLPreviewView }).first else { return }
        previewView.previewItem = fileURL as NSURL
        previewView.refreshPreviewItem()
    }
}
