import AVFoundation
import CoreLocation
import Foundation
import SwiftUI
import UIKit

struct EmergencyContact: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var relationship = ""
    var phone = ""
}

struct EmergencyProfile: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    var contacts: [EmergencyContact] = []
    var bloodType = ""
    var allergies = ""
    var conditions = ""
    var medications = ""
    var notes = ""
}

@MainActor
final class EmergencyProfileStore: ObservableObject {
    @Published var profile: EmergencyProfile
    @Published private(set) var errorMessage: String?

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRoot
        fileURL = root.appendingPathComponent("emergency-profile.json")
        profile = (try? Self.load(from: fileURL)) ?? EmergencyProfile()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(profile)
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtection]
            )
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            errorMessage = nil
        } catch {
            errorMessage = "Emergency information could not be saved."
        }
    }

    private static func load(from url: URL) throws -> EmergencyProfile {
        let profile = try JSONDecoder().decode(
            EmergencyProfile.self,
            from: Data(contentsOf: url)
        )
        guard profile.schemaVersion == EmergencyProfile.schemaVersion else {
            throw CocoaError(.coderReadCorrupt)
        }
        return profile
    }

    private static var defaultRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Aurora", isDirectory: true)
    }
}

struct TripChecklistItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var category: String
    var isComplete = false
    var isCustom = false
}

private struct TripChecklistDocument: Codable {
    static let schemaVersion = 1
    var schemaVersion = Self.schemaVersion
    var items: [TripChecklistItem]
}

@MainActor
final class TripChecklistStore: ObservableObject {
    @Published private(set) var items: [TripChecklistItem]
    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? EmergencyProfileStore.defaultToolsRoot
        fileURL = root.appendingPathComponent("trip-checklist.json")
        items = Self.load(from: fileURL) ?? Self.defaults
    }

    var completedCount: Int { items.filter(\.isComplete).count }

    var categories: [String] {
        Array(Set(items.map(\.category))).sorted()
    }

    func toggle(_ item: TripChecklistItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isComplete.toggle()
        save()
    }

    func add(title: String, category: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(TripChecklistItem(
            title: cleanTitle,
            category: cleanCategory.isEmpty ? "Custom" : cleanCategory,
            isCustom: true
        ))
        save()
    }

    func update(_ item: TripChecklistItem, title: String, category: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        items[index].title = cleanTitle
        items[index].category = category.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? "Custom" : category
        save()
    }

    func delete(_ item: TripChecklistItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func reset() {
        items = Self.defaults
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let document = TripChecklistDocument(items: items)
            try JSONEncoder().encode(document).write(to: fileURL, options: .atomic)
        } catch {
            // The in-memory checklist remains usable and can be saved next edit.
        }
    }

    private static func load(from url: URL) -> [TripChecklistItem]? {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(
                TripChecklistDocument.self,
                from: data
              ),
              document.schemaVersion == TripChecklistDocument.schemaVersion
        else { return nil }
        return document.items
    }

    private static let defaults = [
        TripChecklistItem(title: "Share route and return time", category: "Plan"),
        TripChecklistItem(title: "Check weather and trail conditions", category: "Plan"),
        TripChecklistItem(title: "Download the offline map region", category: "Navigation"),
        TripChecklistItem(title: "Pack map, compass, and backup power", category: "Navigation"),
        TripChecklistItem(title: "Carry water and a treatment method", category: "Essentials"),
        TripChecklistItem(title: "Pack food, layers, and shelter", category: "Essentials"),
        TripChecklistItem(title: "Carry a first-aid kit and medications", category: "Safety"),
        TripChecklistItem(title: "Review emergency contacts and Medical ID", category: "Safety"),
    ]
}

extension EmergencyProfileStore {
    static var defaultToolsRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Aurora", isDirectory: true)
    }
}

@MainActor
final class SurvivalToolsLocationModel: ObservableObject {
    @Published private(set) var latestFix: LocationFix?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let service: SurvivalLocationService
    private var updateTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    init(service: SurvivalLocationService? = nil) {
        let resolvedService = service ?? SurvivalLocationService()
        self.service = resolvedService
        authorizationStatus = resolvedService.authorizationStatus
    }

    func start() {
        updateTask?.cancel()
        authorizationTask?.cancel()

        let fixes = service.updates()
        let authorizations = service.authorizationUpdates()
        updateTask = Task { [weak self] in
            guard let self else { return }
            for await fix in fixes {
                guard !Task.isCancelled else { return }
                latestFix = fix
            }
        }
        authorizationTask = Task { [weak self] in
            guard let self else { return }
            for await status in authorizations {
                guard !Task.isCancelled else { return }
                authorizationStatus = status
            }
        }

        authorizationStatus = service.authorizationStatus
        if authorizationStatus == .notDetermined {
            service.requestWhenInUseAuthorization()
        }
        service.startDisplayUpdates()
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        authorizationTask?.cancel()
        authorizationTask = nil
        service.stopDisplayUpdates()
    }
}

@MainActor
final class SOSFlashlightController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    private var signalTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        signalTask?.cancel()
    }

    func start() {
        guard !isRunning else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            errorMessage = "This device does not have an available rear torch."
            return
        }
        errorMessage = nil
        isRunning = true
        signalTask = Task { [weak self] in
            guard let self else { return }
            let dot: UInt64 = 200_000_000
            let dash: UInt64 = 600_000_000
            while !Task.isCancelled {
                for letter in [[dot, dot, dot], [dash, dash, dash], [dot, dot, dot]] {
                    for duration in letter {
                        guard !Task.isCancelled else { break }
                        setTorch(device, enabled: true)
                        try? await Task.sleep(nanoseconds: duration)
                        setTorch(device, enabled: false)
                        try? await Task.sleep(nanoseconds: dot)
                    }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            setTorch(device, enabled: false)
        }
    }

    func stop() {
        signalTask?.cancel()
        signalTask = nil
        if let device = AVCaptureDevice.default(for: .video) {
            setTorch(device, enabled: false)
        }
        isRunning = false
    }

    private func setTorch(_ device: AVCaptureDevice, enabled: Bool) {
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            errorMessage = "The torch could not be controlled."
            signalTask?.cancel()
            isRunning = false
        }
    }
}
