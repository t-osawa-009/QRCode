#if os(iOS) || os(tvOS)
import UIKit
import Vision

extension UIImage {
    static func makeQRCode(text: String) -> UIImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let QR = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": data]) else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let ciImage = QR.outputImage?.transformed(by: transform) else { return nil }
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func performQRCodeDetection() -> [String] {
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            return []
        }
        guard let ciImage = CIImage(image:self) else {
            return []
        }
        var qrCodeLinks = [String]()
        let features=detector.features(in: ciImage)
        for feature in features as? [CIQRCodeFeature] ?? [] {
            if let messageString = feature.messageString {
                qrCodeLinks.append(messageString)
            }
        }
        
        return qrCodeLinks
    }
    
    func performScanQRCode() {
        guard let cgImage = self.cgImage else { return }
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: { request, error in
            let results = request.results?.compactMap({ $0 as? VNBarcodeObservation }) ?? []
            results.forEach { barcode in
                if let payload = barcode.payloadStringValue {
                    print("Payload: \(payload)")
                }
                
                // Print barcode-values
                print("Symbology: \(barcode.symbology.rawValue)")
                
                if let desc = barcode.barcodeDescriptor as? CIQRCodeDescriptor {
                    let content = String(data: desc.errorCorrectedPayload, encoding: .utf8)
                    
                    // FIXME: This currently returns nil. I did not find any docs on how to encode the data properly so far.
                    print("Payload: \(String(describing: content))")
                    print("Error-Correction-Level: \(desc.errorCorrectionLevel)")
                    print("Symbol-Version: \(desc.symbolVersion)")
                }
            }
        })
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [.properties : ""])
        guard let _ = try? handler.perform([barcodeRequest]) else {
            return
        }
    }
}
#endif
