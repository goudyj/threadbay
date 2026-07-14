import AppKit
import Carbon.HIToolbox
import XCTest

@testable import ThreadBay

@MainActor
final class AppShortcutsTests: XCTestCase {
    func testDefaultShortcutsMatchRequestedActions() throws {
        let shortcuts = AppShortcutSettings()

        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_N, [.command], "n")),
            .newSpace)
        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_W, [.command], "w")),
            .closeSession)
        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_1, [.command, .shift])),
            .launchClaude)
        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_2, [.command, .shift])),
            .launchCodex)
        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_3, [.command, .shift])),
            .launchShell)
    }

    func testLetterShortcutsFollowTheKeyboardLayoutCharacter() throws {
        let shortcuts = AppShortcutSettings()

        XCTAssertEqual(
            shortcuts.action(matching: try keyEvent(kVK_ANSI_Z, [.command], "w")),
            .closeSession)
    }

    func testShortcutSettingsRoundTripThroughUserDefaults() throws {
        let suiteName = "AppShortcutsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var shortcuts = AppShortcutSettings()
        shortcuts[.launchCodex] = AppShortcut(
            keyCode: kVK_ANSI_C, keyLabel: "C", modifiers: [.control, .option])

        shortcuts.save(to: defaults)

        XCTAssertEqual(AppShortcutSettings.load(from: defaults), shortcuts)
    }

    func testRejectsPlainTypingShortcut() throws {
        XCTAssertNil(AppShortcut(event: try keyEvent(kVK_ANSI_C, [])))
        XCTAssertNil(AppShortcut(event: try keyEvent(kVK_ANSI_C, [.shift])))
    }

    func testFindsConflictingShortcut() {
        let shortcuts = AppShortcutSettings()
        let sameLetterOnDifferentLayout = AppShortcut(
            keyCode: kVK_ANSI_Z, keyLabel: "N", modifiers: [.command])

        XCTAssertEqual(
            shortcuts.conflictingAction(
                for: sameLetterOnDifferentLayout, excluding: .launchClaude),
            .newSpace)
    }

    private func keyEvent(
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags,
        _ characters: String = ""
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)))
    }
}
