import Foundation
import XCTest
@testable import Overlaygent

final class JSONFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("JSONFileStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadIfPresentReturnsNilForMissingOrEmptyFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("sample.json", isDirectory: false)
        let store = JSONFileStore<SampleCodable>(fileURL: fileURL)

        XCTAssertNil(try store.loadIfPresent())

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data().write(to: fileURL)

        XCTAssertNil(try store.loadIfPresent())
    }

    func testSaveCreatesDirectoryAndRoundTripsPrettySortedJSON() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("nested/sample.json", isDirectory: false)
        let store = JSONFileStore<SampleCodable>(fileURL: fileURL)
        let value = SampleCodable(name: "example", count: 2)

        try store.save(value)

        XCTAssertEqual(try store.loadIfPresent(), value)
        let json = String(data: try Data(contentsOf: fileURL), encoding: .utf8)
        XCTAssertTrue(json?.contains("\n") ?? false)
        XCTAssertTrue((json?.range(of: #""count""#)?.lowerBound ?? json!.endIndex) < (json?.range(of: #""name""#)?.lowerBound ?? json!.startIndex))
    }

    func testLoadIfPresentThrowsForInvalidJSON() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("invalid.json", isDirectory: false)
        let store = JSONFileStore<SampleCodable>(fileURL: fileURL)

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: fileURL)

        XCTAssertThrowsError(try store.loadIfPresent())
    }

    func testApplicationSupportPathsUseOverlaygentDirectory() {
        let fileURL = ApplicationSupportPaths().fileURL(named: "example.json")

        XCTAssertEqual(fileURL.lastPathComponent, "example.json")
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, ApplicationSupportPaths.appDirectoryName)
    }
}

private struct SampleCodable: Codable, Equatable {
    var name: String
    var count: Int
}
