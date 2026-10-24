# Folio — Private On-Device Document & Financial Vault for iOS

> **Zero Cloud • 100% On-Device • Apple Intelligence • Cryptographic Proofs**

Folio is a native iOS application built with **SwiftUI**, **SwiftData**, and **Apple Foundation Models**. It serves as a secure, private document vault for warranties, payslips, and tax invoices with on-device OCR, automatic event scheduling (Calendar & Reminders), biometric Face ID protection, and SHA-256 cryptographic proof hashing.

---

## ✨ Key Features

### 1. Minimalist Mobbin-Inspired UI/UX
- **Soft-Grey Action Tiles**: Clean, rounded tiles (`cornerRadius: 18`) with icons centered above short labels matching modern iOS design standards.
- **Structured Grouped Lists**: Information grouped in subtle containers separated by hairline dividers.
- **Dark & Light Mode**: Built-in dynamic theme toggle with consistent aesthetics across both modes.
- **UPI-Style Center Scan Button**: A prominent circular scan button floating in the center of the bottom navigation bar for instant access.

### 2. Autonomous Document Ingestion & Auto-Categorization
- **Multi-Modal Ingestion**:
  - **Camera (VisionKit)**: Live hardware document camera scanning.
  - **Photos (Vision OCR)**: Fast optical text recognition from photo library receipts.
  - **Files (PDFKit)**: Stream and extract text from digital PDF bills and statements.
- **Intelligent Auto-Categorization**:
  - Automatically identifies whether an uploaded document is a **Warranty**, **Payslip**, or **Tax Invoice** by reading the document content directly.
  - **No document is left uncategorized**.

### 3. Swiggy-Style Multi-Phase Dynamic Island
- Real-time animated Dynamic Island / Live Activity tracking during document processing:
  1. `Phase 1: Scanning OCR` — Reading text and optical tokens.
  2. `Phase 2: Apple Intelligence` — On-device foundation model date and category extraction.
  3. `Phase 3: Auto Calendar & Reminders` — Auto-scheduling renewal, expiry, or payment dates.
  4. `Phase 4: Vault Stored` — Cryptographically signed and persisted to SwiftData.

### 4. On-Device AI Agent (Apple Foundation Models)
- Powered by `FoundationModels.framework` on Apple Silicon.
- **Live Status Indicator**: Green dot when Apple Foundation Models are connected; red when unavailable.
- **Native Tool Calling**:
  - `scheduleCalendarEvent(title:date:notes:)` — Directly writes events to iOS Calendar via EventKit.
  - `scheduleReminder(title:date:notes:)` — Schedules notification reminders via UNUserNotificationCenter.
- **Dynamic Island Completion**: Smooth expanding Dynamic Island banner whenever an agent task is completed.
- **Robust Keyboard Handling**: Native scroll and keyboard avoidance with a top-left back button.

### 5. Biometric Face ID Vault
- **Strict Zero-Leakage Privacy**: All document titles, amounts, and contents in the Vault remain completely hidden until Face ID authentication succeeds.
- Documents are organized cleanly into 3 categories:
  - **Warranties**: Tracks coverage, serial numbers, and expiry countdowns.
  - **Payslips**: Tracks earnings, employer details, and TDS deductions.
  - **Tax Invoices**: Tracks vendor receipts, GST numbers, and payment dates.

### 6. Cryptographic Genesis Proofs
- Every document is hashed with **SHA-256** using an on-device iOS Keychain anchor (`CryptoKit`).
- Tamper-evident ledger guarantees document integrity offline without any third-party server.

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
│   ├── AgentAndAskView.swift   # On-device AI Agent, Apple Foundation Model session & Tool execution
│   ├── ScannerAndOCR.swift     # Multi-modal Ingest Studio, Vision OCR & Auto-Categorization
│   ├── Models.swift            # SwiftData @Model FolioDocument, CryptoProofService & AutoCategorizer
│   ├── AnalyticsEngine.swift   # Pure Swift analytics (Net pay, GST totals, Document groups)
│   ├── SecurityAndIntents.swift# LocalAuthentication (Face ID), DynamicIslandManager & AppIntents
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

## 🚀 Building & Running

### Option 1: Open in Xcode
1. Double-click `FolioPro.xcodeproj`.
2. Select your signing team in **Signing & Capabilities**.
3. Select your connected physical device or iOS Simulator.
4. Press `Cmd + R` to build and run.

### Option 2: Build from Terminal (`xcodebuild`)
```bash
# Build for connected physical device:
xcodebuild -project FolioPro.xcodeproj \
           -scheme FolioPro \
           -destination "generic/platform=iOS" \
           -configuration Debug build
```

### Option 3: Deploy via `devicectl`
```bash
# Find CoreDevice ID:
xcrun devicectl list devices

# Install app to device:
xcrun devicectl device install app --device <DEVICE_UUID> /path/to/FolioPro.app

# Launch app on device:
xcrun devicectl device process launch --device <DEVICE_UUID> com.folio.vault.pro
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
