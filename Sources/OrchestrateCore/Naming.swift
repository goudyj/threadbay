import Foundation

/// Space-naming rules for spaces created by the macOS app.
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

    /// The app keeps names task-neutral: `<project>__<branch-slug>`.
    public static func branchSpaceName(project: String, branch: String) -> String {
        "\(project)__\(slugify(branch))"
    }

    public static func pullRequestSpaceName(project: String, number: UInt) -> String {
        "\(project)__pr-\(number)"
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
