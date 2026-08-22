import Foundation

public enum TrailRecordingError: Error, Equatable {
    case alreadyActive
    case noActiveTrail
    case notRecording
}

public actor TrailRecordingEngine: TrailRecording {
    private let repository: any TrailRepository
    private let samplingPolicy: TrackSamplingPolicy
    private let batchSize: Int
    private var trail: Trail?
    private var committedPoints: [TrackPoint] = []
    private var pendingPoints: [TrackPoint] = []
    private var storedCheckpoints: [TrailCheckpoint] = []
    private var lastLoopAlertAt: Date?
    private var loaded = false

    public init(
        repository: any TrailRepository,
        samplingPolicy: TrackSamplingPolicy = TrackSamplingPolicy(),
        batchSize: Int = 20
    ) {
        self.repository = repository
        self.samplingPolicy = samplingPolicy
        self.batchSize = max(1, batchSize)
    }

    public func start(name: String, at date: Date = Date()) async throws {
        try await loadIfNeeded()
        guard trail == nil || trail?.state == .idle else {
            throw TrailRecordingError.alreadyActive
        }
        let created = Trail(
            name: name,
            startedAt: date,
            state: .recording,
            lastResumedAt: date
        )
        try await repository.save(trail: created)
        trail = created
        committedPoints = []
        pendingPoints = []
        storedCheckpoints = []
        lastLoopAlertAt = nil
    }

    public func pause(at date: Date = Date()) async throws {
        try await loadIfNeeded()
        guard var active = trail else { throw TrailRecordingError.noActiveTrail }
        guard active.state == .recording else { throw TrailRecordingError.notRecording }
        if let resumed = active.lastResumedAt {
            active.accumulatedActiveSeconds += max(0, date.timeIntervalSince(resumed))
        }
        active.lastResumedAt = nil
        active.state = .paused
        try await flush()
        try await repository.save(trail: active)
        trail = active
    }

    public func resume(at date: Date = Date()) async throws {
        try await loadIfNeeded()
        guard var active = trail else { throw TrailRecordingError.noActiveTrail }
        guard active.state == .paused else { throw TrailRecordingError.notRecording }
        active.state = .recording
        active.lastResumedAt = date
        try await repository.save(trail: active)
        trail = active
    }

    public func finish(at date: Date = Date()) async throws {
        try await loadIfNeeded()
        guard var active = trail else { throw TrailRecordingError.noActiveTrail }
        if active.state == .recording, let resumed = active.lastResumedAt {
            active.accumulatedActiveSeconds += max(0, date.timeIntervalSince(resumed))
        }
        active.lastResumedAt = nil
        active.endedAt = date
        active.state = .idle
        try await flush()
        try await repository.save(trail: active)
        trail = active
    }

    public func ingest(_ fix: LocationFix) async throws -> TrailRecordingSnapshot {
        try await loadIfNeeded()
        guard let active = trail else { throw TrailRecordingError.noActiveTrail }
        guard active.state == .recording else { return makeSnapshot(at: fix.timestamp) }
        let allPoints = committedPoints + pendingPoints
        guard samplingPolicy.accepts(fix, after: allPoints.last?.fix) else {
            return makeSnapshot(at: fix.timestamp)
        }
        let point = TrackPoint(
            trailID: active.id,
            sequence: allPoints.count,
            fix: fix
        )
        pendingPoints.append(point)
        if pendingPoints.count >= batchSize { try await flush() }
        let distance = totalDistance(points: committedPoints + pendingPoints)
        if shouldCreateCheckpoint(at: fix.timestamp, distance: distance) {
            let checkpoint = TrailCheckpoint(
                trailID: active.id,
                coordinate: fix.coordinate,
                createdAt: fix.timestamp,
                distanceMeters: distance
            )
            try await repository.save(checkpoint: checkpoint)
            storedCheckpoints.append(checkpoint)
        }
        let possibleLoop = detectLoop(at: fix)
        if possibleLoop { lastLoopAlertAt = fix.timestamp }
        return makeSnapshot(at: fix.timestamp, possibleLoop: possibleLoop)
    }

    public func snapshot(at date: Date = Date()) async throws -> TrailRecordingSnapshot {
        try await loadIfNeeded()
        return makeSnapshot(at: date)
    }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }
        loaded = true
        trail = try await repository.activeTrail()
        if let trail {
            committedPoints = try await repository.points(trailID: trail.id)
            storedCheckpoints = try await repository.checkpoints(trailID: trail.id)
        }
    }

    private func flush() async throws {
        guard !pendingPoints.isEmpty else { return }
        try await repository.append(points: pendingPoints)
        committedPoints.append(contentsOf: pendingPoints)
        pendingPoints.removeAll(keepingCapacity: true)
    }

    private func shouldCreateCheckpoint(at date: Date, distance: Double) -> Bool {
        guard let trail else { return false }
        let previousDate = storedCheckpoints.last?.createdAt ?? trail.startedAt
        let previousDistance = storedCheckpoints.last?.distanceMeters ?? 0
        return date.timeIntervalSince(previousDate) >= 15 * 60
            || distance - previousDistance >= 1_000
    }

    private func detectLoop(at fix: LocationFix) -> Bool {
        if let lastLoopAlertAt,
           fix.timestamp.timeIntervalSince(lastLoopAlertAt) < 20 * 60 {
            return false
        }
        guard let first = (committedPoints + pendingPoints).first,
              TrackSamplingPolicy.distance(
                from: first.fix.coordinate,
                to: fix.coordinate
              ) > 100
        else { return false }
        return storedCheckpoints.dropLast().contains { checkpoint in
            fix.timestamp.timeIntervalSince(checkpoint.createdAt) >= 10 * 60
                && TrackSamplingPolicy.distance(
                    from: checkpoint.coordinate,
                    to: fix.coordinate
                ) <= 50
        }
    }

    private func makeSnapshot(
        at date: Date,
        possibleLoop: Bool = false
    ) -> TrailRecordingSnapshot {
        let points = committedPoints + pendingPoints
        return TrailRecordingSnapshot(
            trail: trail,
            points: points,
            checkpoints: storedCheckpoints,
            summary: summary(points: points, at: date),
            possibleLoop: possibleLoop
        )
    }

    private func summary(points: [TrackPoint], at date: Date) -> TrailSummary {
        let distance = totalDistance(points: points)
        let elapsed: TimeInterval
        if let trail {
            elapsed = trail.accumulatedActiveSeconds
                + (trail.state == .recording
                    ? max(0, date.timeIntervalSince(trail.lastResumedAt ?? date))
                    : 0)
        } else {
            elapsed = 0
        }
        var elevationGain = 0.0
        for pair in zip(points, points.dropFirst()) {
            let gain = pair.1.fix.altitude - pair.0.fix.altitude
            if gain > 0 { elevationGain += gain }
        }
        return TrailSummary(
            elapsedSeconds: elapsed,
            distanceMeters: distance,
            currentSpeedMetersPerSecond: max(0, points.last?.fix.speed ?? 0),
            averageSpeedMetersPerSecond: elapsed > 0 ? distance / elapsed : 0,
            elevationGainMeters: elevationGain,
            latestAccuracyMeters: points.last?.fix.horizontalAccuracy
        )
    }

    private func totalDistance(points: [TrackPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            result + TrackSamplingPolicy.distance(
                from: pair.0.fix.coordinate,
                to: pair.1.fix.coordinate
            )
        }
    }
}
