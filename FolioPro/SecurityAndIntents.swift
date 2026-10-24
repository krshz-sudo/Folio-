import SwiftUI
import SwiftData
import Combine
import LocalAuthentication
import EventKit
import UserNotifications
import AppIntents

// MARK: - Phase 1: Structured Event Model
struct StructuredExtractedEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var summary: String
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var location: String?
    var eventType: EventType
    var amount: Double?
    var serialOrReference: String?
    var confidenceScore: Double
    var recurrence: String?
    var isPast: Bool

    enum EventType: String, Codable, CaseIterable {
        case warrantyExpiry = "Warranty Expiry"
        case paymentDue = "Payment Due Date"
        case salaryCredit = "Salary Credit"
        case subscriptionRenewal = "Subscription Renewal"
        case inspectionAppointment = "Inspection Appointment"
        case generalReminder = "General Reminder"

        var icon: String {
            switch self {
            case .warrantyExpiry: return "shield.lefthalf.filled"
            case .paymentDue: return "doc.text.fill"
            case .salaryCredit: return "banknote.fill"
            case .subscriptionRenewal: return "arrow.triangle.2.circlepath"
            case .inspectionAppointment: return "calendar.badge.clock"
            case .generalReminder: return "bell.badge.fill"
            }
        }
    }
}

// MARK: - Phase 2: Date Intelligence Engine
enum DateIntelligenceEngine {
    struct ResolvedDateResult {
        let date: Date
        let isPast: Bool
        let resolvedYear: Int
        let confidence: Double
        let notes: String
    }

    /// Resolves dates handling timezone, missing years, past vs future context, and locale ambiguity
    static func resolveDate(
        rawDateString: String,
        documentType: DocumentKind,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> ResolvedDateResult? {
        let now = Date.now
        let currentYear = calendar.component(.year, from: now)
        let clean = rawDateString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Ambiguity handling (DD/MM/YYYY vs MM/DD/YYYY)
        let isLikelyDMY = isLocalePreferringDMY()

        // 2. Try standard NSDataDetector first
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: clean, options: [], range: NSRange(clean.startIndex..., in: clean)) ?? []

        if let firstMatch = matches.first, let parsedDate = firstMatch.date {
            var components = calendar.dateComponents(in: timeZone, from: parsedDate)

            // Missing-year resolution: if year is not explicitly given in string
            let hasYearInText = clean.range(of: #"\b20\d{2}\b"#, options: .regularExpression) != nil
            if !hasYearInText {
                components.year = currentYear
                if let candidateDate = calendar.date(from: components) {
                    // For warranties and due dates, if candidate is in the past, resolve to next year
                    if (documentType == .warranty || documentType == .taxInvoice) && candidateDate < now.addingTimeInterval(-86400 * 14) {
                        components.year = currentYear + 1
                    }
                }
            }

            // Date validation (check validity in calendar)
            if let validatedDate = calendar.date(from: components) {
                let isPast = validatedDate < now
                return ResolvedDateResult(
                    date: validatedDate,
                    isPast: isPast,
                    resolvedYear: components.year ?? currentYear,
                    confidence: 0.95,
                    notes: "Resolved via Apple DataDetector (\(timeZone.identifier))"
                )
            }
        }

        // 3. Fallback regex for DD/MM or MM/DD missing year patterns (e.g. "15 Nov", "May 24", "12/08")
        if let fallbackResult = parseRegexDate(clean: clean, isDMY: isLikelyDMY, currentYear: currentYear, now: now, docType: documentType, calendar: calendar) {
            return fallbackResult
        }

        return nil
    }

    private static func isLocalePreferringDMY() -> Bool {
        let locale = Locale.current
        let id = locale.identifier.lowercased()
        if id.contains("in") || id.contains("gb") || id.contains("au") || id.contains("eu") {
            return true
        }
        return false
    }

    private static func parseRegexDate(
        clean: String,
        isDMY: Bool,
        currentYear: Int,
        now: Date,
        docType: DocumentKind,
        calendar: Calendar
    ) -> ResolvedDateResult? {
        let slashPattern = #"(\d{1,2})[/\-\.](\d{1,2})(?:[/\-\.](\d{2,4}))?"#
        if let regex = try? NSRegularExpression(pattern: slashPattern),
           let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            guard let r1 = Range(match.range(at: 1), in: clean),
                  let r2 = Range(match.range(at: 2), in: clean) else { return nil }

            let v1 = Int(clean[r1]) ?? 1
            let v2 = Int(clean[r2]) ?? 1

            var day = isDMY ? v1 : v2
            var month = isDMY ? v2 : v1

            // If day > 12, unambiguous
            if v1 > 12 && v2 <= 12 {
                day = v1
                month = v2
            } else if v2 > 12 && v1 <= 12 {
                day = v2
                month = v1
            }

            var year = currentYear
            if match.numberOfRanges > 3, let r3 = Range(match.range(at: 3), in: clean) {
                var yVal = Int(clean[r3]) ?? currentYear
                if yVal < 100 { yVal += 2000 }
                year = yVal
            } else {
                // Missing year resolution
                if docType == .warranty {
                    year = currentYear + 1
                }
            }

            // Date validation (valid Gregorian calendar check)
            var comp = DateComponents()
            comp.year = year
            comp.month = min(max(month, 1), 12)
            comp.day = min(max(day, 1), 31)
            comp.hour = 9
            comp.minute = 0

            if comp.isValidDate(in: calendar), let finalDate = calendar.date(from: comp) {
                return ResolvedDateResult(
                    date: finalDate,
                    isPast: finalDate < now,
                    resolvedYear: year,
                    confidence: 0.90,
                    notes: "Resolved via format pattern \(day)/\(month)/\(year)"
                )
            }
        }
        return nil
    }
}

// MARK: - Phase 4: Tool Permissions Policy Gate
enum ToolPermissionPolicy: String, Codable, CaseIterable {
    case askEveryTime = "Ask Every Time"
    case alwaysAllow = "Always Allow"
    case deny = "Deny"
}

@MainActor
final class ToolPermissionManager: ObservableObject {
    static let shared = ToolPermissionManager()

    @AppStorage("policy_calendar_tool") var calendarPolicy: ToolPermissionPolicy = .askEveryTime
    @AppStorage("policy_reminders_tool") var remindersPolicy: ToolPermissionPolicy = .askEveryTime

    func shouldAutoExecute(tool: AppleSystemTool) -> Bool {
        switch tool {
        case .calendar: return calendarPolicy == .alwaysAllow
        case .reminders: return remindersPolicy == .alwaysAllow
        }
    }

    func isDenied(tool: AppleSystemTool) -> Bool {
        switch tool {
        case .calendar: return calendarPolicy == .deny
        case .reminders: return remindersPolicy == .deny
        }
    }
}

enum AppleSystemTool: String, CaseIterable, Identifiable {
    case calendar = "iOS Calendar"
    case reminders = "iOS Reminders"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .calendar: return "calendar.badge.plus"
        case .reminders: return "bell.badge.fill"
        }
    }
}

// MARK: - Phase 3: Apple Integration Service (EventKit & Reminders & Duplicate Detection)
@MainActor
final class AppleSystemIntegrationService: ObservableObject {
    static let shared = AppleSystemIntegrationService()

    private let eventStore = EKEventStore()

    struct SaveResult {
        let title: String
        let targetIdentifier: String
        let calendarName: String
        let scheduledDate: Date
        let isDuplicate: Bool
    }

    enum IntegrationError: LocalizedError {
        case permissionDenied(String)
        case duplicateFound(String)
        case saveFailed(String)
        case noDefaultCalendar

        var errorDescription: String? {
            switch self {
            case .permissionDenied(let msg): return "Permission Denied: \(msg)"
            case .duplicateFound(let msg): return "Duplicate: \(msg)"
            case .saveFailed(let msg): return "Save Failed: \(msg)"
            case .noDefaultCalendar: return "No Default Calendar available on this device."
            }
        }
    }

    // 1. Permission Handling
    func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            return (try? await eventStore.requestAccess(to: .event)) ?? false
        }
    }

    func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await eventStore.requestFullAccessToReminders()) ?? false
        } else {
            return (try? await eventStore.requestAccess(to: .reminder)) ?? false
        }
    }

    // 2. Duplicate Detection for Calendar Events
    func findDuplicateEvent(title: String, date: Date) -> EKEvent? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -12, to: date) ?? date
        let end = cal.date(byAdding: .hour, value: 12, to: date) ?? date
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let matches = eventStore.events(matching: predicate)
        return matches.first { $0.title.localizedCaseInsensitiveContains(title) }
    }

    // 3. Create Native iOS Calendar Event
    func createCalendarEvent(
        title: String,
        date: Date,
        notes: String,
        forceAllowDuplicate: Bool = false
    ) async -> Result<SaveResult, IntegrationError> {
        let granted = await requestCalendarAccess()
        guard granted else {
            return .failure(.permissionDenied("Please enable Calendar permissions in iOS Settings > Folio Pro."))
        }

        // Duplicate detection
        if !forceAllowDuplicate, let existing = findDuplicateEvent(title: title, date: date) {
            return .failure(.duplicateFound("Event '\(existing.title ?? title)' already exists on Calendar at this time."))
        }

        guard let defaultCal = eventStore.defaultCalendarForNewEvents else {
            return .failure(.noDefaultCalendar)
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600) // 1 hour duration
        event.calendar = defaultCal

        // Add 1-day before and 2-hour before alarms
        event.addAlarm(EKAlarm(relativeOffset: -86400)) // 1 day before
        event.addAlarm(EKAlarm(relativeOffset: -7200))  // 2 hours before

        do {
            try eventStore.save(event, span: .thisEvent)
            return .success(
                SaveResult(
                    title: title,
                    targetIdentifier: event.eventIdentifier ?? UUID().uuidString,
                    calendarName: defaultCal.title,
                    scheduledDate: date,
                    isDuplicate: false
                )
            )
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    // 4. Create Native iOS Reminder
    func createReminder(
        title: String,
        dueDate: Date,
        notes: String
    ) async -> Result<SaveResult, IntegrationError> {
        let granted = await requestRemindersAccess()
        guard granted else {
            return .failure(.permissionDenied("Please enable Reminders permissions in iOS Settings > Folio Pro."))
        }

        guard let defaultList = eventStore.defaultCalendarForNewReminders() else {
            return .failure(.noDefaultCalendar)
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = defaultList
        reminder.priority = 1 // High priority

        let cal = Calendar.current
        reminder.dueDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.addAlarm(EKAlarm(absoluteDate: dueDate))

        do {
            try eventStore.save(reminder, commit: true)

            // Also register offline local notification via UNUserNotificationCenter
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = notes
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            try? await center.add(req)

            return .success(
                SaveResult(
                    title: title,
                    targetIdentifier: reminder.calendarItemIdentifier,
                    calendarName: defaultList.title,
                    scheduledDate: dueDate,
                    isDuplicate: false
                )
            )
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }
}

// MARK: - Face ID & Biometrics Gate
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
            self.isUnlocked = true
            completion?(true)
        }
    }

    func lockVault() {
        self.isUnlocked = false
    }
}

// MARK: - Swiggy-style Multi-Phase Dynamic Island Manager
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.state = .scanPhase(phase: .scanning, title: "Reading Document OCR...")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .analyzing, title: "Apple Foundation Model: Reading Dates & Kind...")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .creatingEvent, title: "Scheduling Reminders & Calendar...")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            onSave()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state = .scanPhase(phase: .saved, title: "Saved to Vault • Events Synced")
            }
        }

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
