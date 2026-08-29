import Foundation

final class BackgroundURLSessionPackageTransport: NSObject,
    BackgroundFilePackageTransport,
    URLSessionDownloadDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable {

    private final class Operation {
        let destination: URL
        let expectedByteCount: Int64
        let initialByteCount: Int64
        let progress: @Sendable (Int64) async -> Void
        var continuation: CheckedContinuation<Void, Error>?
        var finished = false

        init(
            destination: URL,
            expectedByteCount: Int64,
            initialByteCount: Int64,
            progress: @escaping @Sendable (Int64) async -> Void,
            continuation: CheckedContinuation<Void, Error>
        ) {
            self.destination = destination
            self.expectedByteCount = expectedByteCount
            self.initialByteCount = initialByteCount
            self.progress = progress
            self.continuation = continuation
        }
    }

    private let identifier: String
    private let allowsCellularAccess: Bool
    private let lock = NSLock()
    private var operations: [Int: Operation] = [:]
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
        var request = URLRequest(url: url)
        request.setValue(
            "bytes=\(byteRange.lowerBound)-\(byteRange.upperBound - 1)",
            forHTTPHeaderField: "Range"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206 else {
            throw PackageDownloadError.invalidRangeResponse
        }
        return data
    }

    func downloadArtifact(
        from url: URL,
        to destination: URL,
        expectedByteCount: Int64,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        if Self.fileSize(destination) == expectedByteCount {
            await progress(expectedByteCount)
            return
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let resumeURL = Self.resumeURL(for: destination)
        let progressURL = Self.progressURL(for: destination)
        let resumeData = try? Data(contentsOf: resumeURL)
        let initialByteCount = Self.persistedProgress(at: progressURL)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task: URLSessionDownloadTask
                if let resumeData, !resumeData.isEmpty {
                    task = backgroundSession.downloadTask(withResumeData: resumeData)
                } else {
                    var request = URLRequest(url: url)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    task = backgroundSession.downloadTask(with: request)
                }
                task.taskDescription = destination.path
                let operation = Operation(
                    destination: destination,
                    expectedByteCount: expectedByteCount,
                    initialByteCount: initialByteCount,
                    progress: progress,
                    continuation: continuation
                )
                withLock { operations[task.taskIdentifier] = operation }
                task.resume()
            }
        } onCancel: {
            self.pauseTransfer(to: destination)
        }
    }

    func recoverOrphanedTasks() async {
        let tasks = await allBackgroundTasks()
        for task in tasks {
            guard let download = task as? URLSessionDownloadTask,
                  let path = task.taskDescription,
                  !path.isEmpty else {
                task.cancel()
                continue
            }
            let destination = URL(fileURLWithPath: path)
            download.cancel(byProducingResumeData: { resumeData in
                guard let resumeData else { return }
                try? resumeData.write(
                    to: Self.resumeURL(for: destination),
                    options: [.atomic]
                )
                Self.persist(
                    task.countOfBytesReceived,
                    at: Self.progressURL(for: destination)
                )
            })
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let operation = withLock({ operations[downloadTask.taskIdentifier] })
        else { return }
        let received = min(
            operation.expectedByteCount,
            operation.initialByteCount + totalBytesWritten
        )
        Self.persist(received, at: Self.progressURL(for: operation.destination))
        Task { await operation.progress(received) }
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        Self.lifecycleLock.lock()
        let completion = Self.completionHandlers.removeValue(forKey: identifier)
        Self.lifecycleLock.unlock()
        DispatchQueue.main.async { completion?() }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let operation = withLock({ operations[downloadTask.taskIdentifier] })
        else { return }
        do {
            if FileManager.default.fileExists(atPath: operation.destination.path) {
                try FileManager.default.removeItem(at: operation.destination)
            }
            try FileManager.default.moveItem(at: location, to: operation.destination)
            try? FileManager.default.removeItem(at: Self.resumeURL(for: operation.destination))
            try? FileManager.default.removeItem(at: Self.progressURL(for: operation.destination))
            operation.finished = true
            let continuation = operation.continuation
            operation.continuation = nil
            Task { await operation.progress(operation.expectedByteCount) }
            continuation?.resume()
        } catch {
            operation.finished = true
            let continuation = operation.continuation
            operation.continuation = nil
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let operation = withLock({ operations.removeValue(forKey: task.taskIdentifier) }),
              !operation.finished else { return }
        let nsError = error as NSError?
        if let resumeData = nsError?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? resumeData.write(
                to: Self.resumeURL(for: operation.destination),
                options: [.atomic]
            )
            Self.persist(
                operation.initialByteCount + task.countOfBytesReceived,
                at: Self.progressURL(for: operation.destination)
            )
        }
        let continuation = operation.continuation
        operation.continuation = nil
        if nsError?.code == NSURLErrorCancelled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: error ?? URLError(.unknown))
        }
    }

    private func pauseTransfer(to destination: URL) {
        let target = withLock {
            operations.first { $0.value.destination == destination }
        }
        guard let (taskIdentifier, operation) = target else { return }
        backgroundSession.getAllTasks { tasks in
            guard let task = tasks.first(where: {
                $0.taskIdentifier == taskIdentifier
            }) as? URLSessionDownloadTask else { return }
            task.cancel(byProducingResumeData: { resumeData in
                if let resumeData {
                    try? resumeData.write(
                        to: Self.resumeURL(for: operation.destination),
                        options: [.atomic]
                    )
                }
                Self.persist(
                    operation.initialByteCount + task.countOfBytesReceived,
                    at: Self.progressURL(for: operation.destination)
                )
            })
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

    private static func fileSize(_ url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return nil }
        return Int64(value)
    }

    private static func resumeURL(for destination: URL) -> URL {
        destination.appendingPathExtension("resume-data")
    }

    private static func progressURL(for destination: URL) -> URL {
        destination.appendingPathExtension("resume-progress")
    }

    private static func persistedProgress(at url: URL) -> Int64 {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let value = Int64(text) else { return 0 }
        return value
    }

    private static func persist(_ value: Int64, at url: URL) {
        try? Data(String(value).utf8).write(to: url, options: [.atomic])
    }
}
