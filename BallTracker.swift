// BallTracker.swift
// GolfShotApp
//
// Uses Vision framework VNDetectTrajectoriesRequest to track a golf ball.

import Vision
import CoreImage
import CoreGraphics
import Combine
import UIKit

// MARK: - TrackingState

enum TrackingState {
    case idle
    case detecting
    case tracking
    case lost
}

// MARK: - BallTracker

final class BallTracker: ObservableObject {

    // MARK: Published

    @Published var state: TrackingState = .idle
    @Published var latestPoints: [VNPoint] = []
    @Published var detectedTrajectory: VNTrajectoryObservation?
    @Published var currentBallPosition: CGPoint?   // normalised 0-1

    // MARK: Callbacks

    /// Called when a ball trajectory is detected and actively tracked.
    var onTrajectoryDetected: (([VNPoint]) -> Void)?
    /// Called when the trajectory is lost / complete.
    var onTrajectoryEnded: (([CGPoint]) -> Void)?

    // MARK: Private

    private var request: VNDetectTrajectoriesRequest?
    private var sequenceHandler = VNSequenceRequestHandler()

    // Accumulated normalised trajectory points (y-flipped for UIKit coords)
    private var accumulatedPoints: [CGPoint] = []
    private var frameCount = 0
    private var noDetectionFrames = 0
    private let maxNoDetectionFrames = 30  // ~0.5s at 60fps

    // MARK: - Lifecycle

    func startTracking() {
        accumulatedPoints = []
        frameCount = 0
        noDetectionFrames = 0
        state = .detecting

        request = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero,
                                              trajectoryLength: 10) { [weak self] request, error in
            self?.handleTrajectoryResults(request: request, error: error)
        }
        request?.minimumObjectSize = 0.01   // minimum fraction of frame dimension
        request?.maximumObjectSize = 0.15   // maximum fraction of frame dimension
    }

    func stopTracking() {
        let points = accumulatedPoints
        state = .idle
        request = nil
        sequenceHandler = VNSequenceRequestHandler()
        if !points.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onTrajectoryEnded?(points)
            }
        }
    }

    // MARK: - Frame processing

    /// Call this for each camera frame (on any background queue).
    func process(sampleBuffer: CMSampleBuffer) {
        guard let req = request else { return }

        do {
            // Phone is lying flat pointing down in landscape orientation.
            // .right matches landscapeRight video orientation.
            try sequenceHandler.perform([req], on: sampleBuffer, orientation: .right)
        } catch {
            print("BallTracker: sequence error – \(error)")
        }

        frameCount += 1

        // Auto-stop if ball has been lost for too long
        if state == .tracking {
            noDetectionFrames += 1
            if noDetectionFrames > maxNoDetectionFrames {
                DispatchQueue.main.async { [weak self] in
                    self?.stopTracking()
                }
            }
        }
    }

    // MARK: - Results handler

    private func handleTrajectoryResults(request: VNRequest, error: Error?) {
        guard error == nil,
              let observations = request.results as? [VNTrajectoryObservation],
              let best = observations.max(by: { $0.confidence < $1.confidence }),
              best.confidence > 0.5
        else { return }

        let points = best.detectedPoints   // [VNPoint], normalised

        // Reset the no-detection counter
        noDetectionFrames = 0

        // Accumulate points (flip Y because Vision uses bottom-left origin)
        let cgPoints = points.map { CGPoint(x: $0.x, y: 1.0 - $0.y) }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestPoints = points
            self.detectedTrajectory = best
            self.currentBallPosition = cgPoints.last
            self.state = .tracking

            // Append only new unique points
            for pt in cgPoints {
                let isDuplicate = self.accumulatedPoints.last.map { approxEqual($0, pt) } ?? false
                if !isDuplicate {
                    self.accumulatedPoints.append(pt)
                }
            }

            self.onTrajectoryDetected?(points)
        }
    }
}

// MARK: - Approximate equality helper

private func approxEqual(_ a: CGPoint, _ b: CGPoint) -> Bool {
    abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001
}
