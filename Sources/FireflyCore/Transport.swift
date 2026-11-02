import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let data: Data
    public let status: Int32
    public init(data: Data, status: Int32) { self.data = data; self.status = status }
}
public protocol CommandExecuting: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}
// A dedicated serial queue owns each Process, its bounded output and completion.
private final class ProcessJob: @unchecked Sendable {
    let queue = DispatchQueue(label: "Firefly.command")
    let process = Process()
    let output = Pipe()
    var data = Data()
    var finished = false
    var cancelled = false
    var launched = false
    var timedOut = false
    var oversized = false
    var outputEnded = false
    var exited = false
    var continuation: CheckedContinuation<CommandResult, Error>?
    func stop() {
        guard launched, process.isRunning else { return }
        process.terminate()
        queue.asyncAfter(deadline: .now() + 0.5) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    func cancel() { queue.async { [self] in cancelled = true; stop() } }
    func start(_ path: String, _ args: [String], _ timeout: TimeInterval, _ c: CheckedContinuation<CommandResult, Error>) {
        queue.async { [self] in
            continuation = c
            if cancelled { complete(.failure(CancellationError())); return }
            process.executableURL = URL(fileURLWithPath: path); process.arguments = args
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.exited = true; self.finishIfReady() }
            }
            do { try process.run(); launched = true } catch { complete(.failure(AcquisitionError.dependencyMissing)); return }
            try? output.fileHandleForWriting.close()
            DispatchQueue.global(qos: .utility).async { [self] in
                while true {
                    let chunk = output.fileHandleForReading.readData(ofLength: 8192)
                    if chunk.isEmpty { break }
                    queue.async { self.consume(chunk) }
                }
                queue.async { self.outputEnded = true; self.finishIfReady() }
            }
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                guard !finished else { return }; timedOut = true; stop()
            }
        }
    }
    func finishIfReady() {
        guard exited, outputEnded else { return }
        if cancelled { complete(.failure(CancellationError())) }
        else if timedOut { complete(.failure(AcquisitionError.timeout)) }
        else if oversized { complete(.failure(AcquisitionError.outputTooLarge)) }
        else { complete(.success(CommandResult(data: data, status: process.terminationStatus))) }
    }
    func consume(_ chunk: Data) {
        guard !finished else { return }
        if data.count + chunk.count > 262144 { oversized = true; stop() } else { data.append(chunk) }
    }
    func complete(_ result: Result<CommandResult, Error>) {
        guard !finished else { return }; finished = true
        try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        continuation?.resume(with: result); continuation = nil
    }
}
public struct ProcessRunner: CommandExecuting {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) async throws -> CommandResult {
        let job = ProcessJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { job.start(executable, arguments, timeout, $0) }
        } onCancel: { job.cancel() }
    }
}
public struct ToolPaths: Sendable {
    public let info: String
    public let discover: String
    public init(info: String, discover: String) { self.info = info; self.discover = discover }
    public static func installed() -> ToolPaths? {
        for base in [Bundle.main.resourceURL?.appendingPathComponent("DeviceTools/bin").path, "/opt/homebrew/bin", "/usr/local/bin"].compactMap({ $0 }) {
            let a = base + "/ideviceinfo", b = base + "/idevice_id"
            if FileManager.default.isExecutableFile(atPath: a) && FileManager.default.isExecutableFile(atPath: b) { return ToolPaths(info: a, discover: b) }
        }
        return nil
    }
}
public actor BatteryService {
    private let runner: any CommandExecuting
    private let paths: ToolPaths?
    private var session: DeviceSession?
    public func close() { session?.stop(); session = nil }
    public func readSession(_ previous: Observation) async throws -> Observation {
        guard let paths else { throw AcquisitionError.dependencyMissing }
        let tool = URL(fileURLWithPath: paths.info).deletingLastPathComponent().appendingPathComponent("firefly-session")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return try await readKnown(previous) }
        if session?.id != previous.deviceID || session?.route != previous.transport || session?.process.isRunning != true {
            close()
            session = try DeviceSession(tool: tool, observation: previous)
        }
        guard let active = session else { throw AcquisitionError.queryFailed }
        do { return try await active.sample(previous: previous) }
        catch {
            if session === active { close() }
            try Task.checkCancellation()
            throw error
        }
    }
    private var verified = false
    private var names: [String: String] = [:]
    public init(runner: any CommandExecuting = ProcessRunner(), paths: ToolPaths? = ToolPaths.installed()) { self.runner = runner; self.paths = paths }
    private func command(_ path: String, _ args: [String]) async throws -> Data {
        try Task.checkCancellation()
        let result = try await runner.run(path, args, timeout: 10)
        guard result.status == 0 else { throw AcquisitionError.queryFailed }
        return result.data
    }
    // Between discovery passes, query only the device and route that last succeeded.
    public func readKnown(_ previous: Observation) async throws -> Observation {
        guard let paths else { throw AcquisitionError.dependencyMissing }
        let args = (previous.transport == .wifi ? ["-n"] : []) + ["-u", previous.deviceID, "-q", "com.apple.mobile.battery", "-x"]
        let data = try await command(paths.info, args)
        return try Observation.parse(data, deviceID: previous.deviceID, name: previous.name, transport: previous.transport)
    }
    // A passive check of the local device list. Do not start a lockdown session
    // for an absent phone or substitute a different paired device.
    public func isListed(_ id: String) async throws -> Bool {
        guard let paths else { throw AcquisitionError.dependencyMissing }
        var succeeded = false
        for flag in ["-l", "-n"] {
            do {
                let bytes = try await command(paths.discover, [flag])
                succeeded = true
                if String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isWhitespace).contains(Substring(id)) { return true }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        if !succeeded { throw AcquisitionError.queryFailed }
        return false
    }
    public func read(preferredID: String?) async throws -> Observation {
        guard let paths else { throw AcquisitionError.dependencyMissing }
        if !verified {
            let info = String(decoding: try await command(paths.info, ["--help"]), as: UTF8.self)
            let discovery = String(decoding: try await command(paths.discover, ["--help"]), as: UTF8.self)
            guard ["--network", "--udid", "--xml", "--domain"].allSatisfy(info.contains), discovery.contains("--network") else { throw AcquisitionError.unsupportedTool }
            verified = true
        }
        var selectedID = preferredID
        var lastError: AcquisitionError = .noDevice
        for transport in Transport.allCases {
            do {
                let found = String(decoding: try await command(paths.discover, transport == .usb ? ["-l"] : ["-n"]), as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.range(of: "^[a-fA-F0-9-]{8,64}$", options: .regularExpression) != nil }
                let ids = Array(Set(found)).sorted()
                if selectedID == nil { selectedID = ids.first }
                guard let id = selectedID, ids.contains(id) else { continue }
                let prefix = (transport == .wifi ? ["-n"] : []) + ["-u", id]
                let battery = try await command(paths.info, prefix + ["-q", "com.apple.mobile.battery", "-x"])
                if names[id] == nil {
                    let nameData = try? await command(paths.info, prefix + ["-k", "DeviceName"])
                    let name = nameData.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "iPhone"
                    names[id] = name.isEmpty ? "iPhone" : String(name.prefix(128))
                }
                return try Observation.parse(battery, deviceID: id, name: names[id] ?? "iPhone", transport: transport)
            } catch is CancellationError { throw CancellationError() }
            catch let error as AcquisitionError { lastError = error }
            catch { lastError = .queryFailed }
        }
        throw lastError
    }
}

// One pipe and one authenticated device session per selected phone.
// The actor's caller serializes reads. Killing the helper also interrupts a stalled handshake.
private final class DeviceSession: @unchecked Sendable {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let id: String
    let route: Transport
    init(tool: URL, observation: Observation) throws {
        id = observation.deviceID
        route = observation.transport
        process.executableURL = tool
        process.arguments = [route == .wifi ? "wifi" : "usb", id]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }
    func stop() { if process.isRunning { process.terminate() } }
    deinit { stop() }
    func sample(previous: Observation) async throws -> Observation {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) { [self] in
                try input.fileHandleForWriting.write(contentsOf: Data([82]))
                let fd = output.fileHandleForReading.fileDescriptor
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, route == .wifi ? 15000 : 4000)
                if ready == 0 { throw AcquisitionError.timeout }
                guard ready > 0 else { throw AcquisitionError.queryFailed }
                var bytes = [UInt8](repeating: 0, count: 2)
                guard Darwin.read(fd, &bytes, 2) == 2, bytes[0] <= 100, bytes[1] <= 2 else { throw AcquisitionError.queryFailed }
                return try Observation(deviceID: id, name: previous.name, percent: Int(bytes[0]),
                                       charging: bytes[1] == 0 ? nil : bytes[1] == 2, transport: route)
            }.value
        } onCancel: { self.stop() }
    }
}
