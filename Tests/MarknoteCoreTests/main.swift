import Foundation

// A small portable runner: Command Line Tools ships Swift but not the XCTest framework.
var failures = 0
var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Expected true", line: Int = #line) {
    assertions += 1
    if !condition() { failures += 1; fputs("FAIL line \(line): \(message)\n", stderr) }
}
func expectFalse(_ condition: @autoclosure () -> Bool, line: Int = #line) { expect(!condition(), "Expected false", line: line) }
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, line: Int = #line) { expect(lhs == rhs, "\(lhs) != \(rhs)", line: line) }
func expectNil<T>(_ value: T?, line: Int = #line) { expect(value == nil, "Expected nil", line: line) }

let suite = MarkdownTests()
let localization = LocalizationTests()
let editing = EditingToolsTests()
let tests: [(String, () throws -> Void)] = [
    ("CommonMark and GFM", suite.testCommonMarkAndGFM),
    ("HTML and unsafe links", suite.testHTMLAndUnsafeLinksAreInert),
    ("Nested lists, reference links and escapes", suite.testNestedListsReferenceLinksAndEscapes),
    ("Local image containment", suite.testImagesStayWithinDocumentDirectory),
    ("Outline and fenced code", suite.testOutlineExcludesFencedAndIndentedCode),
    ("Unicode formatting and toggle", suite.testUnicodeFormattingAndToggle),
    ("Selected line boundaries", suite.testSelectedLineBoundaries),
    ("List continuation and exit", suite.testListContinuationAndExit),
    ("CJK and Latin word counts", suite.testWordCountHandlesCJKAndLatin),
    ("Standalone export and empty state", suite.testStandaloneExportAndEmptyPreview),
    ("Smart URL paste", editing.testSmartLinks),
    ("Command search matching", editing.testSearchMatching),
    ("Table formatting", editing.testTableFormatting),
    ("Table keyboard navigation", editing.testTableNavigation),
    ("Local image attachment storage", editing.testAttachmentStorage),
    ("System language resolution", localization.testSystemLanguageResolution),
    ("Language persistence and notifications", localization.testPreferencePersistenceAndNotifications),
    ("Translation coverage and formats", localization.testEveryTranslationAndFormatIsAvailable)
]
for (name, test) in tests {
    let before = failures
    do { try test() } catch { failures += 1; fputs("FAIL \(name): \(error)\n", stderr) }
    print("\(before == failures ? "PASS" : "FAIL"): \(name)")
}
print("\(tests.count) tests, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
