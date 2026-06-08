import SwiftUI

@main
struct ConnorGraphAgentMacApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
    }
}

struct AppShellView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Graph")
                Text("Observe Log")
                Text("Agent")
            }
            .navigationTitle("Connor")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connor Graph Agent")
                    .font(.largeTitle)
                Text("Local graph store is the runtime knowledge source of truth.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
