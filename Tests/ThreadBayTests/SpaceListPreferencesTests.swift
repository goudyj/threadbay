import XCTest

@testable import ThreadBay

final class SpaceListPreferencesTests: XCTestCase {
    func testReconcileKeepsKnownOrderAndAppendsNewSpaces() {
        var preferences = SpaceListPreferences()
        preferences.reconcile(validSpaceNames: ["a", "b"])
        preferences.move(names: ["a", "b"], fromOffsets: IndexSet(integer: 1), toOffset: 0)

        preferences.reconcile(validSpaceNames: ["a", "b", "c"])

        XCTAssertEqual(preferences.orderedSpaceNames, ["b", "a", "c"])
    }

    func testReconcileRemovesDeletedPinnedSpaces() {
        var preferences = SpaceListPreferences()
        preferences.reconcile(validSpaceNames: ["a", "b"])
        preferences.setPinned(true, name: "b")

        preferences.reconcile(validSpaceNames: ["a"])

        XCTAssertFalse(preferences.isPinned("b"))
        XCTAssertEqual(preferences.orderedSpaceNames, ["a"])
    }

    func testMoveChangesOnlyTheOrderOfTheProvidedGroup() {
        var preferences = SpaceListPreferences()
        preferences.reconcile(validSpaceNames: ["pinned-a", "normal-a", "pinned-b", "normal-b"])

        preferences.move(
            names: ["pinned-a", "pinned-b"],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 2)

        XCTAssertEqual(
            preferences.orderedSpaceNames,
            ["pinned-b", "normal-a", "pinned-a", "normal-b"])
    }

    func testRoundTripThroughUserDefaults() throws {
        let suiteName = "SpaceListPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var preferences = SpaceListPreferences()
        preferences.reconcile(validSpaceNames: ["a", "b"])
        preferences.setPinned(true, name: "a")

        preferences.save(to: defaults)

        XCTAssertEqual(SpaceListPreferences.load(from: defaults), preferences)
    }
}
