import AVFoundation
import UIKit
import Combine

final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum SessionMode {
        case reactionToImportedVideo
        case rearPrimaryWithFrontOverlay
    }

    @Published var isRecording = false
    @Published var permissionGranted = false

    let session = AVCaptureMultiCamSession()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()
    let rearPreviewLayer = AVCaptureVideoPreviewLayer()

    private let frontMovieOutput = AVCaptureMovieFileOutput()
    private let rearMovieOutput = AVCaptureMovieFileOutput()

    private var frontVideoInput: AVCaptureDeviceInput?
    private var rearVideoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private let sessionQueue = DispatchQueue(label: "com.reactcam.cameramanager.session")
    private var configuredMode: SessionMode?
    private var frontPosition: AVCaptureDevice.Position = .front

    private var frontRecordingURL: URL?
    private var rearRecordingURL: URL?
    private var recordingCompletion: ((URL?, URL?) -> Void)?
    private var expectedFinishedOutputs = 0
    private var finishedOutputs = 0

    override init() {
        super.init()
        frontPreviewLayer.videoGravity = .resizeAspectFill
        rearPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.setSessionWithNoConnection(session)
        rearPreviewLayer.setSessionWithNoConnection(session)
    }

    var previewLayer: AVCaptureVideoPreviewLayer { frontPreviewLayer }

    func requestPermissionsAndStart(mode: SessionMode) {
        AVCaptureDevice.requestAccess(for: .video) { videoGranted in
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                guard videoGranted && audioGranted else { return }
                DispatchQueue.main.async { self.permissionGranted = true }
                AudioSessionManager.activate()
                self.sessionQueue.async {
                    self.configureIfNeeded(for: mode)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        AudioSessionManager.deactivate()
    }

    func flipReactionCamera() {
        guard !isRecording, configuredMode == .reactionToImportedVideo else { return }
        sessionQueue.async {
            self.session.beginConfiguration()
            self.removeInputAndConnections(self.frontVideoInput)
            self.frontPosition = (self.frontPosition == .front) ? .back : .front
            self.frontVideoInput = self.addVideoInput(position: self.frontPosition, movieOutput: self.frontMovieOutput, previewLayer: self.frontPreviewLayer, mirrorPreviewWhenFront: true, mirrorOutputWhenFront: true)
            self.session.commitConfiguration()
        }
    }

    func startRecording(completion: @escaping (URL?, URL?) -> Void) {
        guard session.isRunning else { return }
        recordingCompletion = completion
        frontRecordingURL = nil
        rearRecordingURL = nil
        finishedOutputs = 0

        switch configuredMode {
        case .reactionToImportedVideo:
            expectedFinishedOutputs = 1
            let frontURL = FileManager.default.temporaryDirectory.appendingPathComponent("reaction-\(UUID().uuidString).mov")
            frontMovieOutput.startRecording(to: frontURL, recordingDelegate: self)

        case .rearPrimaryWithFrontOverlay:
            expectedFinishedOutputs = 2
            let frontURL = FileManager.default.temporaryDirectory.appendingPathComponent("front-\(UUID().uuidString).mov")
            let rearURL = FileManager.default.temporaryDirectory.appendingPathComponent("rear-\(UUID().uuidString).mov")
            frontMovieOutput.startRecording(to: frontURL, recordingDelegate: self)
            rearMovieOutput.startRecording(to: rearURL, recordingDelegate: self)

        case .none:
            return
        }

        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        if frontMovieOutput.isRecording { frontMovieOutput.stopRecording() }
        if rearMovieOutput.isRecording { rearMovieOutput.stopRecording() }
        if !frontMovieOutput.isRecording && !rearMovieOutput.isRecording {
            DispatchQueue.main.async { self.isRecording = false }
        }
    }

    private func configureIfNeeded(for mode: SessionMode) {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return }
        if configuredMode == mode { return }

        session.beginConfiguration()
        defer {
            configuredMode = mode
            session.commitConfiguration()
        }

        resetSessionGraph()

        switch mode {
        case .reactionToImportedVideo:
            frontPosition = .front
            frontVideoInput = addVideoInput(position: .front, movieOutput: frontMovieOutput, previewLayer: frontPreviewLayer, mirrorPreviewWhenFront: true, mirrorOutputWhenFront: true)
            audioInput = addAudioInput(to: frontMovieOutput)

        case .rearPrimaryWithFrontOverlay:
            rearVideoInput = addVideoInput(position: .back, movieOutput: rearMovieOutput, previewLayer: rearPreviewLayer, mirrorPreviewWhenFront: false, mirrorOutputWhenFront: false)
            frontVideoInput = addVideoInput(position: .front, movieOutput: frontMovieOutput, previewLayer: frontPreviewLayer, mirrorPreviewWhenFront: true, mirrorOutputWhenFront: true)
            audioInput = addAudioInput(to: rearMovieOutput)
        }
    }

    private func resetSessionGraph() {
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
        for connection in session.connections { session.removeConnection(connection) }
        frontVideoInput = nil
        rearVideoInput = nil
        audioInput = nil
    }

    @discardableResult
    private func addVideoInput(position: AVCaptureDevice.Position, movieOutput: AVCaptureMovieFileOutput, previewLayer: AVCaptureVideoPreviewLayer, mirrorPreviewWhenFront: Bool, mirrorOutputWhenFront: Bool) -> AVCaptureDeviceInput? {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            return nil
        }

        session.addInputWithNoConnections(input)
        guard let port = input.ports(for: .video, sourceDeviceType: camera.deviceType, sourceDevicePosition: position).first else {
            return input
        }

        if session.canAddOutput(movieOutput) {
            session.addOutputWithNoConnections(movieOutput)
            let movieConnection = AVCaptureConnection(inputPorts: [port], output: movieOutput)
            if position == .front {
                movieConnection.automaticallyAdjustsVideoMirroring = false
                movieConnection.isVideoMirrored = mirrorOutputWhenFront
            }
            if session.canAddConnection(movieConnection) {
                session.addConnection(movieConnection)
            }
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        if position == .front {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = mirrorPreviewWhenFront
        }
        if session.canAddConnection(previewConnection) {
            session.addConnection(previewConnection)
        }

        return input
    }

    private func addAudioInput(to movieOutput: AVCaptureMovieFileOutput) -> AVCaptureDeviceInput? {
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else {
            return nil
        }

        session.addInputWithNoConnections(input)
        if let audioPort = input.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: .unspecified).first {
            let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: movieOutput)
            if session.canAddConnection(audioConnection) {
                session.addConnection(audioConnection)
            }
        }
        return input
    }

    private func removeInputAndConnections(_ input: AVCaptureDeviceInput?) {
        guard let input else { return }
        let ports = Set(input.ports.map { ObjectIdentifier($0) })
        for connection in session.connections {
            let usesInputPort = connection.inputPorts.contains { ports.contains(ObjectIdentifier($0)) }
            let isTargetOutput = connection.output === frontMovieOutput || connection.videoPreviewLayer === frontPreviewLayer
            if usesInputPort && isTargetOutput {
                session.removeConnection(connection)
            }
        }
        session.removeInput(input)
        for output in [frontMovieOutput] where session.outputs.contains(output) {
            session.removeOutput(output)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let successURL = (error == nil) ? outputFileURL : nil
        if output === frontMovieOutput {
            frontRecordingURL = successURL
        } else if output === rearMovieOutput {
            rearRecordingURL = successURL
        }

        finishedOutputs += 1
        if finishedOutputs >= expectedFinishedOutputs {
            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingCompletion?(self.frontRecordingURL, self.rearRecordingURL)
                self.recordingCompletion = nil
                self.frontRecordingURL = nil
                self.rearRecordingURL = nil
            }
        }
    }
}
