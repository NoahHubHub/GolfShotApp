// ShotCaptureView.swift
// GolfShotApp
//
// Live camera view with ball-tracking overlay and recording controls.

import SwiftUI
import AVFoundation
import Vision

// MARK: - ShotCaptureView

struct ShotCaptureView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var ballTracker   = BallTracker()
    @EnvironmentObject var store: ShotStore

    @State private var selectedClub: Club  = .driver
    @State private var showClubSelector    = false
    @State private var captureState: CaptureState = .ready
    @State private var finishedShot: Shot?
    @State private var showResult          = false
    @State private var countdownValue: Int = 3
    @State private var autoRecordEnabled   = true

    enum CaptureState {
        case ready, armed, recording, processing, done
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Tracking overlay
            TrackingOverlayView(ballTracker: ballTracker)
                .ignoresSafeArea()

            // UI overlays
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .sheet(isPresented: $showClubSelector) {
            ClubSelectorView(selectedClub: $selectedClub, onDismiss: { showClubSelector = false })
        }
        .sheet(isPresented: $showResult) {
            if let shot = finishedShot {
                NavigationView {
                    ShotResultView(shot: shot, onDone: {
                        showResult = false
                        resetCapture()
                    })
                }
            }
        }
        .alert("Permission Required", isPresented: .constant(cameraManager.error != nil)) {
            Button("OK") {}
        } message: {
            Text(cameraManager.error ?? "")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Club selector button
            Button {
                showClubSelector = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedClub.emoji)
                    Text(selectedClub.rawValue)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.5)))
            }

            Spacer()

            // Auto-record toggle
            Toggle(isOn: $autoRecordEnabled) {
                Text("Auto")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: Color("GolfGreen")))
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.5)))

            Spacer()

            // Status indicator
            statusBadge
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.5)))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Live metrics strip (during tracking)
            if captureState == .recording || captureState == .armed {
                liveMetricsStrip
            }

            HStack(spacing: 24) {
                Spacer()

                // Main capture button
                captureButton

                Spacer()
            }
            .padding(.bottom, 24)
        }
        .padding()
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }

    private var captureButton: some View {
        Button(action: handleCaptureButton) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 76, height: 76)

                if captureState == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else if captureState == .processing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                } else {
                    Circle()
                        .fill(Color("GolfGreen"))
                        .frame(width: 54, height: 54)
                }
            }
        }
        .disabled(captureState == .processing)
    }

    private var liveMetricsStrip: some View {
        HStack(spacing: 20) {
            LiveMetric(label: "STATE", value: ballTracker.state == .tracking ? "TRACKING" : "DETECTING")
            if let pos = ballTracker.currentBallPosition {
                LiveMetric(label: "POS", value: String(format: "%.2f, %.2f", pos.x, pos.y))
            }
            LiveMetric(label: "POINTS", value: "\(ballTracker.latestPoints.count)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.6)))
    }

    // MARK: - Status helpers

    private var statusText: String {
        switch captureState {
        case .ready:      return "READY"
        case .armed:      return "ARMED"
        case .recording:  return "● REC"
        case .processing: return "PROCESSING"
        case .done:       return "DONE"
        }
    }

    private var statusColor: Color {
        switch captureState {
        case .ready:      return .white
        case .armed:      return .yellow
        case .recording:  return .red
        case .processing: return .orange
        case .done:       return Color("GolfGreen")
        }
    }

    // MARK: - Actions

    private func handleCaptureButton() {
        switch captureState {
        case .ready:
            armCapture()
        case .armed:
            disarm()
        case .recording:
            stopAndProcess()
        case .processing, .done:
            break
        }
    }

    private func armCapture() {
        captureState = .armed
        ballTracker.startTracking()

        if autoRecordEnabled {
            ballTracker.onTrajectoryDetected = { [self] _ in
                guard captureState == .armed else { return }
                DispatchQueue.main.async { beginRecording() }
            }
        } else {
            beginRecording()
        }

        ballTracker.onTrajectoryEnded = { [self] points in
            guard captureState == .recording else { return }
            DispatchQueue.main.async { stopAndProcess(finalPoints: points) }
        }
    }

    private func disarm() {
        captureState = .ready
        ballTracker.stopTracking()
        ballTracker.onTrajectoryDetected = nil
        ballTracker.onTrajectoryEnded = nil
    }

    private func beginRecording() {
        guard captureState == .armed else { return }
        captureState = .recording
        let filename = "shot_\(UUID().uuidString).mov"
        let url = store.videosDirectory.appendingPathComponent(filename)
        cameraManager.startRecording(to: url)
    }

    private func stopAndProcess(finalPoints: [CGPoint]? = nil) {
        captureState = .processing

        cameraManager.stopRecording { [self] videoURL in
            let points = finalPoints ?? []
            let metrics = ShotAnalyzer.analyze(ballPoints: points, clubName: selectedClub.rawValue)
            let shot = Shot(
                club: selectedClub,
                metrics: metrics,
                videoFilename: videoURL?.lastPathComponent,
                trajectoryPoints: points
            )
            store.add(shot: shot)
            finishedShot = shot
            captureState = .done
            showResult = true
        }

        ballTracker.onTrajectoryDetected = nil
        ballTracker.onTrajectoryEnded = nil
    }

    private func resetCapture() {
        captureState = .ready
        finishedShot = nil
        ballTracker.startTracking()
        ballTracker.stopTracking()
    }

    // MARK: - Lifecycle

    private func onAppear() {
        Task {
            await cameraManager.requestPermissionsAndSetup()
            cameraManager.start()
            cameraManager.onFrame = { [weak ballTracker] buffer in
                ballTracker?.process(sampleBuffer: buffer)
            }
        }
    }

    private func onDisappear() {
        cameraManager.stop()
        if captureState == .recording {
            cameraManager.stopRecording { _ in }
        }
    }
}

// MARK: - LiveMetric

private struct LiveMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - CameraPreviewView

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - TrackingOverlayView

struct TrackingOverlayView: UIViewRepresentable {

    @ObservedObject var ballTracker: BallTracker

    func makeUIView(context: Context) -> OverlayUIView {
        OverlayUIView()
    }

    func updateUIView(_ uiView: OverlayUIView, context: Context) {
        uiView.update(
            points: ballTracker.latestPoints.map { CGPoint(x: $0.x, y: 1 - $0.y) },
            ballPosition: ballTracker.currentBallPosition,
            state: ballTracker.state
        )
    }

    class OverlayUIView: UIView {

        private let trailLayer = CAShapeLayer()
        private let ballLayer  = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            setupLayers()
        }

        required init?(coder: NSCoder) { fatalError() }

        private func setupLayers() {
            trailLayer.fillColor   = UIColor.clear.cgColor
            trailLayer.strokeColor = UIColor.systemGreen.cgColor
            trailLayer.lineWidth   = 2.5
            trailLayer.lineCap     = .round
            trailLayer.lineJoin    = .round
            layer.addSublayer(trailLayer)

            ballLayer.fillColor   = UIColor.systemGreen.withAlphaComponent(0.8).cgColor
            ballLayer.strokeColor = UIColor.white.cgColor
            ballLayer.lineWidth   = 1.5
            layer.addSublayer(ballLayer)
        }

        func update(points: [CGPoint], ballPosition: CGPoint?, state: TrackingState) {
            let w = bounds.width
            let h = bounds.height

            // Trail
            if points.count >= 2 {
                let path = UIBezierPath()
                let mapped = points.map { CGPoint(x: $0.x * w, y: $0.y * h) }
                path.move(to: mapped[0])
                for pt in mapped.dropFirst() { path.addLine(to: pt) }
                trailLayer.path = path.cgPath
                trailLayer.strokeColor = state == .tracking
                    ? UIColor.systemGreen.cgColor
                    : UIColor.systemYellow.cgColor
            } else {
                trailLayer.path = nil
            }

            // Ball indicator
            if let pos = ballPosition {
                let cx = pos.x * w
                let cy = pos.y * h
                let r: CGFloat = 14
                ballLayer.path = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r,
                                                             width: r * 2, height: r * 2)).cgPath
            } else {
                ballLayer.path = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            trailLayer.frame = bounds
            ballLayer.frame  = bounds
        }
    }
}

#Preview {
    ShotCaptureView()
        .environmentObject(ShotStore.shared)
}
