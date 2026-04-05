// Models.swift
// GolfShotApp
//
// Data models for shots, clubs, and metrics

import Foundation
import CoreGraphics

// MARK: - Club

enum Club: String, CaseIterable, Codable, Identifiable {
    case driver       = "Driver"
    case wood3        = "3 Wood"
    case wood5        = "5 Wood"
    case hybrid       = "Hybrid"
    case iron3        = "3 Iron"
    case iron4        = "4 Iron"
    case iron5        = "5 Iron"
    case iron6        = "6 Iron"
    case iron7        = "7 Iron"
    case iron8        = "8 Iron"
    case iron9        = "9 Iron"
    case pitchingWedge = "PW"
    case gapWedge     = "GW"
    case sandWedge    = "SW"
    case lobWedge     = "LW"
    case putter       = "Putter"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .driver:        return "🏌️"
        case .wood3, .wood5: return "🌲"
        case .hybrid:        return "⚡️"
        case .iron3, .iron4, .iron5,
             .iron6, .iron7, .iron8, .iron9: return "🔧"
        case .pitchingWedge, .gapWedge,
             .sandWedge, .lobWedge:          return "⛳"
        case .putter:        return "🎯"
        }
    }

    /// Typical carry distance range in yards for an average golfer
    var typicalDistanceRange: ClosedRange<Double> {
        switch self {
        case .driver:        return 200...280
        case .wood3:         return 180...240
        case .wood5:         return 165...220
                case .hybrid:        return 155...210
        case .iron3:         return 155...200
        case .iron4:         return 145...190
        case .iron5:         return 135...180
        case .iron6:         return 125...170
        case .iron7:         return 115...160
        case .iron8:         return 105...150
        case .iron9:         return 95...140
        case .pitchingWedge: return 80...130
        case .gapWedge:      return 70...115
        case .sandWedge:     return 55...100
        case .lobWedge:      return 40...80
        case .putter:        return 0...30
        }
    }
}

// MARK: - ShotMetrics

struct ShotMetrics: Codable {
    /// Total estimated distance in yards (carry + roll)
    var distanceYards: Double
    /// Carry-only distance in yards
    var carryYards: Double
    /// Estimated launch angle in degrees (derived from club loft)
    var launchAngleDegrees: Double
    /// Launch direction in degrees (positive = right / R, negative = left / L)
    var directionDegrees: Double
    /// Ball speed in mph (measured top-down)
    var ballSpeedMPH: Double
    /// Club head speed in mph (measured top-down, 0 if not tracked)
    var clubSpeedMPH: Double
    /// Smash factor = Ball Speed / Club Speed (0 if club speed unavailable)
    var smashFactor: Double
    /// Shot shape descriptor
    var shotShape: ShotShape
    /// Peak height estimate in feet
    var peakHeightFeet: Double

    static var zero: ShotMetrics {
        ShotMetrics(distanceYards: 0, carryYards: 0, launchAngleDegrees: 0,
                    directionDegrees: 0, ballSpeedMPH: 0, clubSpeedMPH: 0,
                    smashFactor: 0, shotShape: .straight, peakHeightFeet: 0)
    }

    enum ShotShape: String, Codable {
        case straight = "Straight"
        case draw     = "Draw"
        case fade     = "Fade"
        case hook     = "Hook"
        case slice    = "Slice"
        case push     = "Push"
        case pull     = "Pull"

        var color: String {
            switch self {
            case .straight:     return "green"
            case .draw, .fade:  return "blue"
            case .hook, .slice: return "red"
            case .push, .pull:  return "orange"
            }
        }
    }
}

// MARK: - Shot

struct Shot: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var club: Club
    var metrics: ShotMetrics
    /// Local file URL of the recorded video (relative path stored)
    var videoFilename: String?
    /// Trajectory points normalised to 0-1 in both axes
    var trajectoryPoints: [CGPoint]

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - CodablePoint helper

// CGPoint is not Codable by default when embedded inside arrays stored via JSONEncoder.
// We store trajectory points as pairs of Double.
extension CGPoint: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(Double(x))
        try container.encode(Double(y))
    }
}
