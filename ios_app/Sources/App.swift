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
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let drawingLayer = CAShapeLayer()
    private let fpsLabel = UILabel()
    
    private var lastTime = CFAbsoluteTimeGetCurrent()
    private var coreMLModel: VNCoreMLModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        setupModel()
    }

    private func setupCamera() {
        captureSession.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        drawingLayer.frame = view.bounds
        view.layer.addSublayer(drawingLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func setupUI() {
        fpsLabel.frame = CGRect(x: 20, y: 50, width: 250, height: 40)
        fpsLabel.textColor = .green
        fpsLabel.font = .boldSystemFont(ofSize: 18)
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        fpsLabel.layer.cornerRadius = 8
        fpsLabel.clipsToBounds = true
        fpsLabel.textAlignment = .center
        view.addSubview(fpsLabel)
    }

    private func setupModel() {
        if let compiledModel = try? basketball_best(configuration: MLModelConfiguration()) {
            coreMLModel = try? VNCoreMLModel(for: compiledModel.model)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentTime = CFAbsoluteTimeGetCurrent()
        let fps = 1.0 / (currentTime - lastTime)
        lastTime = currentTime

        var requests: [VNRequest] = []

        let poseRequest = VNDetectHumanBodyPoseRequest()
        requests.append(poseRequest)

        if let model = coreMLModel {
            let ballRequest = VNCoreMLRequest(model: model)
            ballRequest.imageCropAndScaleOption = .scaleFill
            requests.append(ballRequest)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform(requests)

        DispatchQueue.main.async {
            self.fpsLabel.text = String(format: "FPS: %.1f", fps)
            self.drawResults(pose: poseRequest, ballRequests: requests)
        }
    }

    private func drawResults(pose: VNDetectHumanBodyPoseRequest, ballRequests: [VNRequest]) {
        drawingLayer.sublayers?.removeAll()
        let path = UIBezierPath()

        if let results = pose.results?.first,
           let recognizedPoints = try? results.recognizedPoints(.all) {
            for (_, point) in recognizedPoints where point.confidence > 0.3 {
                let x = (1.0 - point.location.y) * view.bounds.width
                let y = (1.0 - point.location.x) * view.bounds.height
                path.move(to: CGPoint(x: x, y: y))
                path.addArc(withCenter: CGPoint(x: x, y: y), radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            }
        }

        let skeletonLayer = CAShapeLayer()
        skeletonLayer.path = path.cgPath
        skeletonLayer.fillColor = UIColor.yellow.cgColor
        drawingLayer.addSublayer(skeletonLayer)

        if let ballRequest = ballRequests.compactMap({ $0 as? VNCoreMLRequest }).first,
           let observations = ballRequest.results as? [VNRecognizedObjectObservation] {
            for observation in observations where observation.confidence > 0.3 {
                let bounds = observation.boundingBox
                let rect = CGRect(
                    x: (1.0 - bounds.maxY) * view.bounds.width,
                    y: (1.0 - bounds.maxX) * view.bounds.height,
                    width: bounds.height * view.bounds.width,
                    height: bounds.width * view.bounds.height
                )
                let boxLayer = CAShapeLayer()
                boxLayer.path = UIBezierPath(rect: rect).cgPath
                boxLayer.strokeColor = UIColor.blue.cgColor
                boxLayer.lineWidth = 3
                boxLayer.fillColor = UIColor.clear.cgColor
                drawingLayer.addSublayer(boxLayer)
            }
        }
    }
}