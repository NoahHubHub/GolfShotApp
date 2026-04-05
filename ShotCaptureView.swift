// ShotCaptureView.swift
// GolfShotApp
//
// Live camera view with automatic ball detection, visual tracking overlay,
// and fully automatic shot detection + recording.

import SwiftUI
import AVFoundation
import Vision
import AudioToolbox

// MARK: - CaptureState

enum CaptureState: Equatable {
    case searching      // Camera running, looking for ball
    case ballDetected   // Ball found but not yet stable
    case ballLocked     // Ball stable ≥ 1 s → ready to hit
    case shooting       // Ball hit, tracking trajectory + recording
    case processing     // Analysis running
    case done           // Results ready
}

// MARK: - ShotCaptureView

struct ShotCaptureView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var ballDetector  = BallDetector()
    @StateObject private var ballTracker   = BallTracker()
    @EnvironmentObject var store: ShotStore

    @State private var selectedClub: Club       = .driver
    @State private var showClubSelector         = false
    @State private var captureState: CaptureState = .searching
    @State private var finishedShot: Shot?
    @State private var showResult               = false
    @State private var readyPulse: CGFloat      = 1.0

    var body: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            DetectionOverlayView(
                ballDetector: ballDetector,
                ballTracker:  ballTracker,
                captureState: captureState
            )
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if captureState == .ballLocked {
                    readyBanner
                }
                Spacer()
                statusBar
            }
        }
        .onChange(of: ballDetector.isBallVisible) { visible in
            guard captureState == .searching || captureState == .ballDetected else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                captureState = visible ? .ballDetected : .searching
            }
        }
        .onChange(of: ballDetector.isLocked) { locked in
            if locked && captureState == .ballDetected {
                withAnimation(.spring()) { captureState = .ballLocked }
                armTracker()
            } else if !locked && captureState == .ballLocked {
                withAnimation { captureState = .ballDetected }
                disarmTracker()
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .sheet(isPresented: $showClubSelector) {
            ClubSelectorView(selectedClub: $selectedClub,
                             onDismiss: { showClubSelector = false })
        }
        .sheet(isPresented: $showResult) {
            if let shot = finishedShot {
                NavigationView {
                    ShotResultView(shot: shot, onDone: {
                        showResult = false
                        resetToSearching()
                    })
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { showClubSelector = true } label: {
                HStack(spacing: 6) {
                    Text(selectedClub.emoji)
                    Text(selectedClub.rawValue).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.5)))
            }
            Spacer()
            stateBadge
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var stateBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            Text(stateLabelText)
                .font(.caption).fontWeight(.semibold).foregroundColor(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    // MARK: - Ready Banner

    private var readyBanner: some View {
        Text("⛳ JETZT SCHLAGEN!")
            .font(.system(size: 26, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color("GolfGreen"))
                    .shadow(color: Color("GolfGreen").opacity(0.6), radius: 16)
            )
            .scaleEffect(readyPulse)
            .onAppear {
                // Haptic + sound
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AudioServicesPlayAlertSound(SystemSoundID(1322))
                // Pulsing animation
                withAnimation(
                    .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                ) { readyPulse = 1.07 }
            }
            .onDisappear { readyPulse = 1.0 }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 10) {
            Text(instructionText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            if captureState == .done {
                Button(action: resetToSearching) {
                    Label("Neuer Schlag", systemImage: "arrow.clockwise.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Capsule().fill(Color("GolfGreen")))
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }

    // MARK: - State Helpers

    private var stateLabelText: String {
        switch captureState {
        case .searching:    return "SUCHE BALL..."
        case .ballDetected: return "BALL ERKANNT"
        case .ballLocked:   return "✓ BEREIT"
        case .shooting:     return "● AUFNAHME"
        case .processing:   return "ANALYSE..."
        case .done:         return "✓ FERTIG"
        }
    }

    private var stateColor: Color {
        switch captureState {
        case .searching:    return .white.opacity(0.6)
        case .ballDetected: return .yellow
        case .ballLocked:   return Color("GolfGreen")
        case .shooting:     return .red
        case .processing:   return .orange
        case .done:         return Color("GolfGreen")
        }
    }

    private var instructionText: String {
        switch captureState {
        case .searching:    return "Ball in den Kamerabereich legen"
        case .ballDetected: return "Ball erkannt – kurz stillhalten..."
        case .ballLocked:   return "Ball gesperrt – jetzt schlagen!"
        case .shooting:     return "Aufnahme läuft..."
        case .processing:   return "Schlag wird analysiert..."
        case .done:         return "Analyse abgeschlossen"
        }
    }

    // MARK: - Shot Logic

    private func armTracker() {
        ballTracker.startTracking()

        ballTracker.onTrajectoryDetected = { _ in
            guard captureState == .ballLocked else { return }
            DispatchQueue.main.async { startRecording() }
        }
        ballTracker.onTrajectoryEnded = { points in
            guard captureState == .shooting else { return }
            DispatchQueue.main.async { finishShot(trajectoryPoints: points) }
        }
    }

    private func disarmTracker() {
        ballTracker.stopTracking()
        ballTracker.onTrajectoryDetected = nil
        ballTracker.onTrajectoryEnded    = nil
    }

    private func startRecording() {
        withAnimation { captureState = .shooting }
        ballDetector.stop()

        let filename = "shot_\(UUID().uuidString).mov"
        let url = store.videosDirectory.appendingPathComponent(filename)
        cameraManager.startRecording(to: url)

        // Safety timeout: stop recording after 8 s even if trajectory never ends
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard captureState == .shooting else { return }
            ballTracker.stopTracking()
        }
    }

    private func finishShot(trajectoryPoints: [CGPoint]) {
        withAnimation { captureState = .processing }

        cameraManager.stopRecording { [self] videoURL in
            let metrics = ShotAnalyzer.analyze(
                ballPoints: trajectoryPoints,
                clubName:   selectedClub.rawValue
            )
            let shot = Shot(
                club:             selectedClub,
                metrics:          metrics,
                videoFilename:    videoURL?.lastPathComponent,
                trajectoryPoints: trajectoryPoints
            )
            store.add(shot: shot)
            finishedShot = shot
            captureState = .done
            showResult   = true
        }
    }

    private func resetToSearching() {
        ballDetector.reset()
        disarmTracker()
        finishedShot = nil
        withAnimation { captureState = .searching }
    }

    // MARK: - Lifecycle

    private func onAppear() {
        Task {
            await cameraManager.requestPermissionsAndSetup()
            cameraManager.start()
            cameraManager.onFrame = { [weak ballDetector, weak ballTracker] buffer in
                ballDetector?.process(sampleBuffer: buffer)
                ballTracker?.process(sampleBuffer: buffer)
            }
        }
    }

    private func onDisappear() {
        cameraManager.stop()
        if captureState == .shooting {
            cameraManager.stopRecording { _ in }
        }
    }
}

// MARK: - DetectionOverlayView

struct DetectionOverlayView: UIViewRepresentable {

    @ObservedObject var ballDetector: BallDetector
    @ObservedObject var ballTracker:  BallTracker
    let captureState: CaptureState

    func makeUIView(context: Context) -> OverlayCanvas { OverlayCanvas() }

    func updateUIView(_ view: OverlayCanvas, context: Context) {
        let trajectoryPts = ballTracker.latestPoints.map {
            CGPoint(x: $0.x, y: 1 - $0.y)
        }
        view.update(
            detectedBall:      ballDetector.detected,
            isLocked:          ballDetector.isLocked,
            trajectoryPoints:  trajectoryPts,
            captureState:      captureState
        )
    }

    // MARK: - Canvas

    final class OverlayCanvas: UIView {

        private let ballRingLayer  = CAShapeLayer()
        private let ballDotLayer   = CAShapeLayer()
        private let trailLayer     = CAShapeLayer()
        private let scanRingLayer  = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear

            // Trajectory trail
            trailLayer.fillColor   = UIColor.clear.cgColor
            trailLayer.strokeColor = UIColor.systemGreen.cgColor
            trailLayer.lineWidth   = 2.5
            trailLayer.lineCap     = .round
            trailLayer.lineJoin    = .round
            layer.addSublayer(trailLayer)

            // Scanning ring (searching state)
            scanRingLayer.fillColor   = UIColor.clear.cgColor
            scanRingLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
            scanRingLayer.lineWidth   = 1.5
            scanRingLayer.lineDashPattern = [5, 5]
            layer.addSublayer(scanRingLayer)

            // Ball detection ring
            ballRingLayer.fillColor = UIColor.clear.cgColor
            ballRingLayer.lineWidth = 3
            layer.addSublayer(ballRingLayer)

            // Ball center dot
            ballDotLayer.lineWidth = 0
            layer.addSublayer(ballDotLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        // MARK: Update

        func update(detectedBall:     DetectedBall?,
                    isLocked:         Bool,
                    trajectoryPoints: [CGPoint],
                    captureState:     CaptureState) {

            let w = bounds.width
            let h = bounds.height

            // ── Scanning ring (shown while searching, no ball yet) ──────
            if captureState == .searching {
                let cx = w / 2, cy = h / 2
                let r: CGFloat = min(w, h) * 0.15
                scanRingLayer.path = UIBezierPath(
                    ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ).cgPath
                if scanRingLayer.animation(forKey: "rotate") == nil {
                    let rot = CABasicAnimation(keyPath: "transform.rotation")
                    rot.fromValue  = 0
                    rot.toValue    = CGFloat.pi * 2
                    rot.duration   = 3
                    rot.repeatCount = .infinity
                    scanRingLayer.add(rot, forKey: "rotate")
                }
            } else {
                scanRingLayer.path = nil
                scanRingLayer.removeAnimation(forKey: "rotate")
            }

            // ── Ball detection ring ─────────────────────────────────────
            let showBallRing = detectedBall != nil &&
                (captureState == .ballDetected || captureState == .ballLocked || captureState == .searching)

            if showBallRing, let ball = detectedBall {
                let cx  = ball.center.x * w
                let cy  = ball.center.y * h
                // Scale radius up so the ring is clearly visible around the ball
                let r   = ball.normalizedRadius * w * 3.0

                let ringRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ballRingLayer.path = UIBezierPath(ovalIn: ringRect).cgPath

                // Center dot
                let dotR: CGFloat = 4
                ballDotLayer.path = UIBezierPath(
                    ovalIn: CGRect(x: cx - dotR, y: cy - dotR,
                                  width: dotR * 2, height: dotR * 2)
                ).cgPath

                if isLocked {
                    // Green solid ring + pulse animation
                    ballRingLayer.strokeColor   = UIColor.systemGreen.cgColor
                    ballRingLayer.lineWidth      = 3.5
                    ballRingLayer.lineDashPattern = nil
                    ballDotLayer.fillColor       = UIColor.systemGreen.cgColor

                    if ballRingLayer.animation(forKey: "pulse") == nil {
                        let pulse          = CABasicAnimation(keyPath: "transform.scale")
                        pulse.fromValue    = 1.0
                        pulse.toValue      = 1.18
                        pulse.duration     = 0.55
                        pulse.autoreverses = true
                        pulse.repeatCount  = .infinity
                        ballRingLayer.add(pulse, forKey: "pulse")
                        ballDotLayer.add(pulse,  forKey: "pulse")
                    }
                } else {
                    // Yellow dashed ring
                    ballRingLayer.removeAnimation(forKey: "pulse")
                    ballDotLayer.removeAnimation(forKey: "pulse")
                    ballRingLayer.strokeColor    = UIColor.systemYellow.cgColor
                    ballRingLayer.lineWidth      = 2.5
                    ballRingLayer.lineDashPattern = [8, 5]
                    ballDotLayer.fillColor       = UIColor.systemYellow.cgColor
                }
            } else {
                ballRingLayer.path = nil
                ballDotLayer.path  = nil
                ballRingLayer.removeAnimation(forKey: "pulse")
                ballDotLayer.removeAnimation(forKey: "pulse")
            }

            // ── Trajectory trail ────────────────────────────────────────
            if trajectoryPoints.count >= 2 &&
               (captureState == .shooting || captureState == .processing || captureState == .done) {

                let path   = UIBezierPath()
                let mapped = trajectoryPoints.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                path.move(to: mapped[0])
                mapped.dropFirst().forEach { path.addLine(to: $0) }
                trailLayer.path = path.cgPath

            } else if captureState == .searching || captureState == .ballDetected || captureState == .ballLocked {
                trailLayer.path = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            [scanRingLayer, trailLayer, ballRingLayer, ballDotLayer].forEach {
                $0.frame = bounds
            }
        }
    }
}

// MARK: - CameraPreviewView

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session      = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
