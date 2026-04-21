import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class CaptureManager: ObservableObject {
    @Published var isCapturing = false

    private var timer: Timer?
    private var lastWindowHash: String?
    private let db = Database.shared

    // Privacy-sensitive apps that should never be captured, even if user hasn't explicitly excluded them.
    // Users can add more via the Settings tab.
    private static let defaultExcludedApps: Set<String> = [
        // Password managers
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx-helper",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",

        // Messaging (personal / sensitive)
        "com.apple.MobileSMS",            // Messages
        "com.hnc.Discord",
        "org.whispersystems.signal-desktop",
        "org.telegram.desktop",
        "net.whatsapp.WhatsApp",
        "com.tinyspeck.slackmacgap",      // Slack
        "com.electron.lark",              // Lark
        "com.electron.lark.helper",
        "com.tencent.xinWeChat",          // WeChat
        "com.tencent.qq",

        // Mail
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac",     // Spark
        "com.airmail.AirMail3",

        // Banking / finance (common ones)
        "com.apple.Wallet",

        // System / self
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.Preferences",
        "com.apple.ActivityMonitor",
    ]

    var captureIntervalSec: TimeInterval {
        Double(db.getSetting("capture_interval_sec") ?? "10") ?? 10
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        scheduleTimer()
    }

    func stop() {
        isCapturing = false
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: captureIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isCapturing else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            print("[open-chronicle] No frontmost app detected")
            return
        }

        if Self.defaultExcludedApps.contains(bundleId) {
            return
        }

        let userExcluded = Set(db.excludedApps().map(\.bundleId))
        if userExcluded.contains(bundleId) {
            return
        }

        // Skip Chronicle itself to avoid capturing our own UI
        if bundleId.hasPrefix("Chronicle") || bundleId == Bundle.main.bundleIdentifier {
            return
        }

        let appName = frontApp.localizedName ?? "Unknown"
        let windowTitle = Self.frontmostWindowTitle(pid: frontApp.processIdentifier) ?? ""
        let windowHash = "\(bundleId):\(windowTitle)"

        if windowHash == lastWindowHash {
            return
        }
        lastWindowHash = windowHash

        print("[open-chronicle] Capturing: \(appName) | \(windowTitle)")

        Task.detached(priority: .utility) { [db] in
            guard let screenshot = Self.captureScreenshot() else {
                print("[open-chronicle] Screenshot failed — check Screen Recording permission in System Settings > Privacy & Security")
                return
            }

            let imagePath = Self.saveScreenshot(screenshot)
            let ocrText = await Self.performOCR(on: screenshot)

            let id = db.insertCapture(
                appName: appName,
                windowTitle: windowTitle,
                imagePath: imagePath,
                ocrText: ocrText,
                windowHash: windowHash,
                isDuplicate: false
            )
            print("[open-chronicle] Saved capture #\(id) (\(ocrText?.count ?? 0) chars OCR)")
        }
    }

    // MARK: - Screenshot

    nonisolated private static func captureScreenshot() -> CGImage? {
        CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    nonisolated private static func saveScreenshot(_ image: CGImage) -> String? {
        let filename = "cap_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let url = Database.screenshotsDirectory.appendingPathComponent(filename)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url.path
    }

    // MARK: - Window Title

    private static func frontmostWindowTitle(pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let name = window[kCGWindowName as String] as? String,
                  !name.isEmpty else { continue }
            return name
        }
        return nil
    }

    // MARK: - OCR

    nonisolated private static func performOCR(on image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Cleanup

    func runCleanup() {
        let ttl = Int(db.getSetting("screenshot_ttl_minutes") ?? "30") ?? 30
        db.cleanupOldScreenshots(ttlMinutes: ttl)
    }
}
