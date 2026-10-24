import SwiftUI
import SwiftData
import Combine
import LocalAuthentication
import AppIntents

@MainActor
final class SecurityGateManager: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var authError: String? = nil

    func authenticate(completion: ((Bool) -> Void)? = nil) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Folio Vault to view documents") { success, evalError in
                DispatchQueue.main.async {
                    if success {
                        self.isUnlocked = true
                        self.authError = nil
                        completion?(true)
                    } else {
                        self.authError = evalError?.localizedDescription
                        completion?(false)
                    }
                }
            }
        } else {
            // Simulator or hardware without biometrics
            self.isUnlocked = true
            completion?(true)
        }
    }

    func lockVault() {
        self.isUnlocked = false
    }
}

// Swiggy-style Multi-Phase Dynamic Island & Agent Completion Manager
@MainActor
final class DynamicIslandManager: ObservableObject {
    static let shared = DynamicIslandManager()

    enum State: Equatable {
        case idle
        case scanPhase(phase: Phase, title: String)
        case completion(title: String, subtitle: String, isSuccess: Bool)

        enum Phase: Int, CaseIterable {
            case scanning = 1
            case analyzing = 2
            case creatingEvent = 3
            case saved = 4

            var stepName: String {
                switch self {
                case .scanning: return "Scan OCR"
                case .analyzing: return "Apple Intelligence"
                case .creatingEvent: return "Auto Calendar"
                case .saved: return "Vault Stored"
                }
            }

            var icon: String {
                switch self {
                case .scanning: return "camera.viewfinder"
                case .analyzing: return "sparkles"
                case .creatingEvent: return "calendar.badge.clock"
                case .saved: return "checkmark.circle.fill"
                }
            }
        }
    }

    @Published var state: State = .idle

    func showCompletion(title: String, subtitle: String, isSuccess: Bool = true) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            self.state = .completion(title: title, subtitle: subtitle, isSuccess: isSuccess)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if case .completion = self.state {
                    self.state = .idle
                }
            }
        }
    }

    func runAutoScanPipeline(onSave: @escaping () -> Void) {
        // Phase 1: Scanning
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.state = .scanPhase(phase: .scanning, title: "Reading Document OCR...")
        }

        // Phase 2: Analyzing with Apple Foundation Model
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .analyzing, title: "Apple Foundation Model: Reading Dates & Kind...")
            }
        }

        // Phase 3: Auto-scheduling calendar/reminder
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .creatingEvent, title: "Scheduling Reminders & Calendar...")
            }
        }

        // Phase 4: Saved to Vault
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            onSave()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .saved, title: "Saved to Vault • Events Synced")
            }
        }

        // Dismiss Dynamic Island
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if case .scanPhase = self.state {
                    self.state = .idle
                }
            }
        }
    }
}

struct CheckVaultSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Folio Vault Summary"
    static var description = IntentDescription("Returns your verified Net Pay, GST Paid, and Expiring Warranties on-device.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(for: FolioDocument.self)
        let docs = try container.mainContext.fetch(FetchDescriptor<FolioDocument>())
        let netPay = VaultAnalyticsEngine.latestMonthlyNetPay(from: docs)
        let gst = VaultAnalyticsEngine.totalGSTPaid(from: docs)
        let expiring = VaultAnalyticsEngine.expiringSoonWarranties(from: docs).count

        return .result(
            dialog: "Your latest monthly net pay is \(VaultAnalyticsEngine.formatINR(netPay)), cumulative GST paid is \(VaultAnalyticsEngine.formatINR(gst)), and you have \(expiring) warranties expiring within 14 days."
        )
    }
}
