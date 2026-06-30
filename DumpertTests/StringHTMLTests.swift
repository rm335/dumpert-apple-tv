import Testing
@testable import Dumpert

/// Tests for String.strippingHTML(), which decodes API titles, descriptions and
/// comments. Numeric character references are common in Dutch text, so they must
/// be decoded to real characters — not dropped, as the old delete-regex did.
@Suite("String+HTML Tests")
struct StringHTMLTests {

    @Test("Decodes decimal numeric entities (é, €)")
    func decodesDecimalEntities() {
        #expect("caf&#233;".strippingHTML() == "café")
        #expect("prijs &#8364;5".strippingHTML() == "prijs €5")
    }

    @Test("Decodes hexadecimal numeric entities")
    func decodesHexEntities() {
        #expect("caf&#xE9;".strippingHTML() == "café")
        #expect("&#x20AC;10".strippingHTML() == "€10")
    }

    @Test("Still decodes named entities and existing special cases")
    func decodesNamedEntities() {
        #expect("Tom &amp; Jerry".strippingHTML() == "Tom & Jerry")
        #expect("a&#39;b".strippingHTML() == "a'b")
    }

    @Test("Leaves an out-of-range numeric entity untouched instead of dropping it")
    func leavesOutOfRangeEntity() {
        // 1114112 == 0x110000 is one past the max Unicode scalar — not decodable,
        // so it must be preserved rather than silently deleted (and must not crash).
        #expect("x&#1114112;y".strippingHTML() == "x&#1114112;y")
    }

    @Test("Strips HTML tags around decoded text")
    func stripsTags() {
        #expect("<b>caf&#233;</b>".strippingHTML() == "café")
    }
}
