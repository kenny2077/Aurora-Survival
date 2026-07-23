import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class IntegrationPersistenceTests: XCTestCase {
    func testVerifiedEntitlementPersistsForOfflineLaunch() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("entitlements.json")
        let ledger = EntitlementLedger(fileURL: file)
        try await ledger.apply(
            entitlementEvent(
                id: "purchase-1",
                kind: .purchased
            )
        )

        let reopened = EntitlementLedger(fileURL: file)
        let snapshots = await reopened.snapshots()
        XCTAssertTrue(
            OfflineEntitlementResolver().canLaunch(
                productID: "trailguard.field",
                packageIsInstalled: true,
                cachedEntitlements: snapshots
            )
        )
    }

    func testRefundDeactivatesOfflineEntitlement() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EntitlementLedger(
            fileURL: root.appendingPathComponent("entitlements.json")
        )
        try await ledger.apply(
            entitlementEvent(id: "purchase-1", kind: .purchased)
        )
        try await ledger.apply(
            entitlementEvent(id: "refund-1", kind: .refunded)
        )
        let snapshots = await ledger.snapshots()
        XCTAssertFalse(
            OfflineEntitlementResolver().canLaunch(
                productID: "trailguard.field",
                packageIsInstalled: true,
                cachedEntitlements: snapshots
            )
        )
    }

    func testUnverifiedEntitlementNeverMutatesLedger() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EntitlementLedger(
            fileURL: root.appendingPathComponent("entitlements.json")
        )
        do {
            try await ledger.apply(
                VerifiedEntitlementEvent(
                    eventID: "unverified-1",
                    productID: "trailguard.field",
                    kind: .purchased,
                    verifiedAt: "2026-07-23T00:00:00Z",
                    verificationSucceeded: false
                )
            )
            XCTFail("Expected unverified event rejection")
        } catch {
            XCTAssertEqual(
                error as? EntitlementLedgerError,
                .unverifiedEvent
            )
        }
        let snapshots = await ledger.snapshots()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testFileBackedMapRuntimeOpensReadyPackWithoutNetwork() throws {
        let root = try makeMapDirectory(includeRouting: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = makeMapPack()
        let runtime = FileBackedOfflineMapRuntime(
            readiness: MapReadinessEvaluator {
                ISO8601DateFormatter().date(
                    from: "2026-07-23T00:00:00Z"
                )!
            }
        )
        let session = try runtime.open(
            pack: pack,
            packageDirectory: root,
            tripCoordinate: GeoCoordinate(latitude: 36, longitude: -118),
            requiredTier: .field,
            requiresOfflineRouting: true
        )
        XCTAssertEqual(session.packID, pack.id)
        XCTAssertTrue(session.supportsRouting)
    }

    func testFileBackedMapRuntimeFailsClosedWithoutRoutingGraph() throws {
        let root = try makeMapDirectory(includeRouting: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try FileBackedOfflineMapRuntime().open(
                pack: makeMapPack(),
                packageDirectory: root,
                tripCoordinate: nil,
                requiredTier: .field,
                requiresOfflineRouting: true
            )
        ) { error in
            guard let runtimeError = error as? OfflineMapRuntimeError else {
                return XCTFail("Expected map readiness error")
            }
            guard case .notReady(let issues) = runtimeError else {
                return XCTFail("Expected not-ready result")
            }
            XCTAssertTrue(issues.contains(.routingGraphMissing))
        }
    }

    func testOBDObservationsPersistWithVehicleAndSources() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("obd.json")
        let vehicle = makeVehicle()
        let store = OBDObservationStore(fileURL: file)
        try await store.append(
            OBDObservationRecord(
                id: "capture-1",
                capturedAt: "2026-07-23T00:00:00Z",
                adapterID: "adapter-test",
                vehicle: vehicle,
                rawResponse: "43 01 33\r>",
                troubleCodes: [DiagnosticTroubleCode(code: "P0133")],
                sourceIDs: ["vehicle-manual-test"]
            )
        )
        let reopened = OBDObservationStore(fileURL: file)
        let records = await reopened.all(for: vehicle)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceIDs, ["vehicle-manual-test"])
    }

    func testVehicleDocumentManifestAcceptsExactApplicability() throws {
        let vehicle = makeVehicle()
        let article = makeVehicleArticle(vehicle: vehicle)
        XCTAssertNoThrow(
            try VehicleDocumentIngestor().validate(
                manifest: VehicleDocumentManifest(
                    documentID: "vehicle-manual-test",
                    revision: "2026.1",
                    vehicle: vehicle,
                    articleIDs: [article.id],
                    licenseIdentifier: "LicenseRef-Test"
                ),
                articles: [article]
            )
        )
    }

    func testVehicleDocumentManifestRejectsWrongVehicle() throws {
        let vehicle = makeVehicle()
        let wrongVehicle = VehicleProfile(
            make: "Other",
            model: "Vehicle",
            modelYear: 2024,
            market: "US",
            powertrain: .gasoline,
            documentID: "vehicle-manual-test"
        )
        let article = makeVehicleArticle(vehicle: vehicle)
        XCTAssertThrowsError(
            try VehicleDocumentIngestor().validate(
                manifest: VehicleDocumentManifest(
                    documentID: "vehicle-manual-test",
                    revision: "2026.1",
                    vehicle: wrongVehicle,
                    articleIDs: [article.id],
                    licenseIdentifier: "LicenseRef-Test"
                ),
                articles: [article]
            )
        ) { error in
            XCTAssertEqual(
                error as? VehicleDocumentIngestionError,
                .applicabilityMismatch(article.id)
            )
        }
    }

    private func entitlementEvent(
        id: String,
        kind: EntitlementEventKind
    ) -> VerifiedEntitlementEvent {
        VerifiedEntitlementEvent(
            eventID: id,
            productID: "trailguard.field",
            kind: kind,
            verifiedAt: "2026-07-23T00:00:00Z",
            verificationSucceeded: true
        )
    }

    private func makeMapDirectory(includeRouting: Bool) throws -> URL {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("map".utf8).write(
            to: root.appendingPathComponent("region.pmtiles")
        )
        try Data("style".utf8).write(
            to: root.appendingPathComponent("style.json")
        )
        if includeRouting {
            try Data("route".utf8).write(
                to: root.appendingPathComponent("routing.graph")
            )
        }
        return root
    }

    private func makeMapPack() -> OfflineMapPack {
        OfflineMapPack(
            id: "map.test",
            name: "Test Map",
            regionCode: "TEST",
            tier: .field,
            version: "1",
            generatedAt: "2026-01-01T00:00:00Z",
            recommendedRefreshAfter: "2027-01-01T00:00:00Z",
            bounds: GeoBounds(
                southWest: GeoCoordinate(latitude: 35, longitude: -120),
                northEast: GeoCoordinate(latitude: 38, longitude: -116)
            ),
            pmtilesPath: "region.pmtiles",
            stylePath: "style.json",
            routingGraphPath: "routing.graph",
            byteCount: 13
        )
    }

    private func makeVehicle() -> VehicleProfile {
        VehicleProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            make: "Test",
            model: "Vehicle",
            modelYear: 2024,
            market: "US",
            powertrain: .gasoline,
            documentID: "vehicle-manual-test"
        )
    }

    private func makeVehicleArticle(
        vehicle: VehicleProfile
    ) -> KnowledgeArticle {
        KnowledgeArticle(
            id: "vehicle.exact.fixture",
            domain: .vehicle,
            title: "Exact vehicle fixture",
            summary: "Development-only vehicle procedure.",
            steps: ["Use the exact documented point."],
            warnings: ["Do not apply this to another vehicle."],
            keywords: ["exact", "vehicle"],
            source: SourceReference(
                id: "vehicle-manual-test",
                title: "Test vehicle manual",
                organization: "Test Manufacturer",
                revision: "2026.1"
            ),
            reviewed: true,
            vehicleApplicability: VehicleApplicability(
                makes: [vehicle.make],
                models: [vehicle.model],
                yearFrom: vehicle.modelYear,
                yearThrough: vehicle.modelYear,
                markets: [vehicle.market],
                powertrains: [vehicle.powertrain],
                documentIDs: ["vehicle-manual-test"]
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraIntegration-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
