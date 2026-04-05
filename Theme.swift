// Theme.swift
// GolfShotApp
//
// App-wide colour palette and design tokens.
// Since we cannot ship an Asset Catalog as a plain Swift file, all colours
// are defined here as static properties and referenced throughout the app.
// Replace every `Color("GolfGreen")` with `AppTheme.green` if you prefer
// to avoid the asset-catalog dependency, or add "GolfGreen" to Assets.xcassets.

import SwiftUI

enum AppTheme {
    // Primary brand green (similar to a golf fairway)
    static let green        = Color(red: 0.107, green: 0.420, blue: 0.208)
    static let lightGreen   = Color(red: 0.180, green: 0.800, blue: 0.443)

    // Accent colours
    static let sand         = Color(red: 0.937, green: 0.867, blue: 0.706)
    static let sky          = Color(red: 0.529, green: 0.808, blue: 0.922)

    // Background shades
    static let darkBackground   = Color(red: 0.07, green: 0.12, blue: 0.07)
    static let cardBackground   = Color(.systemBackground)

    // Metric colours
    static let distanceColor    = green
    static let speedColor       = Color.orange
    static let angleColor       = Color.blue
    static let directionColor   = Color.purple
    static let heightColor      = Color.teal
}

// MARK: - View modifier helpers

extension View {
    /// Applies a golf-green card background.
    func golfCard() -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
    }
}
