import AppKit
import SwiftUI

struct ZoomableImagePreview: View {
    let image: NSImage

    @State private var zoomScale = 1.0

    private let minimumZoom = 0.25
    private let maximumZoom = 4.0
    private let zoomStep = 0.25

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AgentChatLayout.spaceXS) {
                Spacer()
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoomScale <= minimumZoom)
                .help("缩小图片")
                .accessibilityLabel("缩小图片")

                Button(action: resetZoom) {
                    Image(systemName: "1.magnifyingglass")
                }
                .disabled(zoomScale == 1)
                .help("回到原始大小")
                .accessibilityLabel("回到原始大小")

                Text(zoomScale, format: .percent.precision(.fractionLength(0)))
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 42)

                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoomScale >= maximumZoom)
                .help("放大图片")
                .accessibilityLabel("放大图片")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, AgentChatLayout.spaceS)
            .frame(height: 34)
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
