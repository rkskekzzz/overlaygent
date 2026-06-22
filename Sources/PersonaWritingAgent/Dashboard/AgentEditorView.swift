import SwiftUI

struct AgentEditorView: View {
    @Binding var profile: AgentProfile

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $profile.name)
                TextField("Description", text: $profile.description, axis: .vertical)

                Toggle("Enabled", isOn: $profile.isEnabled)
                Toggle("Active in Menu", isOn: $profile.isActive)
            }

            Section("Instructions") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $profile.systemPrompt)
                        .frame(minHeight: 90)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("User Instruction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $profile.instruction)
                        .frame(minHeight: 120)
                }
            }

            Section("Behavior") {
                Picker("Tone", selection: $profile.tone) {
                    ForEach(TonePreset.allCases, id: \.self) { tone in
                        Text(tone.label).tag(tone)
                    }
                }

                Picker("Rewrite Aggressiveness", selection: $profile.aggressiveness) {
                    ForEach(RewriteAggressiveness.allCases, id: \.self) { aggressiveness in
                        Text(aggressiveness.label).tag(aggressiveness)
                    }
                }

                Picker("Scope", selection: $profile.scope) {
                    ForEach(CorrectionScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }

                Picker("Apply Mode", selection: $profile.applyMode) {
                    ForEach(ApplyMode.allCases, id: \.self) { applyMode in
                        Text(applyMode.label).tag(applyMode)
                    }
                }
            }

            Section("Provider") {
                TextField(
                    "Model Override",
                    text: Binding(
                        get: { profile.modelOverride ?? "" },
                        set: { profile.modelOverride = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    )
                )

                Text(profile.providerID.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Terminology") {
                if profile.terminologyRules.isEmpty {
                    Text("No terminology rules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.terminologyRules) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(rule.match) -> \(rule.replacement)")
                                .font(.body)
                            if let note = rule.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension TonePreset {
    var label: String {
        switch self {
        case .neutral:
            "Neutral"
        case .natural:
            "Natural"
        case .friendly:
            "Friendly"
        case .professional:
            "Professional"
        case .polite:
            "Polite"
        case .technical:
            "Technical"
        }
    }
}

private extension RewriteAggressiveness {
    var label: String {
        switch self {
        case .minimal:
            "Minimal"
        case .conservative:
            "Conservative"
        case .balanced:
            "Balanced"
        case .assertive:
            "Assertive"
        }
    }
}

private extension CorrectionScope {
    var label: String {
        switch self {
        case .selectedText:
            "Selected Text"
        case .currentInput:
            "Current Input"
        case .currentParagraph:
            "Current Paragraph"
        }
    }
}

private extension ApplyMode {
    var label: String {
        switch self {
        case .askEveryTime:
            "Ask Every Time"
        case .axSelectedText:
            "AX Selected Text"
        case .axValue:
            "AX Value"
        case .clipboardPaste:
            "Clipboard Paste"
        }
    }
}
