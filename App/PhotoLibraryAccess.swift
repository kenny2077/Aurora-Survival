import Foundation
import AVFoundation
import Photos
import UIKit

enum PhotoLibraryAccessStatus: String, Equatable {
    case notDetermined
    case limited
    case authorized
    case denied
    case restricted

    var permitsSelection: Bool {
        self == .limited || self == .authorized
    }

    var displayName: String {
        switch self {
        case .notDetermined: return "Not requested"
        case .limited: return "Limited access"
        case .authorized: return "Full access"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        }
    }
}

@MainActor
protocol PhotoLibraryAuthorizing {
    func currentStatus() -> PhotoLibraryAccessStatus
    func requestReadWriteAccess() async -> PhotoLibraryAccessStatus
    func presentLimitedLibraryPicker()
    func openSettings()
}

@MainActor
struct SystemPhotoLibraryAuthorization: PhotoLibraryAuthorizing {
    func currentStatus() -> PhotoLibraryAccessStatus {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestReadWriteAccess() async -> PhotoLibraryAccessStatus {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func presentLimitedLibraryPicker() {
        guard let viewController = Self.activeViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private static func map(
        _ status: PHAuthorizationStatus
    ) -> PhotoLibraryAccessStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .limited: return .limited
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    private static func activeViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

enum CameraAuthorizationStatus: String, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var permitsCapture: Bool { self == .authorized }
}

@MainActor
protocol CameraAuthorizing {
    func currentStatus() -> CameraAuthorizationStatus
    func isCameraAvailable() -> Bool
    func requestAccess() async -> CameraAuthorizationStatus
}

@MainActor
struct SystemCameraAuthorization: CameraAuthorizing {
    func currentStatus() -> CameraAuthorizationStatus {
        Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func isCameraAvailable() -> Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func requestAccess() async -> CameraAuthorizationStatus {
        guard isCameraAvailable() else { return .restricted }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return currentStatus()
    }

    private static func map(
        _ status: AVAuthorizationStatus
    ) -> CameraAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }
}

@MainActor
protocol CapturedPhotoSaving {
    func savePhoto(data: Data) async throws
}

enum CapturedPhotoSaveError: LocalizedError {
    case invalidImage
    case debugForcedFailure

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The captured photo could not be saved."
        case .debugForcedFailure:
            return "The Debug save-failure fixture rejected the captured photo."
        }
    }
}

@MainActor
struct SystemCapturedPhotoSaver: CapturedPhotoSaving {
    func savePhoto(data: Data) async throws {
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "AURORA_UI_FORCE_CAPTURE_SAVE_FAILURE"
        ] == "1" {
            throw CapturedPhotoSaveError.debugForcedFailure
        }
#endif
        guard UIImage(data: data) != nil else {
            throw CapturedPhotoSaveError.invalidImage
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}

enum AttachmentOperationState: Equatable {
    case idle
    case loading(String)
    case failed(message: String, offersSettings: Bool)
}

enum DraftAttachmentLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

enum DraftAttachmentOCRState: Equatable {
    case pending
    case complete([String])
    case failed(String)

    var observations: [String] {
        if case let .complete(lines) = self { return lines }
        return []
    }
}

struct DraftImageAttachment: Equatable {
    let id: UUID
    let imageData: Data?
    let thumbnailData: Data?
    let loadState: DraftAttachmentLoadState
    let ocrState: DraftAttachmentOCRState

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        loadState: DraftAttachmentLoadState,
        ocrState: DraftAttachmentOCRState = .pending
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.loadState = loadState
        self.ocrState = ocrState
    }
}
