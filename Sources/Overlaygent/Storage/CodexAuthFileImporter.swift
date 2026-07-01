import Foundation

protocol ChatGPTSubscriptionCredentialImporting {
    func importCredential() throws -> ChatGPTSubscriptionCredential
}

enum CodexAuthFileImporterError: Error, Equatable, LocalizedError {
    case authFileNotFound([String])
    case invalidAuthFile(String)
    case missingAccessToken(String)
    case missingAccountID(String)
    case expiredAccessToken(String)

    var errorDescription: String? {
        switch self {
        case .authFileNotFound(let candidates):
            return "Could not find Codex auth.json. Checked: \(candidates.joined(separator: ", "))."
        case .invalidAuthFile(let path):
            return "Codex auth.json could not be decoded at \(path)."
        case .missingAccessToken(let path):
            return "Codex auth.json does not contain a ChatGPT access token at \(path)."
        case .missingAccountID(let path):
            return "Codex auth.json does not contain a ChatGPT account id at \(path)."
        case .expiredAccessToken(let path):
            return "Codex auth.json contains an expired ChatGPT access token at \(path)."
        }
    }
}

struct CodexAuthFileImporter: ChatGPTSubscriptionCredentialImporting {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let authFileURL: URL?
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        authFileURL: URL? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.authFileURL = authFileURL
        self.decoder = decoder
    }

    func importCredential() throws -> ChatGPTSubscriptionCredential {
        let candidates = authFileCandidates()
        guard let existingURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw CodexAuthFileImporterError.authFileNotFound(candidates.map(\.path))
        }

        let authFile: CodexAuthFile
        do {
            authFile = try decoder.decode(CodexAuthFile.self, from: Data(contentsOf: existingURL))
        } catch {
            throw CodexAuthFileImporterError.invalidAuthFile(existingURL.path)
        }

        let accessToken = authFile.tokens?.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard accessToken.isEmpty == false else {
            throw CodexAuthFileImporterError.missingAccessToken(existingURL.path)
        }

        let accountID = authFile.tokens?.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? Self.chatGPTAccountID(fromJWT: authFile.tokens?.idToken)
            ?? Self.chatGPTAccountID(fromJWT: accessToken)
            ?? ""
        guard accountID.isEmpty == false else {
            throw CodexAuthFileImporterError.missingAccountID(existingURL.path)
        }

        let credential = ChatGPTSubscriptionCredential(
            accessToken: accessToken,
            accountID: accountID,
            expiresAt: Self.expirationDate(fromJWT: accessToken)
                ?? Self.expirationDate(fromJWT: authFile.tokens?.idToken),
            sourceDescription: existingURL.path
        )
        guard credential.isUsable else {
            throw CodexAuthFileImporterError.expiredAccessToken(existingURL.path)
        }

        return credential
    }

    private func authFileCandidates() -> [URL] {
        if let authFileURL {
            return [authFileURL]
        }

        var urls: [URL] = []
        if let chatGPTLocalHome = environment["CHATGPT_LOCAL_HOME"], chatGPTLocalHome.isEmpty == false {
            urls.append(URL(fileURLWithPath: chatGPTLocalHome).appendingPathComponent("auth.json"))
        }
        if let codexHome = environment["CODEX_HOME"], codexHome.isEmpty == false {
            urls.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }

        let home = fileManager.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".chatgpt-local/auth.json"))
        urls.append(home.appendingPathComponent(".codex/auth.json"))

        var seen: Set<String> = []
        return urls.filter { seen.insert($0.path).inserted }
    }

    private static func chatGPTAccountID(fromJWT token: String?) -> String? {
        guard let claims = jwtClaims(from: token) else {
            return nil
        }

        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let accountID = auth["chatgpt_account_id"] as? String,
           accountID.isEmpty == false {
            return accountID
        }

        return nil
    }

    private static func expirationDate(fromJWT token: String?) -> Date? {
        guard let claims = jwtClaims(from: token),
              let expiration = claims["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: expiration)
    }

    private static func jwtClaims(from token: String?) -> [String: Any]? {
        guard let token,
              token.isEmpty == false else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)

        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return claims
    }
}

private struct CodexAuthFile: Decodable {
    var tokens: Tokens?

    struct Tokens: Decodable {
        var idToken: String?
        var accessToken: String?
        var accountID: String?

        private enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}
