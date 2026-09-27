import Foundation
import Testing
import TestSupport
@testable import SpecKit

/// `JSONDecoder` ignores unknown keys, but the schema sets `additionalProperties: false`.
/// That gap matters here: every country number lives in JSON, so a misspelled key would decode
/// to `nil` and silently change the geometry instead of failing. These tests walk each spec
/// against the schema itself, so there is no hand-maintained key list to drift.
@Suite("Schema key conformance")
struct SchemaConformanceTests {

    static func schema() throws -> [String: Any] {
        let url = try #require(RepoPaths.specs).appendingPathComponent("document-spec.schema.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    /// Every `specs/**.json` except the schema itself.
    static func specFiles() throws -> [URL] {
        let root = try #require(RepoPaths.specs)
        let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return all
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "document-spec.schema.json" }
            .sorted { $0.path < $1.path }
    }

    @Test("every spec file conforms to the schema's keys")
    func specsConform() throws {
        let schema = try Self.schema()
        let files = try Self.specFiles()
        #expect(!files.isEmpty)

        for file in files {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            let instance = try #require(object as? [String: Any])
            let issues = SchemaKeyChecker(root: schema).check(instance, against: schema, path: "")
            let report = "\(file.lastPathComponent):\n" + issues.joined(separator: "\n")
            #expect(issues.isEmpty, "\(report)")
        }
    }

    @Test("a misspelled key is caught rather than silently decoding to nil")
    func typoIsCaught() throws {
        let schema = try Self.schema()
        let url = try #require(RepoPaths.inPassportSpec)
        var instance = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )

        // Misspell the single most load-bearing number in the file.
        var geometry = try #require(instance["geometry"] as? [String: Any])
        var headHeight = try #require(geometry["headHeight"] as? [String: Any])
        let target = headHeight.removeValue(forKey: "targetMM")
        headHeight["targetMm"] = target
        geometry["headHeight"] = headHeight
        instance["geometry"] = geometry

        // The decoder alone does not notice: targetMM just becomes nil.
        let mutated = try JSONSerialization.data(withJSONObject: instance)
        let spec = try SpecLoader.load(data: mutated)
        #expect(spec.geometry.headHeight.targetMM == nil)

        // The key check does notice, and names the field.
        let issues = SchemaKeyChecker(root: schema).check(instance, against: schema, path: "")
        #expect(issues.contains { $0.contains("targetMm") })
    }

    @Test("a required key that goes missing is caught")
    func missingRequiredIsCaught() throws {
        let schema = try Self.schema()
        let url = try #require(RepoPaths.inPassportSpec)
        var instance = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        instance.removeValue(forKey: "country")

        let issues = SchemaKeyChecker(root: schema).check(instance, against: schema, path: "")
        #expect(issues.contains { $0.contains("country") })
    }
}

/// Walks an instance against the schema checking keys only: unknown properties where
/// `additionalProperties` is false, and missing `required` ones. Not a full JSON Schema
/// validator, it deliberately does not check types, which `Codable` already enforces.
struct SchemaKeyChecker {
    let root: [String: Any]

    func check(_ instance: [String: Any], against schema: [String: Any], path: String) -> [String] {
        let schema = resolve(schema)
        var issues: [String] = []

        var properties = schema["properties"] as? [String: Any] ?? [:]
        // Union in any branch's properties so oneOf/anyOf alternatives stay legal.
        for key in ["oneOf", "anyOf", "allOf"] {
            for branch in schema[key] as? [[String: Any]] ?? [] {
                let branch = resolve(branch)
                for (name, value) in branch["properties"] as? [String: Any] ?? [:] {
                    properties[name] = value
                }
            }
        }

        let allowsExtra = (schema["additionalProperties"] as? Bool) ?? true
        if !allowsExtra && !properties.isEmpty {
            for key in instance.keys where properties[key] == nil {
                issues.append("  unknown key '\(join(path, key))'")
            }
        }
        for key in schema["required"] as? [String] ?? [] where instance[key] == nil {
            issues.append("  missing required key '\(join(path, key))'")
        }

        for (key, value) in instance {
            guard let child = properties[key] as? [String: Any] else { continue }
            issues += descend(value, against: child, path: join(path, key))
        }
        return issues
    }

    private func descend(_ value: Any, against schema: [String: Any], path: String) -> [String] {
        let schema = resolve(schema)
        if let object = value as? [String: Any] {
            return check(object, against: schema, path: path)
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            return array.enumerated().flatMap { index, element in
                descend(element, against: items, path: "\(path)[\(index)]")
            }
        }
        return []
    }

    /// Resolves `{"$ref": "#/$defs/name"}` against the root document.
    private func resolve(_ schema: [String: Any]) -> [String: Any] {
        guard let ref = schema["$ref"] as? String, ref.hasPrefix("#/") else { return schema }
        var node: Any = root
        for part in ref.dropFirst(2).split(separator: "/") {
            guard let dict = node as? [String: Any], let next = dict[String(part)] else { return schema }
            node = next
        }
        guard var resolved = node as? [String: Any] else { return schema }
        // Keep sibling keys alongside the $ref (the schema uses $ref + description).
        for (key, value) in schema where key != "$ref" && resolved[key] == nil {
            resolved[key] = value
        }
        return resolved
    }

    private func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }
}
