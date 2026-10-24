import SwiftUI
import EventKit
import UserNotifications
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
final class AppleFoundationModelAgent: ObservableObject {
    static let shared = AppleFoundationModelAgent()

    private var session: LanguageModelSession?
    @Published var isAvailable: Bool = false

    init() {
        checkAndInitialize()
    }

    func checkAndInitialize() {
        if SystemLanguageModel.default.isAvailable {
            self.session = LanguageModelSession(
                model: .default,
                instructions: """
                You are Folio's private on-device Agent running natively via Apple Foundation Models on Apple Silicon.
                Analyze user documents, extract structured dates, identify warranties and due dates, suggest events, and execute Calendar and Reminder tools safely.
                Be concise, accurate, and respect user privacy.
                """
            )
            self.isAvailable = true
        } else {
            self.isAvailable = false
        }
    }

    func query(userPrompt: String, vaultContext: String) async -> String? {
        guard let session, SystemLanguageModel.default.isAvailable else { return nil }
        let fullPrompt = """
        User Query: "\(userPrompt)"

        User Documents & Events Context:
        \(vaultContext)
        """
        do {
            let response = try await session.respond(to: fullPrompt)
            return response.content
        } catch {
            return nil
        }
    }
}
#endif

// Staged tool action awaiting user approval
struct StagedToolAction: Identifiable, Hashable {
    let id: UUID = UUID()
    let tool: AppleSystemTool
    let title: String
    let targetDate: Date
    let notes: String
    var status: ActionStatus = .pending
    var duplicateDetected: Bool = false
    var duplicateEventName: String? = nil

    enum ActionStatus {
        case pending
        case approved
        case denied
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var toolActionExecuted: String? = nil
    var stagedAction: StagedToolAction? = nil
}

struct AgentView: View {
    let documents: [FolioDocument]
    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isThinking = false
    @FocusState private var isInputFocused: Bool
    @State private var showPermissionsSheet = false

    @ObservedObject private var permissionManager = ToolPermissionManager.shared

    var isModelConnected: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleFoundationModelAgent.shared.isAvailable
        }
        #endif
        return true
    }

    private let exactQuickOptions = [
        ("Set a reminder for a document", "bell.badge.fill"),
        ("Mark an event on Calendar", "calendar.badge.plus"),
        ("Check expiry date / warranty of any product", "shield.lefthalf.filled"),
        ("Calculate metrics from document", "chart.bar.xaxis")
    ]

    private let generalQuestions = [
        "What documents are currently stored in my vault?",
        "Do I have any upcoming warranty or expiry dates?",
        "Suggest calendar events from my documents",
        "Summarize my recently scanned documents"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Subtitle: "Apple Foundation Models" with status dot
                HStack(spacing: 6) {
                    Circle()
                        .fill(isModelConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)

                    Text("Apple Foundation Models")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Tool Permissions toggle link
                    Button {
                        showPermissionsSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Permissions")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    }

                    if isInputFocused || !messages.isEmpty {
                        Button("Clear") {
                            withAnimation {
                                messages.removeAll()
                                inputText = ""
                                isInputFocused = false
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)

                // Main Chat Scroll View
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            if messages.isEmpty {
                                // Phase 7: 4 Quick Options in 2x2 Soft-Grey Tiles
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("QUICK ACTIONS")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                        ForEach(exactQuickOptions, id: \.0) { option, icon in
                                            Button {
                                                sendQuery(option)
                                            } label: {
                                                VStack(spacing: 8) {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                            .fill(Color(uiColor: .systemGray5))
                                                            .frame(width: 34, height: 34)

                                                        Image(systemName: icon)
                                                            .font(.system(size: 15, weight: .medium))
                                                            .foregroundStyle(.primary)
                                                    }

                                                    Text(option)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                        .multilineTextAlignment(.center)
                                                        .lineLimit(2)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 96)
                                                .padding(8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)

                                // Phase 7: Suggested Questions
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SUGGESTED QUESTIONS")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    VStack(spacing: 0) {
                                        ForEach(Array(generalQuestions.enumerated()), id: \.element) { index, question in
                                            Button {
                                                sendQuery(question)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    Image(systemName: "bubble.left")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.secondary)

                                                    Text(question)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.primary)

                                                    Spacer()

                                                    Image(systemName: "arrow.up.forward")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 14)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            if index < generalQuestions.count - 1 {
                                                Divider().padding(.leading, 42)
                                            }
                                        }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 16)
                            } else {
                                // Conversation Feed with Staged Action Cards & Duplicate Alerts
                                LazyVStack(spacing: 14) {
                                    ForEach(messages) { msg in
                                        ChatRowView(
                                            message: msg,
                                            onApprove: { action, always in
                                                handleUserApproval(messageId: msg.id, action: action, alwaysAllow: always)
                                            },
                                            onDeny: { action in
                                                handleUserDenial(messageId: msg.id, action: action)
                                            }
                                        )
                                        .id(msg.id)
                                    }

                                    if isThinking {
                                        HStack {
                                            HStack(spacing: 6) {
                                                ProgressView().controlSize(.small)
                                                Text("Agent is analyzing...")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                            )
                                            Spacer()
                                        }
                                        .id("thinking_indicator")
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastId = messages.last?.id {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Bar with robust keyboard handling
                VStack(spacing: 0) {
                    Divider()

                    HStack(spacing: 10) {
                        TextField("Ask Agent anything...", text: $inputText)
                            .focused($isInputFocused)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .onSubmit {
                                sendQuery(inputText)
                            }

                        Button {
                            sendQuery(inputText)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.4) : Color.primary)
                                )
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isInputFocused || !messages.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation {
                                isInputFocused = false
                                if messages.isEmpty { inputText = "" }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 15))
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPermissionsSheet) {
                ToolPermissionsToggleView()
            }
        }
    }

    private func sendQuery(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        inputText = ""
        isInputFocused = false

        messages.append(ChatMessage(isUser: true, text: query))
        isThinking = true

        Task {
            var handledByFoundationModel = false

            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleFoundationModelAgent.shared.isAvailable {
                let context = buildVaultSummaryContext()
                if let answer = await AppleFoundationModelAgent.shared.query(userPrompt: query, vaultContext: context) {
                    messages.append(ChatMessage(isUser: false, text: answer))
                    handledByFoundationModel = true
                }
            }
            #endif

            if !handledByFoundationModel {
                runAgentToolPipeline(for: query)
            }

            isThinking = false
        }
    }

    // MARK: - Phase 4: Folio Agent Tool Execution & Approval
    private func runAgentToolPipeline(for query: String) {
        let lower = query.lowercased()

        if lower.contains("permission") || lower.contains("settings") {
            showPermissionsSheet = true
            messages.append(ChatMessage(isUser: false, text: "Opened the Tool Permissions settings page for you. You can configure iOS Calendar and Reminders tool policies anytime."))
            return
        }

        if lower.contains("suggest") || lower.contains("event suggestion") {
            // Proactive Event Suggestions based on Vault documents
            let suggestions = generateEventSuggestions()
            if suggestions.isEmpty {
                messages.append(ChatMessage(isUser: false, text: "I analyzed your Vault: all active documents are up to date and no immediate event suggestions are needed right now."))
            } else {
                var reply = "Here are suggested events based on your documents:\n"
                for s in suggestions {
                    reply += "• **\(s.title)** — \(s.startDate.formatted(date: .long, time: .omitted))\n"
                }
                reply += "\nWould you like me to schedule any of these on your Calendar?"
                messages.append(ChatMessage(isUser: false, text: reply))
            }
            return
        }

        if lower.contains("calendar") || lower.contains("event") {
            let doc = documents.first
            let targetDate = doc?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
            let title = doc != nil ? "Warranty Expiry: \(doc!.title)" : "Folio Document Event"
            let notes = "Scheduled by Folio Agent from on-device document"

            stageOrExecuteTool(tool: .calendar, title: title, date: targetDate, notes: notes)

        } else if lower.contains("reminder") || lower.contains("remind") {
            let doc = documents.first
            let targetDate = doc?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
            let title = doc != nil ? "Check Expiry: \(doc!.title)" : "Folio Document Reminder"
            let notes = "Reminder created by Folio Agent"

            stageOrExecuteTool(tool: .reminders, title: title, date: targetDate, notes: notes)

        } else if lower.contains("expiry") || lower.contains("warranty") {
            let warranties = documents.filter { $0.kind == .warranty }
            if warranties.isEmpty {
                messages.append(ChatMessage(isUser: false, text: "No warranty documents found in your Vault. Tap the center scan button to add one."))
            } else {
                var response = "Found **\(warranties.count)** warranty items:\n"
                for w in warranties {
                    let days = w.daysUntilExpiry ?? 0
                    response += "• **\(w.title)**: \(days >= 0 ? "\(days) days remaining" : "Expired") (Serial: \(w.serialOrInvoiceNo))\n"
                }
                messages.append(ChatMessage(isUser: false, text: response))
            }

        } else if lower.contains("metric") || lower.contains("calculate") || lower.contains("summary") || lower.contains("summarize") {
            let total = documents.count
            let warranties = documents.filter { $0.kind == .warranty }.count
            let payslips = documents.filter { $0.kind == .payslip }.count
            let invoices = documents.filter { $0.kind == .taxInvoice }.count
            let totalVal = documents.map(\.primaryAmount).reduce(0, +)

            let reply = """
            **Vault Metrics Summary:**
            • Total Documents: **\(total)**
            • Warranties: **\(warranties)**
            • Payslips: **\(payslips)**
            • Invoices: **\(invoices)**
            • Combined Value: **\(VaultAnalyticsEngine.formatINR(totalVal))**
            """
            messages.append(ChatMessage(isUser: false, text: reply))

        } else {
            if documents.isEmpty {
                messages.append(ChatMessage(isUser: false, text: "Your Vault is currently empty. Use the center scan button to add documents, and I will automatically extract dates, suggest events, and schedule reminders for you."))
            } else {
                var text = "Here are the documents in your Vault:\n"
                for doc in documents.prefix(5) {
                    text += "• **\(doc.title)** (\(doc.kind.rawValue)) — \(doc.documentDate.formatted(date: .abbreviated, time: .omitted))\n"
                }
                messages.append(ChatMessage(isUser: false, text: text))
            }
        }
    }

    private func stageOrExecuteTool(tool: AppleSystemTool, title: String, date: Date, notes: String) {
        if permissionManager.isDenied(tool: tool) {
            messages.append(ChatMessage(isUser: false, text: "Action blocked: \(tool.rawValue) tool is set to 'Deny' in your permissions policy. Tap Permissions in the top right to change this."))
            return
        }

        // Duplicate detection
        var isDuplicate = false
        var duplicateName: String? = nil
        if tool == .calendar {
            if let existing = AppleSystemIntegrationService.shared.findDuplicateEvent(title: title, date: date) {
                isDuplicate = true
                duplicateName = existing.title
            }
        }

        if permissionManager.shouldAutoExecute(tool: tool) && !isDuplicate {
            // Auto-execute if Always Allow is selected and not a duplicate
            executeApprovedTool(tool: tool, title: title, date: date, notes: notes)
        } else {
            // Stage for user approval
            let staged = StagedToolAction(
                tool: tool,
                title: title,
                targetDate: date,
                notes: notes,
                duplicateDetected: isDuplicate,
                duplicateEventName: duplicateName
            )
            let promptText = isDuplicate
                ? "⚠️ **Duplicate Event Detected**: An event with this title already exists on your Calendar around this date. Would you like to proceed or skip?"
                : "I have prepared the action to write to **\(tool.rawValue)**. Please approve below:"

            messages.append(ChatMessage(isUser: false, text: promptText, stagedAction: staged))
        }
    }

    private func handleUserApproval(messageId: UUID, action: StagedToolAction, alwaysAllow: Bool) {
        if alwaysAllow {
            if action.tool == .calendar {
                permissionManager.calendarPolicy = .alwaysAllow
            } else {
                permissionManager.remindersPolicy = .alwaysAllow
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx].stagedAction?.status = .approved
        }

        executeApprovedTool(tool: action.tool, title: action.title, date: action.targetDate, notes: action.notes)
    }

    private func handleUserDenial(messageId: UUID, action: StagedToolAction) {
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx].stagedAction?.status = .denied
        }
        messages.append(ChatMessage(isUser: false, text: "Cancelled action for **\(action.title)**. Zero changes were made."))
    }

    private func executeApprovedTool(tool: AppleSystemTool, title: String, date: Date, notes: String) {
        Task {
            if tool == .calendar {
                let result = await AppleSystemIntegrationService.shared.createCalendarEvent(
                    title: title,
                    date: date,
                    notes: notes,
                    forceAllowDuplicate: true
                )
                switch result {
                case .success(let res):
                    messages.append(
                        ChatMessage(
                            isUser: false,
                            text: "Successfully added to your iOS Calendar (**\(res.calendarName)**) on \(res.scheduledDate.formatted(date: .long, time: .shortened)).",
                            toolActionExecuted: "Event Added to Calendar"
                        )
                    )
                    DynamicIslandManager.shared.showCompletion(title: "Added to iOS Calendar", subtitle: title)

                case .failure(let err):
                    messages.append(ChatMessage(isUser: false, text: "Failed to schedule event: \(err.localizedDescription)"))
                }
            } else {
                let result = await AppleSystemIntegrationService.shared.createReminder(
                    title: title,
                    dueDate: date,
                    notes: notes
                )
                switch result {
                case .success(let res):
                    messages.append(
                        ChatMessage(
                            isUser: false,
                            text: "Successfully created in iOS Reminders (**\(res.calendarName)**) for \(res.scheduledDate.formatted(date: .long, time: .shortened)).",
                            toolActionExecuted: "Reminder Created"
                        )
                    )
                    DynamicIslandManager.shared.showCompletion(title: "Reminder Scheduled", subtitle: title)

                case .failure(let err):
                    messages.append(ChatMessage(isUser: false, text: "Failed to schedule reminder: \(err.localizedDescription)"))
                }
            }
        }
    }

    private func generateEventSuggestions() -> [StructuredExtractedEvent] {
        var suggestions: [StructuredExtractedEvent] = []
        for doc in documents {
            if let exp = doc.expiryDate, exp > Date.now {
                suggestions.append(
                    StructuredExtractedEvent(
                        title: "Warranty Expiry: \(doc.title)",
                        summary: "Serial \(doc.serialOrInvoiceNo) expires on \(exp.formatted(date: .abbreviated, time: .omitted))",
                        startDate: exp,
                        isAllDay: true,
                        location: nil,
                        eventType: .warrantyExpiry,
                        amount: doc.primaryAmount,
                        serialOrReference: doc.serialOrInvoiceNo,
                        confidenceScore: 0.95,
                        isPast: false
                    )
                )
            }
        }
        return suggestions
    }

    private func buildVaultSummaryContext() -> String {
        var context = "Vault Document Count: \(documents.count)\n"
        for doc in documents.prefix(8) {
            context += "- [\(doc.kind.rawValue)] \(doc.title): \(doc.primaryAmount) INR, Serial: \(doc.serialOrInvoiceNo), Date: \(doc.documentDate.formatted())\n"
        }
        return context
    }
}

// MARK: - Chat Row View with Staged Approval Card
struct ChatRowView: View {
    let message: ChatMessage
    let onApprove: (StagedToolAction, Bool) -> Void
    let onDeny: (StagedToolAction) -> Void

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if let tool = message.toolActionExecuted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(tool)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
                }

                Text(.init(message.text))
                    .font(.system(size: 14))
                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                    .lineSpacing(2)

                // Staged User-Approved Action Card (Phase 4)
                if let action = message.stagedAction {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: action.tool.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            Text(action.tool.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()

                            if action.duplicateDetected {
                                Text("DUPLICATE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(action.targetDate.formatted(date: .long, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if action.status == .pending {
                            HStack(spacing: 8) {
                                Button {
                                    onApprove(action, false)
                                } label: {
                                    Text("Allow Once")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.primary)
                                        .foregroundStyle(Color(uiColor: .systemBackground))
                                        .clipShape(Capsule())
                                }

                                Button {
                                    onApprove(action, true)
                                } label: {
                                    Text("Always Allow")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(uiColor: .systemGray5))
                                        .foregroundStyle(.primary)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    onDeny(action)
                                } label: {
                                    Text("Deny")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.red.opacity(0.12))
                                        .foregroundStyle(.red)
                                        .clipShape(Capsule())
                                }
                            }
                        } else if action.status == .approved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Approved & Executed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                                Text("Denied by User")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(message.isUser ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground))
            )

            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Phase 4: Dedicated Tool Permissions Toggle Page
struct ToolPermissionsToggleView: View {
    @ObservedObject private var manager = ToolPermissionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 18))
                                .foregroundStyle(.blue)
                            Text("iOS Calendar Tool")
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Text("Controls whether Folio Agent can create native Calendar events automatically or must ask for confirmation.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("Policy", selection: $manager.calendarPolicy) {
                            ForEach(ToolPermissionPolicy.allCases, id: \.self) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Calendar Actions")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)
                            Text("iOS Reminders Tool")
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Text("Controls whether Folio Agent can schedule reminders and local notifications.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("Policy", selection: $manager.remindersPolicy) {
                            ForEach(ToolPermissionPolicy.allCases, id: \.self) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Reminders Actions")
                }

                Section {
                    Text("Folio strictly executes tools on-device through Apple EventKit with zero telemetry or cloud transmission.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Tool Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Backwards compatibility alias
typealias AskAgentView = AgentView
