// BallDetector.swift
// GolfShotApp
//
// Detects a white golf ball in top-down camera frames via fast Y-plane
// luminance scanning. Also detects when the ball is struck (disappears
// or moves sharply after being locked) and collects post-impact positions.
//
// Coordinate convention for all public outputs:
//   x = 0 (left) … 1 (right) on screen
//   y = 0 (top)  … 1 (bottom) on screen
//
// The camera is set to videoOrientation = .landscapeRight, so the pixel
// buffer is landscape (W>H). Mapping to portrait screen (orientation .right):
//   screen_x = 1 – row / bufferHeight
//   screen_y =     col / bufferWidth

import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics

// MARK: - DetectedBall

struct DetectedBall: Equatable {
    let center: CGPoint        // screen-space, 0-1
    let normalizedRadius: CGFloat

    static func == (l: Self, r: Self) -> Bool {
        abs(l.center.x - r.center.x) < 0.008 &&
        abs(l.center.y - r.center.y) < 0.008
    }
}

// MARK: - BallDetector

final class BallDetector: ObservableObject {

    // MARK: – Published

    @Published var detected:      DetectedBall? = nil
    @Published var isBallVisible: Bool          = false
    @Published var isLocked:      Bool          = false

    // MARK: – Callbacks

    var onLocked:        (() -> Void)?
    var onUnlocked:      (() -> Void)?
    /// Fired once after a shot; receives whatever post-impact positions were collected.
    var onShotDetected:  (([CGPoint]) -> Void)?

    // MARK: – Private state

    private enum Phase { case idle, detecting, locked, shotTracking }
    private var phase: Phase = .idle

    private var stableCount   = 0
    private let lockThreshold = 22          // ~22 detection-frames ≈ 1 s at 20 fps
    private var lastCenter:   CGPoint?
    private var lockedCenter: CGPoint?      // frozen when ball locks
    private var wasLocked     = false

    private var missCount          = 0
    private let shotMissThreshold  = 2      // consecutive misses → shot fired

    private var frameIndex = 0
    private let detectEvery = 5             // process every 5th frame → ~24 fps at 120 fps

    private var postShotPositions:  [CGPoint] = []
    private var postShotFrameCount  = 0
    private let postShotMaxFrames   = 40    // collect up to 40 post-impact frames

    // MARK: – Control

    func startDetecting() {
        resetPrivate()
        phase = .detecting
    }

    func reset() {
        resetPrivate()
        DispatchQueue.main.async {
            self.detected      = nil
            self.isBallVisible = false
            self.isLocked      = false
        }
    }

    func stop() { phase = .idle }

    private func resetPrivate() {
        phase             = .idle
        stableCount       = 0
        lastCenter        = nil
        lockedCenter      = nil
        wasLocked         = false
        missCount         = 0
        frameIndex        = 0
        postShotPositions = []
        postShotFrameCount = 0
    }

    // MARK: – Frame entry point

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        switch phase {
        case .idle:
            break

        case .detecting, .locked:
            frameIndex += 1
            guard frameIndex % detectEvery == 0 else { return }
            let result = scanYPlane(pixelBuffer)
            DispatchQueue.main.async { [weak self] in self?.handleDetectionResult(result) }

        case .shotTracking:
            // Run every frame – collect moving ball positions
            let result = scanYPlane(pixelBuffer)
            DispatchQueue.main.async { [weak self] in self?.handlePostShotFrame(result) }
        }
    }

    // MARK: – Detection result handler

    private func handleDetectionResult(_ result: DetectedBall?) {
        guard phase == .detecting || phase == .locked else { return }

        detected      = result
        isBallVisible = result != nil

        if phase == .locked {
            handleLockedPhase(result)
        } else {
            handleDetectingPhase(result)
        }
    }

    private func handleDetectingPhase(_ result: DetectedBall?) {
        if let ball = result {
            if let last = lastCenter {
                let d = dist(ball.center, last)
                stableCount = d < 0.06
                    ? min(stableCount + 1, lockThreshold + 15)
                    : max(0, stableCount - 3)
            } else {
                stableCount = 1
            }
            lastCenter = ball.center
            missCount  = 0
        } else {
            stableCount = max(0, stableCount - 4)
            missCount  += 1
            if stableCount == 0 { lastCenter = nil }
        }

        let nowLocked = stableCount >= lockThreshold
        isLocked = nowLocked

        if nowLocked && !wasLocked {
            wasLocked    = true
            phase        = .locked
            lockedCenter = lastCenter
            missCount    = 0
            onLocked?()
        } else if !nowLocked && wasLocked {
            wasLocked = false
            onUnlocked?()
        }
    }

    private func handleLockedPhase(_ result: DetectedBall?) {
        if let ball = result {
            // Ball still visible — check if it jumped (impact with follow-through)
            if let lc = lockedCenter {
                let d = dist(ball.center, lc)
                if d > 0.08 {
                    // Ball moved >8 % of frame from locked position → shot
                    fireShotDetected()
                    return
                }
            }
            missCount  = 0
            lastCenter = ball.center
        } else {
            missCount += 1
            if missCount >= shotMissThreshold {
                fireShotDetected()
            }
        }
    }

    private func fireShotDetected() {
        isLocked      = false
        isBallVisible = false
        detected      = nil
        postShotPositions  = lockedCenter.map { [$0] } ?? []
        postShotFrameCount = 0
        phase = .shotTracking
    }

    // MARK: – Post-shot tracking

    private func handlePostShotFrame(_ result: DetectedBall?) {
        if let ball = result {
            postShotPositions.append(ball.center)
        }
        postShotFrameCount += 1

        if postShotFrameCount >= postShotMaxFrames {
            phase = .idle
            let traj = postShotPositions
            onShotDetected?(traj)
        }
    }

    // MARK: – Y-Plane luminance scanner

    /// Scans the luminance (Y) plane of a YCbCr buffer to find the brightest
    /// circular blob — the golf ball. Returns screen-space normalised coords.
    private func scanYPlane(_ pixelBuffer: CVPixelBuffer) -> DetectedBall? {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }

        let bufW   = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let bufH   = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bpr    = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let threshold: UInt8 = 205   // bright white
        let step             = 3     // sample every 3rd pixel

        var sumCol = 0, sumRow = 0, count = 0
        var minCol = bufW, maxCol = 0, minRow = bufH, maxRow = 0

        for row in Swift.stride(from: 0, to: bufH, by: step) {
            for col in Swift.stride(from: 0, to: bufW, by: step) {
                if pixels[row * bpr + col] >= threshold {
                    sumCol += col;  sumRow += row;  count += 1
                    if col < minCol { minCol = col }
                    if col > maxCol { maxCol = col }
                    if row < minRow { minRow = row }
                    if row > maxRow { maxRow = row }
                }
            }
        }

        guard count >= 5 else { return nil }

        let bboxW = Double(maxCol - minCol) / Double(bufW)
        let bboxH = Double(maxRow - minRow) / Double(bufH)

        // Size gate: ball should be ~1–15 % of frame width
        guard bboxW > 0.008 && bboxW < 0.18 else { return nil }

        // Circularity gate (aspect ratio of bright blob)
        let ratio = bboxW / max(bboxH, 0.001)
        guard ratio > 0.3 && ratio < 3.5 else { return nil }

        // Convert buffer (col, row) centroid → screen (x, y)
        // Orientation .right: screen_x = 1 – row_norm, screen_y = col_norm
        let cx = 1.0 - Double(sumRow / count) / Double(bufH)
        let cy = Double(sumCol / count) / Double(bufW)
        let r  = CGFloat((bboxW + bboxH) / 4.0)

        return DetectedBall(center: CGPoint(x: cx, y: cy), normalizedRadius: r)
    }

    // MARK: – Helpers

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
