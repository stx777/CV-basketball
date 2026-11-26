import SwiftUI
import UIKit
import AVFoundation
import Vision
import CoreML

@main
struct BasketballApp: App {
    var body: some Scene {
        WindowGroup {
            CameraViewControllerRepresentable()
                .ignoresSafeArea()
        }
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController { CameraViewController() }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

struct SkeletonGroup {
    let color: UIColor
    let pairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)]
}

private struct FrameRenderPayload {
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let ballResult: (CGRect, Float)?
    let metrics: BasketballMetrics
    let fps: Double
    let modelStatus: String
}

final class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    // Выделенные последовательные очереди для исключения гонок данных
    private let sessionQueue = DispatchQueue(label: "com.basketball.sessionQueue", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.basketball.videoQueue", qos: .userInitiated)

    // Камера и слои
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let drawingLayer = CALayer()

    // Переиспользуемые слои отрисовки (без пересоздания каждый кадр)
    private var skeletonLineLayers: [CAShapeLayer] = []
    private let jointsLayer = CAShapeLayer()
    private let ballBoxLayer = CAShapeLayer()
    private let ballTextLayer = CATextLayer()

    // UI элементы (доступ только с main)
    private let fpsLabel = UILabel()
    private let switchCameraButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let metricsContainer = UIView()
    private let metricsPrimaryLabel = UILabel()
    private let metricsSecondaryLabel = UILabel()
    private var isUIPaused: Bool = false

    // Состояние камеры (доступ только с sessionQueue)
    private var sessionPosition: AVCaptureDevice.Position = .back

    // Состояние обработки кадров (доступ только с videoQueue)
    private var isProcessingPaused: Bool = false
    private var processingPosition: AVCaptureDevice.Position = .back
    private var processingOrientation: UIInterfaceOrientation = .portrait
    private var processingViewSize: CGSize = .zero
    private var lastFrameTime: CFAbsoluteTime?
    private var smoothedFPS: Double = 0.0
    private var modelStatus: String = "Ball: LOADING"
    private var modelInputSize: CGSize = CGSize(width: 640, height: 640)
    private var ballClassChannel: Int = 4

    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var ballRequest: VNCoreMLRequest?
    private let metricsCalculator = MetricsCalculator()

    private let skeletonGroups: [SkeletonGroup] = [
        SkeletonGroup(color: .green, pairs: [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftHip),
            (.rightShoulder, .rightHip),
            (.leftHip, .rightHip)
        ]),
        SkeletonGroup(color: .red, pairs: [
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist)
        ]),
        SkeletonGroup(color: .blue, pairs: [
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist)
        ]),
        SkeletonGroup(color: .yellow, pairs: [
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle)
        ]),
        SkeletonGroup(color: .cyan, pairs: [
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewAndDrawingLayers()
        setupUI()
        setupModelAsync()
        setupCameraAsync()
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

        let btnSize: CGFloat = 44
        let topPadding: CGFloat = max(55, view.safeAreaInsets.top + 8)
        let spacing: CGFloat = 10

        switchCameraButton.frame = CGRect(x: view.bounds.width - btnSize - 16, y: topPadding, width: btnSize, height: btnSize)
        pauseButton.frame = CGRect(x: switchCameraButton.frame.minX - btnSize - spacing, y: topPadding, width: btnSize, height: btnSize)
        resetButton.frame = CGRect(x: pauseButton.frame.minX - btnSize - spacing, y: topPadding, width: btnSize, height: btnSize)

        let labelWidth = resetButton.frame.minX - 16 - 10
        fpsLabel.frame = CGRect(x: 16, y: topPadding, width: max(120, labelWidth), height: btnSize)

        let bottomPadding = max(24, view.safeAreaInsets.bottom + 12)
        let panelHeight: CGFloat = 76
        metricsContainer.frame = CGRect(
            x: 16,
            y: view.bounds.height - bottomPadding - panelHeight,
            width: view.bounds.width - 32,
            height: panelHeight
        )
        metricsPrimaryLabel.frame = CGRect(x: 12, y: 10, width: metricsContainer.bounds.width - 24, height: 26)
        metricsSecondaryLabel.frame = CGRect(x: 12, y: 40, width: metricsContainer.bounds.width - 24, height: 24)
    }

    private func setupPreviewAndDrawingLayers() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.addSublayer(drawingLayer)

        skeletonLineLayers = skeletonGroups.map { group in
            let layer = CAShapeLayer()
            layer.strokeColor = group.color.cgColor
            layer.lineWidth = 4
            layer.lineCap = .round
            layer.fillColor = UIColor.clear.cgColor
            drawingLayer.addSublayer(layer)
            return layer
        }

        jointsLayer.fillColor = UIColor.white.cgColor
        drawingLayer.addSublayer(jointsLayer)

        ballBoxLayer.strokeColor = UIColor.systemBlue.cgColor
        ballBoxLayer.lineWidth = 4
        ballBoxLayer.fillColor = UIColor.clear.cgColor
        ballBoxLayer.isHidden = true
        drawingLayer.addSublayer(ballBoxLayer)

        ballTextLayer.font = UIFont.boldSystemFont(ofSize: 14)
        ballTextLayer.fontSize = 14
        ballTextLayer.foregroundColor = UIColor.white.cgColor
        ballTextLayer.backgroundColor = UIColor.systemBlue.cgColor
        ballTextLayer.alignmentMode = .center
        ballTextLayer.cornerRadius = 4
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
                self.modelStatus = "Ball: ERR"
                DispatchQueue.main.async { [weak self] in
                    self?.fpsLabel.text = "Ball: ERR"
                }
                return
            }

            // Определяем реальный размер входа модели вместо хардкода 640
            if let imageConstraint = mlModel.modelDescription.inputDescriptionsByName.values
                .compactMap({ $0.imageConstraint }).first {
                self.modelInputSize = CGSize(
                    width: CGFloat(imageConstraint.pixelsWide),
                    height: CGFloat(imageConstraint.pixelsHigh)
                )
            }

            // Определяем индекс канала мяча для сырого тензора
            if let labels = mlModel.modelDescription.classLabels as? [String],
               let idx = labels.firstIndex(where: { $0.lowercased().contains("ball") }) {
                self.ballClassChannel = 4 + idx
            } else {
                self.ballClassChannel = 4
            }

            let request = VNCoreMLRequest(model: vnModel)
            // Сохраняем пропорции мяча без сплющивания (letterbox)
            request.imageCropAndScaleOption = .scaleFit
            self.ballRequest = request
            self.modelStatus = "Ball: OK"
        }
    }

    private func setupUI() {
        fpsLabel.textColor = .green
        fpsLabel.font = .boldSystemFont(ofSize: 12)
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        fpsLabel.layer.cornerRadius = 10
        fpsLabel.clipsToBounds = true
        fpsLabel.textAlignment = .center
        fpsLabel.adjustsFontSizeToFitWidth = true
        fpsLabel.text = "Загрузка модели..."
        view.addSubview(fpsLabel)

        resetButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        resetButton.tintColor = .white
        resetButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        resetButton.layer.cornerRadius = 22
        resetButton.clipsToBounds = true
        resetButton.addTarget(self, action: #selector(resetMetrics), for: .touchUpInside)
        view.addSubview(resetButton)

        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.tintColor = .white
        pauseButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        pauseButton.layer.cornerRadius = 22
        pauseButton.clipsToBounds = true
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        view.addSubview(pauseButton)

        switchCameraButton.setImage(UIImage(systemName: "camera.rotate.fill"), for: .normal)
        switchCameraButton.tintColor = .white
        switchCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        switchCameraButton.layer.cornerRadius = 22
        switchCameraButton.clipsToBounds = true
        switchCameraButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
        view.addSubview(switchCameraButton)

        metricsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        metricsContainer.layer.cornerRadius = 14
        metricsContainer.clipsToBounds = true
        view.addSubview(metricsContainer)

        metricsPrimaryLabel.textColor = .white
        metricsPrimaryLabel.font = .boldSystemFont(ofSize: 15)
        metricsPrimaryLabel.textAlignment = .center
        metricsPrimaryLabel.text = "Удары: 0   |   Броски: 0   |   Потери: 0"
        metricsContainer.addSubview(metricsPrimaryLabel)

        metricsSecondaryLabel.textColor = .systemGreen
        metricsSecondaryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        metricsSecondaryLabel.textAlignment = .center
        metricsSecondaryLabel.text = "Темп: 0.00 уд/с   |   Высота: 0.0 см"
        metricsContainer.addSubview(metricsSecondaryLabel)
    }

    @objc private func resetMetrics() {
        videoQueue.async { [weak self] in
            self?.metricsCalculator.reset()
        }
        metricsPrimaryLabel.text = "Удары: 0   |   Броски: 0   |   Потери: 0"
        metricsSecondaryLabel.text = "Темп: 0.00 уд/с   |   Высота: 0.0 см"
    }

    @objc private func togglePause() {
        isUIPaused.toggle()
        let paused = isUIPaused

        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let iconName = paused ? "play.fill" : "pause.fill"
        pauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        pauseButton.tintColor = paused ? .systemYellow : .white

        videoQueue.async { [weak self] in
            guard let self = self else { return }
            self.isProcessingPaused = paused
            self.lastFrameTime = nil
            if paused {
                self.metricsCalculator.notifyPause()
                let status = self.modelStatus
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.isUIPaused else { return }
                    self.fpsLabel.text = String(format: "PAUSED | %@", status)
                    self.fpsLabel.textColor = .systemYellow
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isUIPaused else { return }
                    self.fpsLabel.textColor = .green
                }
            }
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if paused {
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
            } else {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            }
        }
    }

    @objc private func toggleCamera() {
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

    // MARK: - Обработка видеопотока (исполняется строго на videoQueue)

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

        // 1. Извлекаем координаты в неискажённом пространстве ориентированного кадра
        let framePoints = extractPosePoints(from: poseRequest, frameWidth: frameWidth, frameHeight: frameHeight)
        let frameBall = extractBestBallBox(from: ballRequest?.results, frameWidth: frameWidth, frameHeight: frameHeight)

        // 2. Считаем метрики в неискажённых пикселях кадра на videoQueue
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

        // 3. Переводим координаты в экранное пространство previewLayer (resizeAspectFill)
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
            modelStatus: modelStatus
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isUIPaused else { return }
            self.render(payload)
        }
    }

    // MARK: - Извлечение детекций (ориентированные пиксели кадра, top-left origin)

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

        // 1. Модель со встроенным NMS (Vision сам компенсирует .scaleFit)
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

        // 2. Сырой тензор YOLO [1, 4 + numClasses, anchors] с обратным un-letterboxing под .scaleFit
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
                    if conf > bestConf {
                        bestConf = conf
                        bestAnchor = a
                    }
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
                    if conf > bestConf {
                        bestConf = conf
                        bestAnchor = a
                    }
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
                    if conf > bestConf {
                        bestConf = conf
                        bestAnchor = a
                    }
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

                // Приводим к пикселям входа модели, если выход нормализован в [0, 1]
                var cx = rawCX
                var cy = rawCY
                var w = rawW
                var h = rawH
                if cx <= 2.0 && cy <= 2.0 && w <= 2.0 && h <= 2.0 {
                    cx *= modelW
                    cy *= modelH
                    w *= modelW
                    h *= modelH
                }

                // Компенсация letterbox-полей от .scaleFit
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

    // MARK: - Проекция координат на экран (resizeAspectFill) и ориентация

    private func aspectFillTransform(frameWidth: CGFloat, frameHeight: CGFloat, viewSize: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
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

    // MARK: - Отрисовка на main thread без пересоздания слоёв

    private func render(_ payload: FrameRenderPayload) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

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

        if let (screenRect, conf) = payload.ballResult {
            ballBoxLayer.isHidden = false
            ballBoxLayer.path = UIBezierPath(rect: screenRect).cgPath

            ballTextLayer.isHidden = false
            ballTextLayer.string = String(format: "Ball %.2f", conf)
            ballTextLayer.frame = CGRect(x: screenRect.minX, y: max(0, screenRect.minY - 24), width: 85, height: 20)
        } else {
            ballBoxLayer.isHidden = true
            ballTextLayer.isHidden = true
        }

        CATransaction.commit()

        fpsLabel.text = String(format: "FPS: %.1f | Pose: %d | %@", payload.fps, payload.points.count, payload.modelStatus)
        metricsPrimaryLabel.text = String(
            format: "Удары: %d   |   Броски: %d   |   Потери: %d",
            payload.metrics.realBounces, payload.metrics.shots, payload.metrics.falseBounces
        )
        metricsSecondaryLabel.text = String(
            format: "Темп: %.2f уд/с   |   Высота: %.1f см",
            payload.metrics.tempo, payload.metrics.avgBounceHeightCm
        )
    }
}