import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

@MainActor
struct RuleNoticeTests {
    private func application(rule: Rule) -> RuleApplication {
        RuleApplication(file: scheduledFile(expiresIn: 60), ruleId: rule.id, ruleName: rule.name)
    }

    @Test func defaultRuleShowsItsLocalizedName() throws {
        let rules = Rule.defaults(home: "/Users/me")
        let images = try #require(rules.first { $0.name == "Images" })
        let name = RuleNoticeView.ruleName(for: application(rule: images), in: rules)
        #expect(name == RuleSummary.displayName(for: images))
    }

    @Test func renamedRuleShowsItsCurrentName() {
        var rule = Rule(name: "Old", match: .pattern("*.ics"), duration: 60)
        let applied = application(rule: rule)
        rule.name = "New"
        #expect(RuleNoticeView.ruleName(for: applied, in: [rule]) == "New")
    }

    @Test func deletedRuleFallsBackToTheReportedName() {
        let rule = Rule(name: "Gone", match: .pattern("*.ics"), duration: 60)
        #expect(RuleNoticeView.ruleName(for: application(rule: rule), in: []) == "Gone")
    }
}
