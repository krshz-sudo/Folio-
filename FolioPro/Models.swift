import Foundation
import SwiftData
import CryptoKit
import Security

enum DocumentKind: String, Codable, CaseIterable, Identifiable {
    case warranty = "Warranty"
    case payslip = "Payslip"
    case taxInvoice = "Tax Invoice"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .warranty: return "checkmark.shield.fill"
        case .payslip: return "banknote.fill"
        case .taxInvoice: return "doc.text.fill"
        }
    }

    var codePrefix: String {
        switch self {
        case .warranty: return "WRT"
        case .payslip: return "PAY"
        case .taxInvoice: return "DOC"
        }
    }

    var tickerPrefix: String { codePrefix }
}

@Model
final class FolioDocument {
    var id: UUID
    var kindRaw: String
    var title: String
    var tickerSymbol: String
    var primaryAmount: Double
    var secondaryAmount: Double
    var documentDate: Date
    var expiryDate: Date?
    var serialOrInvoiceNo: String
    var rawExtractedText: String
    var sha256ProofHash: String
    var claimableTaxCategory: String
    var isVerified: Bool

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .taxInvoice }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: DocumentKind,
        title: String,
        tickerSymbol: String,
        primaryAmount: Double,
        secondaryAmount: Double = 0,
        documentDate: Date = .now,
        expiryDate: Date? = nil,
        serialOrInvoiceNo: String = "",
        rawExtractedText: String = "",
        claimableTaxCategory: String = "Standard",
        isVerified: Bool = true
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.tickerSymbol = tickerSymbol.uppercased()
        self.primaryAmount = primaryAmount
        self.secondaryAmount = secondaryAmount
        self.documentDate = documentDate
        self.expiryDate = expiryDate
        self.serialOrInvoiceNo = serialOrInvoiceNo
        self.rawExtractedText = rawExtractedText
        self.claimableTaxCategory = claimableTaxCategory
        self.isVerified = isVerified
        self.sha256ProofHash = CryptoProofService.generateDocumentHash(
            title: title,
            amount: primaryAmount,
            date: documentDate,
            serial: serialOrInvoiceNo
        )
    }

    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: expiryDate)).day
    }

    var needsAttention: Bool {
        guard kind == .warranty, let days = daysUntilExpiry else { return false }
        return days >= 0 && days <= 14
    }
}

enum CryptoProofService {
    private static let keychainAccount = "com.folio.vault.genesis.anchor"

    static func generateDocumentHash(title: String, amount: Double, date: Date, serial: String) -> String {
        let payload = "\(title)|\(String(format: "%.2f", amount))|\(Int(date.timeIntervalSince1970))|\(serial)|\(latestKeychainAnchor())"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hashHex = digest.compactMap { String(format: "%02x", $0) }.joined()
        saveKeychainAnchor(String(hashHex.prefix(16)))
        return hashHex
    }

    static func latestKeychainAnchor() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "FOLIO_GENESIS_2026"
    }

    private static func saveKeychainAnchor(_ anchor: String) {
        let data = Data(anchor.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

enum SampleVaultSeeder {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        purgeMockData(context: context)
    }

    @MainActor
    static func purgeMockData(context: ModelContext) {
        let descriptor = FetchDescriptor<FolioDocument>()
        if let docs = try? context.fetch(descriptor) {
            for doc in docs {
                if doc.serialOrInvoiceNo.hasPrefix("EMP-941") ||
                   doc.serialOrInvoiceNo.hasPrefix("INV-2026-") ||
                   doc.serialOrInvoiceNo.hasPrefix("SN-C02X") ||
                   doc.serialOrInvoiceNo.hasPrefix("SN-SNY") ||
                   doc.serialOrInvoiceNo.hasPrefix("SN-LG") ||
                   doc.serialOrInvoiceNo.hasPrefix("SN-ST") {
                    context.delete(doc)
                }
            }
            try? context.save()
        }
    }
}

// MARK: - Phase 1 & 2: Document Auto Categorizer with Date Intelligence
enum DocumentAutoCategorizer {
    struct AnalyzedResult {
        let kind: DocumentKind
        let title: String
        let code: String
        let primaryAmount: Double
        let secondaryAmount: Double
        let serialOrRef: String
        let documentDate: Date
        let expiryDate: Date?
        let foundDates: [Date]
        let extractedEvents: [StructuredExtractedEvent]
        var summary: String {
            extractedEvents.first?.summary ?? ""
        }
    }

    static func analyze(text: String) -> AnalyzedResult {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = cleanText.uppercased()

        // 1. Determine Category from text keywords (No document left uncategorized)
        let kind: DocumentKind
        if upper.contains("WARRANTY") || upper.contains("GUARANTEE") || upper.contains("SERIAL NO") ||
           upper.contains("APPLECARE") || upper.contains("EXPIRY") || upper.contains("HARDWARE") ||
           upper.contains("REPAIR") || upper.contains("COVERAGE") {
            kind = .warranty
        } else if upper.contains("PAYSLIP") || upper.contains("NET PAY") || upper.contains("SALARY") ||
                  upper.contains("EARNINGS") || upper.contains("DEDUCTION") || upper.contains("EMPLOYEE") ||
                  upper.contains("BASIC PAY") || upper.contains("CTC") || upper.contains("TDS") {
            kind = .payslip
        } else {
            kind = .taxInvoice
        }

        // 2. Extract Title
        let lines = cleanText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 2 }

        var title = "\(kind.rawValue) Document"
        if let firstLine = lines.first {
            let candidate = firstLine.replacingOccurrences(of: "WARRANTY CARD:", with: "")
                                    .replacingOccurrences(of: "TAX INVOICE:", with: "")
                                    .replacingOccurrences(of: "PAYSLIP:", with: "")
                                    .trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty {
                title = candidate
            }
        }

        // 3. Extract Amounts
        var primary: Double = 0
        var secondary: Double = 0
        let numberPattern = #"(\d[\d,]*\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let matches = regex.matches(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText))
            let numbers: [Double] = matches.compactMap { match in
                guard let range = Range(match.range, in: cleanText) else { return nil }
                let cleaned = cleanText[range].replacingOccurrences(of: ",", with: "")
                return Double(cleaned)
            }.filter { $0 >= 50 }

            if let maxVal = numbers.max() {
                primary = maxVal
            }
            if numbers.count >= 2 {
                let sorted = numbers.sorted(by: >)
                secondary = sorted[1]
            }
        }

        // 4. Extract Serial / Reference
        var serial = "REF-\(Int.random(in: 1000...9999))"
        let serialPatterns = [
            #"SERIAL(?:\s*NO)?[:\s]+([A-Z0-9\-]+)"#,
            #"INVOICE(?:\s*NO)?[:\s]+([A-Z0-9\-]+)"#,
            #"EMP(?:\s*ID)?[:\s]+([A-Z0-9\-]+)"#,
            #"REF(?:\s*NO)?[:\s]+([A-Z0-9\-]+)"#
        ]
        for pat in serialPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: cleanText) {
                serial = String(cleanText[range])
                break
            }
        }

        // 5. Date Intelligence Engine (Missing-year resolution, past-event detection, timezone)
        var foundDates: [Date] = []
        var expiryDate: Date? = nil
        var structuredEvents: [StructuredExtractedEvent] = []

        // Extract dates with DateIntelligenceEngine
        if let resolved = DateIntelligenceEngine.resolveDate(rawDateString: cleanText, documentType: kind) {
            foundDates.append(resolved.date)

            if kind == .warranty {
                expiryDate = resolved.date
                structuredEvents.append(
                    StructuredExtractedEvent(
                        title: "Warranty Expiry: \(title)",
                        summary: "Product coverage ends on \(resolved.date.formatted(date: .long, time: .omitted)) (Serial: \(serial)).",
                        startDate: resolved.date,
                        isAllDay: true,
                        location: "Authorized Service Center",
                        eventType: .warrantyExpiry,
                        amount: primary,
                        serialOrReference: serial,
                        confidenceScore: resolved.confidence,
                        isPast: resolved.isPast
                    )
                )
            } else if kind == .taxInvoice {
                structuredEvents.append(
                    StructuredExtractedEvent(
                        title: "Payment / Bill Due: \(title)",
                        summary: "Payment due for invoice \(serial) of \(primary > 0 ? "₹\(Int(primary))" : "recorded amount").",
                        startDate: resolved.date,
                        isAllDay: true,
                        location: nil,
                        eventType: .paymentDue,
                        amount: primary,
                        serialOrReference: serial,
                        confidenceScore: resolved.confidence,
                        isPast: resolved.isPast
                    )
                )
            } else if kind == .payslip {
                structuredEvents.append(
                    StructuredExtractedEvent(
                        title: "Salary Credit: \(title)",
                        summary: "Monthly salary disbursement recorded on \(resolved.date.formatted(date: .long, time: .omitted)).",
                        startDate: resolved.date,
                        isAllDay: true,
                        location: nil,
                        eventType: .salaryCredit,
                        amount: primary,
                        serialOrReference: serial,
                        confidenceScore: resolved.confidence,
                        isPast: resolved.isPast
                    )
                )
            }
        }

        let docDate = foundDates.first ?? Date.now
        if kind == .warranty && expiryDate == nil {
            expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: docDate)
        }

        let code = "\(kind.codePrefix).\(String(title.prefix(4)).uppercased().filter { $0.isLetter })"

        return AnalyzedResult(
            kind: kind,
            title: title,
            code: code.isEmpty ? "\(kind.codePrefix).DOC" : code,
            primaryAmount: primary,
            secondaryAmount: secondary,
            serialOrRef: serial,
            documentDate: docDate,
            expiryDate: expiryDate,
            foundDates: foundDates,
            extractedEvents: structuredEvents
        )
    }
}
