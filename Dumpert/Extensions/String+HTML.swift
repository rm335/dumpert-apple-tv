import Foundation

extension String {
    func strippingHTML() -> String {
        guard !self.isEmpty else { return self }

        // Remove HTML tags
        var result = self.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#x2F;": "/",
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode the remaining numeric HTML entities to their actual characters.
        // These are common in Dutch text (é = &#233;, € = &#8364;), so dropping
        // them — as this used to — mangled titles, descriptions and comments.
        result = result.decodingNumericEntities()

        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Decodes decimal (`&#233;`) and hexadecimal (`&#xE9;`) numeric character
    /// references to their Unicode scalar. A malformed or out-of-range code point
    /// is left as-is rather than dropped.
    private func decodingNumericEntities() -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#([xX])?([0-9A-Fa-f]+);") else {
            return self
        }
        var result = self
        // Replace right-to-left so each match's range stays valid in `result`
        // (only text after the match has shifted by the time we reach it).
        let matches = regex.matches(in: self, range: NSRange(startIndex..., in: self))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let digitsRange = Range(match.range(at: 2), in: self) else { continue }
            let isHex = match.range(at: 1).location != NSNotFound
            let digits = String(self[digitsRange])
            let codePoint = isHex ? Int(digits, radix: 16) : Int(digits)
            guard let codePoint, let scalar = Unicode.Scalar(codePoint) else { continue }
            result.replaceSubrange(fullRange, with: String(scalar))
        }
        return result
    }
}
