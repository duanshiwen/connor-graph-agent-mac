import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct SidebarDisclosure<Content: View>: View {
    var title: String
    var systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(.leading, 12)
            .padding(.top, 3)
        } label: {
            Label(title, systemImage: systemImage)
                .font(AppListTypography.rowTitleSelected)
        }
        .disclosureGroupStyle(.automatic)
    }
}

struct SidebarRow: View {
    var title: String
    var systemImage: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    SidebarRowCountText(count: count, isVisible: isHovering)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityCountValue)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var accessibilityCountValue: String {
        count.map { "\($0)" } ?? ""
    }
}

struct SidebarRowCountText: View {
    var count: Int
    var isVisible: Bool

    var body: some View {
        Text("\(count)")
            .font(AppListTypography.rowCaption.monospacedDigit())
            .foregroundStyle(.secondary)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

struct SidebarMutedText: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(AppListTypography.rowSubtitle)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
