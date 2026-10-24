import SwiftUI
import SwiftData
import LocalAuthentication

struct VaultView: View {
    let documents: [FolioDocument]
    @ObservedObject var security: SecurityGateManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedCategory: DocumentKind? = nil
    @State private var selectedDoc: FolioDocument? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if !security.isUnlocked {
                    // Locked State: Zero documents or names visible until Face ID succeeds
                    VaultLockedView {
                        security.authenticate()
                    }
                } else {
                    // Unlocked State: Clean categories and documents inside them. Nothing else.
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Category Filter Tiles (Add to Chat screenshot style)
                            HStack(spacing: 12) {
                                CategoryTileButton(
                                    title: "All",
                                    count: documents.count,
                                    icon: "tray.full.fill",
                                    isSelected: selectedCategory == nil
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedCategory = nil
                                    }
                                }

                                ForEach(DocumentKind.allCases) { kind in
                                    let count = documents.filter { $0.kind == kind }.count
                                    CategoryTileButton(
                                        title: kind.rawValue,
                                        count: count,
                                        icon: kind.icon,
                                        isSelected: selectedCategory == kind
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedCategory = kind
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Document Groups
                            let activeKinds = selectedCategory != nil ? [selectedCategory!] : DocumentKind.allCases

                            ForEach(activeKinds) { kind in
                                let kindDocs = documents.filter { $0.kind == kind }
                                if !kindDocs.isEmpty || selectedCategory == kind {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(kind.rawValue.uppercased())
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(kindDocs.count) items")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 20)

                                        if kindDocs.isEmpty {
                                            Text("No documents stored in this category")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(16)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                                )
                                                .padding(.horizontal, 16)
                                        } else {
                                            // Soft tile list container with thin dividers (matching reference screenshot)
                                            VStack(spacing: 0) {
                                                ForEach(Array(kindDocs.enumerated()), id: \.element.id) { index, doc in
                                                    Button {
                                                        selectedDoc = doc
                                                    } label: {
                                                        DocumentRowView(doc: doc)
                                                    }
                                                    .buttonStyle(.plain)

                                                    if index < kindDocs.count - 1 {
                                                        Divider()
                                                            .padding(.leading, 56)
                                                    }
                                                }
                                            }
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                            )
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                }
                            }

                            if documents.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 38, weight: .light))
                                        .foregroundStyle(.secondary)
                                    Text("No documents in Vault")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Scan or upload a document to store it securely in your vault.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                                .padding(.vertical, 40)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                }

                if security.isUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation {
                                security.lockVault()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                Text("Lock")
                            }
                            .font(.system(size: 13, weight: .medium))
                        }
                    }
                }
            }
            .onAppear {
                if !security.isUnlocked {
                    security.authenticate()
                }
            }
            .sheet(item: $selectedDoc) { doc in
                DocumentDetailView(document: doc) {
                    modelContext.delete(doc)
                    try? modelContext.save()
                    selectedDoc = nil
                }
            }
        }
    }
}

// Category Tile Button: soft tile background, icon over short label
struct CategoryTileButton: View {
    let title: String
    let count: Int
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(uiColor: .systemGray5) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Document Row View: matching reference screenshot list rows
struct DocumentRowView: View {
    let doc: FolioDocument

    var body: some View {
        HStack(spacing: 14) {
            // Soft rounded tile icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 36, height: 36)

                Image(systemName: doc.kind.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(doc.documentDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let days = doc.daysUntilExpiry {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(days >= 0 ? "\(days)d left" : "Expired")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(days <= 14 ? Color.orange : Color.secondary)
                    }
                }
            }

            Spacer()

            if doc.primaryAmount > 0 {
                Text(VaultAnalyticsEngine.formatINR(doc.primaryAmount))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// Vault Locked View: clean, soft tile Face ID prompt
struct VaultLockedView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 80, height: 80)

                Image(systemName: "faceid")
                    .font(.system(size: 38))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 6) {
                Text("Vault Locked")
                    .font(.system(size: 20, weight: .bold))
                Text("Face ID is required to view your stored documents.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onUnlock) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                    Text("Unlock with Face ID")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 60)
    }
}

// Document Detail View
struct DocumentDetailView: View {
    let document: FolioDocument
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Category")
                        Spacer()
                        Text(document.kind.rawValue)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Date")
                        Spacer()
                        Text(document.documentDate.formatted(date: .long, time: .omitted))
                            .foregroundStyle(.secondary)
                    }

                    if document.primaryAmount > 0 {
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text(VaultAnalyticsEngine.formatINR(document.primaryAmount))
                                .fontWeight(.semibold)
                        }
                    }

                    if document.secondaryAmount > 0 {
                        HStack {
                            Text(document.kind == .payslip ? "TDS Deducted" : "GST")
                            Spacer()
                            Text(VaultAnalyticsEngine.formatINR(document.secondaryAmount))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let exp = document.expiryDate {
                        HStack {
                            Text("Expiry Date")
                            Spacer()
                            Text(exp.formatted(date: .long, time: .omitted))
                                .foregroundStyle(document.needsAttention ? Color.orange : Color.secondary)
                        }
                    }

                    if !document.serialOrInvoiceNo.isEmpty {
                        HStack {
                            Text("Reference / Serial")
                            Spacer()
                            Text(document.serialOrInvoiceNo)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !document.rawExtractedText.isEmpty {
                    Section("Extracted Text") {
                        Text(document.rawExtractedText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Document")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(document.title)
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
typealias VaultListView = VaultView
