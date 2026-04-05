// BallDetector.swift
// GolfShotApp
//
// Detects a white golf ball using an integral-image density scan on the
// luminance (Y) plane of the YCbCr camera buffer.
//
// Key idea: Instead of collecting ALL bright pixels and using their combined
// bounding-box (which fails when multiple bright objects are in frame), we
// slide a window of the expected ball size across the frame and find the
// location with the HIGHEST density of bright pixels. That densest region
// is the ball — even if there are other bright objects nearby.
//
// Coordinate mapping (landscape buffer → portrait screen, orientation .right):
//   screen_x = 1 – row / bufferHeight
//   screen_y =     col / bufferWidth

import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics

// MARK: - DetectedBall

struct DetectedBall: Equatable {
    let center: CGPoint          // screen-space 0-1 (origin top-left)
    let normalizedRadius: CGFloat

    static func == (l: Self, r: Self) -> Bool {
        abs(l.center.x - r.center.x) < 0.01 &&
        abs(l.center.y - r.center.y) < 0.01
    }
}

// MARK: - BallDetector

final class BallDetector: ObservableObject {

    // MARK: Published

    @Published var detected:      DetectedBall? = nil
    @Published var isBallVisible: Bool          = false
    @Published var isLocked:      Bool          = false

    // MARK: Callbacks

    var onLocked:       (() -> Void)?
    var onUnlocked:     (() -> Void)?
    var onShotDetected: (([CGPoint]) -> Void)?

    // MARK: Private state

    private enum Phase { case idle, detecting, locked, shotTracking }
    private var phase: Phase = .idle

    private var stableCount   = 0
    private let lockThreshold = 18          // detection-frames needed (~1 s at ~18 fps)
    private var lastCenter:   CGPoint?
    private var lockedCenter: CGPoint?
    private var wasLocked     = false
    private var missCount     = 0
    private let missThreshold = 3           // consecutive misses → shot

    private var frameIndex  = 0
    private let detectEvery = 6             // ~20 fps at 120 fps input

    private var postShotPositions:  [CGPoint] = []
    private var postShotFrameCount  = 0
    private let postShotMaxFrames   = 45

    // MARK: - Control

    func startDetecting() {
        hardReset()
        phase = .detecting
    }

    func reset() {
        hardReset()
        DispatchQueue.main.async {
            self.detected      = nil
            self.isBallVisible = false
            self.isLocked      = false
        }
    }

    func stop() { phase = .idle }

    private func hardReset() {
        phase              = .idle
        stableCount        = 0
        lastCenter         = nil
        lockedCenter       = nil
        wasLocked          = false
        missCount          = 0
        frameIndex         = 0
        postShotPositions  = []
        postShotFrameCount = 0
    }

    // MARK: - Frame entry point

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pxBuf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        switch phase {
        case .idle:
            break

        case .detecting, .locked:
            frameIndex += 1
            guard frameIndex % detectEvery == 0 else { return }
            if let ball = findBall(pxBuf) {
                DispatchQueue.main.async { [weak self] in self?.onDetected(ball) }
            } else {
                DispatchQueue.main.async { [weak self] in self?.onNotDetected() }
            }

        case .shotTracking:
            // No throttle – grab every frame for direction data
            let ball = findBall(pxBuf)
            DispatchQueue.main.async { [weak self] in self?.onPostShotFrame(ball) }
        }
    }

    // MARK: - Detection handlers

    private func onDetected(_ ball: DetectedBall) {
        guard phase == .detecting || phase == .locked else { return }

        detected      = ball
        isBallVisible = true

        if phase == .locked {
            // Check whether ball moved from locked position → shot
            if let lc = lockedCenter, dist(ball.center, lc) > 0.07 {
                triggerShot(); return
            }
            missCount  = 0
            lastCenter = ball.center
            return
        }

        // Detecting phase: build up stability count
        if let last = lastCenter {
            stableCount = dist(ball.center, last) < 0.07
                ? min(stableCount + 1, lockThreshold + 15)
                : max(0, stableCount - 2)
        } else {
            stableCount = 1
        }
        lastCenter = ball.center
        missCount  = 0

        let nowLocked = stableCount >= lockThreshold
        isLocked = nowLocked
        if nowLocked && !wasLocked {
            wasLocked    = true
            phase        = .locked
            lockedCenter = lastCenter
            missCount    = 0
            onLocked?()
        }
    }

    private func onNotDetected() {
        guard phase == .detecting || phase == .locked else { return }

        detected      = nil
        isBallVisible = false

        if phase == .locked {
            missCount += 1
            if missCount >= missThreshold { triggerShot() }
            return
        }

        stableCount = max(0, stableCount - 3)
        missCount  += 1
        if stableCount == 0 { lastCenter = nil }

        if wasLocked {
            wasLocked = false
            isLocked  = false
            onUnlocked?()
        }
    }

    private func triggerShot() {
        isLocked      = false
        isBallVisible = false
        detected      = nil
        postShotPositions  = lockedCenter.map { [$0] } ?? []
        postShotFrameCount = 0
        phase = .shotTracking
    }

    // MARK: - Post-shot tracking

    private func onPostShotFrame(_ ball: DetectedBall?) {
        if let b = ball { postShotPositions.append(b.center) }
        postShotFrameCount += 1
        if postShotFrameCount >= postShotMaxFrames {
            phase = .idle
            onShotDetected?(postShotPositions)
        }
    }

    // MARK: - Ball detection (integral-image density scan)

    private func findBall(_ pixelBuffer: CVPixelBuffer) -> DetectedBall? {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let bufW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let bufH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bpr  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let px   = base.assumingMemoryBound(to: UInt8.self)

        // Downsample step — balance speed vs resolution
        let step = 4
        let gW   = bufW / step
        let gH   = bufH / step

        // Try three brightness thresholds — handles dirty/shaded balls
        let thresholds: [UInt8] = [185, 165, 145]

        for threshold in thresholds {
            if let result = densityScan(
                pixels: px, gW: gW, gH: gH, bpr: bpr, step: step,
                bufW: bufW, bufH: bufH, threshold: threshold
            ) {
                return result
            }
        }
        return nil
    }

    /// Integral-image density scan at a given brightness threshold.
    private func densityScan(pixels: UnsafePointer<UInt8>,
                             gW: Int, gH: Int, bpr: Int, step: Int,
                             bufW: Int, bufH: Int,
                             threshold: UInt8) -> DetectedBall? {

        // ── 1. Build binary brightness grid ─────────────────────────────
        var grid = [UInt8](repeating: 0, count: gW * gH)
        var brightTotal = 0

        for gy in 0..<gH {
            let rowOff = (gy * step) * bpr
            for gx in 0..<gW {
                if pixels[rowOff + gx * step] >= threshold {
                    grid[gy * gW + gx] = 1
                    brightTotal += 1
                }
            }
        }

        // Bail-out: frame too bright (overexposed / all white) or nothing visible
        let cellCount = gW * gH
        guard brightTotal > 4 else { return nil }
        guard brightTotal < cellCount / 2 else { return nil }   // >50% bright = bad scene

        // ── 2. Build integral image (SAT) ────────────────────────────────
        let iW = gW + 1
        var sat = [Int32](repeating: 0, count: iW * (gH + 1))

        for gy in 0..<gH {
            for gx in 0..<gW {
                sat[(gy+1) * iW + (gx+1)] =
                    Int32(grid[gy * gW + gx])
                    + sat[gy * iW + (gx+1)]
                    + sat[(gy+1) * iW + gx]
                    - sat[gy * iW + gx]
            }
        }

        // ── 3. Determine search radii (expected ball size) ───────────────
        // Golf ball ≈ 42.67 mm. At 60-120 cm height, it covers ~1-5 % of 1280 px frame.
        // In grid units (step=4): radius = 1280 * 0.01..0.05 / 4 = 3..16
        let radii = [max(3, gW/32), max(4, gW/20), max(6, gW/14)]

        // ── 4. Slide window, find max fill ───────────────────────────────
        var bestFill:   Float = 0
        var bestGX      = 0, bestGY = 0, bestR = radii[0]

        for r in radii {
            let margin = r + 1
            guard margin < gW - margin && margin < gH - margin else { continue }

            for gy in margin..<(gH - margin) {
                for gx in margin..<(gW - margin) {
                    let x1 = gx - r, x2 = gx + r
                    let y1 = gy - r, y2 = gy + r
                    let sum = sat[(y2+1)*iW + (x2+1)]
                              - sat[y1*iW + (x2+1)]
                              - sat[(y2+1)*iW + x1]
                              + sat[y1*iW + x1]
                    let fill = Float(sum) / Float((2*r+1)*(2*r+1))
                    if fill > bestFill {
                        bestFill = fill
                        bestGX = gx; bestGY = gy; bestR = r
                    }
                }
            }
        }

        // Minimum fill rate: at least 25 % of the search window must be bright
        guard bestFill >= 0.25 else { return nil }

        // ── 5. Verify aspect ratio of bright region ───────────────────────
        // Collect bright pixels within bestR to check circularity
        var minGX = bestGX + bestR, maxGX = bestGX - bestR
        var minGY = bestGY + bestR, maxGY = bestGY - bestR
        var regionCount = 0

        let y1 = max(0, bestGY - bestR), y2 = min(gH-1, bestGY + bestR)
        let x1 = max(0, bestGX - bestR), x2 = min(gW-1, bestGX + bestR)

        for gy in y1...y2 {
            for gx in x1...x2 {
                if grid[gy * gW + gx] == 1 {
                    regionCount += 1
                    if gx < minGX { minGX = gx }; if gx > maxGX { maxGX = gx }
                    if gy < minGY { minGY = gy }; if gy > maxGY { maxGY = gy }
                }
            }
        }

        let rgnW = maxGX - minGX + 1
        let rgnH = maxGY - minGY + 1
        let aspect = rgnW > 0 && rgnH > 0
            ? Double(max(rgnW, rgnH)) / Double(min(rgnW, rgnH))
            : 999.0
        guard aspect < 3.0 else { return nil }   // too elongated = not a ball

        // ── 6. Convert grid centroid to screen coordinates ────────────────
        let bufCol = Double(bestGX * step)
        let bufRow = Double(bestGY * step)

        // Landscape buffer (bufW > bufH) + orientation .right on portrait phone:
        //   screen_x = 1 – row / bufH
        //   screen_y =     col / bufW
        // If the buffer is portrait (bufH > bufW) — no rotation needed:
        //   screen_x = col / bufW
        //   screen_y = row / bufH
        let screenX: Double
        let screenY: Double
        if bufW > bufH {
            // Landscape buffer → rotated display
            screenX = 1.0 - bufRow / Double(bufH)
            screenY = bufCol / Double(bufW)
        } else {
            // Portrait buffer
            screenX = bufCol / Double(bufW)
            screenY = bufRow / Double(bufH)
        }

        let radius = CGFloat(bestR * step) / CGFloat(max(bufW, bufH)) * 2.0

        return DetectedBall(
            center: CGPoint(x: max(0, min(1, screenX)),
                            y: max(0, min(1, screenY))),
            normalizedRadius: radius
        )
    }

    // MARK: - Helpers

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
