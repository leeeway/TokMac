import Foundation

@main
struct DownloadFileTests {
    static func main() throws {
        let tests = DownloadFileTests()
        tests.testRejectsUntrustedPagesAndForeignBlobs()
        try tests.testHTTPErrorCannotBeSavedEvenWithVideoMime()
        tests.testRejectsHTMLAndJSONErrorBodiesWithSuccessStatus()
        try tests.testAcceptsVideoAndNativeBlobResponses()
        try tests.testSuccessfulDownloadAtomicallyReplacesExistingFile()
        try tests.testMissingOrEmptyDownloadPreservesOriginal()
        try tests.testFailedReplacementPreservesDestinationAndDownloadedBytes()
        print("7 Swift download validation and atomic-save checks passed.")
    }

    private let page = URL(string: "https://www.tiktok.com/foryou")!

    func testRejectsUntrustedPagesAndForeignBlobs() {
        for value in ["https://tiktok.com.evil.example", "http://www.tiktok.com", "file:///tmp/tiktok.com"] {
            checkFalse(DownloadFile.isTrustedPage(URL(string: value)))
        }
        checkTrue(DownloadFile.isTrustedPage(page))
        checkTrue(DownloadFile.isVideoSource(URL(string: "blob:https://www.tiktok.com/id")!, pageURL: page))
        for value in ["blob:https://evil.example/id", "file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.com/video"] {
            checkFalse(DownloadFile.isVideoSource(URL(string: value)!, pageURL: page))
        }
    }

    func testHTTPErrorCannotBeSavedEvenWithVideoMime() throws {
        let response = HTTPURLResponse(url: page, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "video/mp4"])!
        checkThrows(try DownloadFile.validateResponse(response))
    }

    func testRejectsHTMLAndJSONErrorBodiesWithSuccessStatus() {
        for mime in ["text/html", "application/json", "application/vnd.apple.mpegurl"] {
            let response = HTTPURLResponse(url: page, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
            checkThrows(try DownloadFile.validateResponse(response))
        }
    }

    func testAcceptsVideoAndNativeBlobResponses() throws {
        for mime in ["video/mp4", "video/webm", "application/octet-stream", "application/mp4"] {
            let response = HTTPURLResponse(url: page, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
            try DownloadFile.validateResponse(response)
        }
        try DownloadFile.validateResponse(URLResponse(url: URL(string: "blob:https://www.tiktok.com/id")!, mimeType: nil, expectedContentLength: 10, textEncodingName: nil))
    }

    func testSuccessfulDownloadAtomicallyReplacesExistingFile() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("O'Connor.mp4")
            try Data("original".utf8).write(to: target)
            let temporary = DownloadFile.temporaryURL(for: target)
            checkEqual(temporary.deletingLastPathComponent(), target.deletingLastPathComponent())
            try Data("new video".utf8).write(to: temporary)
            try DownloadFile.commit(temporary, to: target)
            checkEqual(try Data(contentsOf: target), Data("new video".utf8))
            checkFalse(FileManager.default.fileExists(atPath: temporary.path))
        }
    }

    func testMissingOrEmptyDownloadPreservesOriginal() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("video.mp4")
            let original = Data("original".utf8)
            try original.write(to: target)
            let temporary = DownloadFile.temporaryURL(for: target)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            try Data().write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            checkEqual(try Data(contentsOf: target), original)
        }
    }

    func testFailedReplacementPreservesDestinationAndDownloadedBytes() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("existing-directory")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let sentinel = target.appendingPathComponent("sentinel")
            try Data("original".utf8).write(to: sentinel)
            let temporary = DownloadFile.temporaryURL(for: target)
            try Data("new video".utf8).write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            checkEqual(try String(contentsOf: sentinel, encoding: .utf8), "original")
            checkEqual(try String(contentsOf: temporary, encoding: .utf8), "new video")
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private func checkTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
private func checkFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
private func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Values differ: \(lhs) and \(rhs)", file: file, line: line)
}
private func checkThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected an error", file: file, line: line)
}
