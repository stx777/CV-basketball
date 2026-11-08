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
        
        // Кнопка поворота камеры (крайняя справа)
        switchCameraButton.frame = CGRect(x: view.bounds.width - btnSize - 16, y: topPadding, width: btnSize, height: btnSize)
        
        // Кнопка паузы (слева от кнопки поворота)
        pauseButton.frame = CGRect(x: switchCameraButton.frame.minX - btnSize - spacing, y: topPadding, width: btnSize, height: btnSize)
        
        // Плашка FPS (занимает оставшееся место слева)
        let labelWidth = pauseButton.frame.minX - 16 - 12
        fpsLabel.frame = CGRect(x: 16, y: topPadding, width: min(labelWidth, 190), height: btnSize)
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
        // Метка FPS
        fpsLabel.textColor = .green
        fpsLabel.font = .boldSystemFont(ofSize: 14)
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        fpsLabel.layer.cornerRadius = 10
        fpsLabel.clipsToBounds = true
        fpsLabel.textAlignment = .center
        view.addSubview(fpsLabel)

        // Кнопка Паузы
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.tintColor = .white
        pauseButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        pauseButton.layer.cornerRadius = 22
        pauseButton.clipsToBounds = true
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        view.addSubview(pauseButton)

        // Кнопка смены камеры
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
            lastTime = CFAbsoluteTimeGetCurrent() // Сброс таймера, чтобы не было скачка FPS
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

        captureSession.commitConfiguration()
    }

    private func setupModel() {
        if let model = try? basketball_best(configuration: MLModelConfiguration()).model {
            self.coreMLModel = try? VNCoreMLModel(for: model)
            self.modelStatus = "Ball: OK"
        } else if let modelURL = Bundle.main.url(forResource: "basketball_best", withExtension: "mlmodelc"),
                  let mlModel = try? MLModel(contentsOf: modelURL) {
            self.coreMLModel = try? VNCoreMLModel(for: mlModel)
            self.modelStatus = "Ball: OK"
        } else {
            self.modelStatus = "Ball: ERR"
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Если стоит пауза — игнорируем входящие кадры
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
            self.fpsLabel.text = String(format: "FPS: %.1f | %@", fps, self.modelStatus)
            self.drawResults(pose: poseRequest, ballRequest: ballRequest)
        }
    }

    private func drawResults(pose: VNDetectHumanBodyPoseRequest, ballRequest: VNCoreMLRequest?) {
        drawingLayer.sublayers?.removeAll()
        let width = view.bounds.width
        let height = view.bounds.height

        // 1. Отрисовка скелета
        if let results = pose.results?.first {
            var pointsDict: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

            for group in skeletonGroups {
                for pair in group.pairs {
                    for joint in [pair.0, pair.1] {
                        if pointsDict[joint] == nil,
                           let point = try? results.recognizedPoint(joint), point.confidence > 0.3 {
                            let screenPoint = CGPoint(x: point.location.x * width, y: (1 - point.location.y) * height)
                            pointsDict[joint] = screenPoint
                        }
                    }
                }
            }

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
                drawingLayer.addSublayer(lineLayer)
            }

            let jointsPath = UIBezierPath()
            for (_, p) in pointsDict {
                jointsPath.move(to: p)
                jointsPath.addArc(withCenter: p, radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            }
            let jointsLayer = CAShapeLayer()
            jointsLayer.path = jointsPath.cgPath
            jointsLayer.fillColor = UIColor.white.cgColor
            drawingLayer.addSublayer(jointsLayer)
        }

        // 2. Отрисовка мяча
        if let observations = ballRequest?.results as? [VNRecognizedObjectObservation] {
            for observation in observations where observation.confidence > 0.25 {
                let box = observation.boundingBox
                let screenRect = CGRect(
                    x: box.origin.x * width,
                    y: (1 - box.origin.y - box.height) * height,
                    width: box.width * width,
                    height: box.height * height
                )

                let boxLayer = CAShapeLayer()
                boxLayer.path = UIBezierPath(rect: screenRect).cgPath
                boxLayer.strokeColor = UIColor.blue.cgColor
                boxLayer.lineWidth = 4
                boxLayer.fillColor = UIColor.clear.cgColor
                drawingLayer.addSublayer(boxLayer)
            }
        }
    }
}