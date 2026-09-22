import Foundation

/// Locates repo-root files (`specs/`, `fixtures/`) from tests. The package lives at
/// `<repo>/PassportKit`, so walk up from this file until a directory holds both.
public enum RepoPaths {
    public static let root: URL? = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let specs = dir.appendingPathComponent("specs/document-spec.schema.json")
            if FileManager.default.fileExists(atPath: specs.path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    public static var specs: URL? { root?.appendingPathComponent("specs") }
    public static var fixtures: URL? { root?.appendingPathComponent("fixtures") }
    public static var fixturePhotos: URL? { fixtures?.appendingPathComponent("photos") }
    /// Third-party portraits used only to calibrate thresholds. Gitignored; absent on a clone.
    public static var calibrationPhotos: URL? { fixtures?.appendingPathComponent("calibration") }

    public static var hasCalibrationPhotos: Bool {
        guard let dir = calibrationPhotos else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.lowercased().hasSuffix(".jpg") }
    }

    public static var inPassportSpec: URL? { specs?.appendingPathComponent("in-passport.json") }
    public static var usPassportSpec: URL? { specs?.appendingPathComponent("us-passport.json") }
    public static var squareTestSpec: URL? { specs?.appendingPathComponent("test/fixture-square.json") }
    public static var expectedJSON: URL? { fixtures?.appendingPathComponent("expected.json") }

    /// `fixtures/photos/` is the owner's face and is gitignored. Tests that need it skip
    /// cleanly when it is absent (for example on a fresh clone or in CI).
    public static var hasFixturePhotos: Bool {
        guard let dir = fixturePhotos else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue
        else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.lowercased().hasSuffix(".heic") || $0.lowercased().hasSuffix(".jpg") }
    }

    public static var skipReason: String {
        "fixtures/photos is missing (it is gitignored; copy the owner's photos in to run these)."
    }
}
