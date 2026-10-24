# Folio — Private On-Device Document & Financial Vault for iOS

> **Zero Cloud • 100% On-Device • Apple Intelligence • Cryptographic Proofs**

Folio is a native iOS application built with **SwiftUI**, **SwiftData**, and **Apple Foundation Models**. It serves as a secure, private document vault for warranties, payslips, and tax invoices with on-device OCR, multi-phase intelligence pipelines, automatic event scheduling (Calendar & Reminders), biometric Face ID protection, and SHA-256 cryptographic proof hashing.

---

## 🧠 4-Phase Intelligence Engine Architecture

### Phase 1 — Image Intelligence
- **High-Accuracy Vision OCR**: Powered by Apple's `VNRecognizeTextRequest` with `.accurate` recognition and language correction across camera scans, photo library assets, and digital PDFs.
- **PhotosPicker Integration**: Fast, native iOS photo library picker allowing instant receipt and bill ingestion.
- **Foundation Models Integration**: Uses on-device heuristics and `FoundationModels.framework` to interpret unstructured text into structured schema records.
- **Event Extraction**: Extracts event types (`warrantyExpiry`, `paymentDue`, `salaryCredit`, `subscriptionRenewal`), locations, amounts, serial numbers, and reference codes.
- **Event Summaries**: Produces human-readable, structured executive summaries for every analyzed document.

### Phase 2 — Date Intelligence
- **Timezone & Locale Awareness**: Captures current time and device timezone (`TimeZone.current`, `Calendar.current`) to interpret relative date markers ("due next Friday", "due in 30 days").
- **Missing-Year Resolution**: Accurately infers missing years based on document context (e.g. historical invoices infer past years, upcoming renewal dates infer future years).
- **Past-Event Detection**: Distinguishes historical events from future deadlines (`isPast = true`), ensuring alarms are not created for elapsed dates.
- **Ambiguity Handling**: Resolves ambiguous numeric formats (e.g., `05/06/2026`) based on regional locale standards (`en_IN` DD/MM/YYYY vs `en_US` MM/DD/YYYY).
- **Strict Date Validation**: Gregorian date validation ensuring leap years, day-count boundaries, and timestamps are mathematically sound.

### Phase 3 — Apple Integration
- **Native iOS Calendar Events**: Schedules real `EKEvent` entries in the user's default iOS Calendar via `EKEventStore` with dual alarm triggers (1-day before and 2-hours before).
- **Native iOS Reminders**: Creates real `EKReminder` entries with high priority and local notifications via `UNUserNotificationCenter`.
- **Permission Handling**: Fully compliant with iOS 17+ / iOS 26+ full access permissions (`requestFullAccessToEvents()`, `requestFullAccessToReminders()`).
- **Duplicate Detection**: Evaluates Calendar entries within a 24-hour window (`findDuplicateEvent(title:date:)`) before writing, preventing duplicate events.
- **Save Confirmation & Error Handling**: Rich user feedback via Swiggy-style animated Dynamic Island banners and typed `IntegrationError` recovery flows.

### Phase 4 — Folio Agent
- **Natural-Language Commands**: Parses complex intent queries (e.g., *"Schedule my MacBook warranty expiry"*, *"Remind me to check rent next Monday"*, *"How much did I earn this month?"*).
- **Proactive Event Suggestions**: Recommends actionable calendar reminders directly from stored documents without prompting.
- **User-Approved Actions Gate**: Displays interactive approval cards for tool calls with three distinct options:
  - **Allow Once**: Executes the single action immediately.
  - **Always Allow**: Sets persistent policy to always permit that tool without asking again.
  - **Deny**: Cancels execution and records user refusal.
- **Dedicated Tool Permissions Toggle Page**: Accessible anytime via the dashboard header or agent settings (`ToolPermissionsToggleView`) with segmented selectors for Calendar and Reminders tools (`Ask Every Time`, `Always Allow`, `Deny`).
- **Confirmation & Success Feedback**: Native haptic feedback and Dynamic Island banners on completion.

---

## ✨ Visual Aesthetics & UI/UX

- **Mobbin-Inspired Soft Tiles**: Rounded containers (`cornerRadius: 18`) with subtle borders, thin hairline dividers, and clean typography.
- **Custom Floating Bottom Navigation Bar**: Elevated capsule bar featuring a prominent center UPI-style scan button.
- **Swiggy-Style Dynamic Island**: Multi-phase real-time status banner animating across scanning, analyzing, calendar scheduling, and vault storage.
- **Biometric Face ID Shield**: Absolute zero-leakage security. All document names, amounts, and dates are completely hidden until Face ID verification passes.
- **Dynamic Light & Dark Mode**: Seamless toggle matching iOS system aesthetics.

---

## 📁 Repository Structure

```
FolioPro/
├── FolioPro.xcodeproj/
│   ├── project.pbxproj         # Xcode project configuration (Deployment target: iOS 17.0+)
│   └── xcshareddata/
│       └── xcschemes/
│           └── FolioPro.xcscheme # Shared build scheme for command line & CI
├── FolioPro/
│   ├── FolioProApp.swift       # App entry point, RootContainerView, Theme toggle & Custom Bottom Bar
│   ├── VaultAndChartsView.swift# Face ID-gated Vault, Category lists & Document detail view
│   ├── AgentAndAskView.swift   # On-device AI Agent, Tool calling, Approval cards & Permissions sheet
│   ├── ScannerAndOCR.swift     # Multi-modal Ingest Studio, Vision OCR & Date Intelligence review
│   ├── Models.swift            # SwiftData @Model FolioDocument, DateIntelligenceEngine & Categorizer
│   ├── AnalyticsEngine.swift   # Pure Swift analytics (Net pay, GST totals, Document groups)
│   ├── SecurityAndIntents.swift# EventKit Integration, Face ID Manager, Dynamic Island & Permissions
│   ├── Info.plist              # Camera, Face ID, Calendar & Reminders permission strings
│   └── Assets.xcassets/        # AppIcon & AccentColor asset catalogs
├── .gitignore                  # Clean gitignore excluding build/ and xcuserdata
└── README.md                   # Project documentation
```

---

## 🛠️ Requirements & Prerequisites

- **macOS**: Sonoma 14.0 or newer.
- **Xcode**: Xcode 16.0 or newer (SDK: `iPhoneOS 17.0+` / `iPhoneOS 26.5+`).
- **Device**: iPhone running iOS 17.0+ (Tested on iPhone 16 Plus with iOS 27.2 Beta on Apple Silicon A18).
- **Entitlements**:
  - Camera (`NSCameraUsageDescription`)
  - Face ID (`NSFaceIDUsageDescription`)
  - Calendars (`NSCalendarsFullAccessUsageDescription`)
  - Reminders (`NSRemindersFullAccessUsageDescription`)

---

## 🚀 Building & Deploying

### Option 1: Build in Xcode
1. Double-click `FolioPro.xcodeproj`.
2. Select your Apple Development Team in **Signing & Capabilities**.
3. Choose your connected physical iPhone or iOS Simulator.
4. Press `Cmd + R` to build and run.

### Option 2: Build & Deploy via Terminal
```bash
# Build for physical device
xcodebuild -project FolioPro.xcodeproj \
           -scheme FolioPro \
           -destination "id=00008140-0014308E0C40801C" \
           -configuration Debug build

# Install and launch on device
xcrun devicectl device install app --device 64FC44D2-46EA-5ADF-8BD6-E3DFFBCDBAB1 /path/to/FolioPro.app
xcrun devicectl device process launch --device 64FC44D2-46EA-5ADF-8BD6-E3DFFBCDBAB1 com.folio.vault.pro
```

---

## 🛡️ Privacy & Security Architecture

1. **Zero Network Calls**: Folio does not connect to any external cloud API, telemetry service, or remote database.
2. **SwiftData On-Device Database**: Stored in the app's secure sandboxed application support directory.
3. **Keychain Anchor**: Cryptographic SHA-256 genesis hashes are anchored in the iOS Secure Enclave / Keychain.
4. **Local Authentication**: Uses `LAContext().evaluatePolicy(.deviceOwnerAuthentication)` for biometric Face ID authorization.

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).
