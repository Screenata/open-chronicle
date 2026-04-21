import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: Step = .welcome
    @State private var hasPermission = Onboarding.hasScreenRecordingPermission()
    @State private var provider: Provider = .anthropic
    @State private var apiKey: String = ""
    @State private var customModel: String = ""
    @State private var useCustomModel: Bool = false
    @State private var isInstalling = false
    @State private var installLog: [String] = []
    @State private var installError: String?
    @State private var detectedAgents: Set<AgentCLI> = []
    @State private var selectedAgents: Set<AgentCLI> = []
    @State private var didDetectAgents = false

    enum Step {
        case welcome, permission, apiKey, install, done
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 540)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack {
            Image(systemName: "memorychip.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chronicle Setup")
                    .font(.headline)
                Text(stepSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isInstalling)
            .help("Quit Chronicle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var stepSubtitle: String {
        switch step {
        case .welcome: return "Welcome"
        case .permission: return "Step 1 of 3 — Screen Recording"
        case .apiKey: return "Step 2 of 3 — API Key"
        case .install: return "Step 3 of 3 — Install"
        case .done: return "Ready to go"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .permission: permissionStep
        case .apiKey: apiKeyStep
        case .install: installStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chronicle captures what you're working on and makes it available to Claude Code as memory.")
                .font(.callout)
            VStack(alignment: .leading, spacing: 8) {
                bullet("Screenshots every 10 seconds of editors, terminals, and browsers")
                bullet("On-device OCR (Apple Vision — no cloud)")
                bullet("LLM-summarized into 1-minute memory windows")
                bullet("Claude Code reads memories over MCP")
            }
            Text("Everything stays on your machine except the LLM summarization call. Setup takes about a minute.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chronicle needs permission to capture your screen.")
                .font(.callout)

            HStack {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(hasPermission ? .green : .orange)
                Text(hasPermission ? "Permission granted" : "Permission not granted")
            }
            .font(.callout)

            if !hasPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click **Grant Permission** below. macOS will prompt the first time, or you can open System Settings manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Grant Permission") {
                            _ = Onboarding.requestScreenRecordingPermission()
                            hasPermission = Onboarding.hasScreenRecordingPermission()
                        }
                        Button("Open System Settings") {
                            Onboarding.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text("After granting in System Settings, you may need to quit and relaunch Chronicle for it to take effect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            hasPermission = Onboarding.hasScreenRecordingPermission()
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chronicle uses an LLM to turn raw screen captures into short memory summaries.")
                .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                Text("Provider").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $provider) {
                    ForEach(Provider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption).foregroundStyle(.secondary)
                SecureField(provider.apiKeyEnvVar, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in mcp/.env locally. Never transmitted anywhere except to \(provider.displayName).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Agents to wire up").font(.caption).foregroundStyle(.secondary)
                if !didDetectAgents {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Detecting installed agents...").font(.caption).foregroundStyle(.tertiary)
                    }
                } else if detectedAgents.isEmpty {
                    Text("No supported agents detected. Install Claude Code or Codex CLI first.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    ForEach(AgentCLI.allCases) { agent in
                        Toggle(isOn: Binding(
                            get: { selectedAgents.contains(agent) },
                            set: { isOn in
                                if isOn { selectedAgents.insert(agent) } else { selectedAgents.remove(agent) }
                            }
                        )) {
                            HStack(spacing: 4) {
                                Text(agent.displayName).font(.caption)
                                if !detectedAgents.contains(agent) {
                                    Text("(not installed)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(!detectedAgents.contains(agent))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Use custom model", isOn: $useCustomModel)
                        .font(.caption)
                    if useCustomModel {
                        TextField(provider.defaultModel, text: $customModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    } else {
                        Text("Default: \(provider.defaultModel)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .task {
            guard !didDetectAgents else { return }
            let found = await Onboarding.detectInstalledAgents()
            detectedAgents = found
            selectedAgents = found
            didDetectAgents = true
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installing Chronicle...")
                .font(.callout)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(installLog.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(installLog[i])
                            .font(.caption)
                    }
                }
                if isInstalling {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let installError {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Installation failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                Text("Setup complete").font(.headline)
            }

            Text("Chronicle is now capturing and Claude Code is wired up.")
                .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                bullet("Restart Claude Code to pick up the MCP server")
                bullet("Work in an editor, terminal, or browser for 2–3 minutes")
                bullet("Ask Claude Code: \"what was I just working on?\"")
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
                    .disabled(isInstalling)
            }
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { step = .permission }
                .buttonStyle(.borderedProminent)
        case .permission:
            Button("Continue") { step = .apiKey }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPermission)
        case .apiKey:
            Button("Install") { startInstall() }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || selectedAgents.isEmpty)
        case .install:
            if installError != nil {
                Button("Retry") { startInstall() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") { step = .done }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
            }
        case .done:
            Button("Finish") {
                Onboarding.markSetupComplete()
                appState.onboardingNeeded = false
                appState.bootstrap()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func goBack() {
        switch step {
        case .permission: step = .welcome
        case .apiKey: step = .permission
        case .install: step = .apiKey
        default: break
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption)
        }
    }

    private func startInstall() {
        step = .install
        installLog = []
        installError = nil
        isInstalling = true

        Task {
            do {
                guard !selectedAgents.isEmpty else {
                    throw OnboardingError.noAgentSelected
                }

                try Onboarding.writeEnvFile(
                    provider: provider,
                    apiKey: apiKey,
                    model: useCustomModel && !customModel.isEmpty ? customModel : nil
                )
                installLog.append("Wrote .env with \(provider.displayName) credentials")

                installLog.append("Installing Node dependencies (this can take ~30s)...")
                try await Onboarding.runNpmInstall()
                installLog[installLog.count - 1] = "Installed Node dependencies"

                if selectedAgents.contains(.claude) {
                    try await Onboarding.registerClaudeMcp()
                    installLog.append("Registered Chronicle MCP server with Claude Code")
                    try Onboarding.appendClaudeMd()
                    installLog.append("Added auto-invoke rule to ~/.claude/CLAUDE.md")
                }

                if selectedAgents.contains(.codex) {
                    try Onboarding.registerCodexMcp()
                    installLog.append("Registered Chronicle MCP server with Codex CLI")
                    try Onboarding.appendCodexAgentsMd()
                    installLog.append("Added auto-invoke rule to ~/.codex/AGENTS.md")
                }

                isInstalling = false
                step = .done
            } catch {
                isInstalling = false
                installError = error.localizedDescription
            }
        }
    }
}
