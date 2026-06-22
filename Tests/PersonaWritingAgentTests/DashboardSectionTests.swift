import XCTest
@testable import PersonaWritingAgent

final class DashboardSectionTests: XCTestCase {
    func testDashboardSectionsMatchPRDOrder() {
        XCTAssertEqual(
            DashboardSection.allCases.map(\.title),
            [
                "General",
                "LLM Provider",
                "Agents",
                "App Rules",
                "Privacy",
                "Diagnostics"
            ]
        )
    }

    func testDashboardSectionsHaveSidebarIconNames() {
        for section in DashboardSection.allCases {
            XCTAssertFalse(section.systemImageName.isEmpty)
        }
    }
}
