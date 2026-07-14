import AppKit
import Carbon.HIToolbox
import SwiftTerm
import XCTest

@testable import ThreadBay

@MainActor
final class SessionTerminalViewTests: XCTestCase {
    func testTerminalThemesKeepTextReadable() {
        let terminal = SessionTerminalView(frame: .zero)

        terminal.applyTheme(.light)
        XCTAssertGreaterThan(
            brightness(of: terminal.nativeBackgroundColor),
            brightness(of: terminal.nativeForegroundColor))

        terminal.applyTheme(.dark)
        XCTAssertLessThan(
            brightness(of: terminal.nativeBackgroundColor),
            brightness(of: terminal.nativeForegroundColor))
    }

    func testShiftReturnSendsGhosttyLegacySequence() throws {
        let event = try keyEvent(keyCode: kVK_Return, modifiers: .shift)
        let terminal = RecordingSessionTerminalView(frame: .zero)

        XCTAssertTrue(terminal.handleShortcut(event))
        XCTAssertEqual(terminal.sentBytes, Array("\u{1b}[27;2;13~".utf8))
    }

    func testShiftReturnUsesKittySequenceWhenEnabled() throws {
        let event = try keyEvent(keyCode: kVK_Return, modifiers: .shift)
        let terminal = RecordingSessionTerminalView(frame: .zero)
        terminal.feed(text: "\u{1b}[>1u")

        XCTAssertFalse(terminal.handleShortcut(event))
        terminal.keyDown(with: event)
        XCTAssertEqual(terminal.sentBytes, Array("\u{1b}[13;2u".utf8))
    }

    func testCommandBackspaceDeletesToStartOfLine() throws {
        let event = try keyEvent(keyCode: kVK_Delete, modifiers: .command)
        let terminal = RecordingSessionTerminalView(frame: .zero)

        XCTAssertTrue(terminal.handleShortcut(event))
        XCTAssertEqual(terminal.sentBytes, [0x15])
    }

    func testUnmodifiedReturnIsLeftToSwiftTerm() throws {
        let event = try keyEvent(keyCode: kVK_Return, modifiers: [])
        let terminal = RecordingSessionTerminalView(frame: .zero)

        XCTAssertFalse(terminal.handleShortcut(event))
        XCTAssertTrue(terminal.sentBytes.isEmpty)
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let characters = keyCode == kVK_Return ? "\r" : ""
        return try XCTUnwrap(NSEvent.keyEvent(
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

    private func brightness(of color: NSColor) -> CGFloat {
        color.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
    }
}

private final class RecordingSessionTerminalView: SessionTerminalView {
    private(set) var sentBytes: [UInt8] = []

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sentBytes.append(contentsOf: data)
    }
}
