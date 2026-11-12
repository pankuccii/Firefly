import XCTest
@testable import FireflyCore

final class CoreTests: XCTestCase {
    func observation(_ percent: Int = 50, date: Date = Date(), charging: Bool? = false, id: String = "12345678") throws -> Observation {
        try Observation(deviceID: id, name: "Test iPhone", percent: percent, charging: charging, timestamp: date, transport: .usb)
    }
    func plist(_ value: Any, charging: Any = true) throws -> Data { try PropertyListSerialization.data(fromPropertyList: ["BatteryCurrentCapacity": value, "BatteryIsCharging": charging], format: .xml, options: 0) }
    func testStrictBatteryParsing() throws {
        for value: Any in [-1, 101, 20.5, true, "85"] {
            XCTAssertThrowsError(try Observation.parse(plist(value), deviceID: "12345678", name: "Phone", transport: .usb))
        }
        for value in [0, 85, 100] { XCTAssertEqual(try Observation.parse(plist(value), deviceID: "12345678", name: "Phone", transport: .wifi).percent, value) }
        XCTAssertThrowsError(try Observation.parse(Data("bad".utf8), deviceID: "12345678", name: "Phone", transport: .usb))
        XCTAssertNil(try Observation.parse(plist(50, charging: "yes"), deviceID: "12345678", name: "Phone", transport: .usb).charging)
    }
    func testFreshnessAndClockValidation() throws {
        let now = Date(); let value = try observation(date: now)
        XCTAssertEqual(value.freshness(now: now, connected: true), .fresh)
        XCTAssertEqual(value.freshness(now: now.addingTimeInterval(100), connected: true), .recent)
        XCTAssertEqual(value.freshness(now: now.addingTimeInterval(301), connected: true), .stale)
        XCTAssertEqual(value.freshness(now: now, connected: false), .disconnected)
        XCTAssertThrowsError(try observation(date: now.addingTimeInterval(100)))
    }
    func testRetryBound() {
        let p = RetryPolicy(); XCTAssertEqual((1...7).map { p.delay(failures: $0) }, [5,10,20,40,80,160,300])
        XCTAssertFalse(p.mayRetry(failures: 6)); XCTAssertTrue(p.mayRetry(failures: 5))
    }
    func testAlertCrossingDedupAndCooldown() throws {
        var engine = AlertEngine(); let now = Date()
        XCTAssertEqual(engine.evaluate(try observation(25, date: now.addingTimeInterval(-60)), lows: [20,10], chargeTarget: 80), [])
        let low = try observation(9, date: now)
        XCTAssertEqual(engine.evaluate(low, lows: [20,10], chargeTarget: 80), ["low:10"])
        XCTAssertEqual(engine.evaluate(low, lows: [20,10], chargeTarget: 80), [])
        _ = engine.evaluate(try observation(25, date: now.addingTimeInterval(1)), lows: [20,10], chargeTarget: nil)
        XCTAssertEqual(engine.evaluate(try observation(9, date: now.addingTimeInterval(2)), lows: [20,10], chargeTarget: nil), [])
    }
    func testNoAlertsFromStaleUnknownChargeOrDifferentDevice() throws {
        var e = AlertEngine(); let now = Date()
        _ = e.evaluate(try observation(79, date: now.addingTimeInterval(-20)), lows: [20], chargeTarget: 80)
        XCTAssertTrue(e.evaluate(try observation(80, date: now, charging: nil), lows: [20], chargeTarget: 80).isEmpty)
        XCTAssertTrue(e.evaluate(try observation(5, id: "87654321"), lows: [20], chargeTarget: 80).isEmpty)
        XCTAssertTrue(e.evaluate(try observation(5, date: now.addingTimeInterval(-600)), lows: [20], chargeTarget: 80).isEmpty)
    }
    func testHistoryRetentionAndRelaunch() throws {
        var h = History(); let v = try observation(); h.append(v); h.append(v)
        h.append(try observation(date: Date().addingTimeInterval(-8*86400)))
        XCTAssertEqual(h.values.count, 1)
        let saved = try JSONEncoder().encode(h); let restored = try JSONDecoder().decode(History.self, from: saved)
        XCTAssertEqual(restored.values, h.values); XCTAssertTrue(h.csv(deviceID: v.deviceID).contains(",50,false,USB"))
    }
    func testScheduleWeekdays() {
        var rule = ScheduleRule(); rule.enabled = true
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8, minute: 30))!
        XCTAssertTrue(rule.due(at: monday, calendar: calendar))
        XCTAssertFalse(rule.due(at: monday.addingTimeInterval(60), calendar: calendar))
        rule.enabled = false; XCTAssertFalse(rule.due(at: monday, calendar: calendar))
    }
    func testChargingEstimatesRequireReliableContinuousData() throws {
        let now = Date()
        let values = try (0..<6).map { try observation(50 + $0, date: now.addingTimeInterval(Double($0 - 5) * 60), charging: true) }
        XCTAssertEqual(InsightsEngine.minutesToFull(values, deviceID: "12345678", now: now), 45)
        XCTAssertEqual(InsightsEngine.sessions(values, deviceID: "12345678").count, 1)
        XCTAssertNil(InsightsEngine.minutesToFull(Array(values.prefix(2)), deviceID: "12345678", now: now))
        XCTAssertNil(InsightsEngine.minutesToFull(values, deviceID: "12345678", now: now.addingTimeInterval(600)))
        let gap = try observation(70, date: now.addingTimeInterval(-2000), charging: true)
        XCTAssertEqual(InsightsEngine.sessions([gap] + values, deviceID: "12345678").count, 1)
    }
    func testWidgetSnapshotPrivacyFreshnessAndDisconnection() throws {
        let now = Date(), value = WidgetSnapshot(name: "Phone", percent: 41, timestamp: Date(), connected: true)
        let data = try JSONEncoder().encode(value)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("deviceID"))
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), value)
        XCTAssertTrue(value.live(at: now)); XCTAssertFalse(value.live(at: now.addingTimeInterval(301)))
        XCTAssertFalse(WidgetSnapshot(name: "Phone", percent: 41, timestamp: now, connected: false).live(at: now))
        // Snapshots written by older builds carry a "language" key; they must still decode.
        let old = Data(#"{"name":"Phone","percent":41,"timestamp":0,"connected":true,"language":"tr"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: old).percent, 41)
    }
    func testMissingDependencies() async {
        do { _ = try await BatteryService(paths: nil).read(preferredID: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AcquisitionError, .dependencyMissing) }
    }
    func testActualProcessTimeoutAndCancellation() async throws {
        let runner = ProcessRunner()
        do { _ = try await runner.run("/bin/sleep", ["5"], timeout: 0.1); XCTFail() }
        catch { XCTAssertEqual(error as? AcquisitionError, .timeout) }
        let task = Task { try await runner.run("/bin/sleep", ["5"], timeout: 10) }
        try await Task.sleep(nanoseconds: 100_000_000); task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await runner.run("/bin/echo", ["85"], timeout: 1)
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), "85\n")
    }
    func testProcessOutputLimitAndFastExit() async throws {
        let runner = ProcessRunner()
        do { _ = try await runner.run("/usr/bin/yes", [], timeout: 3); XCTFail() }
        catch { XCTAssertEqual(error as? AcquisitionError, .outputTooLarge) }
        for _ in 0..<20 {
            let result = try await runner.run("/bin/echo", [String(repeating: "x", count: 20000)], timeout: 3)
            XCTAssertEqual(result.data.count, 20001)
        }
    }
    func testAlertCooldownSurvivesRelaunch() throws {
        let now = Date(); var engine = AlertEngine()
        _ = engine.evaluate(try observation(21, date: now.addingTimeInterval(-20)), lows: [20], chargeTarget: nil)
        XCTAssertEqual(engine.evaluate(try observation(19, date: now.addingTimeInterval(-10)), lows: [20], chargeTarget: nil), ["low:20"])
        var restored = try JSONDecoder().decode(AlertEngine.self, from: JSONEncoder().encode(engine))
        _ = restored.evaluate(try observation(21, date: now), lows: [20], chargeTarget: nil)
        XCTAssertTrue(restored.evaluate(try observation(19, date: now.addingTimeInterval(1)), lows: [20], chargeTarget: nil).isEmpty)
    }
    func testUSBAndWiFiFailoverRemainOnSameDevice() async throws {
        let fake = FakeRunner(failUSB: true)
        let service = BatteryService(runner: fake, paths: ToolPaths(info: "info", discover: "discover"))
        let result = try await service.read(preferredID: "12345678")
        XCTAssertEqual(result.transport, .wifi); XCTAssertEqual(result.percent, 85); XCTAssertEqual(result.deviceID, "12345678")
    }
    func testUSBAndDuplicateDiscovery() async throws {
        let result = try await BatteryService(runner: FakeRunner(failUSB: false), paths: ToolPaths(info: "info", discover: "discover")).read(preferredID: nil)
        XCTAssertEqual(result.transport, .usb)
    }
    func testNeverSelectDifferentPhoneWhenDisconnected() async {
        do { _ = try await BatteryService(runner: FakeRunner(failUSB: false), paths: ToolPaths(info: "info", discover: "discover")).read(preferredID: "87654321"); XCTFail() }
        catch { XCTAssertEqual(error as? AcquisitionError, .noDevice) }
    }
}
struct FakeRunner: CommandExecuting {
    let failUSB: Bool
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        if arguments == ["--help"] { return CommandResult(data: Data("--network --udid --xml --domain".utf8), status: 0) }
        if executable == "discover" { return CommandResult(data: Data("12345678\n12345678\n".utf8), status: 0) }
        if arguments.contains("DeviceName") { return CommandResult(data: Data("Test iPhone\n".utf8), status: 0) }
        if failUSB && !arguments.contains("-n") { throw AcquisitionError.queryFailed }
        return CommandResult(data: try PropertyListSerialization.data(fromPropertyList: ["BatteryCurrentCapacity": 85, "BatteryIsCharging": true], format: .xml, options: 0), status: 0)
    }
}

extension CoreTests {
    func testChargeTransitionAtSamePercentageOnKnownWiFiDevice() async throws {
        let runner = ChargeSwitch()
        let service = BatteryService(runner: runner, paths: ToolPaths(info: "info", discover: "discover"))
        let initial = try Observation(deviceID: "12345678", name: "Test", percent: 64, charging: false, transport: .wifi)
        let plugged = try await service.readKnown(initial)
        let unplugged = try await service.readKnown(plugged)
        XCTAssertEqual(plugged.percent, unplugged.percent)
        XCTAssertEqual(plugged.charging, true)
        XCTAssertEqual(unplugged.charging, false)
        let calls = await runner.calls
        XCTAssertEqual(calls, Array(repeating: ["info", "-n", "-u", "12345678", "-q", "com.apple.mobile.battery", "-x"], count: 2))
    }
}
private actor ChargeSwitch: CommandExecuting {
    var calls: [[String]] = []
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append([executable] + arguments)
        let payload: [String: Any] = ["BatteryCurrentCapacity": 64, "BatteryIsCharging": calls.count == 1]
        return CommandResult(data: try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0), status: 0)
    }
}

extension CoreTests {
    func testRepeatedSessionReadsAndClose() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A tiny pipe peer resets its counter whenever the helper is relaunched.
        let helper = directory.appendingPathComponent("firefly-session")
        let script = """
        #!/bin/bash
        n=0
        while IFS= read -r -n 1 request; do
            [[ "$request" == R ]] || exit 2
            if [[ $n == 0 ]]; then printf '\\106\\001'; else printf '\\107\\002'; fi
            n=1
        done
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let service = BatteryService(paths: ToolPaths(info: directory.appendingPathComponent("ideviceinfo").path, discover: "unused"))
        let previous = try Observation(deviceID: "12345678", name: "iPhone", percent: 69, charging: nil, transport: .wifi)
        let first = try await service.readSession(previous)
        let next = try await service.readSession(first)
        XCTAssertEqual(first.percent, 70); XCTAssertEqual(first.charging, false)
        XCTAssertEqual(next.percent, 71); XCTAssertEqual(next.charging, true)
        await service.close()
        let reopened = try await service.readSession(next)
        XCTAssertEqual(reopened.percent, 70)
        await service.close()
    }
}

extension CoreTests {
    func testWiFiReadDoesNotDiscardSlowValidResponseAtFourSeconds() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let helper = dir.appendingPathComponent("firefly-session")
        try "#!/bin/bash\nIFS= read -r -n 1 _\nsleep 5\nprintf '\\107\\001'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let service = BatteryService(paths: ToolPaths(info: dir.appendingPathComponent("info").path, discover: "unused"))
        let previous = try Observation(deviceID: "12345678", name: "Phone", percent: 70, charging: nil, transport: .wifi)
        let next = try await service.readSession(previous)
        XCTAssertEqual(next.percent, 71)
        await service.close()
    }
    func testPassiveDiscoveryMatchesOnlyTheSelectedPhone() async throws {
        let service = BatteryService(runner: FakeRunner(failUSB: false), paths: ToolPaths(info: "info", discover: "discover"))
        let absent = try await service.isListed("87654321")
        let present = try await service.isListed("12345678")
        XCTAssertFalse(absent); XCTAssertTrue(present)
    }
}

extension CoreTests {
    func testRemoteReportUsesPhoneTimeAndRejectsInvalidReports() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-11-02T10:00:00Z")!
        let reading = try RemoteBatteryReading.parse(Data("67\r\n2026-11-02T13:00:00+03:00\r\n".utf8), now: instant)
        XCTAssertEqual(reading.percent, 67)
        XCTAssertEqual(reading.date, instant)
        XCTAssertFalse(reading.recent(at: instant.addingTimeInterval(301)))
        for payload in ["101\n2026-11-02T10:00:00Z", "50\n2026-11-02T10:01:00Z", "50\nyesterday", "50", String(repeating: "7", count: 257)] {
            XCTAssertThrowsError(try RemoteBatteryReading.parse(Data(payload.utf8), now: instant))
        }
    }
}

extension CoreTests {
    func testFirstReadingAfterReconnectCanUseActualPriorSession() throws {
        let now = Date()
        let history = try (0...6).map { try observation(50 + $0, date: now.addingTimeInterval(Double($0 - 20) * 60), charging: true) }
        let current = try observation(28, date: now, charging: true)
        let disconnected = try observation(28, date: now.addingTimeInterval(-10), charging: false)
        let estimate = InsightsEngine.completionEstimate(history + [disconnected], current: current, now: now)
        XCTAssertEqual(estimate?.minutes, 72)
        XCTAssertEqual(estimate?.fromHistory, true)
        XCTAssertNil(InsightsEngine.completionEstimate([], current: current, now: now))
        XCTAssertNil(InsightsEngine.completionEstimate(history, current: try observation(28, date: now, charging: false), now: now))
    }
}

// A stand-in for the system usbmuxd socket.
private final class FakeMux {
    let path: String
    private let listener: Int32
    init?(path: String, devices: Data, wifiAddress: String) {
        guard let listener = MuxSocket.listen(path) else { return nil }
        self.path = path; self.listener = listener
        Thread.detachNewThread {
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 { return }
                Thread.detachNewThread {
                    defer { close(client) }
                    while let request = MuxSocket.readPacket(client) {
                        let message = MuxPacket.decode(request.body)?["MessageType"] as? String ?? ""
                        var reply: [String: Any] = ["MessageType": "Result", "Number": 0, "Echo": message]
                        if message == "ListDevices" { reply = MuxPacket.decode(devices) ?? [:] }
                        if message == "ReadPairRecord", let record = try? PropertyListSerialization.data(
                            fromPropertyList: ["WiFiMACAddress": wifiAddress, "HostID": "not-for-the-app"], format: .xml, options: 0) {
                            reply = ["PairRecordData": record]
                        }
                        guard let packet = MuxPacket.encode(reply, tag: request.tag), MuxSocket.write(client, packet) else { return }
                    }
                }
            }
        }
    }
    func stop() { close(listener); unlink(path) }
}

extension CoreTests {
    private func device(_ serial: String, _ connection: String) -> [String: Any] {
        ["DeviceID": 3, "MessageType": "Attached", "Properties": ["ConnectionType": connection, "DeviceID": 3, "SerialNumber": serial] as [String: Any]]
    }
    private func ask(_ path: String, _ message: String) throws -> [String: Any] {
        let descriptor = try XCTUnwrap(MuxSocket.connect(path))
        defer { close(descriptor) }
        XCTAssertTrue(MuxSocket.write(descriptor, try XCTUnwrap(MuxPacket.encode(["MessageType": message], tag: 7))))
        let reply = try XCTUnwrap(MuxSocket.readPacket(descriptor))
        XCTAssertEqual(reply.tag, 7)
        return try XCTUnwrap(MuxPacket.decode(reply.body))
    }
    private func listed(_ reply: [String: Any]) -> [String] {
        (reply["DeviceList"] as? [[String: Any]] ?? []).compactMap {
            guard let properties = $0["Properties"] as? [String: Any] else { return nil }
            return "\(properties["SerialNumber"] as? String ?? "?") \(properties["ConnectionType"] as? String ?? "?")"
        }
    }
    private func sockets(_ name: String) -> (upstream: String, front: String) {
        let directory = FileManager.default.temporaryDirectory
        return (directory.appendingPathComponent("ff-\(name)-u\(getpid()).sock").path, directory.appendingPathComponent("ff-\(name)-f\(getpid()).sock").path)
    }
    func testMuxPeerAndServiceNameParsing() throws {
        XCTAssertEqual(MuxRecords.wifiAddress(fromService: "B8:45:EB:51:2A:96@fe80::ba45:ebff:fe51:2a96-supportsRP-26"), "b8:45:eb:51:2a:96")
        XCTAssertNil(MuxRecords.wifiAddress(fromService: "Living Room"))
        XCTAssertNil(MuxRecords.normalized("aa:bb:cc:dd:ee"))
        XCTAssertNil(MuxRecords.normalized("aa:bb:cc:dd:ee:zz"))
        XCTAssertEqual(MuxRecords.normalized("A:b:0C:dd:EE:f"), "0a:0b:0c:dd:ee:0f")
        // The layouts usbmuxd itself reports: sockaddr_in and sockaddr_in6 with the lockdown port.
        XCTAssertEqual(try XCTUnwrap(NetworkPeer(ipv4: Data([10, 0, 0, 5]), interfaceIndex: 4)).address,
                       Data([16, 2, 0xF2, 0x7E, 10, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0]))
        let scoped = try XCTUnwrap(NetworkPeer(ipv6: Data(repeating: 0xFE, count: 16), interfaceIndex: 12)).address
        XCTAssertEqual(scoped.count, 28)
        XCTAssertEqual(Array(scoped.prefix(4)), [28, 30, 0xF2, 0x7E])
        XCTAssertEqual(Array(scoped.suffix(4)), [12, 0, 0, 0])
        XCTAssertNil(NetworkPeer(ipv4: Data([1, 2, 3]), interfaceIndex: 0))
        XCTAssertNil(NetworkPeer(ipv6: Data(count: 4), interfaceIndex: 0))
    }
    func testMuxPacketFraming() throws {
        let packet = try XCTUnwrap(MuxPacket.encode(["MessageType": "ListDevices"], tag: 9))
        let header = try XCTUnwrap(MuxPacket.parseHeader(packet.prefix(16)))
        XCTAssertEqual(header.length, packet.count); XCTAssertEqual(header.kind, 8); XCTAssertEqual(header.tag, 9)
        XCTAssertEqual(MuxPacket.decode(packet.dropFirst(16))?["MessageType"] as? String, "ListDevices")
        XCTAssertNil(MuxPacket.parseHeader(Data(count: 16)))                       // Shorter than its own header.
        XCTAssertNil(MuxPacket.parseHeader(Data([0, 0, 0, 0x7F] + [UInt8](repeating: 0, count: 12)))) // Oversized.
        XCTAssertNil(MuxPacket.parseHeader(Data(count: 8)))
    }
    func testMuxBridgeAddsOnlyTheSelectedReachablePhoneAndRelaysTheRest() throws {
        let paths = sockets("a")
        let devices = try XCTUnwrap(MuxPacket.encode(["DeviceList": [device("OTHER", "USB")]], tag: 0)).dropFirst(16)
        let fake = try XCTUnwrap(FakeMux(path: paths.upstream, devices: Data(devices), wifiAddress: "AA:BB:CC:DD:EE:0F"))
        defer { fake.stop() }
        let bridge = try XCTUnwrap(MuxBridge(path: paths.front, upstream: paths.upstream))
        defer { bridge.stop() }
        let peer = try XCTUnwrap(NetworkPeer(ipv4: Data([192, 168, 1, 20]), interfaceIndex: 12))
        bridge.setPeers(["aa:bb:cc:dd:ee:0f": peer])
        XCTAssertEqual(listed(try ask(paths.front, "ListDevices")), ["OTHER USB"])   // No device selected.
        bridge.select("PHONE")
        XCTAssertEqual(bridge.wifiAddress(for: "PHONE"), "aa:bb:cc:dd:ee:0f")
        bridge.setPeers(["11:22:33:44:55:66": peer])
        XCTAssertEqual(listed(try ask(paths.front, "ListDevices")), ["OTHER USB"])   // Another phone is nearby, not ours.
        bridge.setPeers(["aa:bb:cc:dd:ee:0f": peer])
        let reply = try ask(paths.front, "ListDevices")
        XCTAssertEqual(listed(reply), ["OTHER USB", "PHONE Network"])
        let added = (reply["DeviceList"] as? [[String: Any]])?.last?["Properties"] as? [String: Any]
        XCTAssertEqual(added?["NetworkAddress"] as? Data, peer.address)
        XCTAssertEqual(added?["InterfaceIndex"] as? Int, 12)
        XCTAssertEqual(try ask(paths.front, "ReadBUID")["Echo"] as? String, "ReadBUID") // Relayed untouched.
        bridge.setPeers([:])
        XCTAssertEqual(listed(try ask(paths.front, "ListDevices")), ["OTHER USB"])   // The phone left the network.
    }
    func testMuxBridgeLeavesAListThatAlreadyHasThePhone() throws {
        let paths = sockets("b")
        let devices = try XCTUnwrap(MuxPacket.encode(["DeviceList": [device("PHONE", "Network")]], tag: 0)).dropFirst(16)
        let fake = try XCTUnwrap(FakeMux(path: paths.upstream, devices: Data(devices), wifiAddress: "aa:bb:cc:dd:ee:0f"))
        defer { fake.stop() }
        let bridge = try XCTUnwrap(MuxBridge(path: paths.front, upstream: paths.upstream))
        defer { bridge.stop() }
        bridge.select("PHONE")
        bridge.setPeers(["aa:bb:cc:dd:ee:0f": try XCTUnwrap(NetworkPeer(ipv4: Data([192, 168, 1, 20]), interfaceIndex: 12))])
        XCTAssertEqual(listed(try ask(paths.front, "ListDevices")), ["PHONE Network"])
    }
    func testMuxBridgeWithoutUsbmuxdFailsClosed() throws {
        let paths = sockets("c")
        let bridge = try XCTUnwrap(MuxBridge(path: paths.front, upstream: paths.upstream)) // Nothing listens upstream.
        defer { bridge.stop() }
        bridge.select("PHONE")
        XCTAssertNil(bridge.wifiAddress(for: "PHONE"))
        let descriptor = try XCTUnwrap(MuxSocket.connect(paths.front))
        defer { close(descriptor) }
        XCTAssertTrue(MuxSocket.write(descriptor, try XCTUnwrap(MuxPacket.encode(["MessageType": "ListDevices"], tag: 1))))
        XCTAssertNil(MuxSocket.readPacket(descriptor))                             // The connection is closed, not answered with an invented list.
    }
}
