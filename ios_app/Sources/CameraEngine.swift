import SwiftUI
import UIKit
import AVFoundation
import Vision
import CoreML

// MARK: - Мост между SwiftUI HUD и CameraViewController

final class CameraSessionStore: ObservableObject {
    @Published var metrics = BasketballMetrics()
    @Published var fps: Double = 0.0
    @Published var poseJointsCount: Int = 0
    @Published var modelStatus: String = "AI..."
    @Published var isModelReady: Bool = false
    @Published var isPaused: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var showSkeleton: Bool
    @Published var showBallBox: Bool

    fileprivate weak var controller: CameraViewController?
    private var timer: Timer?

    init(showSkeleton: Bool, showBallBox: Bool) {
        self.showSkeleton = showSkeleton
        self.showBallBox = showBallBox
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    var formattedElapsed: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var controlPercent: Int {
        let total = metrics.realBounces + metrics.falseBounces
        guard total > 0 else { return 100 }
        return Int((Double(metrics.realBounces) / Double(total) * 100.0).rounded())
    }

    func togglePause() {
        isPaused.toggle()
        controller?.setPaused(isPaused)
    }

    func reset() {
        elapsedSeconds = 0
        metrics = BasketballMetrics()
        controller?.resetMetrics()
    }

    func switchCamera() {
        controller?.toggleCamera()
    }

    func toggleSkeleton() {
        showSkeleton.toggle()
        controller?.setOverlayOptions(showSkeleton: showSkeleton, showBallBox: showBallBox)
    }

    func toggleBallBox() {
        showBallBox.toggle()
        controller?.setOverlayOptions(showSkeleton: showSkeleton, showBallBox: showBallBox)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        controller?.stopSession()
    }

    func buildRecord(mode: WorkoutMode) -> WorkoutRecord {
        WorkoutRecord(
            date: Date(),
            mode: mode,
            durationSec: max(elapsedSeconds, 1),
            realBounces: metrics.realBounces,
            falseBounces: metrics.falseBounces,
            shots: metrics.shots,
            tempo: metrics.tempo,
            avgHeightCm: metrics.avgBounceHeightCm
        )
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.elapsedSeconds += 1
        }
    }
}

struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var session: CameraSessionStore

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController(session: session)
        session.controller = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.setOverlayOptions(
            showSkeleton: session.showSkeleton,
            showBallBox: session.showBallBox
        )
    }
}

// MARK: - Камера + Vision + Core ML

private struct SkeletonGroup {
    let color: UIColor
    let pairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)]
}

private struct FrameRenderPayload {
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let ballResult: (CGRect, Float)?
    let metrics: BasketballMetrics
    let fps: Double
    let modelStatus: String
    let isModelReady: Bool
}

final class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var sessionStore: CameraSessionStore?

    private let sessionQueue = DispatchQueue(label: "com.basketball.sessionQueue", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.basketball.videoQueue", qos: .userInitiated)

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let drawingLayer = CALayer()

    private var skeletonLineLayers: [CAShapeLayer] = []
    private let jointsLayer = CAShapeLayer()
    private let ballBoxLayer = CAShapeLayer()
    private let ballTextLayer = CATextLayer()

    // Флаги видимости оверлеев (main thread)
    private var showSkeletonOverlay: Bool = true
    private var showBallBoxOverlay: Bool = true

    // Состояние камеры (sessionQueue)
    private var sessionPosition: AVCaptureDevice.Position = .back

    // Состояние пайплайна (videoQueue)
    private var isProcessingPaused: Bool = false
    private var processingPosition: AVCaptureDevice.Position = .back
    private var processingOrientation: UIInterfaceOrientation = .portrait
    private var processingViewSize: CGSize = .zero
    private var lastFrameTime: CFAbsoluteTime?
    private var smoothedFPS: Double = 0.0
    private var modelStatus: String = "AI..."
    private var isModelReady: Bool = false
    private var modelInputSize: CGSize = CGSize(width: 640, height: 640)
    private var ballClassChannel: Int = 4

    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var ballRequest: VNCoreMLRequest?
    private let metricsCalculator = MetricsCalculator()

    private let skeletonGroups: [SkeletonGroup] = [
        SkeletonGroup(color: UIColor(red: 0.18, green: 0.90, blue: 0.62, alpha: 0.95), pairs: [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftHip),
            (.rightShoulder, .rightHip),
            (.leftHip, .rightHip)
        ]),
        SkeletonGroup(color: UIColor(red: 1.0, green: 0.42, blue: 0.10, alpha: 0.95), pairs: [
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist)
        ]),
        SkeletonGroup(color: UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.95), pairs: [
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist)
        ]),
        SkeletonGroup(color: UIColor.systemYellow.withAlphaComponent(0.9), pairs: [
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle)
        ]),
        SkeletonGroup(color: UIColor.systemTeal.withAlphaComponent(0.9), pairs: [
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ])
    ]

    init(session: CameraSessionStore) {
        self.sessionStore = session
        self.showSkeletonOverlay = session.showSkeleton
        self.showBallBoxOverlay = session.showBallBox
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopSession()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)
        setupPreviewAndDrawingLayers()
        setupModelAsync()
        setupCameraAsync()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        drawingLayer.frame = view.bounds
        CATransaction.commit()

        let currentOrientation = currentInterfaceOrientation()
        updatePreviewOrientation(currentOrientation)

        let boundsSize = view.bounds.size
        videoQueue.async { [weak self] in
            self?.processingViewSize = boundsSize
            self?.processingOrientation = currentOrientation
        }
    }

    // MARK: - Внешнее управление из SwiftUI

    func setPaused(_ paused: Bool) {
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            self.isProcessingPaused = paused
            self.lastFrameTime = nil
            if paused {
                self.metricsCalculator.notifyPause()
            }
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if paused {
                if self.captureSession.isRunning { self.captureSession.stopRunning() }
            } else {
                if !self.captureSession.isRunning { self.captureSession.startRunning() }
            }
        }
    }

    func resetMetrics() {
        videoQueue.async { [weak self] in
            self?.metricsCalculator.reset()
        }
    }

    func setOverlayOptions(showSkeleton: Bool, showBallBox: Bool) {
        showSkeletonOverlay = showSkeleton
        showBallBoxOverlay = showBallBox

        if !showSkeleton {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            skeletonLineLayers.forEach { $0.path = nil }
            jointsLayer.path = nil
            CATransaction.commit()
        }
        if !showBallBox {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ballBoxLayer.isHidden = true
            ballTextLayer.isHidden = true
            CATransaction.commit()
        }
    }

    func toggleCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()

            guard let currentInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else {
                self.captureSession.commitConfiguration()
                return
            }

            let nextPosition: AVCaptureDevice.Position = (self.sessionPosition == .back) ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: nextPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.removeInput(currentInput)
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.sessionPosition = nextPosition
            } else {
                self.captureSession.addInput(currentInput)
            }

            if let connection = self.videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }

            self.captureSession.commitConfiguration()

            let confirmedPosition = self.sessionPosition
            self.videoQueue.async { [weak self] in
                guard let self = self else { return }
                self.processingPosition = confirmedPosition
                self.metricsCalculator.notifyPause()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    // MARK: - Настройка слоёв, камеры и модели

    private func setupPreviewAndDrawingLayers() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.addSublayer(drawingLayer)

        skeletonLineLayers = skeletonGroups.map { group in
            let layer = CAShapeLayer()
            layer.strokeColor = group.color.cgColor
            layer.lineWidth = 3.5
            layer.lineCap = .round
            layer.fillColor = UIColor.clear.cgColor
            drawingLayer.addSublayer(layer)
            return layer
        }

        jointsLayer.fillColor = UIColor.white.cgColor
        drawingLayer.addSublayer(jointsLayer)

        let orangeUI = UIColor(red: 1.0, green: 0.42, blue: 0.10, alpha: 1.0)
        ballBoxLayer.strokeColor = orangeUI.cgColor
        ballBoxLayer.lineWidth = 3.5
        ballBoxLayer.fillColor = orangeUI.withAlphaComponent(0.10).cgColor
        ballBoxLayer.isHidden = true
        drawingLayer.addSublayer(ballBoxLayer)

        ballTextLayer.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        ballTextLayer.fontSize = 12
        ballTextLayer.foregroundColor = UIColor.white.cgColor
        ballTextLayer.backgroundColor = orangeUI.cgColor
        ballTextLayer.alignmentMode = .center
        ballTextLayer.cornerRadius = 6
        ballTextLayer.masksToBounds = true
        ballTextLayer.contentsScale = UIScreen.main.scale
        ballTextLayer.isHidden = true
        drawingLayer.addSublayer(ballTextLayer)
    }

    private func setupCameraAsync() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1280x720

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.sessionPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updatePreviewOrientation(self.currentInterfaceOrientation())
            }
        }
    }

    private func setupModelAsync() {
        videoQueue.async { [weak self] in
            guard let self = self else { return }

            let config = MLModelConfiguration()
            config.computeUnits = .all

            let loadedModel: MLModel?
            if let model = try? basketball_best(configuration: config).model {
                loadedModel = model
            } else if let modelURL = Bundle.main.url(forResource: "basketball_best", withExtension: "mlmodelc"),
                      let model = try? MLModel(contentsOf: modelURL, configuration: config) {
                loadedModel = model
            } else {
                loadedModel = nil
            }

            guard let mlModel = loadedModel, let vnModel = try? VNCoreMLModel(for: mlModel) else {
                self.modelStatus = "AI ERR"
                self.isModelReady = false
                DispatchQueue.main.async { [weak self] in
                    self?.sessionStore?.modelStatus = "AI ERR"
                    self?.sessionStore?.isModelReady = false
                }
                return
            }

            if let imageConstraint = mlModel.modelDescription.inputDescriptionsByName.values
                .compactMap({ $0.imageConstraint }).first {
                self.modelInputSize = CGSize(
                    width: CGFloat(imageConstraint.pixelsWide),
                    height: CGFloat(imageConstraint.pixelsHigh)
                )
            }

            if let labels = mlModel.modelDescription.classLabels as? [String],
               let idx = labels.firstIndex(where: { $0.lowercased().contains("ball") }) {
                self.ballClassChannel = 4 + idx
            } else {
                self.ballClassChannel = 4
            }

            let request = VNCoreMLRequest(model: vnModel)
            request.imageCropAndScaleOption = .scaleFit
            self.ballRequest = request
            self.modelStatus = "AI OK"
            self.isModelReady = true

            DispatchQueue.main.async { [weak self] in
                self?.sessionStore?.modelStatus = "AI OK"
                self?.sessionStore?.isModelReady = true
            }
        }
    }

    // MARK: - Обработка кадров (videoQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingPaused,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let currentTime = CFAbsoluteTimeGetCurrent()
        if let prev = lastFrameTime {
            let instantFPS = 1.0 / max(0.001, currentTime - prev)
            smoothedFPS = (smoothedFPS == 0) ? instantFPS : (0.2 * instantFPS + 0.8 * smoothedFPS)
        }
        lastFrameTime = currentTime

        let cgOrientation = visionOrientation(for: processingPosition, interfaceOrientation: processingOrientation)
        let rawWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let rawHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let isPortraitOriented: Bool
        switch cgOrientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            isPortraitOriented = true
        default:
            isPortraitOriented = false
        }

        let frameWidth = isPortraitOriented ? rawHeight : rawWidth
        let frameHeight = isPortraitOriented ? rawWidth : rawHeight

        var requests: [VNRequest] = [poseRequest]
        if let ballReq = ballRequest {
            requests.append(ballReq)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: cgOrientation, options: [:])
        try? handler.perform(requests)

        let framePoints = extractPosePoints(from: poseRequest, frameWidth: frameWidth, frameHeight: frameHeight)
        let frameBall = extractBestBallBox(from: ballRequest?.results, frameWidth: frameWidth, frameHeight: frameHeight)

        let metrics = metricsCalculator.update(
            ballRect: frameBall?.0,
            leftWrist: framePoints[.leftWrist],
            rightWrist: framePoints[.rightWrist],
            leftShoulder: framePoints[.leftShoulder],
            rightShoulder: framePoints[.rightShoulder],
            timestamp: currentTime,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )

        let viewSize = processingViewSize
        let screenPoints = mapPointsToScreen(framePoints, frameWidth: frameWidth, frameHeight: frameHeight, viewSize: viewSize)
        let screenBall: (CGRect, Float)? = frameBall.map { (rect, conf) in
            (mapRectToScreen(rect, frameWidth: frameWidth, frameHeight: frameHeight, viewSize: viewSize), conf)
        }

        let payload = FrameRenderPayload(
            points: screenPoints,
            ballResult: screenBall,
            metrics: metrics,
            fps: smoothedFPS,
            modelStatus: modelStatus,
            isModelReady: isModelReady
        )

        DispatchQueue.main.async { [weak self] in
            self?.render(payload)
        }
    }

    // MARK: - Парсинг детекций и геометрия

    private func extractPosePoints(
        from pose: VNDetectHumanBodyPoseRequest,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var pointsDict: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        guard let observation = pose.results?.first else { return pointsDict }

        for group in skeletonGroups {
            for (j1, j2) in group.pairs {
                for joint in [j1, j2] where pointsDict[joint] == nil {
                    if let point = try? observation.recognizedPoint(joint), point.confidence > 0.15 {
                        pointsDict[joint] = CGPoint(
                            x: point.location.x * frameWidth,
                            y: (1.0 - point.location.y) * frameHeight
                        )
                    }
                }
            }
        }
        return pointsDict
    }

    private func extractBestBallBox(
        from results: [Any]?,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> (CGRect, Float)? {
        guard let results = results else { return nil }

        if let observations = results as? [VNRecognizedObjectObservation] {
            let ballObs = observations.filter { obs in
                guard let label = obs.labels.first?.identifier.lowercased() else { return true }
                return label.contains("ball") || label == "0"
            }
            if let best = ballObs.max(by: { $0.confidence < $1.confidence }), best.confidence > 0.20 {
                let box = best.boundingBox
                let rect = CGRect(
                    x: box.origin.x * frameWidth,
                    y: (1.0 - box.origin.y - box.height) * frameHeight,
                    width: box.width * frameWidth,
                    height: box.height * frameHeight
                )
                return (rect, best.confidence)
            }
        }

        if let featureObs = results as? [VNCoreMLFeatureValueObservation],
           let multiArray = featureObs.first?.featureValue.multiArrayValue {
            let shape = multiArray.shape.map { $0.intValue }
            guard shape.count == 3 else { return nil }
            let channels = shape[1]
            let anchors = shape[2]
            guard channels >= 5, anchors > 0 else { return nil }

            let targetChannel = min(ballClassChannel, channels - 1)
            let strides = multiArray.strides.map { $0.intValue }
            let cStride = strides[1]
            let aStride = strides[2]

            var bestConf: Float = 0.20
            var bestAnchor = -1
            var rawCX: CGFloat = 0
            var rawCY: CGFloat = 0
            var rawW: CGFloat = 0
            var rawH: CGFloat = 0

            #if arch(arm64)
            if multiArray.dataType == .float16 {
                let ptr = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: multiArray.count)
                for a in 0..<anchors {
                    let conf = Float(ptr[targetChannel * cStride + a * aStride])
                    if conf > bestConf { bestConf = conf; bestAnchor = a }
                }
                if bestAnchor >= 0 {
                    rawCX = CGFloat(ptr[0 * cStride + bestAnchor * aStride])
                    rawCY = CGFloat(ptr[1 * cStride + bestAnchor * aStride])
                    rawW  = CGFloat(ptr[2 * cStride + bestAnchor * aStride])
                    rawH  = CGFloat(ptr[3 * cStride + bestAnchor * aStride])
                }
            } else if multiArray.dataType == .float32 {
                let ptr = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
                for a in 0..<anchors {
                    let conf = ptr[targetChannel * cStride + a * aStride]
                    if conf > bestConf { bestConf = conf; bestAnchor = a }
                }
                if bestAnchor >= 0 {
                    rawCX = CGFloat(ptr[0 * cStride + bestAnchor * aStride])
                    rawCY = CGFloat(ptr[1 * cStride + bestAnchor * aStride])
                    rawW  = CGFloat(ptr[2 * cStride + bestAnchor * aStride])
                    rawH  = CGFloat(ptr[3 * cStride + bestAnchor * aStride])
                }
            }
            #else
            if multiArray.dataType == .float32 {
                let ptr = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
                for a in 0..<anchors {
                    let conf = ptr[targetChannel * cStride + a * aStride]
                    if conf > bestConf { bestConf = conf; bestAnchor = a }
                }
                if bestAnchor >= 0 {
                    rawCX = CGFloat(ptr[0 * cStride + bestAnchor * aStride])
                    rawCY = CGFloat(ptr[1 * cStride + bestAnchor * aStride])
                    rawW  = CGFloat(ptr[2 * cStride + bestAnchor * aStride])
                    rawH  = CGFloat(ptr[3 * cStride + bestAnchor * aStride])
                }
            }
            #endif

            if bestAnchor >= 0 {
                let modelW = modelInputSize.width
                let modelH = modelInputSize.height

                var cx = rawCX, cy = rawCY, w = rawW, h = rawH
                if cx <= 2.0 && cy <= 2.0 && w <= 2.0 && h <= 2.0 {
                    cx *= modelW; cy *= modelH; w *= modelW; h *= modelH
                }

                let scale = min(modelW / frameWidth, modelH / frameHeight)
                let padX = (modelW - frameWidth * scale) / 2.0
                let padY = (modelH - frameHeight * scale) / 2.0

                let imgCX = (cx - padX) / scale
                let imgCY = (cy - padY) / scale
                let imgW = w / scale
                let imgH = h / scale

                let rect = CGRect(x: imgCX - imgW / 2.0, y: imgCY - imgH / 2.0, width: imgW, height: imgH)
                return (rect, bestConf)
            }
        }
        return nil
    }

    private func aspectFillTransform(frameWidth: CGFloat, frameHeight: CGFloat, viewSize: CGSize) -> (CGFloat, CGFloat, CGFloat) {
        guard frameWidth > 0, frameHeight > 0, viewSize.width > 0, viewSize.height > 0 else {
            return (1, 0, 0)
        }
        let scale = max(viewSize.width / frameWidth, viewSize.height / frameHeight)
        let offsetX = (viewSize.width - frameWidth * scale) / 2.0
        let offsetY = (viewSize.height - frameHeight * scale) / 2.0
        return (scale, offsetX, offsetY)
    }

    private func mapPointsToScreen(
        _ points: [VNHumanBodyPoseObservation.JointName: CGPoint],
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        viewSize: CGSize
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        let (scale, offsetX, offsetY) = aspectFillTransform(frameWidth: frameWidth, frameHeight: frameHeight, viewSize: viewSize)
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        mapped.reserveCapacity(points.count)
        for (joint, pt) in points {
            mapped[joint] = CGPoint(x: pt.x * scale + offsetX, y: pt.y * scale + offsetY)
        }
        return mapped
    }

    private func mapRectToScreen(_ rect: CGRect, frameWidth: CGFloat, frameHeight: CGFloat, viewSize: CGSize) -> CGRect {
        let (scale, offsetX, offsetY) = aspectFillTransform(frameWidth: frameWidth, frameHeight: frameHeight, viewSize: viewSize)
        return CGRect(
            x: rect.origin.x * scale + offsetX,
            y: rect.origin.y * scale + offsetY,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        view.window?.windowScene?.interfaceOrientation ?? .portrait
    }

    private func updatePreviewOrientation(_ orientation: UIInterfaceOrientation) {
        guard let connection = previewLayer?.connection else { return }
        if #available(iOS 17.0, *) {
            let angle: CGFloat
            switch orientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeRight:     angle = 0
            case .landscapeLeft:      angle = 180
            default:                  angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            switch orientation {
            case .portrait:           connection.videoOrientation = .portrait
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            case .landscapeRight:     connection.videoOrientation = .landscapeRight
            case .landscapeLeft:      connection.videoOrientation = .landscapeLeft
            default:                  connection.videoOrientation = .portrait
            }
        }
    }

    private func visionOrientation(
        for position: AVCaptureDevice.Position,
        interfaceOrientation: UIInterfaceOrientation
    ) -> CGImagePropertyOrientation {
        switch (position, interfaceOrientation) {
        case (.front, .portrait):           return .leftMirrored
        case (.front, .portraitUpsideDown): return .rightMirrored
        case (.front, .landscapeRight):     return .upMirrored
        case (.front, .landscapeLeft):      return .downMirrored
        case (_, .portrait):                return .right
        case (_, .portraitUpsideDown):      return .left
        case (_, .landscapeRight):          return .up
        case (_, .landscapeLeft):           return .down
        default:                            return position == .front ? .leftMirrored : .right
        }
    }

    private func render(_ payload: FrameRenderPayload) {
        guard let store = sessionStore, !store.isPaused else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if showSkeletonOverlay {
            for (idx, group) in skeletonGroups.enumerated() {
                let groupPath = UIBezierPath()
                for (j1, j2) in group.pairs {
                    if let p1 = payload.points[j1], let p2 = payload.points[j2] {
                        groupPath.move(to: p1)
                        groupPath.addLine(to: p2)
                    }
                }
                skeletonLineLayers[idx].path = groupPath.isEmpty ? nil : groupPath.cgPath
            }

            if payload.points.isEmpty {
                jointsLayer.path = nil
            } else {
                let jointsPath = UIBezierPath()
                for (_, p) in payload.points {
                    jointsPath.append(UIBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)))
                }
                jointsLayer.path = jointsPath.cgPath
            }
        } else {
            skeletonLineLayers.forEach { $0.path = nil }
            jointsLayer.path = nil
        }

        if showBallBoxOverlay, let (screenRect, conf) = payload.ballResult {
            ballBoxLayer.isHidden = false
            ballBoxLayer.path = UIBezierPath(roundedRect: screenRect, cornerRadius: 10).cgPath

            ballTextLayer.isHidden = false
            ballTextLayer.string = String(format: "Мяч %.0f%%", conf * 100)
            ballTextLayer.frame = CGRect(x: screenRect.minX, y: max(0, screenRect.minY - 24), width: 78, height: 20)
        } else {
            ballBoxLayer.isHidden = true
            ballTextLayer.isHidden = true
        }

        CATransaction.commit()

        store.metrics = payload.metrics
        store.fps = payload.fps
        store.poseJointsCount = payload.points.count
        store.modelStatus = payload.modelStatus
        store.isModelReady = payload.isModelReady
    }
}