import Foundation

@main
struct DownloadFileTests {
    static func main() throws {
        let tests = DownloadFileTests()
        tests.testRejectsUntrustedPagesAndForeignBlobs()
        try tests.testHTTPErrorCannotBeSavedEvenWithVideoMime()
        tests.testRejectsPartialVideoResponses()
        tests.testRejectsHTMLAndJSONErrorBodiesWithSuccessStatus()
        try tests.testAcceptsVideoAndNativeBlobResponses()
        try tests.testSuccessfulDownloadAtomicallyReplacesExistingFile()
        try tests.testMissingOrEmptyDownloadPreservesOriginal()
        try tests.testFailedReplacementPreservesDestinationAndDownloadedBytes()
        try tests.testFormatCorrectionDoesNotOverwriteUnselectedFiles()
        try tests.testWatchLaterPersistenceAndValidation()
        print("Swift download and watch-later checks passed.")
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/" + name))
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

    func testRejectsPartialVideoResponses() {
        for (status, range) in [(206, "bytes 0-7/1000"), (206, nil), (200, "bytes 0-7/1000")] {
            var headers = ["Content-Type": "video/mp4", "Content-Length": "8"]
            headers["Content-Range"] = range
            let response = HTTPURLResponse(url: page, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
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
            let video = try fixture("tiny.mp4")
            try video.write(to: temporary)
            try DownloadFile.commit(temporary, to: target)
            checkEqual(try Data(contentsOf: target), video)
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
            try Data("{\"error\":\"Not video\"}".utf8).write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            try fixture("tiny.mp4").dropLast().write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            checkEqual(try Data(contentsOf: target), original)
        }
    }

    func testFailedReplacementPreservesDestinationAndDownloadedBytes() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("existing-directory.mp4")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let sentinel = target.appendingPathComponent("sentinel")
            try Data("original".utf8).write(to: sentinel)
            let temporary = DownloadFile.temporaryURL(for: target)
            let video = try fixture("tiny.mp4")
            try video.write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            checkEqual(try String(contentsOf: sentinel, encoding: .utf8), "original")
            checkEqual(try Data(contentsOf: temporary), video)
        }
    }

    func testFormatCorrectionDoesNotOverwriteUnselectedFiles() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("clip.mp4")
            let movie = directory.appendingPathComponent("clip.mov")
            let temporary = DownloadFile.temporaryURL(for: target)
            let original = Data("original".utf8)
            try original.write(to: target)
            try original.write(to: movie)
            try fixture("tiny.mov").write(to: temporary)
            checkThrows(try DownloadFile.commit(temporary, to: target))
            checkEqual(try Data(contentsOf: movie), original)
            try FileManager.default.removeItem(at: movie)
            checkEqual(try DownloadFile.commit(temporary, to: target), movie)
            checkEqual(try Data(contentsOf: movie), try fixture("tiny.mov"))
            checkEqual(try Data(contentsOf: target), original)

            // Minimal EBML structure with a WebM video track, an unknown-size segment and a cluster.
            let webM = Data([0x1a, 0x45, 0xdf, 0xa3, 0x87, 0x42, 0x82, 0x84, 0x77, 0x65, 0x62, 0x6d,
                             0x18, 0x53, 0x80, 0x67, 0xff, 0x16, 0x54, 0xae, 0x6b, 0x85, 0xae, 0x83,
                             0x83, 0x81, 0x01, 0x1f, 0x43, 0xb6, 0x75, 0x83, 0xe7, 0x81, 0x00])
            try webM.write(to: temporary)
            checkEqual(try DownloadFile.commit(temporary, to: target).pathExtension, "webm")
            checkEqual(try Data(contentsOf: target), original)
        }
    }

    func testWatchLaterPersistenceAndValidation() throws {
        for value in ["https://tiktok.com.evil.example/@user/video/123", "http://tiktok.com/@user/video/123",
                      "https://name@tiktok.com/@user/video/123", "https://tiktok.com:123/@user/video/123",
                      "https://tiktok.com/@user/video/123/extra"] {
            checkTrue(SavedVideo(value) == nil)
        }
        try withDirectory { directory in
            let file = directory.appendingPathComponent("library/watch-later.json")
            let store = WatchLaterStore(file: file)
            let first = SavedVideo("https://m.tiktok.com/@first/video/123/?ref=feed#more")!
            let second = SavedVideo("https://www.tiktok.com/@second/video/456")!
            let renamed = SavedVideo("https://www.tiktok.com/@renamed/video/123")!
            checkEqual(first.url.absoluteString, "https://www.tiktok.com/@first/video/123")
            checkEqual(try store.videos(), [])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let legacy = try JSONEncoder().encode([second.url.absoluteString, first.url.absoluteString])
            try legacy.write(to: file)
            checkEqual(try store.videos(), [second, first])
            checkEqual(try Data(contentsOf: file), legacy)
            checkTrue(first.matches(" FIRST 123 "))
            let enriched = SavedVideo(first.url.absoluteString, caption: "山间\n Night Walk")!
            let cover = Data([1, 2, 3])
            try store.refresh(enriched)
            try store.refreshThumbnail(for: first.id, data: cover)
            checkEqual(try store.add(renamed), false)
            let modern = try WatchLaterStore(file: file).videos()
            checkEqual(modern, [second, SavedVideo(renamed.url.absoluteString, caption: "山间 Night Walk", thumbnail: cover)!])
            checkTrue(modern[1].matches("night RENAMED 山间"))
            checkFalse(modern[1].matches("night absent"))
            try store.remove(first)
            try store.refresh(enriched)
            try store.refreshThumbnail(for: first.id, data: cover)
            checkEqual(try WatchLaterStore(file: file).videos(), [second])
            let corrupt = Data("[null]".utf8)
            try corrupt.write(to: file)
            checkThrows(try store.add(first))
            checkEqual(try Data(contentsOf: file), corrupt)
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
