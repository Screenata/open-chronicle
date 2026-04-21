import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .memories

    enum Tab {
        case memories, settings
    }

    var body: some View {
        Group {
            if appState.onboardingNeeded {
                OnboardingView()
            } else {
                VStack(spacing: 0) {
                    headerBar
                    Divider()
                    tabContent
                }
                .frame(width: 400, height: 540)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            appState.bootstrap()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chronicle")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isRecording ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.isRecording ? "Recording" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if appState.claudeIntegrationEnabled {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("Claude Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: {
                FloatingWindowController.shared.open(appState: appState)
            }) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Open as floating window (stays visible when other apps are focused)")

            Button(action: appState.toggleRecording) {
                Image(systemName: appState.isRecording ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appState.isRecording ? .orange : .green)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Picker("", selection: $selectedTab) {
                Image(systemName: "brain.head.profile").tag(Tab.memories)
                Image(systemName: "gearshape").tag(Tab.settings)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .memories:
            if appState.selectedMemory != nil {
                MemoryDetailView()
            } else {
                MemoryListView()
            }
        case .settings:
            SettingsView()
        }
    }
}
