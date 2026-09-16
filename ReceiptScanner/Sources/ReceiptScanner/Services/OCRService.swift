import UIKit
import Vision
import CoreImage

enum OCRServiceError: LocalizedError {
    case noImageData
    case noTextFound
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noImageData: return "Could not get image data"
        case .noTextFound: return "No text could be recognized in this image"
        case .recognitionFailed(let error): return "OCR failed: \(error.localizedDescription)"
        }
    }
}

actor OCRService {
    /// Recognizes text from a UIImage using Apple Vision framework.
    /// Returns the raw text string, sorted top-to-bottom by line position.
    func recognizeText(from image: UIImage) async throws -> String {
        // Preprocess: enhance contrast, convert to grayscale for better OCR
        let processed = Self.preprocessForOCR(image)

        guard let cgImage = processed.cgImage else {
            throw OCRServiceError.noImageData
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRServiceError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: OCRServiceError.noTextFound)
                    return
                }

                // Sort by Y coordinate (top to bottom), then by X (left to right)
                let sorted = observations.sorted { a, b in
                    let aY = a.boundingBox.origin.y
                    let bY = b.boundingBox.origin.y
                    // Group rows within ~5% height tolerance
                    if abs(aY - bY) < 0.05 {
                        return a.boundingBox.origin.x < b.boundingBox.origin.x
                    }
                    return aY > bY // Vision uses bottom-left origin
                }

                let text = sorted.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            // Use accurate recognition for receipt text
            request.recognitionLevel = .accurate

            // Language correction helps with Romanian diacritics
            request.usesLanguageCorrection = true

            // Romanian first, English as fallback
            request.recognitionLanguages = ["ro-RO", "en-US"]

            // Known Romanian receipt keywords — helps Vision prioritize them
            request.customWords = [
                "BON", "FISCAL", "TOTAL", "LEI", "RON", "BANCA", "CARD",
                "CANTITATEA", "CANTITATE", "DENUMIREA", "DENUMIRE",
                "PRET", "PRETUL", "TVA", "CUI", "CASA", "DE PLATA",
                "SUBTOTAL", "REST", "NUMAR", "NUMAR", "BUC", "BUCATI",
                "AMB", "AMBALAJ", "PRODUSE", "CURS", "VALOAREA",
                "MONEDA", "CEC", "NR", "CANT", "UM", "RON", "LEI"
            ]

            // Ignore tiny fragments (noise/bleed from thermal paper)
            request.minimumTextHeight = 0.1

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRServiceError.recognitionFailed(error))
            }
        }
    }

    // MARK: - Image Preprocessing

    /// Enhances receipt images for better OCR: grayscale, boosted contrast, noise reduction.
    /// Thermal paper receipts are often low-contrast and faded — this step is critical.
    static func preprocessForOCR(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let context = CIContext(options: [
            .highQualityDownsample: true,
            .workingColorSpace: NSNull()
        ])

        // 1. Grayscale + boost contrast
        let colorControls = CIFilter(name: "CIColorControls")!
        colorControls.setValue(ciImage, forKey: kCIInputImageKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)     // grayscale
        colorControls.setValue(0.10, forKey: kCIInputBrightnessKey)     // slight brighten
        colorControls.setValue(2.5, forKey: kCIInputContrastKey)        // high contrast

        // 2. Apply exposure adjustment for faded thermal paper
        let exposure = CIFilter(name: "CIExposureAdjust")!
        exposure.setValue(colorControls.outputImage, forKey: kCIInputImageKey)
        exposure.setValue(0.3, forKey: kCIInputEVKey)

        // 3. Unsharp mask to sharpen text edges
        let sharpen = CIFilter(name: "CIUnsharpMask")!
        sharpen.setValue(exposure.outputImage, forKey: kCIInputImageKey)
        sharpen.setValue(0.8, forKey: kCIInputRadiusKey)
        sharpen.setValue(1.5, forKey: kCIInputIntensityKey)

        guard let output = sharpen.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage)
    }

    /// Scale image to a sensible size for OCR.
    /// Upscales very small images so Vision has enough resolution.
    static func prepareImage(_ image: UIImage, maxDimension: CGFloat = 1800) -> UIImage? {
        let originalWidth = image.size.width * image.scale
        let originalHeight = image.size.height * image.scale

        // If image is very small (e.g. 474px wide), upscale it
        // Vision's accurate mode works best with text at ~20+ px height
        if originalWidth < 800 || originalHeight < 600 {
            let scale = max(maxDimension / originalWidth, maxDimension / originalHeight, 2.0)
            let newSize = CGSize(
                width: originalWidth * scale / image.scale,
                height: originalHeight * scale / image.scale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        // Normal case: downsize to max dimension
        let scale = min(maxDimension / originalWidth, maxDimension / originalHeight, 1.0)
        let newSize = CGSize(
            width: originalWidth * scale / image.scale,
            height: originalHeight * scale / image.scale
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Save receipt image to app's Documents directory, return the relative path.
    @discardableResult
    static func saveImage(_ image: UIImage, receiptID: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let receiptDir = documentsDir.appendingPathComponent("receipt_images", isDirectory: true)

        try? FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)

        let fileURL = receiptDir.appendingPathComponent("\(receiptID.uuidString).jpg")
        try? data.write(to: fileURL)
        return fileURL.path
    }

    /// Load a saved receipt image from its path.
    static func loadImage(from path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    /// Delete a saved receipt image.
    static func deleteImage(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
