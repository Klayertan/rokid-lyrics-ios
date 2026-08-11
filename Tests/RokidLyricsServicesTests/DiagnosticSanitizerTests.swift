import Foundation
import RokidLyricsServices
import Testing

@Suite("Diagnostic sanitizer")
struct DiagnosticSanitizerTests {
    @Test("redacts credentials, callback queries, home folders, and email addresses")
    func redactsSensitiveShapes() {
        let input =
            "token=abc123 callback cxrl://auth/callback?token=secret "
            + "at /Users/TestPerson/file for tester@example.test"

        let output = DiagnosticSanitizer.sanitizedError(input)

        #expect(output?.contains("abc123") == false)
        #expect(output?.contains("?token=secret") == false)
        #expect(output?.contains("TestPerson") == false)
        #expect(output?.contains("tester@example.test") == false)
        #expect(output?.contains("<redacted>") == true)
    }

    @Test("public URLs retain location but remove sensitive components")
    func sanitizesPublicURL() {
        let output = DiagnosticSanitizer.sanitizedPublicURL(
            "https://user:pass@example.test/catalog/song?token=secret#account"
        )

        #expect(output == "https://example.test/catalog/song")
    }

    @Test("rejects non-web URLs")
    func rejectsNonWebURL() {
        #expect(DiagnosticSanitizer.sanitizedPublicURL("cxrl://auth/callback?token=secret") == nil)
    }

    @Test("bounds arbitrary error text")
    func boundsErrorText() {
        let output = DiagnosticSanitizer.sanitizedError(String(repeating: "x ", count: 450))
        #expect(output?.count == 501)
        #expect(output?.hasSuffix("…") == true)
    }
}
