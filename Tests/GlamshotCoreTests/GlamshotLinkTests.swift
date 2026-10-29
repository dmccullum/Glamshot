import Foundation
import Testing
@testable import GlamshotCore

@Suite("glamshot:// links")
struct GlamshotLinkTests {
    @Test func aBookmarkletLinkOpensItsPage() throws {
        // encodeURIComponent(location.href) in a bookmarklet.
        let link = try #require(URL(string: "glamshot://open?url=https%3A%2F%2Fexample.com%2Fa%3Fx%3D1%26y%3D2%23top"))
        #expect(GlamshotLink.page(from: link) == URL(string: "https://example.com/a?x=1&y=2#top"))
    }

    @Test func aHandTypedLinkKeepsAnUnencodedQuery() throws {
        let link = try #require(URL(string: "glamshot://open?url=https://example.com/a?x=1&y=2#top"))
        #expect(GlamshotLink.page(from: link) == URL(string: "https://example.com/a?x=1&y=2#top"))
    }

    @Test func onlyWebPagesOpen() throws {
        for target in ["file:///etc/hosts", "javascript:alert(1)", "glamshot://open", "https:"] {
            let encoded = try #require(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
            #expect(GlamshotLink.page(from: try #require(URL(string: "glamshot://open?url=\(encoded)"))) == nil)
        }
    }

    @Test func otherAddressesAreNotLinks() throws {
        #expect(GlamshotLink.page(from: try #require(URL(string: "https://example.com/?url=https://apple.com"))) == nil)
        #expect(GlamshotLink.page(from: try #require(URL(string: "glamshot://capture?url=https%3A%2F%2Fexample.com"))) == nil)
    }
}
