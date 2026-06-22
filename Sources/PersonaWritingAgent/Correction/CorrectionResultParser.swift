import Foundation

struct CorrectionResult: Codable, Equatable {
    var summary: String?
    var edits: [CorrectionEdit]
    var fullRewrite: String?

    init(
        summary: String? = nil,
        edits: [CorrectionEdit] = [],
        fullRewrite: String? = nil
    ) {
        self.summary = summary
        self.edits = edits
        self.fullRewrite = fullRewrite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            edits: try container.decodeIfPresent([CorrectionEdit].self, forKey: .edits) ?? [],
            fullRewrite: try container.decodeIfPresent(String.self, forKey: .fullRewrite)
        )
    }
}

struct CorrectionEdit: Codable, Equatable {
    var rangeStart: Int
    var rangeEnd: Int
    var original: String
    var replacement: String
    var reason: String

    var range: Range<Int> {
        rangeStart..<rangeEnd
    }
}

enum CorrectionResultParserError: Error, Equatable {
    case jsonObjectNotFound
    case malformedJSON(String)
    case missingUsableFields
    case invalidRange(editIndex: Int, start: Int, end: Int)
    case emptyOriginal(editIndex: Int)
}

struct CorrectionResultParser {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func parse(_ providerResponse: String) throws -> CorrectionResult {
        let candidates = jsonCandidates(from: providerResponse)
        guard candidates.isEmpty == false else {
            if providerResponse.contains("{") {
                throw CorrectionResultParserError.malformedJSON("No complete JSON object found.")
            }

            throw CorrectionResultParserError.jsonObjectNotFound
        }

        var decodeError: Error?
        for candidate in candidates {
            do {
                let result = try decoder.decode(CorrectionResult.self, from: Data(candidate.utf8))
                try validate(result)
                return normalized(result)
            } catch let error as CorrectionResultParserError {
                throw error
            } catch {
                decodeError = error
            }
        }

        throw CorrectionResultParserError.malformedJSON(
            decodeError.map { String(describing: $0) } ?? "Unable to decode correction result JSON."
        )
    }

    private func validate(_ result: CorrectionResult) throws {
        for (index, edit) in result.edits.enumerated() {
            guard edit.rangeStart >= 0, edit.rangeEnd >= edit.rangeStart else {
                throw CorrectionResultParserError.invalidRange(
                    editIndex: index,
                    start: edit.rangeStart,
                    end: edit.rangeEnd
                )
            }

            guard edit.original.isEmpty == false else {
                throw CorrectionResultParserError.emptyOriginal(editIndex: index)
            }
        }

        guard result.edits.isEmpty == false || nonEmptyText(result.fullRewrite) != nil else {
            throw CorrectionResultParserError.missingUsableFields
        }
    }

    private func normalized(_ result: CorrectionResult) -> CorrectionResult {
        CorrectionResult(
            summary: nonEmptyText(result.summary),
            edits: result.edits,
            fullRewrite: nonEmptyText(result.fullRewrite)
        )
    }

    private func nonEmptyText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func jsonCandidates(from providerResponse: String) -> [String] {
        var candidates = fencedJSONBlocks(in: providerResponse)
        if let jsonObject = firstBalancedJSONObject(in: providerResponse),
           candidates.contains(jsonObject) == false {
            candidates.append(jsonObject)
        }

        return candidates
    }

    private func fencedJSONBlocks(in providerResponse: String) -> [String] {
        let pattern = #"```[ \t]*(?:json)?[ \t]*\r?\n([\s\S]*?)```"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(providerResponse.startIndex..<providerResponse.endIndex, in: providerResponse)

        return regex?.matches(in: providerResponse, range: range).compactMap { match in
            guard let blockRange = Range(match.range(at: 1), in: providerResponse) else {
                return nil
            }

            return firstBalancedJSONObject(in: String(providerResponse[blockRange]))
        } ?? []
    }

    private func firstBalancedJSONObject(in text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            guard let objectStartIndex = startIndex else {
                if character == "{" {
                    startIndex = currentIndex
                    depth = 1
                }

                currentIndex = text.index(after: currentIndex)
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                switch character {
                case "\"":
                    isInsideString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[objectStartIndex...currentIndex])
                    }
                default:
                    break
                }
            }

            currentIndex = text.index(after: currentIndex)
        }

        return nil
    }
}
