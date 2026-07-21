import Foundation

struct SpaceListPreferences: Codable, Equatable {
    private static let defaultsKey = "spaceListPreferences"

    private(set) var pinnedSpaceNames: [String] = []
    private(set) var orderedSpaceNames: [String] = []

    func isPinned(_ name: String) -> Bool {
        pinnedSpaceNames.contains(name)
    }

    mutating func setPinned(_ pinned: Bool, name: String) {
        pinnedSpaceNames.removeAll { $0 == name }
        if pinned {
            pinnedSpaceNames.append(name)
        }
    }

    mutating func reconcile(validSpaceNames: [String]) {
        let validNames = Set(validSpaceNames)
        pinnedSpaceNames = pinnedSpaceNames.filter(validNames.contains)
        orderedSpaceNames = orderedSpaceNames.filter(validNames.contains)

        let orderedNames = Set(orderedSpaceNames)
        orderedSpaceNames.append(contentsOf: validSpaceNames.filter { !orderedNames.contains($0) })
    }

    mutating func move(names: [String], fromOffsets: IndexSet, toOffset: Int) {
        let offsets = fromOffsets.sorted()
        guard !offsets.isEmpty,
            offsets.allSatisfy({ names.indices.contains($0) }),
            (0...names.count).contains(toOffset)
        else { return }

        let movedNames = offsets.map { names[$0] }
        var reorderedNames = names
        for offset in offsets.reversed() {
            reorderedNames.remove(at: offset)
        }
        let removedBeforeDestination = offsets.count { $0 < toOffset }
        reorderedNames.insert(
            contentsOf: movedNames,
            at: toOffset - removedBeforeDestination)

        let affectedNames = Set(names)
        var reorderedIterator = reorderedNames.makeIterator()
        orderedSpaceNames = orderedSpaceNames.map { name in
            guard affectedNames.contains(name) else { return name }
            return reorderedIterator.next() ?? name
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
            let preferences = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return preferences
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
