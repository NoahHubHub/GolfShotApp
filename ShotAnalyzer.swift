// ShotAnalyzer.swift
// GolfShotApp
//
// Calculates shot metrics from a top-down camera perspective.
// The phone lies flat on a tripod ~50-100 cm above the ball, pointing straight down.
//
// What is VISIBLE from top-down:
//   - Club head path and speed (before impact)
//   - Ball movement direction and speed (after impact)
//   - Launch direction (L/R angle) — directly measurable
//   - Shot shape (draw/fade/hook/slice)
//
// What must be ESTIMATED:
//   - Launch angle (not visible from above; estimated from club loft lookup)
//   - Carry distance (physics: v² sin(2θ) / g)
//   - Peak height (physics: v² sin²(θ) / 2g)
//   - Total distance (carry + roll estimate)

import Foundation
import CoreGraphics

// MARK: - ShotAnalyzer

struct ShotAnalyzer {

    // MARK: - Camera geometry constants

    /// iPhone wide-angle lens horizontal FOV ≈ 67°.
    /// At 80 cm mounting height: frame width = 2 × 0.8 × tan(33.5°) ≈ 1.06 m.
    /// Adjust `mountingHeightCM` to match the actual tripod height used.
    static var mountingHeightCM: Double = 80.0

    private static let iPhoneHorizontalFOVDeg: Double = 67.0

    /// Real-world width of the camera frame (metres) at the configured height.
    private static var frameWidthMetres: Double {
        let halfAngleRad = (iPhoneHorizontalFOVDeg / 2.0) * .pi / 180.0
        return 2.0 * (mountingHeightCM / 100.0) * tan(halfAngleRad)
    }

    // MARK: - Physical constants

    private static let gravity: Double        = 9.81   // m/s²
    private static let mphPerMPS: Double      = 2.23694
    private static let yardsPerMetre: Double  = 1.09361
    private static let rollFactor: Double     = 1.15   // total ≈ carry × 1.15

    // MARK: - Typical club loft table (degrees)
    // Used to estimate launch angle when it cannot be seen from above.

    private static let clubLoftTable: [String: Double] = [
        "Driver":  11,  "3 Wood": 15,  "5 Wood":  18,
        "3 Iron":  21,  "4 Iron": 24,  "5 Iron":  27,
        "6 Iron":  31,  "7 Iron": 35,  "8 Iron":  39,
        "9 Iron":  43,  "PW":     47,  "GW":      51,
        "SW":      55,  "LW":     59,  "60°":     60,
        "Putter":   4
    ]

    // Optimal launch angle is typically 70-75 % of loft for a well-struck shot.
    private static let launchEfficiency: Double = 0.72

    // MARK: - Main Analysis

    /// Analyses a top-down trajectory and returns ShotMetrics.
    ///
    /// - Parameters:
    ///   - ballPoints:  Normalised (0-1) ball trajectory points AFTER impact,
    ///                  Y increasing downward (Vision coords flipped in BallTracker).
    ///   - clubPoints:  Normalised club-head trajectory points BEFORE impact.
    ///   - clubName:    Name of the club used (for loft lookup).
    ///   - capturedFPS: Frame rate of the capture session.
    static func analyze(ballPoints: [CGPoint],
                        clubPoints: [CGPoint] = [],
                        clubName: String = "7 Iron",
                        capturedFPS: Double = 120.0) -> ShotMetrics {

        guard ballPoints.count >= 2 else {
            return .zero
        }

        let fw = frameWidthMetres

        // ------------------------------------------------------------------
        // 1. Ball speed  (from first few post-impact frames)
        // ------------------------------------------------------------------
        let ballPixelSpeed  = averagePixelSpeed(from: ballPoints, window: 5)
        // pixel displacement is in normalised units (0-1 = full frame width)
        let ballSpeedMPS    = ballPixelSpeed * fw * capturedFPS
        let ballSpeedMPH    = ballSpeedMPS * mphPerMPS

        // ------------------------------------------------------------------
        // 2. Club speed  (from last few pre-impact frames)
        // ------------------------------------------------------------------
        var clubSpeedMPH: Double = 0
        if clubPoints.count >= 2 {
            let clubPixelSpeed = averagePixelSpeed(from: clubPoints, window: 5)
            let clubSpeedMPS   = clubPixelSpeed * fw * capturedFPS
            clubSpeedMPH       = clubSpeedMPS * mphPerMPS
        }

        // ------------------------------------------------------------------
        // 3. Smash factor  = Ball Speed / Club Speed
        // ------------------------------------------------------------------
        let smashFactor: Double = clubSpeedMPH > 0
            ? min(ballSpeedMPH / clubSpeedMPH, 1.55)   // physical max ~1.55
            : 0

        // ------------------------------------------------------------------
        // 4. Launch direction  (degrees, R = right, L = left)
        //    Measured as the angle of ball movement from the "away" axis.
        //    In top-down view the ball moves away from the player;
        //    lateral deviation = left/right.
        // ------------------------------------------------------------------
        let directionDeg = calculateLaunchDirection(from: ballPoints)

        // ------------------------------------------------------------------
        // 5. Estimated launch angle  (not visible from above)
        // ------------------------------------------------------------------
        let loft              = clubLoftTable[clubName] ?? 35.0
        let launchAngleDeg    = loft * launchEfficiency

        // ------------------------------------------------------------------
        // 6. Carry distance  (projectile physics)
        // ------------------------------------------------------------------
        let carryMetres       = carryDistance(speedMPS: ballSpeedMPS, angleDeg: launchAngleDeg)
        let carryYards        = carryMetres * yardsPerMetre

        // ------------------------------------------------------------------
        // 7. Total distance  (carry + estimated roll)
        // ------------------------------------------------------------------
        let totalYards        = carryYards * rollFactor

        // ------------------------------------------------------------------
        // 8. Peak height
        // ------------------------------------------------------------------
        let peakMetres        = peakHeight(speedMPS: ballSpeedMPS, angleDeg: launchAngleDeg)
        let peakHeightFeet    = peakMetres * 3.28084

        // ------------------------------------------------------------------
        // 9. Shot shape
        // ------------------------------------------------------------------
        let shotShape = classifyShotShape(directionDeg: directionDeg,
                                          ballPoints: ballPoints)

        return ShotMetrics(
            distanceYards:      max(0, totalYards),
            carryYards:         max(0, carryYards),
            launchAngleDegrees: launchAngleDeg,
            directionDegrees:   directionDeg,
            ballSpeedMPH:       max(0, ballSpeedMPH),
            clubSpeedMPH:       max(0, clubSpeedMPH),
            smashFactor:        smashFactor,
            shotShape:          shotShape,
            peakHeightFeet:     max(0, peakHeightFeet)
        )
    }

    // MARK: - Private helpers

    /// Average pixel speed (normalised units/frame) over a sliding window.
    private static func averagePixelSpeed(from points: [CGPoint], window: Int) -> Double {
        let w = min(window, points.count - 1)
        guard w > 0 else { return 0 }
        var total = 0.0
        for i in 0..<w {
            let dx = Double(points[i + 1].x - points[i].x)
            let dy = Double(points[i + 1].y - points[i].y)
            total += sqrt(dx * dx + dy * dy)
        }
        return total / Double(w)
    }

    /// Launch direction in degrees.
    /// Top-down view: ball moves "away" along one axis (Y in normalised coords).
    /// Lateral deviation (X) gives left/right angle relative to target line.
    /// Positive = right (R), negative = left (L).
    private static func calculateLaunchDirection(from points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        // Use the initial movement vector (first 3 points if available)
        let endIdx = min(3, points.count - 1)
        let dx = Double(points[endIdx].x - points[0].x)  // lateral
        let dy = Double(points[endIdx].y - points[0].y)  // forward (away from player)

        guard abs(dy) > 0.001 else { return 0 }

        // atan2(lateral, forward) gives angle off the target line
        let angleRad = atan2(dx, abs(dy))
        return angleRad * 180.0 / .pi
    }

    /// Carry: R = v² sin(2θ) / g
    private static func carryDistance(speedMPS: Double, angleDeg: Double) -> Double {
        guard angleDeg > 0, speedMPS > 0 else { return 0 }
        let angleRad = angleDeg * .pi / 180.0
        return (speedMPS * speedMPS * sin(2 * angleRad)) / gravity
    }

    /// Peak height: H = v² sin²(θ) / (2g)
    private static func peakHeight(speedMPS: Double, angleDeg: Double) -> Double {
        guard angleDeg > 0, speedMPS > 0 else { return 0 }
        let angleRad = angleDeg * .pi / 180.0
        let sinT = sin(angleRad)
        return (speedMPS * speedMPS * sinT * sinT) / (2 * gravity)
    }

    /// Shot shape from top-down trajectory curvature and direction.
    private static func classifyShotShape(directionDeg: Double,
                                           ballPoints: [CGPoint]) -> ShotMetrics.ShotShape {
        let curvature = horizontalCurvature(from: ballPoints)
        let isRight    = directionDeg  >  2
        let isLeft     = directionDeg  < -2
        let curvesRight = curvature    >  0.02
        let curvesLeft  = curvature    < -0.02

        switch (isRight, isLeft, curvesRight, curvesLeft) {
        case (false, false, false, false): return .straight
        case (true,  _,     false, true):  return .draw
        case (false, true,  true,  false): return .fade
        case (true,  _,     _,     false) where abs(directionDeg) > 10: return .push
        case (false, true,  false, _)     where abs(directionDeg) > 10: return .pull
        case (_,     _,     false, true)  where curvature < -0.08:      return .hook
        case (_,     _,     true,  false) where curvature  >  0.08:     return .slice
        case (false, false, true,  false): return .fade
        case (false, false, false, true):  return .draw
        default:                           return .straight
        }
    }

    /// Net lateral curvature: positive = curves right, negative = left.
    private static func horizontalCurvature(from points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        let third = max(1, points.count / 3)
        let startDX = Double(points[third].x - points[0].x)
        let last    = points.count - 1
        let endDX   = Double(points[last].x - points[last - third].x)
        return endDX - startDX
    }
}
