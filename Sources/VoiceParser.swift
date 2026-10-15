import Foundation

struct ParsedTask {
    var title: String
    var details: String
    var due: Date?
}

/// Exemple dicté : « Appeler le dentiste demain à 15h, description : demander un devis »
/// → titre « Appeler le dentiste », rappel demain 15h, détails « Demander un devis ».
enum VoiceParser {
    static func parse(_ raw: String) -> ParsedTask {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var main = text
        var details = ""

        // 1. Description explicite : "description", "détails", "précision"
        if let r = text.range(of: #"(?i)\b(description|détails?|précisions?)\b\s*:?\s*"#,
                              options: .regularExpression) {
            main = String(text[..<r.lowerBound])
            details = String(text[r.upperBound...])
        }

        // 2. Date / heure détectée dans la langue du téléphone
        var title = main
        var due: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = main as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = detector.matches(in: main, range: range).first, let date = m.date {
                due = date
                let before = ns.substring(to: m.range.location)
                let after = ns.substring(from: m.range.location + m.range.length)
                if clean(before).isEmpty {
                    title = after                       // « Demain à 15h appeler Paul »
                } else {
                    title = before
                    if details.isEmpty { details = after } // texte après la date = description
                }
            }
        }
        return ParsedTask(title: clean(title), details: clean(details), due: due)
    }

    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters))
        for w in [" à", " le", " pour", " et", " de"] where t.lowercased().hasSuffix(w) {
            t = String(t.dropLast(w.count)).trimmingCharacters(in: .whitespaces)
        }
        guard let f = t.first else { return "" }
        return f.uppercased() + t.dropFirst()
    }
}
