import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .recording
    @Published var memories: [Memory] = []
    @Published var captures: [Capture] = []
    @Published var excludedApps: [ExcludedApp] = []
    @Published var selectedMemory: Memory?
    @Published var claudeIntegrationEnabled: Bool = true
    @Published var onboardingNeeded: Bool = !Onboarding.isSetupComplete()

    let captureManager = CaptureManager()
    private let db = Database.shared
    private var refreshTimer: Timer?

    var isRecording: Bool { recordingState == .recording }

    func bootstrap() {
        if onboardingNeeded { return }

        claudeIntegrationEnabled = db.getSetting("claude_integration_enabled") == "1"
        loadExcludedApps()
        refreshData()

        if isRecording {
            captureManager.start()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshData()
                self?.captureManager.runCleanup()
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            recordingState = .paused
            captureManager.stop()
        } else {
            recordingState = .recording
            captureManager.start()
        }
        db.setSetting("capture_enabled", value: isRecording ? "1" : "0")
    }

    func toggleClaudeIntegration() {
        claudeIntegrationEnabled.toggle()
        db.setSetting("claude_integration_enabled", value: claudeIntegrationEnabled ? "1" : "0")
    }

    func refreshData() {
        memories = db.recentMemories(limit: 50)
        captures = db.recentCaptures(limit: 20)
    }

    func loadExcludedApps() {
        excludedApps = db.excludedApps()
    }

    func addExclusion(bundleId: String, appName: String) {
        db.addExcludedApp(bundleId: bundleId, appName: appName)
        loadExcludedApps()
    }

    func removeExclusion(bundleId: String) {
        db.removeExcludedApp(bundleId: bundleId)
        loadExcludedApps()
    }

    @discardableResult
    func clearMemories() -> Int {
        selectedMemory = nil
        let n = db.clearMemories()
        refreshData()
        print("[open-chronicle] Cleared \(n) memories")
        return n
    }

    @discardableResult
    func clearAllData() -> Database.ClearResult {
        selectedMemory = nil
        let result = db.clearAllData()
        refreshData()
        print("[open-chronicle] Cleared \(result.memories) memories, \(result.captures) captures, \(result.screenshots) screenshots")
        return result
    }
}
