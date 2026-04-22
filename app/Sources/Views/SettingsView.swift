import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var captureInterval: String = "10"
    @State private var memoryWindow: String = "60"
    @State private var screenshotTTL: String = "30"
    @State private var showAddExclusion = false
    @State private var runningApps: [(String, String)] = []

    @State private var llmProvider: Provider = .anthropic
    @State private var llmModel: String = ""
    @State private var llmApiKey: String = ""
    @State private var llmBaseURL: String = ""
    @State private var llmSaved: Bool = false
    @State private var llmError: String?

    @State private var confirmClearMemories = false
    @State private var confirmClearAll = false
    @State private var lastClearSummary: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalSection
                Divider()
                llmSection
                Divider()
                claudeSection
                Divider()
                excludedAppsSection
                Divider()
                dangerSection
            }
            .padding(16)
        }
        .onAppear { loadSettings() }
    }

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LLM")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("Provider") {
                Picker("", selection: $llmProvider) {
                    ForEach(Provider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: llmProvider) { _, newProvider in
                    let env = Onboarding.readEnvFile()
                    llmApiKey = env.apiKeys[newProvider] ?? ""
                    llmBaseURL = newProvider == .openaiCompatible
                        ? (env.openaiCompatBaseURL.isEmpty ? newProvider.defaultBaseURL : env.openaiCompatBaseURL)
                        : newProvider.defaultBaseURL
                    if llmModel.isEmpty || !env.apiKeys.keys.contains(newProvider) {
                        llmModel = newProvider.defaultModel
                    }
                }
            }

            LabeledContent("Model") {
                TextField(llmProvider.defaultModel, text: $llmModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            if llmProvider == .openaiCompatible {
                LabeledContent("Base URL") {
                    TextField("https://api.example.com/v1", text: $llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                LabeledContent("API Key (optional)") {
                    SecureField("", text: $llmApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            } else if llmProvider.needsBaseURL {
                LabeledContent("Server URL") {
                    TextField(llmProvider.defaultBaseURL, text: $llmApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            } else {
                LabeledContent(llmProvider.apiKeyEnvVar) {
                    SecureField("", text: $llmApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }

            HStack {
                Button("Save LLM Settings") { saveLLM() }
                    .disabled(
                        (llmProvider.requiresApiKey && llmApiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        || (llmProvider == .openaiCompatible && llmBaseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    )
                if llmSaved {
                    Label("Saved — restart MCP to apply", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if let err = llmError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Text("Changes write to mcp/.env. Restart Claude Code (or the MCP server) to pick them up.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func saveLLM() {
        llmError = nil
        do {
            let model = llmModel.isEmpty ? nil : llmModel
            try Onboarding.writeEnvFile(
                provider: llmProvider,
                apiKey: llmApiKey,
                baseURL: llmBaseURL,
                model: model
            )
            llmSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { llmSaved = false }
        } catch {
            llmError = error.localizedDescription
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            captureField(
                title: "Capture interval",
                unit: "seconds",
                text: $captureInterval,
                help: "How often to take a screenshot when the active app changes. Lower = more responsive memory, but more CPU and OCR work. Captures are deduped when window title hasn't changed.",
                onSave: { saveSetting("capture_interval_sec", captureInterval) }
            )

            captureField(
                title: "Memory window",
                unit: "seconds",
                text: $memoryWindow,
                help: "How much activity is grouped into a single memory. Each window becomes one LLM-summarized memory card. Shorter windows = more granular, faster-appearing memories, but more LLM calls.",
                onSave: { saveSetting("memory_window_sec", memoryWindow) }
            )

            captureField(
                title: "Screenshot retention",
                unit: "minutes",
                text: $screenshotTTL,
                help: "How long to keep raw PNG screenshots on disk before auto-deletion. Memories (LLM summaries) are kept forever — only the raw images expire. Lower = smaller disk footprint; higher = ability to browse older captures in the UI.",
                onSave: { saveSetting("screenshot_ttl_minutes", screenshotTTL) }
            )
        }
    }

    private func captureField(title: String, unit: String, text: Binding<String>, help: String, onSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.callout)
                Spacer()
                TextField("", text: text)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text.wrappedValue) { _, _ in onSave() }
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(help)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("MCP integration enabled", isOn: Binding(
                get: { appState.claudeIntegrationEnabled },
                set: { _ in appState.toggleClaudeIntegration() }
            ))
            .font(.callout)

            Text("When enabled, Claude Code can retrieve your recent memories through the Chronicle MCP server.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var excludedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Excluded Apps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button("Add") { prepareAddExclusion() }
                    .font(.caption)
            }

            if appState.excludedApps.isEmpty {
                Text("No apps excluded. All allowed apps will be captured.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(appState.excludedApps) { app in
                    HStack {
                        Text(app.appName)
                            .font(.callout)
                        Spacer()
                        Button(role: .destructive) {
                            appState.removeExclusion(bundleId: app.bundleId)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .sheet(isPresented: $showAddExclusion) {
            addExclusionSheet
        }
    }

    private var addExclusionSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select app to exclude")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(runningApps, id: \.0) { (bundleId, name) in
                        Button(action: {
                            appState.addExclusion(bundleId: bundleId, appName: name)
                            showAddExclusion = false
                        }) {
                            Text(name)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 200)
            Button("Cancel") { showAddExclusion = false }
        }
        .padding()
        .frame(width: 300)
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if confirmClearMemories {
                confirmRow(
                    message: "Clear all memory summaries?",
                    confirmLabel: "Clear memories",
                    onCancel: { confirmClearMemories = false },
                    onConfirm: {
                        let n = appState.clearMemories()
                        confirmClearMemories = false
                        showSummary("Cleared \(n) memories. They'll regenerate on the next memory builder poll.")
                    }
                )
            } else if confirmClearAll {
                confirmRow(
                    message: "Delete all captures, memories, and screenshot files?",
                    confirmLabel: "Delete everything",
                    onCancel: { confirmClearAll = false },
                    onConfirm: {
                        let r = appState.clearAllData()
                        confirmClearAll = false
                        showSummary("Deleted \(r.memories) memories, \(r.captures) captures, \(r.screenshots) screenshot files.")
                    }
                )
            } else {
                HStack(spacing: 8) {
                    Button("Clear memories") { confirmClearMemories = true }
                    Button("Clear all data") { confirmClearAll = true }
                }
                .font(.callout)
                .buttonStyle(.bordered)
            }

            Text("**Clear memories**: deletes LLM summaries only. Captures stay, and the memory builder will regenerate memories on the next poll. **Clear all data**: wipes captures, memories, and screenshot files. Cannot be undone.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = lastClearSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            Divider().padding(.vertical, 4)

            Button("Quit Chronicle") {
                NSApplication.shared.terminate(nil)
            }
            .font(.callout)
            .foregroundStyle(.red)
        }
    }

    private func confirmRow(message: String, confirmLabel: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .font(.callout)
        }
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 0.5))
    }

    private func showSummary(_ text: String) {
        lastClearSummary = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if lastClearSummary == text { lastClearSummary = nil }
        }
    }

    private func loadSettings() {
        captureInterval = Database.shared.getSetting("capture_interval_sec") ?? "10"
        memoryWindow = Database.shared.getSetting("memory_window_sec") ?? "60"
        screenshotTTL = Database.shared.getSetting("screenshot_ttl_minutes") ?? "30"

        let env = Onboarding.readEnvFile()
        llmProvider = env.provider
        llmModel = env.model
        llmApiKey = env.apiKeys[env.provider] ?? ""
        llmBaseURL = env.provider == .openaiCompatible
            ? env.openaiCompatBaseURL
            : env.provider.defaultBaseURL
    }

    private func saveSetting(_ key: String, _ value: String) {
        Database.shared.setSetting(key, value: value)
    }

    private func prepareAddExclusion() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let bid = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (bid, name)
            }
            .sorted { $0.1 < $1.1 }
        runningApps = apps
        showAddExclusion = true
    }
}
