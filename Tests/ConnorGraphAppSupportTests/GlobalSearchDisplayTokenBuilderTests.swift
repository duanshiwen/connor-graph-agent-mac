import Testing
@testable import ConnorGraphAppSupport

@Suite("Global Search Display Token Builder Tests")
struct GlobalSearchDisplayTokenBuilderTests {
    @Test func travelCostQuestionHidesLowValueFillerTokens() {
        let tokens = GlobalSearchDisplayTokenBuilder.tokens(for: "去雅加达玩一个星期需要多少钱")

        #expect(tokens.contains("雅加达"))
        #expect(!tokens.contains("一个"))
        #expect(!tokens.contains("星期"))
        #expect(!tokens.contains("需要"))
        #expect(!tokens.contains("多少"))
    }

    @Test func allFilteredQueriesFallBackToSearchableTokens() {
        let tokens = GlobalSearchDisplayTokenBuilder.tokens(for: "现在星期几")

        #expect(!tokens.isEmpty)
    }
}
