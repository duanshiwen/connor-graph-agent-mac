import SwiftUI
import ConnorGraphAppSupport

struct MemoryOSDashboardView: View {
    var presentation: MemoryOSDashboardPresentation
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.title2.bold())
                    Text("L0-L4 production memory substrate · health: \(presentation.healthLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") { onRefresh() }
            }

            if !presentation.operationalWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.operationalWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(presentation.layerRows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.label)
                            .font(.headline)
                        Text(row.primaryMetric)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Text("Memory OS 已替代旧 staging / distillation / candidate review 作为新生产主入口。旧 Graph Memory 诊断页面仅作为迁移期内部兼容面，后续删除。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppShellColors.detailBackground)
    }
}
