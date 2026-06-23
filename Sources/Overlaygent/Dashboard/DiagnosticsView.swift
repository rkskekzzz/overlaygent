import SwiftUI

struct DiagnosticsViewModel: Equatable {
    var summary: AppCompatibilityDiagnosticsSummary

    init(registry: AppCompatibilityRegistry = .defaultRegistry) {
        self.summary = registry.diagnosticsSummary()
    }

    var registrySummaryText: String {
        "\(summary.knownAppCount) known apps - \(summary.visibleContextAdapterCount) visible context adapters"
    }
}

struct DiagnosticsView: View {
    let viewModel: DiagnosticsViewModel

    init(viewModel: DiagnosticsViewModel = DiagnosticsViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.summary.rows) { row in
                        appCompatibilityRow(row)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.title)
                .fontWeight(.semibold)

            Text(viewModel.registrySummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func appCompatibilityRow(_ row: AppCompatibilityDiagnosticsRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(.headline)

                Text(row.bundleIDs.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(row.capabilities) { capability in
                    capabilityBadge(capability)
                }
            }

            if row.notes.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(row.notes) { note in
                        Label(note.message, systemImage: note.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func capabilityBadge(_ summary: AppCompatibilityCapabilitySummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: summary.support))
                .foregroundStyle(color(for: summary.support))

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.capability.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(summary.support.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconName(for support: AppCompatibilitySupport) -> String {
        switch support {
        case .supported:
            "checkmark.circle.fill"
        case .limited:
            "exclamationmark.circle.fill"
        case .required:
            "bolt.circle.fill"
        case .unsupported:
            "xmark.circle.fill"
        }
    }

    private func color(for support: AppCompatibilitySupport) -> Color {
        switch support {
        case .supported:
            .green
        case .limited:
            .orange
        case .required:
            .blue
        case .unsupported:
            .secondary
        }
    }
}
