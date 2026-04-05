// GolfShotApp.swift
// GolfShotApp
//
// App entry point.
//
// ─── Required Info.plist entries ─────────────────────────────────────────────
//
// Key: NSCameraUsageDescription
// Value: "GolfShotApp uses the camera to detect and track your golf ball during a shot."
//
// Key: NSMicrophoneUsageDescription
// Value: "Microphone access is needed to record shot videos with audio."
//
// Key: NSPhotoLibraryAddUsageDescription
// Value: "Shot videos are saved to your Photo Library so you can review them later."
//
// Key: NSPhotoLibraryUsageDescription  (iOS 14+, needed for PHPicker if used)
// Value: "Allows access to Photo Library for saving shot videos."
//
// ─── Asset Catalog ────────────────────────────────────────────────────────────
//
// Add a Color named "GolfGreen" (hex #1B6B35 / dark: #2ECC71) to Assets.xcassets.
// You can also add it programmatically via the extension below as a fallback.
//
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

@main
struct GolfShotApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - GolfGreen fallback colour

extension Color {
    /// Fallback used when the Asset Catalog colour "GolfGreen" is not defined.
    static let golfGreenFallback = Color(red: 0.107, green: 0.420, blue: 0.208)

    /// Call this during app init to register a programmatic colour if needed.
    static func registerGolfGreenIfNeeded() {
        // If Assets.xcassets contains "GolfGreen" this is a no-op;
        // otherwise components use .golfGreenFallback explicitly.
    }
}
