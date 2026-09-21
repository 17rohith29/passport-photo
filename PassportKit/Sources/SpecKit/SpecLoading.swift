import Foundation

/// Parses a `yyyy-MM-dd` date without pulling in a locale-sensitive formatter.
enum DateOnly {
    static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

public struct SpecValidationError: Error, CustomStringConvertible, Equatable {
    public var issues: [String]
    public var description: String {
        "Invalid document spec:\n" + issues.map { "  • \($0)" }.joined(separator: "\n")
    }
}

public enum SpecLoadError: Error, CustomStringConvertible {
    case fileNotReadable(URL, underlying: Error)
    case malformedJSON(String)
    case invalid(SpecValidationError)

    public var description: String {
        switch self {
        case let .fileNotReadable(url, underlying):
            return "Could not read spec at \(url.path): \(underlying.localizedDescription)"
        case let .malformedJSON(message):
            return "Spec JSON could not be decoded: \(message)"
        case let .invalid(error):
            return error.description
        }
    }
}

public enum SpecLoader {
    /// Decode and validate a spec from raw JSON.
    public static func load(data: Data) throws -> DocumentSpec {
        let spec: DocumentSpec
        do {
            spec = try JSONDecoder().decode(DocumentSpec.self, from: data)
        } catch {
            throw SpecLoadError.malformedJSON(Self.readable(error))
        }
        do {
            try spec.validate()
        } catch let error as SpecValidationError {
            throw SpecLoadError.invalid(error)
        }
        return spec
    }

    /// Decode and validate a spec from a file URL.
    public static func load(contentsOf url: URL) throws -> DocumentSpec {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SpecLoadError.fileNotReadable(url, underlying: error)
        }
        return try load(data: data)
    }

    /// Turn a `DecodingError` into a message that names the field, so a bad spec is easy to fix.
    static func readable(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "\(error)" }
        func path(_ context: DecodingError.Context) -> String {
            let p = context.codingPath.map(\.stringValue).joined(separator: ".")
            return p.isEmpty ? "(root)" : p
        }
        switch decoding {
        case let .keyNotFound(key, ctx):
            return "missing required field '\(key.stringValue)' at \(path(ctx))"
        case let .typeMismatch(type, ctx):
            return "wrong type for '\(path(ctx))' (expected \(type))"
        case let .valueNotFound(type, ctx):
            return "missing value for '\(path(ctx))' (expected \(type))"
        case let .dataCorrupted(ctx):
            return "corrupted value at '\(path(ctx))': \(ctx.debugDescription)"
        @unknown default:
            return "\(decoding)"
        }
    }
}

public extension DocumentSpec {
    /// Semantic checks the JSON schema expresses but `Codable` cannot enforce. Collects every
    /// problem so one load reports all of them, not just the first.
    func validate() throws {
        var issues: [String] = []

        if schemaVersion != 1 {
            issues.append("schemaVersion must be 1, got \(schemaVersion)")
        }
        if id.range(of: "^[a-z0-9-]+$", options: .regularExpression) == nil {
            issues.append("id '\(id)' must match ^[a-z0-9-]+$")
        }
        if country.code.range(of: "^[A-Z]{2}$", options: .regularExpression) == nil {
            issues.append("country.code '\(country.code)' must be two uppercase letters")
        }
        if DateOnly.parse(status.lastVerified) == nil {
            issues.append("status.lastVerified '\(status.lastVerified)' is not a yyyy-MM-dd date")
        }

        // digital: exactly one of sizePx / sizePxRange
        switch (photo.digital.sizePx, photo.digital.sizePxRange) {
        case (nil, nil):
            issues.append("photo.digital must have either sizePx or sizePxRange")
        case (.some, .some):
            issues.append("photo.digital must not have both sizePx and sizePxRange")
        default:
            break
        }
        if let range = photo.digital.sizePxRange {
            if range.max.width < range.min.width || range.max.height < range.min.height {
                issues.append("photo.digital.sizePxRange max must be >= min")
            }
        }
        checkRange(photo.digital.fileSizeKB, "photo.digital.fileSizeKB", &issues)

        // headHeight: at least one of passMM / passFraction
        if geometry.headHeight.passMM == nil && geometry.headHeight.passFraction == nil {
            issues.append("geometry.headHeight must have passMM or passFraction")
        }
        checkRange(geometry.headHeight.passMM, "geometry.headHeight.passMM", &issues)
        checkRange(geometry.headHeight.passFraction, "geometry.headHeight.passFraction", &issues)
        checkRange(geometry.topMargin?.passMM, "geometry.topMargin.passMM", &issues)
        if let eye = geometry.eyeLine, eye.fromBottomFraction == nil && eye.fromBottomMM == nil {
            issues.append("geometry.eyeLine must have fromBottomFraction or fromBottomMM")
        }
        checkRange(geometry.eyeLine?.fromBottomFraction, "geometry.eyeLine.fromBottomFraction", &issues)
        checkRange(geometry.eyeLine?.fromBottomMM, "geometry.eyeLine.fromBottomMM", &issues)

        if let bg = background,
           bg.colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
            issues.append("background.colorHex '\(bg.colorHex)' must be #RRGGBB")
        }
        if sources.isEmpty {
            issues.append("sources must not be empty")
        }

        if !issues.isEmpty {
            throw SpecValidationError(issues: issues)
        }
    }

    private func checkRange(_ range: Range?, _ name: String, _ issues: inout [String]) {
        guard let range else { return }
        if range.max < range.min {
            issues.append("\(name) max (\(range.max)) must be >= min (\(range.min))")
        }
    }
}
