import Foundation

/// Space-naming rules, ported 1:1 from the Rust CLI (`src/naming.rs`) so the app
/// and the CLI produce identical directory/space names.
public enum Naming {
    /// Lowercase; map `a-z0-9` through; map `/ _ space -` to a single `-`
    /// (collapsing runs); drop anything else; trim leading/trailing `-`.
    public static func slugify(_ branch: String) -> String {
        var output = ""
        var prevDash = false

        for c in branch {
            let mapped: Character?
            switch c {
            case "a"..."z", "0"..."9":
                mapped = c
            case "A"..."Z":
                mapped = Character(c.lowercased())
            case "/", "_", " ", "-":
                mapped = "-"
            default:
                mapped = nil
            }

            guard let ch = mapped else { continue }
            if ch == "-" {
                if !prevDash {
                    output.append("-")
                    prevDash = true
                }
            } else {
                output.append(ch)
                prevDash = false
            }
        }

        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `<project>__feature-<slug>` — the app always creates feature spaces
    /// (a new branch from a base), matching the CLI's feature naming.
    public static func featureSpaceName(project: String, branch: String) -> String {
        "\(project)__feature-\(slugify(branch))"
    }

    /// Appends `-2`, `-3`, … until the name is free inside `parent`.
    public static func ensureUniqueName(parent: URL, base: String) -> String {
        var i = 1
        var name = base
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            i += 1
            name = "\(base)-\(i)"
        }
        return name
    }
}
