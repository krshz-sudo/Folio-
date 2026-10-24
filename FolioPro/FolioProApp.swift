import SwiftUI
import SwiftData

@main
struct FolioProApp: App {
    @AppStorage("app_theme") private var appTheme: String = "system"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([FolioDocument.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }()

    var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolioDocument.documentDate, order: .reverse) private var documents: [FolioDocument]

    @AppStorage("app_theme") private var appTheme: String = "system"
    @StateObject private var security = SecurityGateManager()
    @StateObject private var dynamicIsland = DynamicIslandManager.shared

    @State private var selectedTab: Int = 0 // 0 = Dashboard, 1 = Agent
    @State private var showScanner = false
    @State private var showVaultSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Tabs
            Group {
                if selectedTab == 0 {
                    DashboardView(
                        documents: documents,
                        showScanner: $showScanner,
                        showVault: $showVaultSheet,
                        appTheme: $appTheme
                    )
                } else {
                    AgentView(documents: documents)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80) // Space for custom bottom navigation bar

            // Phase 6: Custom Bottom Navigation Bar
            CustomBottomBar(
                selectedTab: $selectedTab,
                onCenterScanTap: {
                    showScanner = true
                }
            )

            // Phase 8 & 9: Swiggy-style Dynamic Island Overlay
            if dynamicIsland.state != .idle {
                DynamicIslandBannerView(state: dynamicIsland.state)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            // Phase 2: Purge mock/fake data on startup
            SampleVaultSeeder.seedIfNeeded(context: modelContext)
        }
        .sheet(isPresented: $showScanner) {
            DocumentIngestSheet()
        }
        .sheet(isPresented: $showVaultSheet) {
            VaultView(documents: documents, security: security)
        }
    }
}

// Phase 5: Clean, Minimalist Dashboard (No day/date, no tickers, no filler)
struct DashboardView: View {
    let documents: [FolioDocument]
    @Binding var showScanner: Bool
    @Binding var showVault: Bool
    @Binding var appTheme: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        // Phase 1 Button Style: Action Tiles matching reference screenshot
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ACTIONS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            HStack(spacing: 12) {
                                // Scan Document Tile
                                Button {
                                    showScanner = true
                                } label: {
                                    SoftActionTile(icon: "camera.viewfinder", label: "Scan Document", count: nil)
                                }

                                // Vault Tile (Requires Face ID)
                                Button {
                                    showVault = true
                                } label: {
                                    SoftActionTile(icon: "lock.shield.fill", label: "Vault", count: documents.count)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                        // Recent Documents Container (Reference screenshot style: soft container with thin dividers)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("DOCUMENTS")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Open Vault") {
                                    showVault = true
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 4)

                            if documents.isEmpty {
                                // Empty state: clean, honest, zero mock data
                                VStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 34, weight: .light))
                                        .foregroundStyle(.secondary)
                                    Text("No documents stored yet")
                                        .font(.system(size: 15, weight: .medium))
                                    Text("Tap Scan Document above to securely add warranties, payslips, or invoices.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                )
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(documents.prefix(5).enumerated()), id: \.element.id) { index, doc in
                                        Button {
                                            showVault = true
                                        } label: {
                                            DocumentRowView(doc: doc)
                                        }
                                        .buttonStyle(.plain)

                                        if index < min(documents.count, 5) - 1 {
                                            Divider()
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Phase 1: Theme Toggle (Light / Dark mode toggle)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if appTheme == "dark" {
                                appTheme = "light"
                            } else {
                                appTheme = "dark"
                            }
                        }
                    } label: {
                        Image(systemName: appTheme == "dark" ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}

// Phase 1: Soft Tile Button (Icon centered above short label)
struct SoftActionTile: View {
    let icon: String
    let label: String
    let count: Int?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let count = count {
                    Text("\(count) items")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

// Phase 6: Custom Bottom Navigation Bar
struct CustomBottomBar: View {
    @Binding var selectedTab: Int
    let onCenterScanTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left: Dashboard tab
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 0
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                        .font(.system(size: 20, weight: .medium))
                    Text("Dashboard")
                        .font(.system(size: 10, weight: selectedTab == 0 ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == 0 ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
            }

            // Center: Large circular Scan Document button (like UPI scan button)
            Button(action: onCenterScanTap) {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
            .offset(y: -14) // Floating prominent UPI style button
            .frame(maxWidth: .infinity)

            // Right: Agent tab
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 1
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: selectedTab == 1 ? "sparkles" : "sparkle")
                        .font(.system(size: 20, weight: .medium))
                    Text("Agent")
                        .font(.system(size: 10, weight: selectedTab == 1 ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == 1 ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// Phase 8 & 9: Swiggy-style Multi-Phase Dynamic Island / Live Activity Banner
struct DynamicIslandBannerView: View {
    let state: DynamicIslandManager.State

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .idle:
                EmptyView()

            case .completion(let title, let subtitle, _):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

            case .scanPhase(let phase, let title):
                Image(systemName: phase.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Swiggy-style 4-phase step indicator dots
                    HStack(spacing: 4) {
                        ForEach(DynamicIslandManager.State.Phase.allCases, id: \.rawValue) { p in
                            Circle()
                                .fill(p.rawValue <= phase.rawValue ? Color.green : Color.white.opacity(0.25))
                                .frame(width: 5, height: 5)

                            if p.rawValue < 4 {
                                Rectangle()
                                    .fill(p.rawValue < phase.rawValue ? Color.green : Color.white.opacity(0.25))
                                    .frame(width: 14, height: 2)
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
}
