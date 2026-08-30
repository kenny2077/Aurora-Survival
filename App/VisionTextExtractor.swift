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
            let completion = VisionTextCompletion(continuation)

            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    ?? []
                completion.resume(returning: Array(lines.prefix(30)))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: image)
                do {
                    try handler.perform([request])
                } catch {
                    completion.resume(returning: [])
                }
            }
        }
    }
}

private final class VisionTextCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<[String], Never>

    init(_ continuation: CheckedContinuation<[String], Never>) {
        self.continuation = continuation
    }

    func resume(returning lines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: lines)
    }
}
