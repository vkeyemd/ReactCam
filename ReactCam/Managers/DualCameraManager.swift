import AVFoundation
import UIKit
import Combine

/// Drives simultaneous front + back camera capture for "Dual Capture" mode.
///
/// Like `CameraManager`, both preview layers are created once and owned here
/// for the manager's entire lifetime — SwiftUI never gets to recreate them.
/// Two independent `AVCaptureMovieFileOutput`s are used (one per camera)
/// rather than a single shared output, since each needs its own
/// `AVCaptureConnection` back to its own device input.
final class DualCameraManager: NSObject, ObservableObject {

    @Published private(set) var isSessionRunning = false
    @Published private(set) var isRecording = false
    @Published var permissionDenied = false

    /// Devices report multi-cam support individually; check this before ever
    /// offering "Dual Capture" in the UI.
    static var isSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    let session = AVCaptureMultiCamSession()
    let frontPreviewLayer: AVCaptureVideoPreviewLayer
    let backPreviewLayer: AVCaptureVideoPreviewLayer

    private let frontOutput = AVCaptureMovieFileOutput()
    private let backOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.reactcam.dualcameramanager.session")

    private var frontURL: URL?
    private var backURL: URL?
    private var pendingCompletion: ((_ front: URL?, _ back: URL?) -> Void)?
    private var outputsFinished = 0

    override init() {
        frontPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        backPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        frontPreviewLayer.videoGravity = .resizeAspectFill
        backPreviewLayer.videoGravity = .resizeAspectFill
        super.init()
        configureSession()
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, DualCameraManager.isSupported else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            // Back camera
            if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let backInput = try? AVCaptureDeviceInput(device: backCamera),
               self.session.canAddInput(backInput) {
                self.session.addInputWithNoConnections(backInput)
                if let port = backInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: .back).first,
                   self.session.canAddOutput(self.backOutput) {
                    self.session.addOutputWithNoConnections(self.backOutput)
                    let connection = AVCaptureConnection(inputPorts: [port], output: self.backOutput)
                    if self.session.canAddConnection(connection) {
                        self.session.addConnection(connection)
                    }
                    self.backPreviewLayer.setSessionWithNoConnection(self.session)
                    let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: self.backPreviewLayer)
                    if self.session.canAddConnection(previewConnection) {
                        self.session.addConnection(previewConnection)
                    }
                }
            }

            // Front camera
            if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let frontInput = try? AVCaptureDeviceInput(device: frontCamera),
               self.session.canAddInput(frontInput) {
                self.session.addInputWithNoConnections(frontInput)
                if let port = frontInput.ports(for: .video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition: .front).first,
                   self.session.canAddOutput(self.frontOutput) {
                    self.session.addOutputWithNoConnections(self.frontOutput)
                    let connection = AVCaptureConnection(inputPorts: [port], output: self.frontOutput)
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                    if self.session.canAddConnection(connection) {
                        self.session.addConnection(connection)
                    }
                    self.frontPreviewLayer.setSessionWithNoConnection(self.session)
                    let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: self.frontPreviewLayer)
                    if self.session.canAddConnection(previewConnection) {
                        self.session.addConnection(previewConnection)
                    }
                }
            }

            // Shared microphone
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(audioInput) {
                self.session.addInputWithNoConnections(audioInput)
                if let audioPort = audioInput.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: .unspecified).first {
                    let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: self.backOutput)
                    if self.session.canAddConnection(audioConnection) {
                        self.session.addConnection(audioConnection)
                    }
                }
            }
        }
    }

    func requestPermissionsAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            if !granted {
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            AudioSessionManager.activate()
            self.sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async { self.isSessionRunning = true }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
        AudioSessionManager.deactivate()
    }

    // MARK: Recording

    func startRecording(completion: @escaping (_ front: URL?, _ back: URL?) -> Void) {
        guard !frontOutput.isRecording, !backOutput.isRecording else { return }
        pendingCompletion = completion
        outputsFinished = 0

        let frontTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("front-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let backTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("back-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        frontOutput.startRecording(to: frontTemp, recordingDelegate: self)
        backOutput.startRecording(to: backTemp, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        if frontOutput.isRecording { frontOutput.stopRecording() }
        if backOutput.isRecording { backOutput.stopRecording() }
    }
}

extension DualCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let succeeded = (error == nil)
        if output === frontOutput {
            frontURL = succeeded ? outputFileURL : nil
        } else if output === backOutput {
            backURL = succeeded ? outputFileURL : nil
        }

        outputsFinished += 1
        if outputsFinished == 2 {
            DispatchQueue.main.async {
                self.isRecording = false
                self.pendingCompletion?(self.frontURL, self.backURL)
                self.pendingCompletion = nil
                self.frontURL = nil
                self.backURL = nil
            }
        }
    }
}
