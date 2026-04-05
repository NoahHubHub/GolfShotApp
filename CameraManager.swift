// CameraManager.swift
// GolfShotApp
//
// AVFoundation camera setup, high-frame-rate capture, and video recording.
//
// Required Info.plist keys:
//   NSCameraUsageDescription  – "Used to track your golf ball during a shot."
//   NSMicrophoneUsageDescription – "Used to capture audio during recording."
//   NSPhotoLibraryAddUsageDescription – "Shot videos are saved to your Photo Library."

import AVFoundation
import UIKit
import Photos
import Combine

// MARK: - CameraManager

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published var isRunning         = false
    @Published var isRecording       = false
    @Published var permissionGranted = false
    @Published var error: String?

    // MARK: AVFoundation objects

    let session                        = AVCaptureSession()
    private var videoOutput            = AVCaptureVideoDataOutput()
    private var fileOutput             = AVCaptureMovieFileOutput()
    private var currentRecordingURL: URL?

    // MARK: Frame delivery

    /// Called on a background queue with every sample buffer
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Setup

    func requestPermissionsAndSetup() async {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch videoStatus {
        case .authorized:
            await setup()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await setup() } else { error = "Camera access denied." }
        default:
            error = "Camera access denied. Please enable in Settings."
        }
    }

    // MARK: - Session lifecycle

    func start() {
        guard !isRunning else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.session.startRunning()
            await MainActor.run { self?.isRunning = true }
        }
    }

    func stop() {
        guard isRunning else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.session.stopRunning()
            await MainActor.run { self?.isRunning = false }
        }
    }

    // MARK: - Recording

    /// Start recording to a temp file in the Documents/Videos folder.
    func startRecording(to destinationURL: URL) {
        guard !isRecording else { return }
        guard fileOutput.isRecording == false else { return }
        currentRecordingURL = destinationURL
        fileOutput.startRecording(to: destinationURL, recordingDelegate: self)
        isRecording = true
    }

    /// Stop the active recording. Completion returns the saved URL.
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else { completion(nil); return }
        recordingCompletion = completion
        fileOutput.stopRecording()
    }

    private var recordingCompletion: ((URL?) -> Void)?

    // MARK: - Private setup

    private func setup() async {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // --- Device ---
        guard let device = bestCamera() else {
            error = "No suitable camera found."
            session.commitConfiguration()
            return
        }

        // --- High frame rate ---
        configureHighFrameRate(for: device)

        // --- Video input ---
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            self.error = "Could not create camera input: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }

        // --- Sample buffer output (for Vision) ---
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.golfshot.frames", qos: .userInteractive))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // --- Movie file output ---
        if session.canAddOutput(fileOutput) { session.addOutput(fileOutput) }

        // Top-down tripod setup: phone lies flat, camera pointing down.
        // Use landscape orientation so the frame is wider than tall.
        for connection in videoOutput.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
        }
        for connection in fileOutput.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
        }

        session.commitConfiguration()
        permissionGranted = true
    }

    private func bestCamera() -> AVCaptureDevice? {
        // Prefer wide-angle back camera
        if let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return d
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configureHighFrameRate(for device: AVCaptureDevice) {
        let targetFPS: Int32 = 240
        let fallbackFPS: Int32 = 120
        let minimumFPS: Int32 = 60

        var selectedFormat: AVCaptureDevice.Format?
        var selectedFPS: Int32 = minimumFPS

        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            // Only 720p or smaller for high fps
            guard dims.height <= 720 else { continue }

            for range in format.videoSupportedFrameRateRanges {
                let fps = Int32(range.maxFrameRate)
                if fps >= targetFPS && selectedFPS < targetFPS {
                    selectedFormat = format
                    selectedFPS = targetFPS
                } else if fps >= fallbackFPS && selectedFPS < fallbackFPS {
                    selectedFormat = format
                    selectedFPS = fallbackFPS
                } else if fps >= minimumFPS && selectedFPS < minimumFPS {
                    selectedFormat = format
                    selectedFPS = minimumFPS
                }
            }
        }

        guard let format = selectedFormat else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTimeMake(value: 1, timescale: selectedFPS)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            print("CameraManager: configured \(selectedFPS) fps")
        } catch {
            print("CameraManager: could not set frame rate – \(error)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {

        let savedURL: URL? = error == nil ? outputFileURL : nil

        // Save to Photos Library
        if let url = savedURL {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized || status == .limited {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }, completionHandler: nil)
                }
            }
        }

        Task { @MainActor [weak self] in
            self?.isRecording = false
            self?.recordingCompletion?(savedURL)
            self?.recordingCompletion = nil
        }
    }
}
