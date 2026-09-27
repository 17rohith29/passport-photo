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

        if let bg = background {
            if bg.colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
                issues.append("background.colorHex '\(bg.colorHex)' must be #RRGGBB")
            }
            // The schema bounds this 0-255 but Codable does not enforce it, and the value is
            // converted straight to UInt8 when checking a finished photo, out of range it traps
            // and takes the app with it. A country file must not be able to crash the app.
            if let value = bg.minChannelValue, value < 0 || value > 255 {
                issues.append("background.minChannelValue \(value) must be between 0 and 255")
            }
            // A spec whose own background colour is darker than its own purity floor can never
            // pass its own background check: every correct photo would be failed, and the user
            // would be blamed for it.
            if let value = bg.minChannelValue, let darkest = darkestChannel(bg.colorHex) {
                if darkest < value {
                    issues.append(
                        "background.colorHex \(bg.colorHex) has a darkest channel of \(darkest), "
                        + "below background.minChannelValue \(value); no photo could ever pass"
                    )
                }
            }
        }

        // The renderer never upscales (LESSONS 3), so a spec that permits it would be stating
        // a rule the app does not implement. Rejected rather than silently ignored.
        if input?.allowUpscaling == true {
            issues.append("input.allowUpscaling must be false: the app never upscales")
        }

        // Sizes and dpi are multiplied out into pixel counts and buffer allocations.
        checkPositive(photo.sizeMM.width, "photo.sizeMM.width", &issues, max: 1000)
        checkPositive(photo.sizeMM.height, "photo.sizeMM.height", &issues, max: 1000)
        checkPositive(photo.print.dpi, "photo.print.dpi", &issues, max: 2400)
        if let dpi = photo.digital.dpi { checkPositive(dpi, "photo.digital.dpi", &issues, max: 2400) }
        if let size = photo.digital.sizePx {
            checkPositive(size.width, "photo.digital.sizePx.width", &issues, max: 20000)
            checkPositive(size.height, "photo.digital.sizePx.height", &issues, max: 20000)
        }
        if let range = photo.digital.sizePxRange {
            checkPositive(range.min.width, "photo.digital.sizePxRange.min.width", &issues, max: 20000)
            checkPositive(range.min.height, "photo.digital.sizePxRange.min.height", &issues, max: 20000)
            checkPositive(range.max.width, "photo.digital.sizePxRange.max.width", &issues, max: 20000)
            checkPositive(range.max.height, "photo.digital.sizePxRange.max.height", &issues, max: 20000)
        }
        if let copies = photo.print.copiesRequired, copies < 1 {
            issues.append("photo.print.copiesRequired must be at least 1, got \(copies)")
        }

        // A head taller than the photo, or a negative one, makes the crop maths meaningless.
        if let band = geometry.headHeight.passMM {
            if band.min <= 0 { issues.append("geometry.headHeight.passMM.min must be positive") }
            if band.max > photo.sizeMM.height {
                issues.append("geometry.headHeight.passMM.max (\(band.max)) exceeds the photo height (\(photo.sizeMM.height))")
            }
        }
        if let fraction = geometry.headHeight.passFraction {
            if fraction.min <= 0 || fraction.max > 1 {
                issues.append("geometry.headHeight.passFraction must lie within 0-1, got \(fraction.min)-\(fraction.max)")
            }
        }
        if let target = geometry.headHeight.targetMM, target <= 0 || target > photo.sizeMM.height {
            issues.append("geometry.headHeight.targetMM \(target) must be positive and fit the photo")
        }
        if sources.isEmpty {
            issues.append("sources must not be empty")
        }

        if !issues.isEmpty {
            throw SpecValidationError(issues: issues)
        }
    }

    /// Countries are data, so a data file must not be able to take the app down. Positive and
    /// finite is not enough: these values are multiplied into pixel counts and buffer lengths,
    /// and Int(1e30) traps (LESSONS 24).
    /// The darkest of the three channels in `#RRGGBB`, or nil if it does not parse.
    private func darkestChannel(_ hex: String) -> Int? {
        let digits = hex.dropFirst()
        guard hex.hasPrefix("#"), digits.count == 6, let value = UInt32(digits, radix: 16)
        else { return nil }
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
        return channels.min().map(Int.init)
    }

    private func checkPositive(
        _ value: Double, _ name: String, _ issues: inout [String], max limit: Double = 1e5
    ) {
        if !value.isFinite || value <= 0 {
            issues.append("\(name) must be a positive, finite number, got \(value)")
        } else if value > limit {
            issues.append("\(name) must be at most \(Int(limit)), got \(value)")
        }
    }

    private func checkRange(_ range: Range?, _ name: String, _ issues: inout [String]) {
        guard let range else { return }
        if range.max < range.min {
            issues.append("\(name) max (\(range.max)) must be >= min (\(range.min))")
        }
    }
}
