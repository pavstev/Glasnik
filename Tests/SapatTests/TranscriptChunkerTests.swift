import XCTest
@testable import Sapat

/// Verifies the long-transcript splitter: every chunk stays within the size budget and the
/// whole transcript survives the round trip. This is the core of the "the whole recording
/// gets refined, not just the tail" guarantee.
final class TranscriptChunkerTests: XCTestCase {

    // MARK: Token estimate

    func testEstimateIsPositiveAndMonotonic() {
        XCTAssertGreaterThan(TranscriptChunker.estimateTokens("hello"), 0)
        XCTAssertGreaterThan(
            TranscriptChunker.estimateTokens(String(repeating: "a", count: 100)),
            TranscriptChunker.estimateTokens(String(repeating: "a", count: 10))
        )
    }

    func testEstimateOverCountsToStaySafe() {
        // ~2.5 chars/token: 100 chars -> 40 tokens. An over-estimate is the safe direction.
        XCTAssertEqual(TranscriptChunker.estimateTokens(String(repeating: "x", count: 100)), 40)
    }

    // MARK: Splitting

    func testEmptyOrWhitespaceYieldsNoChunks() {
        XCTAssertTrue(TranscriptChunker.split("", maxChars: 50).isEmpty)
        XCTAssertTrue(TranscriptChunker.split("   \n\t ", maxChars: 50).isEmpty)
    }

    func testShortTextStaysOneChunk() {
        let text = "Ovo je kratka recenica."
        XCTAssertEqual(TranscriptChunker.split(text, maxChars: 100), [text])
    }

    func testLongTextSplitsIntoMultipleChunks() {
        let text = "Prva recenica je ovde. Druga recenica je malo duza. Treca recenica zatvara misao."
        let chunks = TranscriptChunker.split(text, maxChars: 30)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testEveryChunkRespectsTheLimit() {
        let text = String(repeating: "Ovo je jedna recenica koja se ponavlja. ", count: 20)
        let limit = 80
        for chunk in TranscriptChunker.split(text, maxChars: limit) {
            XCTAssertLessThanOrEqual(chunk.count, limit, "chunk exceeded the limit: \(chunk)")
        }
    }

    func testSplitsOnSentenceBoundaries() {
        // "A je tu." is 8 chars; two of them plus a space is exactly 17, so a 17-char limit
        // packs whole sentences two at a time and never breaks mid-sentence.
        let chunks = TranscriptChunker.split("A je tu. B je tu. C je tu. D je tu.", maxChars: 17)
        XCTAssertEqual(chunks, ["A je tu. B je tu.", "C je tu. D je tu."])
    }

    func testAllContentSurvivesTheRoundTrip() {
        let text = """
        Prva ideja je da sistem mora da obradi ceo snimak. Druga ideja, koja je vazna, \
        jeste da se ne sme izgubiti pocetak. Treca stvar je da LM Studio uvek mora da radi. \
        I na kraju, sve mora da se sklopi u jednu recenicu.
        """
        let chunks = TranscriptChunker.split(text, maxChars: 40)
        XCTAssertEqual(normalize(chunks.joined(separator: " ")), normalize(text))
    }

    func testRunOnSentenceIsHardSplitOnWords() {
        // No terminal punctuation: one long "sentence" split on word boundaries.
        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        let limit = 20
        let chunks = TranscriptChunker.split(text, maxChars: limit)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, limit)
        }
        XCTAssertEqual(normalize(chunks.joined(separator: " ")), normalize(text))
    }

    func testGiantWordIsCharacterSplitAsLastResort() {
        let word = String(repeating: "z", count: 50)
        let chunks = TranscriptChunker.split(word, maxChars: 10)
        XCTAssertTrue(chunks.count >= 5)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 10)
        }
        // A single unbreakable word: concatenated pieces reproduce it exactly.
        XCTAssertEqual(chunks.joined(), word)
    }

    // MARK: Helpers

    /// Collapse runs of whitespace to single spaces so comparisons ignore reflow.
    private func normalize(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
