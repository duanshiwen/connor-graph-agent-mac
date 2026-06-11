import SwiftUI
import ConnorGraphAppSupport

struct ConnorRuntimeCenterView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: ConnorRuntimeCenterPresentation {
        viewModel.runtimeCenterPresentation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RuntimeHeroCard(hero: presentation.hero)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 12)], spacing: 12) {
                    ForEach(presentation.metricTiles) { tile in
                        RuntimeMetricTileView(tile: tile) { target in
                            viewModel.navigate(to: target)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(presentation.sections) { section in
                        RuntimeSectionCard(section: section) { target in
                            viewModel.navigate(to: target)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
        .navigationTitle("运行中心")
        .toolbar {
            Button("刷新") {
                viewModel.reloadChatSessions()
                viewModel.reloadPendingApprovals()
                viewModel.reloadGraphWriteCandidates()
                viewModel.reloadGraphExtractionTraces()
                viewModel.reloadMemoryChangeLog()
            }
        }
        .onAppear {
            viewModel.reloadChatSessions()
            viewModel.reloadPendingApprovals()
            viewModel.reloadGraphWriteCandidates()
            viewModel.reloadGraphExtractionTraces()
            viewModel.reloadMemoryChangeLog()
        }
    }
}

private struct RuntimeHeroCard: View {
    var hero: ConnorRuntimeCenterHero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(hero.title)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)
                    Text(hero.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(hero.statusText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.14), in: Capsule())
                    Text(hero.updatedText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text("Connor-owned runtime cockpit: sessions, approvals, automation, graph memory, and events stay governed in one native macOS surface.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RuntimeMetricTileView: View {
    var tile: ConnorRuntimeMetricTile
    var onNavigate: (ConnorNativeShellItem) -> Void

    var body: some View {
        Button(action: { if let target = tile.target { onNavigate(target) } }) {
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color(for: tile.severity))
                    .frame(width: 8, height: 8)
                Text(tile.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(tile.value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Text(tile.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(tile.target == nil)
    }
}

private struct RuntimeSectionCard: View {
    var section: ConnorRuntimeCenterSection
    var onNavigate: (ConnorNativeShellItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { if let target = section.target { onNavigate(target) } }) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline)
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(section.target == nil)

            if section.items.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(section.items.prefix(5)) { item in
                        RuntimeCenterRow(item: item) { target in
                            onNavigate(target)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RuntimeCenterRow: View {
    var item: ConnorRuntimeCenterItem
    var onNavigate: (ConnorNativeShellItem) -> Void

    var body: some View {
        Button(action: { if let target = item.target { onNavigate(target) } }) {
            HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: item.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
            .padding(10)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(item.target == nil)
    }
}

private func color(for severity: AgentEventPresentationSeverity) -> Color {
    switch severity {
    case .info: .blue
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
}
