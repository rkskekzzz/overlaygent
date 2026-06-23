import ApplicationServices
import AppKit
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

protocol AXFocusedElementProviding {
    func focusedElement() throws -> AXFocusedElement
}

extension AXClient: AXFocusedElementProviding {}

protocol AXSourceBundleResolving {
    func sourceBundleID(for element: AXElement) -> String?
}

protocol AgentRunInputCapturing {
    func capture() throws -> FocusedTextCapture
}

struct FocusedTextCapture: Equatable {
    var focusedElement: AXFocusedElement
    var snapshot: TextSnapshot
    var geometry: AXTextGeometry
}

enum FocusedTextSessionError: Error, Equatable, CustomStringConvertible {
    case rejected(reason: AXTextInputRejectionReason)
    case missingSourceBundleID

    var description: String {
        switch self {
        case let .rejected(reason):
            return "Focused text session rejected: \(reason.description)"
        case .missingSourceBundleID:
            return "Focused text session rejected: missing source bundle identifier"
        }
    }
}

struct TextSnapshotHasher {
    func hash(text: String) -> String {
        let bytes = Array(text.utf8)

        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(bytes))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "fnv1a64:" + fnv1a64Hex(bytes)
        #endif
    }

    private func fnv1a64Hex(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x00000100000001b3

        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(format: "%016llx", hash)
    }
}

final class FocusedTextSession {
    private let focusedElementProvider: AXFocusedElementProviding
    private let secureFieldDetector: AXSecureFieldDetector
    private let sourceBundleResolver: AXSourceBundleResolving
    private let geometryResolver: AXGeometryResolver
    private let hasher: TextSnapshotHasher

    init(
        focusedElementProvider: AXFocusedElementProviding = AXClient(),
        secureFieldDetector: AXSecureFieldDetector = AXSecureFieldDetector(),
        sourceBundleResolver: AXSourceBundleResolving = SystemAXSourceBundleResolver(),
        geometryResolver: AXGeometryResolver = AXGeometryResolver(),
        hasher: TextSnapshotHasher = TextSnapshotHasher()
    ) {
        self.focusedElementProvider = focusedElementProvider
        self.secureFieldDetector = secureFieldDetector
        self.sourceBundleResolver = sourceBundleResolver
        self.geometryResolver = geometryResolver
        self.hasher = hasher
    }

    func snapshot() throws -> TextSnapshot {
        try capture().snapshot
    }

    func capture() throws -> FocusedTextCapture {
        let focusedElement = try focusedElementProvider.focusedElement()

        switch secureFieldDetector.guardTextInput(focusedElement) {
        case .allowed:
            break
        case let .rejected(reason):
            throw FocusedTextSessionError.rejected(reason: reason)
        }

        guard let text = focusedElement.value else {
            throw FocusedTextSessionError.rejected(reason: .missingTextValue)
        }

        guard let sourceBundleID = sourceBundleResolver.sourceBundleID(for: focusedElement.element) else {
            throw FocusedTextSessionError.missingSourceBundleID
        }

        let snapshot = TextSnapshot(
            text: text,
            selectedRange: selectedRange(from: focusedElement.selectedRange, text: text),
            sourceBundleID: sourceBundleID,
            sourceElementRole: focusedElement.role,
            contentHash: hasher.hash(text: text)
        )

        return FocusedTextCapture(
            focusedElement: focusedElement,
            snapshot: snapshot,
            geometry: geometryResolver.resolveGeometry(for: focusedElement)
        )
    }

    private func selectedRange(from axRange: AXTextRange?, text: String) -> Range<Int>? {
        guard let axRange,
              axRange.location >= 0,
              axRange.length >= 0,
              axRange.upperBound <= text.count
        else {
            return nil
        }

        return axRange.location..<axRange.upperBound
    }
}

struct SystemAXSourceBundleResolver: AXSourceBundleResolving {
    func sourceBundleID(for element: AXElement) -> String? {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(axElement, &processIdentifier) == .success else {
            return nil
        }

        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }
}
