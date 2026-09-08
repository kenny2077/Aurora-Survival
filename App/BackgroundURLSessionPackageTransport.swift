import Foundation

final class BackgroundURLSessionPackageTransport: NSObject,
    ValidatedRangePackageTransport,
    URLSessionDownloadDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable {

    private final class RangeOperation {
        let requestedRange: Range<Int64>
        var downloadedData: Data?
        var downloadError: Error?
        var continuation: CheckedContinuation<PackageRangeResponse, Error>?

        init(
            requestedRange: Range<Int64>,
            continuation: CheckedContinuation<PackageRangeResponse, Error>
        ) {
            self.requestedRange = requestedRange
            self.continuation = continuation
        }
    }

    private let identifier: String
    private let allowsCellularAccess: Bool
    private let lock = NSLock()
    private var operations: [Int: RangeOperation] = [:]
    private static let lifecycleLock = NSLock()
    private static var completionHandlers: [String: () -> Void] = [:]

    static func handleEvents(
        for identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        lifecycleLock.lock()
        completionHandlers[identifier] = completionHandler
        lifecycleLock.unlock()
    }

    private lazy var backgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: identifier
        )
        configuration.allowsCellularAccess = allowsCellularAccess
        configuration.allowsExpensiveNetworkAccess = allowsCellularAccess
        configuration.allowsConstrainedNetworkAccess = true
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    init(identifier: String, allowsCellularAccess: Bool) {
        self.identifier = identifier
        self.allowsCellularAccess = allowsCellularAccess
        super.init()
        _ = backgroundSession
    }

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validate(response)
        return data
    }

    func download(from url: URL, to destination: URL) async throws {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        try Self.validate(response)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    func data(from url: URL, byteRange: Range<Int64>) async throws -> Data {
        try await range(from: url, byteRange: byteRange).data
    }

    func range(
        from url: URL,
        byteRange: Range<Int64>
    ) async throws -> PackageRangeResponse {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "bytes=\(byteRange.lowerBound)-\(byteRange.upperBound - 1)",
            forHTTPHeaderField: "Range"
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = backgroundSession.downloadTask(with: request)
                task.taskDescription = "range:\(byteRange.lowerBound):\(byteRange.upperBound)"
                withLock {
                    operations[task.taskIdentifier] = RangeOperation(
                        requestedRange: byteRange,
                        continuation: continuation
                    )
                }
                task.resume()
            }
        } onCancel: {
            self.cancel(range: byteRange)
        }
    }

    /// Orphaned tasks contain at most one uncommitted chunk. Wait for their
    /// cancellation before the coordinator resumes from the durable partial.
    func recoverOrphanedTasks() async {
        let tasks = await allBackgroundTasks()
        for task in tasks { task.cancel() }
        guard !tasks.isEmpty else { return }
        while !(await allBackgroundTasks()).isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        withLock {
            do {
                operations[downloadTask.taskIdentifier]?.downloadedData = try Data(
                    contentsOf: location
                )
            } catch {
                operations[downloadTask.taskIdentifier]?.downloadError = error
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let operation = withLock({
            operations.removeValue(forKey: task.taskIdentifier)
        }) else { return }
        let continuation = operation.continuation
        operation.continuation = nil

        if let error {
            let nsError = error as NSError
            continuation?.resume(throwing:
                nsError.code == NSURLErrorCancelled ? CancellationError() : error
            )
            return
        }

        do {
            if let downloadError = operation.downloadError { throw downloadError }
            guard let response = task.response as? HTTPURLResponse,
                  response.url == task.originalRequest?.url,
                  let downloadedData = operation.downloadedData else {
                throw PackageDownloadError.invalidRangeResponse
            }
            let metadata = try PackageRangeResponse.validate(
                response: response,
                requestedRange: operation.requestedRange
            )
            continuation?.resume(returning: PackageRangeResponse(
                data: downloadedData,
                totalByteCount: metadata.totalByteCount,
                validator: metadata.validator
            ))
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        Self.lifecycleLock.lock()
        let completion = Self.completionHandlers.removeValue(forKey: identifier)
        Self.lifecycleLock.unlock()
        DispatchQueue.main.async { completion?() }
    }

    private func cancel(range: Range<Int64>) {
        backgroundSession.getAllTasks { tasks in
            tasks.first(where: { task in
                self.withLock {
                    self.operations[task.taskIdentifier]?.requestedRange == range
                }
            })?.cancel()
        }
    }

    private func allBackgroundTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            backgroundSession.getAllTasks { continuation.resume(returning: $0) }
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
