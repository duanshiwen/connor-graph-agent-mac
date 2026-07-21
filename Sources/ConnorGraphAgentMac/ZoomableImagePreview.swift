import AppKit
import SwiftUI

enum ZoomableImagePreviewControlPresentation {
    static let zoomOutSystemImage = "minus"
    static let zoomInSystemImage = "plus"
    static let resetSystemImage = "arrow.counterclockwise"
}

struct ZoomableImagePreview: View {
    let image: NSImage

    @State private var zoomScale = 1.0

    private let minimumZoom = 0.25
    private let maximumZoom = 4.0
    private let zoomStep = 0.25

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AgentChatLayout.spaceS) {
                Spacer()

                HStack(spacing: 0) {
                    zoomButton(
                        systemImage: ZoomableImagePreviewControlPresentation.zoomOutSystemImage,
                        help: "缩小图片",
                        isDisabled: zoomScale <= minimumZoom,
                        action: zoomOut
                    )

                    Divider()
                        .frame(height: 16)

                    Text(zoomScale, format: .percent.precision(.fractionLength(0)))
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, height: 28)
                        .accessibilityLabel("当前缩放比例")
                        .accessibilityValue(Text(zoomScale, format: .percent.precision(.fractionLength(0))))

                    Divider()
                        .frame(height: 16)

                    zoomButton(
                        systemImage: ZoomableImagePreviewControlPresentation.zoomInSystemImage,
                        help: "放大图片",
                        isDisabled: zoomScale >= maximumZoom,
                        action: zoomIn
                    )
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )

                Divider()
                    .frame(height: 18)

                Button(action: resetZoom) {
                    Image(systemName: ZoomableImagePreviewControlPresentation.resetSystemImage)
                        .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(zoomScale == 1)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .help("回到原始大小")
                .accessibilityLabel("回到原始大小")
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .frame(height: 40)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: max(1, image.size.width * zoomScale),
                        height: max(1, image.size.height * zoomScale)
                    )
                    .padding(AgentChatLayout.spaceM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func zoomButton(
        systemImage: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func zoomIn() {
        zoomScale = min(maximumZoom, zoomScale + zoomStep)
    }

    private func zoomOut() {
        zoomScale = max(minimumZoom, zoomScale - zoomStep)
    }

    private func resetZoom() {
        zoomScale = 1
    }
}
