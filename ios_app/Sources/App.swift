import SwiftUI
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

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let drawingLayer = CAShapeLayer()
    
    // UI Элементы
    private let fpsLabel = UILabel()
    private let switchCameraButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    
    // Состояние
    private var isPaused: Bool = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private let videoOutput = AVCaptureVideoDataOutput()
    private var lastTime = CFAbsoluteTimeGetCurrent()
    private var coreMLModel: VNCoreMLModel?
    private var modelStatus: String = "NO MODEL"

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
        setupCamera()
        setupUI()
        setupModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        drawingLayer.frame = view.bounds
        
        let btnSize: CGFloat = 44
        let topPadding: CGFloat = 55
        let spacing: CGFloat = 12
        
        switchCameraButton.frame = CGRect(x: view.bounds.width - btnSize - 16, y: topPadding, width: btnSize, height: btnSize)
        pauseButton.frame = CGRect(x: switchCameraButton.frame.minX - btnSize - spacing, y: topPadding, width: btnSize, height: btnSize)
        
        let labelWidth = pauseButton.frame.minX - 16 - 12
        fpsLabel.frame = CGRect(x: 16, y: topPadding, width: min(labelWidth, 230), height: btnSize)
    }

    private func setupCamera() {
        captureSession.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.addSublayer(drawingLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func setupUI() {
        fpsLabel.textColor = .green
        fpsLabel.font = .boldSystemFont(ofSize: 13)
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        fpsLabel.layer.cornerRadius = 10
        fpsLabel.clipsToBounds = true
        fpsLabel.textAlignment = .center
        view.addSubview(fpsLabel)

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
    }

    @objc private func togglePause() {
        isPaused.toggle()
        
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let iconName = isPaused ? "play.fill" : "pause.fill"
        pauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        pauseButton.tintColor = isPaused ? .systemYellow : .white

        if isPaused {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.stopRunning()
            }
            fpsLabel.text = String(format: "PAUSED | %@", modelStatus)
            fpsLabel.textColor = .systemYellow
        } else {
            lastTime = CFAbsoluteTimeGetCurrent()
            fpsLabel.textColor = .green
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    @objc private func toggleCamera() {
        captureSession.beginConfiguration()
        guard let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.removeInput(currentInput)

        currentPosition = (currentPosition == .back) ? .front : .back

        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(newInput) { captureSession.addInput(newInput) }

        // Отключаем аппаратное зеркалирование буфера: Vision сделает это сам через orientation .leftMirrored
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }

        captureSession.commitConfiguration()
    }

    private func setupModel() {
        if let model = try? basketball_best(configuration: MLModelConfiguration()).model,
           let vnModel = try? VNCoreMLModel(for: model) {
            self.coreMLModel = vnModel
            self.modelStatus = "Ball: OK"
        } else if let modelURL = Bundle.main.url(forResource: "basketball_best", withExtension: "mlmodelc"),
                  let mlModel = try? MLModel(contentsOf: modelURL),
                  let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.coreMLModel = vnModel
            self.modelStatus = "Ball: OK"
        } else {
            self.modelStatus = "Ball: ERR"
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentTime = CFAbsoluteTimeGetCurrent()
        let fps = 1.0 / max(0.001, currentTime - lastTime)
        lastTime = currentTime

        var requests: [VNRequest] = []

        let poseRequest = VNDetectHumanBodyPoseRequest()
        requests.append(poseRequest)

        var ballRequest: VNCoreMLRequest?
        if let model = coreMLModel {
            let req = VNCoreMLRequest(model: model)
            req.imageCropAndScaleOption = .scaleFill
            requests.append(req)
            ballRequest = req
        }

        let orientation: CGImagePropertyOrientation = (currentPosition == .front) ? .leftMirrored : .right
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform(requests)

        DispatchQueue.main.async {
            guard !self.isPaused else { return }
            let detectedJointsCount = self.drawResults(pose: poseRequest, ballRequest: ballRequest)
            self.fpsLabel.text = String(format: "FPS: %.1f | Pose: %d | %@", fps, detectedJointsCount, self.modelStatus)
        }
    }

    private func extractBestBallBox(from results: [Any]?, width: CGFloat, height: CGFloat) -> (CGRect, Float)? {
        guard let results = results else { return nil }

        // 1. Модель со встроенным NMS
        if let observations = results as? [VNRecognizedObjectObservation] {
            let ballObs = observations.filter { obs in
                guard let label = obs.labels.first?.identifier.lowercased() else { return true }
                return label.contains("ball") || label == "0"
            }
            if let best = ballObs.max(by: { $0.confidence < $1.confidence }), best.confidence > 0.20 {
                let box = best.boundingBox
                let rect = CGRect(
                    x: box.origin.x * width,
                    y: (1 - box.origin.y - box.height) * height,
                    width: box.width * width,
                    height: box.height * height
                )
                return (rect, best.confidence)
            }
        }

        // 2. Модель с сырым тензором [1, 6, 8400]
        if let featureObs = results as? [VNCoreMLFeatureValueObservation],
           let multiArray = featureObs.first?.featureValue.multiArrayValue {
            
            let shape = multiArray.shape.map { $0.intValue }
            guard shape.count == 3 else { return nil }
            let channels = shape[1]
            let anchors = shape[2]
            guard channels >= 5, anchors > 0 else { return nil }

            let strides = multiArray.strides.map { $0.intValue }
            let cStride = strides[1]
            let aStride = strides[2]

            var bestConf: Float = 0.20
            var bestAnchor = -1

            if multiArray.dataType == .float16 {
                let ptr = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: multiArray.count)
                for a in 0..<anchors {
                    let conf = Float(ptr[4 * cStride + a * aStride])
                    if conf > bestConf {
                        bestConf = conf
                        bestAnchor = a
                    }
                }
                if bestAnchor >= 0 {
                    var cx = CGFloat(ptr[0 * cStride + bestAnchor * aStride])
                    var cy = CGFloat(ptr[1 * cStride + bestAnchor * aStride])
                    var w  = CGFloat(ptr[2 * cStride + bestAnchor * aStride])
                    var h  = CGFloat(ptr[3 * cStride + bestAnchor * aStride])
                    if cx > 2.0 || cy > 2.0 || w > 2.0 {
                        cx /= 640.0; cy /= 640.0; w /= 640.0; h /= 640.0
                    }
                    let rect = CGRect(x: (cx - w / 2) * width, y: (cy - h / 2) * height, width: w * width, height: h * height)
                    return (rect, bestConf)
                }
            } else if multiArray.dataType == .float32 {
                let ptr = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
                for a in 0..<anchors {
                    let conf = ptr[4 * cStride + a * aStride]
                    if conf > bestConf {
                        bestConf = conf
                        bestAnchor = a
                    }
                }
                if bestAnchor >= 0 {
                    var cx = CGFloat(ptr[0 * cStride + bestAnchor * aStride])
                    var cy = CGFloat(ptr[1 * cStride + bestAnchor * aStride])
                    var w  = CGFloat(ptr[2 * cStride + bestAnchor * aStride])
                    var h  = CGFloat(ptr[3 * cStride + bestAnchor * aStride])
                    if cx > 2.0 || cy > 2.0 || w > 2.0 {
                        cx /= 640.0; cy /= 640.0; w /= 640.0; h /= 640.0
                    }
                    let rect = CGRect(x: (cx - w / 2) * width, y: (cy - h / 2) * height, width: w * width, height: h * height)
                    return (rect, bestConf)
                }
            }
        }
        return nil
    }

    @discardableResult
    private func drawResults(pose: VNDetectHumanBodyPoseRequest, ballRequest: VNCoreMLRequest?) -> Int {
        drawingLayer.sublayers?.removeAll()
        let width = view.bounds.width
        let height = view.bounds.height
        var totalPoints = 0

        // 1. Отрисовка скелета
        if let results = pose.results?.first {
            var pointsDict: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

            // Берем точки с порогом уверенности 0.15 (вместо завышенного 0.3)
            for group in skeletonGroups {
                for pair in group.pairs {
                    for joint in [pair.0, pair.1] {
                        if pointsDict[joint] == nil,
                           let point = try? results.recognizedPoint(joint), point.confidence > 0.15 {
                            let screenPoint = CGPoint(x: point.location.x * width, y: (1 - point.location.y) * height)
                            pointsDict[joint] = screenPoint
                        }
                    }
                }
            }
            totalPoints = pointsDict.count

            // Отрисовываем линии костей (ВАЖНО: fillColor = clear!)
            for group in skeletonGroups {
                let groupPath = UIBezierPath()
                for (j1, j2) in group.pairs {
                    if let p1 = pointsDict[j1], let p2 = pointsDict[j2] {
                        groupPath.move(to: p1)
                        groupPath.addLine(to: p2)
                    }
                }
                let lineLayer = CAShapeLayer()
                lineLayer.path = groupPath.cgPath
                lineLayer.strokeColor = group.color.cgColor
                lineLayer.lineWidth = 4
                lineLayer.lineCap = .round
                lineLayer.fillColor = UIColor.clear.cgColor // <-- Убираем чёрную заливку!
                drawingLayer.addSublayer(lineLayer)
            }

            // Отрисовываем аккуратные белые кружки суставов
            let jointsPath = UIBezierPath()
            for (_, p) in pointsDict {
                let circle = UIBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                jointsPath.append(circle)
            }
            let jointsLayer = CAShapeLayer()
            jointsLayer.path = jointsPath.cgPath
            jointsLayer.fillColor = UIColor.white.cgColor
            drawingLayer.addSublayer(jointsLayer)
        }

        // 2. Отрисовка мяча
        if let (screenRect, conf) = extractBestBallBox(from: ballRequest?.results, width: width, height: height) {
            let boxLayer = CAShapeLayer()
            boxLayer.path = UIBezierPath(rect: screenRect).cgPath
            boxLayer.strokeColor = UIColor.blue.cgColor
            boxLayer.lineWidth = 4
            boxLayer.fillColor = UIColor.clear.cgColor
            drawingLayer.addSublayer(boxLayer)

            let textLayer = CATextLayer()
            textLayer.string = String(format: "Ball %.2f", conf)
            textLayer.font = UIFont.boldSystemFont(ofSize: 14)
            textLayer.fontSize = 14
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.backgroundColor = UIColor.blue.cgColor
            textLayer.alignmentMode = .center
            textLayer.cornerRadius = 4
            textLayer.masksToBounds = true
            textLayer.frame = CGRect(x: screenRect.minX, y: max(0, screenRect.minY - 24), width: 85, height: 20)
            textLayer.contentsScale = UIScreen.main.scale
            drawingLayer.addSublayer(textLayer)
        }

        return totalPoints
    }
}