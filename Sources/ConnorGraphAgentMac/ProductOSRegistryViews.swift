import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct ProductOSRegistryView: View {
    @Bindable var model: ProductOSControlFeatureModel
    var governanceConfig: AppSessionGovernanceConfig
    var commercialReadinessDashboard: CommercialReadinessDashboard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Product OS Registry")
                            .font(.largeTitle.bold())
                        Text("Phase 5 将 Automation / Labels / Statuses 纳入康纳同学控制平面：自动化只能记录和建议，不能绕过权限、审计和图谱准入。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新加载") {
                        model.reloadRegistry()
                        model.reloadAutomation(governanceConfig: governanceConfig)
                    }
                }

                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProductOSRegistrySummary(snapshot: model.registry, automationConfig: model.automationConfig, triggerRecords: model.automationTriggerRecords)

                CommercialReadinessProductOSSection(
                    dashboard: commercialReadinessDashboard,
                    releaseGateResult: model.commercialReleaseGateResult,
                    onCheck: { model.runCommercialReadinessReleaseGate(dashboard: commercialReadinessDashboard) }
                )

                GroupBox("Statuses") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(governanceConfig.statuses) { status in
                            HStack {
                                Label(status.name, systemImage: status.systemImage)
                                Spacer()
                                ProductOSRegistryChip("id: \(status.id)")
                                ProductOSRegistryChip(status.isTerminal ? "terminal" : "open")
                                ProductOSRegistryChip("sort: \(status.sortOrder)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Labels") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(governanceConfig.labels) { label in
                            HStack {
                                Text(label.name).font(.headline)
                                Text(label.id).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                ProductOSRegistryChip(label.colorName)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Automations") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.automationConfig.rules) { rule in
                            ProductOSAutomationRuleRow(rule: rule) { enabled in
                                model.setAutomationRuleEnabled(id: rule.id, isEnabled: enabled, governanceConfig: governanceConfig)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Automation Trigger Log") {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.automationTriggerRecords.isEmpty {
                            Text("暂无触发记录。状态/标签/Source/Skill 变更后会在这里留下可审计记录。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.automationTriggerRecords.prefix(8)) { record in
                                ProductOSAutomationRecordRow(record: record)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Sources") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.registry.sources) { source in
                            ProductOSSourceRow(source: source) { status in
                                model.setSourceRegistryStatus(id: source.id, status: status)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Skills") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.registry.skills) { skill in
                            ProductOSSkillRow(skill: skill) { status in
                                model.setSkillRegistryStatus(id: skill.id, status: status)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Phase 5 Guardrails") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Single Home Root: no multi-workspace abstraction is introduced.", systemImage: "house")
                        Label("数据源凭据和连接器执行仍由康纳同学治理。", systemImage: "lock.shield")
                        Label("Skills are instruction profiles; they cannot bypass Memory OS projection gates or audit.", systemImage: "checkmark.seal")
                        Label("Memory OS stays a kernel, not a normal RAG/source plugin.", systemImage: "brain.head.profile")
                        Label("Automation execution is audit-first: actions are recorded for review before becoming background execution.", systemImage: "bolt.badge.clock")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

struct CommercialReadinessProductOSSection: View {
    var dashboard: CommercialReadinessDashboard
    var releaseGateResult: CommercialReadinessReleaseGateResult?
    var onCheck: () -> Void

    var body: some View {
        GroupBox("Commercial Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dashboard.summary)
                            .font(.headline)
                        if let releaseGateResult {
                            Text(releaseGateResult.summary)
                                .font(.caption)
                                .foregroundStyle(releaseGateResult.status == .ready ? .green : .orange)
                        } else {
                            Text("Run the release gate to verify whether this build is commercial-ready.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Check Commercial Readiness", action: onCheck)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(dashboard.cards) { card in
                        CommercialReadinessProductOSCard(card: card)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct CommercialReadinessProductOSCard: View {
    var card: CommercialReadinessCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.headline)
                Spacer()
                ProductOSRegistryChip(card.status.rawValue)
            }
            Text(card.evidence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !card.metrics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.metrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        ProductOSRegistryChip("\(key): \(value)")
                    }
                }
            }
            if !card.blockingReasons.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(card.blockingReasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card.status == .ready ? Color.green.opacity(0.08) : Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductOSRegistrySummary: View {
    var snapshot: ProductOSRegistrySnapshot
    var automationConfig: ProductOSAutomationConfig
    var triggerRecords: [ProductOSAutomationTriggerRecord]

    var body: some View {
        HStack(spacing: 12) {
            ProductOSMetricCard(title: "Sources", value: "\(snapshot.sources.count)", detail: "\(snapshot.sources.filter { $0.status == .enabled }.count) enabled")
            ProductOSMetricCard(title: "Skills", value: "\(snapshot.skills.count)", detail: "\(snapshot.skills.filter { $0.status == .enabled }.count) enabled")
            ProductOSMetricCard(title: "Automations", value: "\(automationConfig.rules.count)", detail: "\(automationConfig.rules.filter(\.isEnabled).count) enabled")
            ProductOSMetricCard(title: "Triggers", value: "\(triggerRecords.count)", detail: "recent audit log")
        }
    }
}

struct ProductOSMetricCard: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductOSAutomationRuleRow: View {
    var rule: ProductOSAutomationRule
    var onEnabledChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).font(.headline)
                    Text(rule.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { newValue in
                            Task { @MainActor in
                                await Task.yield()
                                onEnabledChange(newValue)
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip("trigger: \(rule.trigger.kind.rawValue)")
                if let status = rule.trigger.status { ProductOSRegistryChip("status: \(status.rawValue)") }
                if let labelID = rule.trigger.labelID { ProductOSRegistryChip("label: \(labelID)") }
                ProductOSRegistryChip(rule.requiresReview ? "review required" : "audit only")
            }
            ForEach(rule.actions) { action in
                Text("• \(action.kind.rawValue): \(action.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProductOSAutomationRecordRow: View {
    var record: ProductOSAutomationTriggerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.ruleName).font(.headline)
                Spacer()
                ProductOSRegistryChip(record.trigger.rawValue)
            }
            Text("Session: \(record.sessionID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(record.actionSummaries, id: \.self) { summary in
                Text("• \(summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductOSSourceRow: View {
    var source: ProductOSSourceDefinition
    var onStatusChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.displayName).font(.headline)
                    Text(source.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ProductOSRegistryStatusPicker(status: source.status, onChange: onStatusChange)
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip(source.kind.rawValue)
                ProductOSRegistryChip(source.credentialRequirement.rawValue)
                ProductOSRegistryChip("graph: \(source.graphIngestionEnabled ? "on" : "off")")
                ProductOSRegistryChip("write: \(source.graphWritePolicy.rawValue)")
            }
            Text(source.notes).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProductOSSkillRow: View {
    var skill: ProductOSSkillDefinition
    var onStatusChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.displayName).font(.headline)
                    Text(skill.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ProductOSRegistryStatusPicker(status: skill.status, onChange: onStatusChange)
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip(skill.scope.rawValue)
                ProductOSRegistryChip("triggers: \(skill.triggers.map(\.rawValue).joined(separator: ", "))")
                ProductOSRegistryChip("graph: \(skill.graphContextPolicy.rawValue)")
            }
            Text(skill.notes).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProductOSRegistryStatusPicker: View {
    var status: ProductOSRegistryEntryStatus
    var onChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        Picker(
            "Status",
            selection: Binding(
                get: { status },
                set: { newValue in
                    Task { @MainActor in
                        await Task.yield()
                        onChange(newValue)
                    }
                }
            )
        ) {
            ForEach(ProductOSRegistryEntryStatus.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }
}

struct ProductOSRegistryChip: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
