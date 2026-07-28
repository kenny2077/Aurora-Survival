import Foundation
import ImageIO
@preconcurrency import Vision

struct VisionTextExtractor: Sendable {
    func extractText(from data: Data) async -> [String] {
        await withCheckedContinuation { continuation in
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                continuation.resume(returning: [])
                return
            }

            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    ?? []
                continuation.resume(returning: Array(lines.prefix(30)))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: image)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
