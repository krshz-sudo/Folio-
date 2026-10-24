import SwiftUI
import SwiftData
import Vision
import VisionKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

struct DocumentIngestSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraScanner = false
    @State private var showPDFImporter = false
    @State private var rawExtractedText = ""

    // Auto-analysis state
    @State private var isProcessing = false
    @State private var analyzedResult: DocumentAutoCategorizer.AnalyzedResult? = nil
    @State private var showReviewForm = false

    // Editable fields if user wants to tweak
    @State private var draftKind: DocumentKind = .taxInvoice
    @State private var draftTitle: String = ""
    @State private var draftAmount: String = ""
    @State private var draftSerial: String = ""
    @State private var draftDate: Date = .now
    @State private var draftExpiry: Date = .now

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Section: 3 Top Action Tiles matching "Add to Chat" reference screenshot exactly!
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ADD DOCUMENT")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            HStack(spacing: 12) {
                                // 1. Camera Tile
                                Button {
                                    if VNDocumentCameraViewController.isSupported {
                                        showCameraScanner = true
                                    } else {
                                        // Simulator fallback
                                        processDocumentText("WARRANTY CARD: Apple MacBook Pro\nSERIAL NO: SN-MBP99214\nPRICE: 249900\nEXPIRY: 2027-10-24")
                                    }
                                } label: {
                                    ActionTileButton(icon: "camera", label: "Camera")
                                }

                                // 2. Photos Tile
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    ActionTileButton(icon: "photo", label: "Photos")
                                }

                                // 3. Files Tile
                                Button {
                                    showPDFImporter = true
                                } label: {
                                    ActionTileButton(icon: "folder", label: "Files")
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        // If processing auto-scan pipeline
                        if isProcessing {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("Analyzing document with on-device intelligence...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 16)
                        }

                        // Auto-Categorized Review Card (Phase 2 & Phase 9)
                        if showReviewForm, let analyzed = analyzedResult {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                        Text("AUTO-CATEGORIZED")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.green)
                                    }

                                    Spacer()

                                    Text(draftKind.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color(uiColor: .systemGray5))
                                        .clipShape(Capsule())
                                }

                                // Grouped list container with thin dividers (reference screenshot style)
                                VStack(spacing: 0) {
                                    ReviewRow(title: "Title", text: $draftTitle)
                                    Divider().padding(.leading, 16)

                                    ReviewRow(title: "Amount (₹)", text: $draftAmount, keyboardType: .decimalPad)
                                    Divider().padding(.leading, 16)

                                    ReviewRow(title: "Serial / Reference", text: $draftSerial)
                                    Divider().padding(.leading, 16)

                                    HStack {
                                        Text("Date")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        DatePicker("", selection: $draftDate, displayedComponents: .date)
                                            .labelsHidden()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)

                                    if draftKind == .warranty {
                                        Divider().padding(.leading, 16)
                                        HStack {
                                            Text("Warranty Expiry")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            DatePicker("", selection: $draftExpiry, displayedComponents: .date)
                                                .labelsHidden()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(uiColor: .systemBackground))
                                )

                                // Auto-Event notice
                                if analyzed.expiryDate != nil || !analyzed.foundDates.isEmpty {
                                    HStack(spacing: 8) {
                                        Image(systemName: "calendar.badge.clock")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.blue)
                                        Text("Calendar event & reminder will be auto-created on save.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                }

                                // Save button: soft tile style
                                Button {
                                    saveVerifiedDocument()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Save to Vault")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                    .background(Color.primary)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .padding(.top, 4)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scan Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15))
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        recognizeTextFromImage(img)
                    }
                }
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result {
                    extractTextFromPDF(url: url)
                }
            }
            .sheet(isPresented: $showCameraScanner) {
                VisionCameraScannerView { scannedText in
                    processDocumentText(scannedText)
                }
            }
        }
    }

    private func recognizeTextFromImage(_ image: UIImage) {
        isProcessing = true
        guard let cgImage = image.cgImage else { isProcessing = false; return }

        let request = VNRecognizeTextRequest { req, _ in
            let observations = req.results as? [VNRecognizedTextObservation] ?? []
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.processDocumentText(text)
            }
        }
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    private func extractTextFromPDF(url: URL) {
        isProcessing = true
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else { isProcessing = false; return }

        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i)?.string {
                fullText += page + "\n"
            }
        }
        isProcessing = false
        processDocumentText(fullText)
    }

    private func processDocumentText(_ text: String) {
        self.rawExtractedText = text
        let result = DocumentAutoCategorizer.analyze(text: text)
        self.analyzedResult = result

        self.draftKind = result.kind
        self.draftTitle = result.title
        self.draftAmount = result.primaryAmount > 0 ? "\(Int(result.primaryAmount))" : ""
        self.draftSerial = result.serialOrRef
        self.draftDate = result.documentDate
        self.draftExpiry = result.expiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.showReviewForm = true
        }
    }

    private func saveVerifiedDocument() {
        let amount = Double(draftAmount) ?? 0
        let doc = FolioDocument(
            kind: draftKind,
            title: draftTitle.isEmpty ? "\(draftKind.rawValue) Document" : draftTitle,
            tickerSymbol: "\(draftKind.codePrefix).DOC",
            primaryAmount: amount,
            secondaryAmount: 0,
            documentDate: draftDate,
            expiryDate: draftKind == .warranty ? draftExpiry : nil,
            serialOrInvoiceNo: draftSerial,
            rawExtractedText: rawExtractedText,
            claimableTaxCategory: draftKind == .taxInvoice ? "ITC-GST" : "Standard",
            isVerified: true
        )

        // Phase 9: Run Swiggy-style multi-phase Dynamic Island live activity!
        dismiss()

        DynamicIslandManager.shared.runAutoScanPipeline {
            modelContext.insert(doc)
            try? modelContext.save()

            // Phase 9 Auto-creation of Calendar event / Reminder if dates found
            if let exp = doc.expiryDate {
                AgentSystemWriteService.scheduleCalendarEvent(
                    title: "Warranty Expiry: \(doc.title)",
                    date: exp,
                    notes: "Serial: \(doc.serialOrInvoiceNo). Auto-scheduled by Folio on-device intelligence."
                )
                AgentSystemWriteService.scheduleReminder(
                    title: "Check Warranty Status: \(doc.title)",
                    date: exp,
                    notes: "Expires soon (Serial: \(doc.serialOrInvoiceNo))."
                )
            } else if doc.documentDate > Date.now {
                AgentSystemWriteService.scheduleCalendarEvent(
                    title: "Due Date: \(doc.title)",
                    date: doc.documentDate,
                    notes: "Auto-scheduled from verified document."
                )
            }
        }
    }
}

// Action Tile Button: matching reference screenshot exactly (rounded soft-grey tile, icon over label)
struct ActionTileButton: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

struct ReviewRow: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("", text: $text)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct VisionCameraScannerView: UIViewControllerRepresentable {
    var onTextScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: VisionCameraScannerView
        init(_ parent: VisionCameraScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var combinedText = ""
            let group = DispatchGroup()

            for pageIndex in 0..<scan.pageCount {
                let img = scan.imageOfPage(at: pageIndex)
                guard let cgImage = img.cgImage else { continue }
                group.enter()
                let req = VNRecognizeTextRequest { request, _ in
                    let obs = request.results as? [VNRecognizedTextObservation] ?? []
                    let pageText = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    combinedText += pageText + "\n"
                    group.leave()
                }
                req.recognitionLevel = .accurate
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([req])
            }

            group.notify(queue: .main) {
                self.parent.onTextScanned(combinedText)
                self.parent.dismiss()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }
    }
}
