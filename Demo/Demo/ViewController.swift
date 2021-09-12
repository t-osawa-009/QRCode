import UIKit
import Vision
import AVFoundation
import Foundation

class ScanViewController: UIViewController {
    private var process: ProcessQRCode = defaultPrintJSON
    private static var defaultPrintJSON: ProcessQRCode = { data in
        guard let jsonString = String(data: data, encoding: .utf8) else { return }
        print(jsonString)
    }
    @IBOutlet private weak var videoPreviewView: VideoPreviewView!

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCameraLiveView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewView.updateVideoOrientationForDeviceOrientation()
    }
  
    private func checkCameraSettings(){
        if AVCaptureDevice.authorizationStatus(for: .video) !=  .authorized {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
                if !granted {
                    let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "BoardingAgent"
                    let cameraDisableAlert = UIAlertController(title: "Camera Disabled",
                                                                message: "Please enable Camera in \(bundleName) Settings.", preferredStyle: .alert)
                    
                    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (alert) in
                        cameraDisableAlert.dismiss(animated: true, completion: nil)
                    }
                    cameraDisableAlert.addAction(cancelAction)

                    func settingsAction(action: UIAlertAction) {
                        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
                        
                        if UIApplication.shared.canOpenURL(settingsUrl) { UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil) }
                        cameraDisableAlert.dismiss(animated: true)
                    }
                    
                    let goToSettingsAction = UIAlertAction(title: "Go to Settings", style: .default, handler: settingsAction)
                    cameraDisableAlert.addAction(goToSettingsAction)
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.present(cameraDisableAlert, animated: true, completion: nil)
                    }
                }
            })
        }
    }
    
    private func setupCameraLiveView() {
        // MARK: Ensure Camera Settings Allowed
        #if !targetEnvironment(simulator)
        checkCameraSettings()
        #endif
        
        // Set up the video device.
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                      mediaType: AVMediaType.video,
                                                                      position: .back)
        
        // MARK: Get Back Camera
        guard let backCamera = deviceDiscoverySession.devices.first(where: { $0.position == .back }) else { return }
        guard let session = videoPreviewView.session else {
            return
        }
        // Set up the input and output stream.
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: backCamera)
            session.addInput(captureDeviceInput)
        } catch {
            showAlert(withTitle: "Camera error", message: "Your camera can't be used as an input device.")
            return
        }
        
        let deviceOutput = AVCaptureVideoDataOutput()
        deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        
        // Set the quality of the video
        deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        
        // What we will display on the screen
        session.addOutput(deviceOutput)
        
        // MARK: Start Camera
        session.startRunning()
    }
    
    lazy var detectBarcodeRequest: VNDetectBarcodesRequest = {
        return VNDetectBarcodesRequest(completionHandler: { (request, error) in
            guard error == nil else { return }
            self.processClassification(for: request)
        })
    }()
    
    private func processClassification(for request: VNRequest) {
        DispatchQueue.main.async {
            if let bestResult = request.results?.first as? VNBarcodeObservation,
               let payload = bestResult.payloadStringValue {
                if bestResult.symbology == .QR {
                    guard let data = payload.data(using: .utf8) else { return }
                    self.process(data)
                    if let session = self.videoPreviewView.session, session.isRunning {
                        session.stopRunning()
                    }
                }
            }
        }
    }
    
    public func startCamera() {
        videoPreviewView.session?.startRunning()
    }
    
    private func showAlert(withTitle title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}

extension ScanViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var requestOptions: [VNImageOption : Any] = [:]
        
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics : camData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: requestOptions)
        try? imageRequestHandler.perform([self.detectBarcodeRequest])
    }
}

public typealias ProcessQRCode = (_ data: Data) -> ()

// MARK: UIDeviceOrientation and AVCaptureVideoOrientation Equivalent
extension UIDeviceOrientation {
    var forVideoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .faceUp, .portrait:
            return .portrait
        case .faceDown, .portraitUpsideDown:
            return .portraitUpsideDown
        case .unknown:
            return .portrait
        @unknown default:
            return .portrait
        }
    }
}
