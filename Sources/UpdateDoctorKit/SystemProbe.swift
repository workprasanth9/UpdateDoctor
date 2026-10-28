import Foundation

/// Everything UpdateDoctor learns about the Mac goes through this protocol, so
/// tests can replay recorded command output instead of touching the system.
/// Every method is read only.
public protocol SystemProbe {
    var isRoot: Bool { get }
    /// Runs a command and returns stdout plus stderr, or nil if it could not run.
    func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String?
    func readFile(_ path: String) -> Data?
    func fileExists(_ path: String) -> Bool
    /// Returns the HTTP status code, or nil if the host could not be reached.
    func httpStatus(_ url: URL, timeout: TimeInterval) -> Int?
    func httpGet(_ url: URL, timeout: TimeInterval) -> Data?
}

public final class LiveProbe: SystemProbe {
    public init() {}

    public var isRoot: Bool { geteuid() == 0 }

    public func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var output = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); output.append(chunk); lock.unlock()
        }
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); output.append(rest); lock.unlock()
        return String(decoding: output, as: UTF8.self)
    }

    public func readFile(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    public func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func httpStatus(_ url: URL, timeout: TimeInterval) -> Int? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        return fetch(request, timeout: timeout).status
    }

    public func httpGet(_ url: URL, timeout: TimeInterval) -> Data? {
        let result = fetch(URLRequest(url: url, timeoutInterval: timeout), timeout: timeout)
        guard let status = result.status, (200..<300).contains(status) else { return nil }
        return result.data
    }

    private func fetch(_ request: URLRequest, timeout: TimeInterval) -> (status: Int?, data: Data?) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)
        var status: Int?
        var body: Data?
        session.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode
            body = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 2)
        session.invalidateAndCancel()
        return (status, body)
    }
}
