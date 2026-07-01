import Foundation
import XCTest
@testable import Overlaygent

final class CodexAuthFileImporterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodexAuthFileImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testImportsAccessTokenAndAccountIDFromCodexAuthFile() throws {
        let authFileURL = temporaryDirectory.appendingPathComponent("auth.json")
        try Data(
            """
            {
              "tokens": {
                "access_token": "access-token",
                "account_id": "account-id"
              }
            }
            """.utf8
        )
        .write(to: authFileURL)
        let importer = CodexAuthFileImporter(authFileURL: authFileURL)

        let credential = try importer.importCredential()

        XCTAssertEqual(credential.accessToken, "access-token")
        XCTAssertEqual(credential.accountID, "account-id")
        XCTAssertEqual(credential.sourceDescription, authFileURL.path)
    }

    func testImportsAccountIDAndExpirationFromJWTFallbacks() throws {
        let authFileURL = temporaryDirectory.appendingPathComponent("auth.json")
        let expiration = 2_000_000_000
        let accessToken = jwtToken(
            payload:
                """
                {
                  "exp": \(expiration)
                }
                """
        )
        let idToken = jwtToken(
            payload:
                """
                {
                  "https://api.openai.com/auth": {
                    "chatgpt_account_id": "account-from-id-token"
                  }
                }
                """
        )
        try Data(
            """
            {
              "tokens": {
                "access_token": "\(accessToken)",
                "id_token": "\(idToken)"
              }
            }
            """.utf8
        )
        .write(to: authFileURL)
        let importer = CodexAuthFileImporter(authFileURL: authFileURL)

        let credential = try importer.importCredential()

        XCTAssertEqual(credential.accessToken, accessToken)
        XCTAssertEqual(credential.accountID, "account-from-id-token")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: TimeInterval(expiration)))
    }

    func testImportsFromEnvironmentCandidateBeforeHomeFallbacks() throws {
        let chatGPTLocalHome = temporaryDirectory.appendingPathComponent("chatgpt-local", isDirectory: true)
        try FileManager.default.createDirectory(at: chatGPTLocalHome, withIntermediateDirectories: true)
        let authFileURL = chatGPTLocalHome.appendingPathComponent("auth.json")
        try Data(
            """
            {
              "tokens": {
                "access_token": "env-access-token",
                "account_id": "env-account-id"
              }
            }
            """.utf8
        )
        .write(to: authFileURL)
        let importer = CodexAuthFileImporter(
            environment: ["CHATGPT_LOCAL_HOME": chatGPTLocalHome.path]
        )

        let credential = try importer.importCredential()

        XCTAssertEqual(credential.accessToken, "env-access-token")
        XCTAssertEqual(credential.accountID, "env-account-id")
        XCTAssertEqual(credential.sourceDescription, authFileURL.path)
    }

    func testRejectsExpiredAccessToken() throws {
        let authFileURL = temporaryDirectory.appendingPathComponent("auth.json")
        let accessToken = jwtToken(
            payload:
                """
                {
                  "exp": 1,
                  "https://api.openai.com/auth": {
                    "chatgpt_account_id": "expired-account"
                  }
                }
                """
        )
        try Data(
            """
            {
              "tokens": {
                "access_token": "\(accessToken)"
              }
            }
            """.utf8
        )
        .write(to: authFileURL)
        let importer = CodexAuthFileImporter(authFileURL: authFileURL)

        XCTAssertThrowsError(try importer.importCredential()) { error in
            XCTAssertEqual(error as? CodexAuthFileImporterError, .expiredAccessToken(authFileURL.path))
        }
    }

    func testInvalidAndIncompleteAuthFilesProduceSpecificErrors() throws {
        let invalidAuthFileURL = temporaryDirectory.appendingPathComponent("invalid-auth.json")
        try Data("{".utf8).write(to: invalidAuthFileURL)
        XCTAssertThrowsError(try CodexAuthFileImporter(authFileURL: invalidAuthFileURL).importCredential()) { error in
            XCTAssertEqual(error as? CodexAuthFileImporterError, .invalidAuthFile(invalidAuthFileURL.path))
        }

        let missingTokenURL = temporaryDirectory.appendingPathComponent("missing-token-auth.json")
        try Data(#"{"tokens":{"account_id":"account-id"}}"#.utf8).write(to: missingTokenURL)
        XCTAssertThrowsError(try CodexAuthFileImporter(authFileURL: missingTokenURL).importCredential()) { error in
            XCTAssertEqual(error as? CodexAuthFileImporterError, .missingAccessToken(missingTokenURL.path))
        }

        let missingAccountURL = temporaryDirectory.appendingPathComponent("missing-account-auth.json")
        try Data(#"{"tokens":{"access_token":"access-token"}}"#.utf8).write(to: missingAccountURL)
        XCTAssertThrowsError(try CodexAuthFileImporter(authFileURL: missingAccountURL).importCredential()) { error in
            XCTAssertEqual(error as? CodexAuthFileImporterError, .missingAccountID(missingAccountURL.path))
        }
    }

    func testMissingAuthFileReportsCheckedPath() {
        let authFileURL = temporaryDirectory.appendingPathComponent("missing-auth.json")
        let importer = CodexAuthFileImporter(authFileURL: authFileURL)

        XCTAssertThrowsError(try importer.importCredential()) { error in
            XCTAssertEqual(error as? CodexAuthFileImporterError, .authFileNotFound([authFileURL.path]))
        }
    }

    private func jwtToken(payload: String) -> String {
        [
            base64URL(#"{"alg":"none","typ":"JWT"}"#),
            base64URL(payload),
            "signature"
        ]
        .joined(separator: ".")
    }

    private func base64URL(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
