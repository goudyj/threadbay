import Foundation

/// Space-naming rules for spaces created by the macOS app.
public enum Naming {
    private static let adjectives = [
        "brave", "calm", "clever", "cosmic", "curious", "daring", "gentle", "happy",
        "jolly", "lucky", "mighty", "nimble", "playful", "quiet", "sleepy", "witty",
    ]

    private static let animals = [
        "badger", "capybara", "dolphin", "falcon", "gecko", "koala", "lemur", "otter",
        "panda", "penguin", "raccoon", "sloth", "tiger", "turtle", "walrus", "wombat",
    ]

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

    /// Stable task-neutral identity: `<project>__<adjective>-<animal>`.
    public static func randomSpaceName(project: String) -> String {
        let adjective = adjectives.randomElement() ?? "curious"
        let animal = animals.randomElement() ?? "otter"
        let projectSlug = slugify(project)
        return "\(projectSlug.isEmpty ? "project" : projectSlug)__\(adjective)-\(animal)"
    }

    /// Appends `-2`, `-3`, … until `isTaken` clears the candidate.
    public static func ensureUniqueName(base: String, isTaken: (String) -> Bool) -> String {
        var i = 1
        var name = base
        while isTaken(name) {
            i += 1
            name = "\(base)-\(i)"
        }
        return name
    }

    /// Appends `-2`, `-3`, … until the name is free inside `parent`.
    public static func ensureUniqueName(parent: URL, base: String) -> String {
        ensureUniqueName(base: base) {
            FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
        }
    }
}
