import SwiftUI
import ConnorGraphAppSupport

struct ConnorCommandPaletteView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var query = ""

    private var palette: ConnorCommandPalettePresentation {
        ConnorCommandPalettePresentation.build(shell: ConnorNativeShellPresentation.default)
    }

    private var results: [ConnorCommandPaletteEntry] {
        palette.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Search commands and destinations", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                Button(action: { viewModel.isCommandPalettePresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(results.prefix(12)) { entry in
                        Button(action: { activate(entry) }) {
                            HStack(spacing: 12) {
                                Image(systemName: entry.systemImage)
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let shortcut = entry.keyboardShortcut {
                                    Text(shortcut)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }

    private func activate(_ entry: ConnorCommandPaletteEntry) {
        if entry.kind == .command,
           let command = ConnorNativeShellPresentation.default.commands.first(where: { $0.target == entry.target && $0.title == entry.title }) {
            viewModel.performShellCommand(command.id)
        } else {
            viewModel.navigate(to: entry.target)
        }
        viewModel.isCommandPalettePresented = false
    }
}
