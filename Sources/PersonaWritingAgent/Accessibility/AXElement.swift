import CoreGraphics
import Foundation

struct AXElement: Hashable {
    let rawValue: AnyObject

    init(_ rawValue: AnyObject) {
        self.rawValue = rawValue
    }

    static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        lhs.rawValue === rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(rawValue))
    }
}

struct AXTextRange: Equatable {
    var location: Int
    var length: Int

    var upperBound: Int {
        location + length
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: CFRange) {
        self.location = range.location
        self.length = range.length
    }
}

struct AXFocusedElement: Equatable {
    var element: AXElement
    var role: String?
    var subrole: String?
    var value: String?
    var selectedRange: AXTextRange?
    var frame: CGRect? = nil
}
