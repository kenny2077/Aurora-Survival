#if AURORA_MESH_BETA
import CoreBluetooth
import Foundation

@MainActor
final class MeshBLELink: NSObject, ObservableObject {
    enum RadioState: Equatable {
        case stopped
        case unavailable
        case denied
        case starting
        case ready
    }

    private struct Frame {
        static let headerSize = 20
        let transferID: UUID
        let index: UInt16
        let count: UInt16
        let payload: Data

        var encoded: Data {
            var data = Data(capacity: Self.headerSize + payload.count)
            var uuid = transferID.uuid
            withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
            var bigIndex = index.bigEndian
            var bigCount = count.bigEndian
            withUnsafeBytes(of: &bigIndex) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &bigCount) { data.append(contentsOf: $0) }
            data.append(payload)
            return data
        }

        init?(data: Data) {
            guard data.count >= Self.headerSize else { return nil }
            let bytes = Array(data.prefix(16))
            transferID = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            index = UInt16(data[16]) << 8 | UInt16(data[17])
            count = UInt16(data[18]) << 8 | UInt16(data[19])
            guard count > 0, index < count else { return nil }
            payload = Data(data.dropFirst(Self.headerSize))
        }

        init(transferID: UUID, index: UInt16, count: UInt16, payload: Data) {
            self.transferID = transferID
            self.index = index
            self.count = count
            self.payload = payload
        }
    }

    private struct Reassembly {
        let count: Int
        var parts: [Int: Data]
        let startedAt: Date
    }

    static let serviceUUID = CBUUID(string: "D8E18F40-6D2C-4C91-97BB-9A8CB5877201")
    static let packetUUID = CBUUID(string: "53D1F90A-850A-46A9-94B4-2A9B02E8FC11")

    @Published private(set) var state: RadioState = .stopped
    @Published private(set) var directLinkCount = 0
    @Published private(set) var debugStatus = "Stopped"
    @Published private(set) var sentPacketCount = 0
    @Published private(set) var receivedPacketCount = 0
    @Published private(set) var noLinkSendCount = 0
    var onPacket: ((Data) -> Void)?

    private let localToken: String
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var mutableCharacteristic: CBMutableCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var writableCharacteristics: [UUID: CBCharacteristic] = [:]
    private var subscribedCentrals: [UUID: CBCentral] = [:]
    private var reassemblies: [String: [UUID: Reassembly]] = [:]
    private var pendingWrites: [UUID: [Data]] = [:]
    private var pendingNotifications: [UUID: [Data]] = [:]
    private var isRunning = false

    init(identityID: String) {
        localToken = String(identityID.prefix(12))
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        switch CBManager.authorization {
        case .denied, .restricted:
            state = .denied
            return
        default:
            break
        }
        isRunning = true
        state = .starting
        debugStatus = "Starting central and peripheral radios"
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        isRunning = false
        centralManager?.stopScan()
        if let manager = centralManager {
            peripherals.values.forEach { manager.cancelPeripheralConnection($0) }
        }
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        centralManager = nil
        peripheralManager = nil
        mutableCharacteristic = nil
        peripherals.removeAll()
        writableCharacteristics.removeAll()
        subscribedCentrals.removeAll()
        reassemblies.removeAll()
        pendingWrites.removeAll()
        pendingNotifications.removeAll()
        directLinkCount = 0
        state = .stopped
        debugStatus = "Stopped"
    }

    @discardableResult
    func broadcast(_ packetData: Data) -> Bool {
        guard isRunning else {
            noLinkSendCount += 1
            debugStatus = "Send paused because Mesh is stopped"
            return false
        }
        var reachedLink = false
        for (id, peripheral) in peripherals {
            guard let characteristic = writableCharacteristics[id] else { continue }
            reachedLink = true
            let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
            for frame in Self.frames(for: packetData, maximumLength: mtu) {
                if peripheral.canSendWriteWithoutResponse {
                    peripheral.writeValue(frame, for: characteristic, type: .withoutResponse)
                } else {
                    Self.enqueue(frame, in: &pendingWrites[id, default: []])
                }
            }
        }
        guard let manager = peripheralManager, let characteristic = mutableCharacteristic else { return reachedLink }
        for central in subscribedCentrals.values {
            reachedLink = true
            for frame in Self.frames(for: packetData, maximumLength: central.maximumUpdateValueLength) {
                if !manager.updateValue(frame, for: characteristic, onSubscribedCentrals: [central]) {
                    Self.enqueue(frame, in: &pendingNotifications[central.identifier, default: []])
                }
            }
        }
        if reachedLink {
            sentPacketCount += 1
            debugStatus = "Packet sent over BLE"
        } else {
            noLinkSendCount += 1
            debugStatus = "Waiting for a writable BLE link"
        }
        return reachedLink
    }

    private static func enqueue(_ frame: Data, in queue: inout [Data]) {
        guard queue.count < AuroraMeshLimits.maximumQueuedFrames else { return }
        queue.append(frame)
    }

    private static func frames(for data: Data, maximumLength: Int) -> [Data] {
        let chunkSize = max(1, maximumLength - Frame.headerSize)
        let count = max(1, Int(ceil(Double(data.count) / Double(chunkSize))))
        guard count <= Int(UInt16.max) else { return [] }
        let transferID = UUID()
        return (0..<count).map { index in
            let lower = min(data.count, index * chunkSize)
            let upper = min(data.count, lower + chunkSize)
            return Frame(
                transferID: transferID,
                index: UInt16(index),
                count: UInt16(count),
                payload: data.subdata(in: lower..<upper)
            ).encoded
        }
    }

    private func ingest(frameData: Data, peerID: String) {
        guard let frame = Frame(data: frameData) else { return }
        var peer = reassemblies[peerID, default: [:]]
        peer = peer.filter { Date().timeIntervalSince($0.value.startedAt) < 30 }
        guard peer[frame.transferID] != nil || peer.count < AuroraMeshLimits.maximumReassembliesPerPeer else {
            reassemblies[peerID] = peer
            return
        }
        var assembly = peer[frame.transferID] ?? Reassembly(
            count: Int(frame.count),
            parts: [:],
            startedAt: Date()
        )
        guard assembly.count == Int(frame.count) else { return }
        assembly.parts[Int(frame.index)] = frame.payload
        if assembly.parts.count == assembly.count {
            let packet = (0..<assembly.count).reduce(into: Data()) { output, index in
                if let part = assembly.parts[index] { output.append(part) }
            }
            peer.removeValue(forKey: frame.transferID)
            receivedPacketCount += 1
            debugStatus = "Packet received over BLE"
            onPacket?(packet)
        } else {
            peer[frame.transferID] = assembly
        }
        reassemblies[peerID] = peer
    }

    private func refreshState() {
        directLinkCount = min(
            AuroraMeshLimits.maximumDirectLinks,
            writableCharacteristics.count + subscribedCentrals.count
        )
        guard isRunning else { return }
        if centralManager?.state == .unauthorized || peripheralManager?.state == .unauthorized {
            state = .denied
        } else if centralManager?.state == .poweredOn, peripheralManager?.state == .poweredOn {
            state = .ready
        } else if centralManager?.state == .poweredOff || peripheralManager?.state == .poweredOff {
            state = .unavailable
        } else {
            state = .starting
        }
    }

    private func restartScanIfPossible() {
        guard isRunning, let centralManager, centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        debugStatus = "Scanning and advertising"
    }
}

extension MeshBLELink: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshState()
        guard isRunning, central.state == .poweredOn else { return }
        restartScanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard peripherals.count + subscribedCentrals.count < AuroraMeshLimits.maximumDirectLinks else { return }
        let remoteToken = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard remoteToken == nil || localToken < remoteToken! else {
            debugStatus = "Peer discovered; waiting for its connection"
            return
        }
        guard peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        debugStatus = "Peer discovered; connecting"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        debugStatus = "Connected; discovering Mesh service"
        peripheral.discoverServices([Self.serviceUUID])
        refreshState()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals.removeValue(forKey: peripheral.identifier)
        writableCharacteristics.removeValue(forKey: peripheral.identifier)
        debugStatus = "Connection failed; scanning again"
        refreshState()
        restartScanIfPossible()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripherals.removeValue(forKey: peripheral.identifier)
        writableCharacteristics.removeValue(forKey: peripheral.identifier)
        debugStatus = "Peer disconnected; scanning again"
        refreshState()
        restartScanIfPossible()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            debugStatus = "Mesh service discovery failed"
            return
        }
        peripheral.services?.filter { $0.uuid == Self.serviceUUID }.forEach {
            peripheral.discoverCharacteristics([Self.packetUUID], for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            debugStatus = "Mesh characteristic discovery failed"
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.packetUUID }) else { return }
        writableCharacteristics[peripheral.identifier] = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        debugStatus = "Writable BLE link ready"
        refreshState()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        ingest(frameData: data, peerID: peripheral.identifier.uuidString)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let characteristic = writableCharacteristics[peripheral.identifier] else { return }
        var queue = pendingWrites[peripheral.identifier, default: []]
        while peripheral.canSendWriteWithoutResponse, !queue.isEmpty {
            peripheral.writeValue(queue.removeFirst(), for: characteristic, type: .withoutResponse)
        }
        pendingWrites[peripheral.identifier] = queue
    }
}

extension MeshBLELink: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        refreshState()
        guard isRunning, peripheral.state == .poweredOn else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.packetUUID,
            properties: [.notify, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        mutableCharacteristic = characteristic
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            debugStatus = "Mesh advertising service failed"
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: localToken,
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        debugStatus = error == nil ? "Scanning and advertising" : "Mesh advertising failed"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == Self.packetUUID {
            if let value = request.value {
                ingest(frameData: value, peerID: request.central.identifier.uuidString)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard writableCharacteristics.count + subscribedCentrals.count < AuroraMeshLimits.maximumDirectLinks else { return }
        subscribedCentrals[central.identifier] = central
        debugStatus = "Subscribed BLE link ready"
        refreshState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeValue(forKey: central.identifier)
        refreshState()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let characteristic = mutableCharacteristic else { return }
        for central in subscribedCentrals.values {
            var queue = pendingNotifications[central.identifier, default: []]
            while !queue.isEmpty {
                guard peripheral.updateValue(queue[0], for: characteristic, onSubscribedCentrals: [central]) else { break }
                queue.removeFirst()
            }
            pendingNotifications[central.identifier] = queue
        }
    }
}
#endif
