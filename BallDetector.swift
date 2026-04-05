// BallDetector.swift
// GolfShotApp
//
// Detects a stationary white golf ball in top-down camera frames using
// Vision contour detection. Publishes ball position and a "locked" state
// once the ball has been stable for ~1 second.

import Foundation
import Vision
import CoreMedia
import CoreGraphics

// MARK: - DetectedBall

struct DetectedBall: Equatable {
    /// Normalised 0-1, origin top-left (screen coords).
    let center: CGPoint
    /// Normalised radius (fraction of frame width).
    let normalizedRadius: CGFloat

    static func == (lhs: DetectedBall, rhs: DetectedBall) -> Bool {
        abs(lhs.center.x - rhs.center.x) < 0.005 &&
        abs(lhs.center.y - rhs.center.y) < 0.005
    }
}

// MARK: - BallDetector

final class BallDetector: ObservableObject {

    // MARK: Published

    @Published var detected:      DetectedBall? = nil
    @Published var isBallVisible: Bool          = false
    @Published var isLocked:      Bool          = false

    // MARK: Callbacks

    var onLocked:   (() -> Void)?
    var onUnlocked: (() -> Void)?

    // MARK: Private

    private var stableCount   = 0
    private let lockThreshold = 20          // ~1 s at 20 fps
    private var lastCenter:   CGPoint?
    private var frameCounter  = 0
    private let processEvery  = 6           // 1 in 6 frames → ~20 fps at 120 fps input
    private var wasLocked     = false
    private var isActive      = true

    // MARK: - Control

    func start() { isActive = true }

    func reset() {
        stableCount  = 0
        lastCenter   = nil
        wasLocked    = false
        frameCounter = 0
        isActive     = true
        DispatchQueue.main.async {
            self.detected      = nil
            self.isBallVisible = false
            self.isLocked      = false
        }
    }

    func stop() {
        isActive = false
        DispatchQueue.main.async {
            self.detected      = nil
            self.isBallVisible = false
            self.isLocked      = false
        }
    }

    // MARK: - Frame Processing

    func process(sampleBuffer: CMSampleBuffer) {
        guard isActive else { return }
        frameCounter += 1
        guard frameCounter % processEvery == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let result = findBall(in: pixelBuffer)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive else { return }

            // Update stability counter
            if let ball = result {
                if let last = self.lastCenter {
                    let d = hypot(ball.center.x - last.x, ball.center.y - last.y)
                    if d < 0.05 {
                        self.stableCount = min(self.stableCount + 1, self.lockThreshold + 10)
                    } else {
                        self.stableCount = max(0, self.stableCount - 3)
                    }
                } else {
                    self.stableCount = 1
                }
                self.lastCenter = ball.center
            } else {
                self.stableCount = max(0, self.stableCount - 4)
                if self.stableCount == 0 { self.lastCenter = nil }
            }

            self.detected      = result
            self.isBallVisible = result != nil

            let locked = self.stableCount >= self.lockThreshold
            self.isLocked = locked

            if locked && !self.wasLocked {
                self.wasLocked = true
                self.onLocked?()
            } else if !locked && self.wasLocked {
                self.wasLocked = false
                self.onUnlocked?()
            }
        }
    }

    // MARK: - Vision Detection

    private func findBall(in pixelBuffer: CVPixelBuffer) -> DetectedBall? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 3.0
        request.detectsDarkOnLight = false  // white ball on dark/green background

        // .right matches CameraManager's landscapeRight video orientation
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )
        do { try handler.perform([request]) } catch { return nil }

        guard let observations = request.results as? [VNContoursObservation],
              let obs = observations.first else { return nil }

        var bestCenter = CGPoint.zero
        var bestRadius = CGFloat(0)
        var bestScore  = 0.0

        for i in 0..<min(obs.contourCount, 40) {
            guard let contour = try? obs.contour(at: i) else { continue }
            let bbox = contour.normalizedPath.boundingBox

            // Size: ball should be 1.5–13 % of frame
            let avgSize = Double((bbox.width + bbox.height) / 2)
            guard avgSize > 0.015 && avgSize < 0.13 else { continue }

            // Circularity: width/height close to 1
            let ratio = Double(bbox.width / max(bbox.height, 0.001))
            guard ratio > 0.45 && ratio < 2.2 else { continue }

            let score = 1.0 - abs(1.0 - ratio)
            if score > bestScore {
                bestScore  = score
                // Vision origin is bottom-left → flip Y for screen (top-left) coords
                bestCenter = CGPoint(x: Double(bbox.midX), y: 1.0 - Double(bbox.midY))
                bestRadius = CGFloat((bbox.width + bbox.height) / 4)
            }
        }

        guard bestScore > 0.35 else { return nil }
        return DetectedBall(center: bestCenter, normalizedRadius: bestRadius)
    }
}
