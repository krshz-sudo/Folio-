import Foundation

struct DocumentGroup: Identifiable, Hashable {
    var id: String { symbol }
    let symbol: String
    let title: String
    let kind: DocumentKind
    let documents: [FolioDocument]

    var sortedDocs: [FolioDocument] {
        documents.sorted { $0.documentDate < $1.documentDate }
    }

    var latestValue: Double {
        sortedDocs.last?.primaryAmount ?? 0
    }

    var peakValue: Double {
        sortedDocs.map(\.primaryAmount).max() ?? 0
    }

    var lowValue: Double {
        sortedDocs.map(\.primaryAmount).min() ?? 0
    }

    var averageValue: Double {
        guard !sortedDocs.isEmpty else { return 0 }
        return sortedDocs.map(\.primaryAmount).reduce(0, +) / Double(sortedDocs.count)
    }

    var deltaPercentage: Double {
        guard sortedDocs.count >= 2 else { return 0 }
        let prev = sortedDocs[sortedDocs.count - 2].primaryAmount
        guard prev > 0 else { return 0 }
        return ((latestValue - prev) / prev) * 100.0
    }
}

// Type alias for backwards compatibility
typealias TickerGroup = DocumentGroup

enum VaultAnalyticsEngine {
    static func totalNetPay(from docs: [FolioDocument]) -> Double {
        docs.filter { $0.kind == .payslip }.map(\.primaryAmount).reduce(0, +)
    }

    static func latestMonthlyNetPay(from docs: [FolioDocument]) -> Double {
        docs.filter { $0.kind == .payslip }
            .sorted { $0.documentDate < $1.documentDate }
            .last?.primaryAmount ?? 0
    }

    static func totalGSTPaid(from docs: [FolioDocument]) -> Double {
        docs.filter { $0.kind == .taxInvoice }.map(\.secondaryAmount).reduce(0, +)
    }

    static func totalInvoiceSpend(from docs: [FolioDocument]) -> Double {
        docs.filter { $0.kind == .taxInvoice }.map(\.primaryAmount).reduce(0, +)
    }

    static func totalProtectedWarrantyValue(from docs: [FolioDocument]) -> Double {
        docs.filter {
            $0.kind == .warranty && (($0.daysUntilExpiry ?? -1) >= 0)
        }.map(\.primaryAmount).reduce(0, +)
    }

    static func expiringSoonWarranties(from docs: [FolioDocument]) -> [FolioDocument] {
        docs.filter { $0.needsAttention }
            .sorted { ($0.daysUntilExpiry ?? 999) < ($1.daysUntilExpiry ?? 999) }
    }

    static func buildTickerGroups(from docs: [FolioDocument]) -> [DocumentGroup] {
        buildDocumentGroups(from: docs)
    }

    static func buildDocumentGroups(from docs: [FolioDocument]) -> [DocumentGroup] {
        let grouped = Dictionary(grouping: docs, by: \.tickerSymbol)
        return grouped.compactMap { symbol, items in
            guard let first = items.first else { return nil }
            return DocumentGroup(symbol: symbol, title: first.title, kind: first.kind, documents: items)
        }.sorted { $0.symbol < $1.symbol }
    }

    static func formatINR(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "₹\(Int(value))"
    }
}
