import Foundation
import Darwin

// macOS lists a paired iPhone on Wi-Fi only after its own discovery has seen the
// phone announce itself again, which can take until the phone is next woken. The
// phone accepts connections long before that. This bridge sits between the bundled
// device tools and the system usbmuxd socket. It relays everything unchanged and
// only adds a network record for the selected phone to a device list that lacks
// one, so the tools connect straight to the phone. The pairing handshake still
// decides whether the device at that address is the selected one.

/// Where a phone can be reached on the local network, in the form usbmuxd reports it.
public struct NetworkPeer: Equatable, Sendable {
    public let address: Data
    public let interfaceIndex: Int
    private static let lockdownPort: UInt16 = 62078
    /// `bytes` is a 4-byte IPv4 address.
    public init?(ipv4 bytes: Data, interfaceIndex: Int) {
        guard bytes.count == 4 else { return nil }
        var value = Data([16, UInt8(AF_INET), UInt8(Self.lockdownPort >> 8), UInt8(Self.lockdownPort & 0xFF)])
        value.append(bytes); value.append(Data(count: 8))
        address = value; self.interfaceIndex = interfaceIndex
    }
    /// `bytes` is a 16-byte IPv6 address. The interface index doubles as the scope of a link-local address.
    public init?(ipv6 bytes: Data, interfaceIndex: Int) {
        guard bytes.count == 16, interfaceIndex >= 0 else { return nil }
        var value = Data([28, UInt8(AF_INET6), UInt8(Self.lockdownPort >> 8), UInt8(Self.lockdownPort & 0xFF)])
        value.append(Data(count: 4)); value.append(bytes)
        withUnsafeBytes(of: UInt32(interfaceIndex)) { value.append(contentsOf: $0) }
        address = value; self.interfaceIndex = interfaceIndex
    }
}

/// usbmuxd framing: a 16-byte little-endian header (length, version, message, tag) and an XML property list.
enum MuxPacket {
    static let headerLength = 16
    static let plistMessage: UInt32 = 8
    static let limit = 1 << 20
    static func parseHeader(_ data: Data) -> (length: Int, kind: UInt32, tag: UInt32)? {
        guard data.count == headerLength else { return nil }
        func field(_ index: Int) -> UInt32 {
            data.subdata(in: index * 4..<index * 4 + 4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }
        let length = Int(field(0))
        guard (headerLength...limit).contains(length) else { return nil }
        return (length, field(2), field(3))
    }
    static func encode(_ value: [String: Any], tag: UInt32) -> Data? {
        guard let body = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
              body.count + headerLength <= limit else { return nil }
        var packet = Data()
        for field in [UInt32(body.count + headerLength), 1, plistMessage, tag] {
            withUnsafeBytes(of: field.littleEndian) { packet.append(contentsOf: $0) }
        }
        return packet + body
    }
    static func decode(_ body: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
    }
}

public enum MuxRecords {
    /// The Wi-Fi address that names a `_apple-mobdev2._tcp` service: `aa:bb:cc:dd:ee:ff@fe80::…`.
    public static func wifiAddress(fromService name: String) -> String? {
        guard let at = name.firstIndex(of: "@") else { return nil }
        return normalized(String(name[..<at]))
    }
    public static func normalized(_ address: String) -> String? {
        let parts = address.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return parts.map { $0.count == 1 ? "0" + $0 : String($0) }.joined(separator: ":")
    }
    /// The only field read from a pairing record. Keys and certificates are never kept.
    static func wifiAddress(fromPairRecordReply reply: [String: Any]) -> String? {
        guard let data = reply["PairRecordData"] as? Data, let record = MuxPacket.decode(data),
              let address = record["WiFiMACAddress"] as? String else { return nil }
        return normalized(address)
    }
    static func listsNetworkDevice(_ reply: [String: Any], deviceID: String) -> Bool {
        (reply["DeviceList"] as? [[String: Any]] ?? []).contains {
            let properties = $0["Properties"] as? [String: Any]
            return properties?["SerialNumber"] as? String == deviceID && properties?["ConnectionType"] as? String == "Network"
        }
    }
    static func adding(deviceID: String, peer: NetworkPeer, to reply: [String: Any]) -> [String: Any] {
        let handle = 0x46460001 // Outside the small numbers usbmuxd hands out; network connections never use it.
        var result = reply
        result["DeviceList"] = (reply["DeviceList"] as? [Any] ?? []) + [[
            "DeviceID": handle, "MessageType": "Attached",
            "Properties": ["ConnectionType": "Network", "DeviceID": handle, "InterfaceIndex": peer.interfaceIndex,
                           "NetworkAddress": peer.address, "SerialNumber": deviceID] as [String: Any],
        ] as [String: Any]]
        return result
    }
}

enum MuxSocket {
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    private static func open(_ path: String, _ body: (Int32, UnsafePointer<sockaddr>, socklen_t) -> Bool) -> Int32? {
        guard var address = address(path) else { return nil }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var on: Int32 = 1 // A peer that goes away must not raise SIGPIPE in the app.
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let done = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if !done { close(descriptor); return nil }
        return descriptor
    }
    static func connect(_ path: String) -> Int32? { open(path) { Darwin.connect($0, $1, $2) == 0 } }
    static func listen(_ path: String) -> Int32? {
        unlink(path)
        return open(path) { Darwin.bind($0, $1, $2) == 0 && chmod(path, 0o600) == 0 && Darwin.listen($0, 16) == 0 }
    }
    static func read(_ descriptor: Int32, _ count: Int) -> Data? {
        guard count > 0 else { return Data() }
        var data = Data(count: count), done = 0
        while done < count {
            let step = data.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress! + done, count - done) }
            if step > 0 { done += step } else if step < 0 && errno == EINTR { continue } else { return nil }
        }
        return data
    }
    static func write(_ descriptor: Int32, _ data: Data) -> Bool {
        var done = 0
        while done < data.count {
            let step = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress! + done, data.count - done) }
            if step > 0 { done += step } else if step < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
    static func readPacket(_ descriptor: Int32) -> (packet: Data, kind: UInt32, tag: UInt32, body: Data)? {
        guard let header = read(descriptor, MuxPacket.headerLength), let info = MuxPacket.parseHeader(header),
              let body = read(descriptor, info.length - MuxPacket.headerLength) else { return nil }
        return (header + body, info.kind, info.tag, body)
    }
    static func pump(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(source, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0, write(destination, Data(buffer[0..<count])) else { return }
        }
    }
}

public final class MuxBridge: @unchecked Sendable {
    public static let systemSocket = "/var/run/usbmuxd"
    public let path: String
    private let upstream: String
    private let lock = NSLock()
    private let source: DispatchSourceRead
    private var selected: String?
    private var peers: [String: NetworkPeer] = [:]
    private var wifiAddresses: [String: String] = [:]

    /// Fails when the socket cannot be created; the caller then keeps using usbmuxd directly.
    public init?(path: String, upstream: String = MuxBridge.systemSocket) {
        guard let listener = MuxSocket.listen(path) else { return nil }
        self.path = path; self.upstream = upstream
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: DispatchQueue(label: "Firefly.mux"))
        source.setEventHandler { [weak self] in
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard let self else { close(client); return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            Thread.detachNewThread { self.serve(client) }
        }
        source.setCancelHandler { close(listener); unlink(path) }
        source.resume()
    }
    public func stop() { source.cancel() }
    deinit { source.cancel() }

    /// Sockets left behind by instances that are no longer running.
    public static func removeStaleSockets(in directory: URL, prefix: String) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix(prefix) && name.hasSuffix(".sock") {
            guard let pid = Int32(name.dropFirst(prefix.count).dropLast(5)), pid > 0, kill(pid, 0) != 0, errno == ESRCH else { continue }
            unlink(directory.appendingPathComponent(name).path)
        }
    }

    /// The only device a record is ever added for.
    public func select(_ deviceID: String?) { lock.lock(); selected = deviceID; lock.unlock() }
    /// Reachable phones keyed by their Wi-Fi address. Replaces the previous set.
    public func setPeers(_ value: [String: NetworkPeer]) { lock.lock(); peers = value; lock.unlock() }

    /// The Wi-Fi address stored in the pairing record of `deviceID`. Asks usbmuxd on first use; call off the main thread.
    public func wifiAddress(for deviceID: String) -> String? {
        lock.lock(); let known = wifiAddresses[deviceID]; lock.unlock()
        if let known { return known }
        let request: [String: Any] = ["MessageType": "ReadPairRecord", "PairRecordID": deviceID, "ProgName": "Firefly",
                                      "ClientVersionString": "Firefly", "kLibUSBMuxVersion": 3]
        guard let packet = MuxPacket.encode(request, tag: 1), let reply = exchange(packet), let plist = MuxPacket.decode(reply.body),
              let address = MuxRecords.wifiAddress(fromPairRecordReply: plist) else { return nil }
        lock.lock(); wifiAddresses[deviceID] = address; lock.unlock()
        return address
    }

    private func exchange(_ packet: Data) -> (tag: UInt32, body: Data, packet: Data)? {
        guard let descriptor = MuxSocket.connect(upstream) else { return nil }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard MuxSocket.write(descriptor, packet), let reply = MuxSocket.readPacket(descriptor) else { return nil }
        return (reply.tag, reply.body, reply.packet)
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        while let request = MuxSocket.readPacket(client) {
            let message = request.kind == MuxPacket.plistMessage ? MuxPacket.decode(request.body)?["MessageType"] as? String : nil
            guard message == "ListDevices" else { relay(client, first: request.packet); return }
            guard let reply = exchange(request.packet) else { return }
            guard MuxSocket.write(client, completed(reply.body, tag: reply.tag) ?? reply.packet) else { return }
        }
    }

    // The device list with the selected phone added, or nil when the reply should pass through as it is.
    private func completed(_ body: Data, tag: UInt32) -> Data? {
        lock.lock(); let deviceID = selected; lock.unlock()
        guard let deviceID, let address = wifiAddress(for: deviceID) else { return nil }
        lock.lock(); let peer = peers[address]; lock.unlock()
        guard let peer, let reply = MuxPacket.decode(body), !MuxRecords.listsNetworkDevice(reply, deviceID: deviceID) else { return nil }
        return MuxPacket.encode(MuxRecords.adding(deviceID: deviceID, peer: peer, to: reply), tag: tag)
    }

    // Everything except a device list goes to usbmuxd untouched, including the raw stream that follows a Connect.
    private func relay(_ client: Int32, first packet: Data) {
        guard let server = MuxSocket.connect(upstream) else { return }
        defer { close(server) }
        guard MuxSocket.write(server, packet) else { return }
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            MuxSocket.pump(from: server, to: client)
            shutdown(client, SHUT_RDWR)
            finished.signal()
        }
        MuxSocket.pump(from: client, to: server)
        shutdown(server, SHUT_RDWR)
        finished.wait()
    }
}
