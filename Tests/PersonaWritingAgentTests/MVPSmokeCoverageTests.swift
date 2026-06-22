import Foundation
import XCTest

final class MVPSmokeCoverageTests: XCTestCase {
    func testSmokeScriptRunsOnlyMockedSwiftPMTestCommands() throws {
        let script = try String(contentsOf: packageRoot.appendingPathComponent("scripts/mvp-smoke.sh"))

        XCTAssertTrue(script.contains("swift test"))
        XCTAssertTrue(script.contains("CorrectionResultParserTests|OpenAICompatibleProviderTests|CorrectionEngineTests"))
        XCTAssertTrue(script.contains("AppContextAdapterTests|SlackContextAdapterTests|ChannelTalkContextAdapterTests"))
        XCTAssertTrue(script.contains("mocked fixtures"))

        XCTAssertFalse(script.contains("swift run PersonaWritingAgent"))
        XCTAssertFalse(script.contains("curl "))
        XCTAssertFalse(script.contains("osascript"))
        XCTAssertFalse(script.contains("pbcopy"))
        XCTAssertFalse(script.contains("pbpaste"))
    }

    func testReadmeDocumentsFullAndFocusedSmokeCommands() throws {
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"))

        XCTAssertTrue(readme.contains("## MVP Smoke"))
        XCTAssertTrue(readme.contains("bash scripts/mvp-smoke.sh full"))
        XCTAssertTrue(readme.contains("bash scripts/mvp-smoke.sh parser-provider-engine"))
        XCTAssertTrue(readme.contains("bash scripts/mvp-smoke.sh context-adapters"))
        XCTAssertTrue(readme.contains("swift test"))
        XCTAssertTrue(readme.contains("mocked XCTest"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
