import Testing
import Foundation
@testable import Dumpert

/// Resolves the shipped `Sounds.json`, which is bundled into the test target
/// (see project.yml) so the real manifest is validated, not a copy.
private final class BundleToken {}

@Suite("Loading sound NSFW classification")
struct LoadingSoundCatalogTests {

    private func sampleCatalog() -> LoadingSoundCatalog {
        LoadingSoundCatalog(entries: [
            LoadingSoundCatalog.Entry(file: "safe-a.mp3", nsfw: false),
            LoadingSoundCatalog.Entry(file: "safe-b.mp3", nsfw: false),
            LoadingSoundCatalog.Entry(file: "rude.mp3", nsfw: true)
        ])
    }

    @Test("Safe-for-work sounds are eligible regardless of the NSFW preference")
    func safeAlwaysEligible() {
        let catalog = sampleCatalog()
        #expect(catalog.isSafe(filename: "safe-a.mp3"))
        #expect(catalog.eligible(["safe-a.mp3"], allowNSFW: false) == ["safe-a.mp3"])
        #expect(catalog.eligible(["safe-a.mp3"], allowNSFW: true) == ["safe-a.mp3"])
    }

    @Test("NSFW sounds are withheld when NSFW is hidden, allowed when shown")
    func nsfwGatedByPreference() {
        let catalog = sampleCatalog()
        #expect(catalog.isNSFW(filename: "rude.mp3"))
        #expect(catalog.eligible(["rude.mp3"], allowNSFW: false).isEmpty)
        #expect(catalog.eligible(["rude.mp3"], allowNSFW: true) == ["rude.mp3"])
    }

    @Test("Unknown (unclassified) sounds are withheld while NSFW is hidden")
    func unknownTreatedAsUnsafe() {
        let catalog = sampleCatalog()
        #expect(catalog.isSafe(filename: "mystery.mp3") == false)
        #expect(catalog.eligible(["mystery.mp3"], allowNSFW: false).isEmpty)
        // ...but they still play when NSFW is allowed, so nothing is lost there.
        #expect(catalog.eligible(["mystery.mp3"], allowNSFW: true) == ["mystery.mp3"])
    }

    @Test("Mixed pool keeps only safe sounds when NSFW is hidden")
    func mixedPoolFiltered() {
        let catalog = sampleCatalog()
        let pool = ["safe-a.mp3", "rude.mp3", "safe-b.mp3", "mystery.mp3"]
        #expect(catalog.eligible(pool, allowNSFW: false) == ["safe-a.mp3", "safe-b.mp3"])
        #expect(catalog.eligible(pool, allowNSFW: true) == pool)
    }

    @Test("An empty catalog fails safe — withholds everything while NSFW is hidden")
    func emptyCatalogFailsSafe() {
        let catalog = LoadingSoundCatalog(entries: [])
        #expect(catalog.eligible(["anything.mp3"], allowNSFW: false).isEmpty)
        #expect(catalog.eligible(["anything.mp3"], allowNSFW: true) == ["anything.mp3"])
    }

    // MARK: - Shipped manifest

    @Test("Shipped Sounds.json classifies the explicit-profanity sounds as NSFW")
    func shippedManifestFlagsKnownNSFW() {
        let catalog = LoadingSoundCatalog.bundled(bundle: Bundle(for: BundleToken.self))
        let knownNSFW = [
            "he-vieze-tiefuslijer.mp3",
            "hoeren-kut-kankerzooi.mp3",
            "ik-ben-een-eerste-klas-hoerenloper.mp3",
            "ik-sloop-die-hele-kanker-kamer.mp3",
            "vuile-vieze-kk-lijer.mp3"
        ]
        for file in knownNSFW {
            #expect(catalog.isNSFW(filename: file), "Expected \(file) to be NSFW")
            #expect(catalog.isSafe(filename: file) == false, "\(file) must not be in the SFW allowlist")
        }
        // None of the NSFW sounds may pass while NSFW is hidden.
        #expect(catalog.eligible(knownNSFW, allowNSFW: false).isEmpty)
    }

    @Test("Shipped Sounds.json keeps harmless sounds safe-for-work")
    func shippedManifestKeepsSafeSounds() {
        let catalog = LoadingSoundCatalog.bundled(bundle: Bundle(for: BundleToken.self))
        let knownSafe = [
            "pizza-maar-ik-heb-al-heel-veel-pizza-gegeten.mp3",
            "gratis-g-r-a-t-i-s.mp3",
            "nou-nee.mp3",
            "you-speak-nederlands.mp3"
        ]
        for file in knownSafe {
            #expect(catalog.isSafe(filename: file), "Expected \(file) to be safe-for-work")
        }
        #expect(catalog.eligible(knownSafe, allowNSFW: false) == knownSafe)
    }
}
