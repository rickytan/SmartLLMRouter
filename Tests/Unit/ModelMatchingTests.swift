import XCTest
@testable import SmartLLMRouter

/// Unit tests for `ModelSwitcher.modelMatches` / `modelMatchScore` fuzzy matching.
final class ModelMatchingTests: XCTestCase {
    // MARK: - Exact

    func testExactMatch() {
        XCTAssertTrue(ModelSwitcher.modelMatches(requested: "gpt-4o", stored: "gpt-4o"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "gpt-4o", stored: "gpt-4o"), .exact)
    }

    // MARK: - Provider prefix

    func testProviderPrefixStripped() {
        XCTAssertTrue(ModelSwitcher.modelMatches(requested: "z-ai/glm-5.1", stored: "glm-5.1"))
        XCTAssertTrue(ModelSwitcher.modelMatches(requested: "glm-5.1", stored: "z-ai/glm-5.1"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "z-ai/glm-5.1", stored: "glm-5.1"), .exact)
    }

    // MARK: - Normalized

    func testNormalizedMatch() {
        XCTAssertTrue(ModelSwitcher.modelMatches(requested: "gpt-4o", stored: "gpt_4o"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "gpt-4o", stored: "GPT_4O"), .normalized)
    }

    // MARK: - Prefix (base name + build/date suffix)

    func testPrefixBuildSuffixMatch() {
        // User scenario: request "glm-5.2" matches a channel model "glm-5-2-260717".
        XCTAssertTrue(ModelSwitcher.modelMatches(requested: "glm-5.2", stored: "glm-5-2-260717"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "glm-5.2", stored: "glm-5-2-260717"), .prefix)
    }

    func testDifferentModelSuffixDoesNotMatch() {
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4", stored: "gpt-4o"))
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4o", stored: "gpt-4"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "gpt-4", stored: "gpt-4o"), .none)
    }

    // MARK: - No match

    func testNoMatchForUnrelatedModels() {
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4", stored: "claude-3-5-sonnet"))
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4", stored: "glm-5-2-260717"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "gpt-4", stored: "claude-3-5-sonnet"), .none)
    }

    func testDifferentMinorVersionDoesNotMatch() {
        // "glm-5.2" must NOT match "glm-5-5-..." (different minor version) -- this is why
        // we use prefix matching instead of subsequence.
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "glm-5.2", stored: "glm-5-5-260617"))
        XCTAssertEqual(ModelSwitcher.modelMatchScore(requested: "glm-5.2", stored: "glm-5-5-260617"), .none)
    }

    func testShortNeedleDoesNotMatch() {
        // "g" alone is too short; must not match "gpt-4o".
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "g", stored: "gpt-4o"))
    }

    func testShortNumericSuffixDoesNotMatch() {
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4", stored: "gpt-4-1"))
        XCTAssertFalse(ModelSwitcher.modelMatches(requested: "gpt-4", stored: "gpt-42024"))
    }

    // MARK: - Score ordering

    func testExactBeatsPrefixScore() {
        let exact = ModelSwitcher.modelMatchScore(requested: "gpt-4o", stored: "gpt-4o")
        let prefix = ModelSwitcher.modelMatchScore(requested: "glm-5.2", stored: "glm-5-2-260717")
        XCTAssertGreaterThan(exact, prefix)
    }

    func testNormalizedBeatsPrefixScore() {
        let normalized = ModelSwitcher.modelMatchScore(requested: "gpt-4o", stored: "gpt_4o")
        let prefix = ModelSwitcher.modelMatchScore(requested: "glm-5.2", stored: "glm-5-2-260717")
        XCTAssertGreaterThan(normalized, prefix)
    }
}
