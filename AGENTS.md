# Repository Guidelines

## Project Structure & Module Organization

ThreadBay is a Swift 6 package targeting macOS 14+. `Sources/ThreadBayCore/` contains reusable models, YAML persistence, Git/GitHub operations, naming, and agent-event services. Keep platform-independent behavior here so it remains easy to test. `Sources/ThreadBay/` contains the SwiftUI application, menu-bar and window views, session management, and SwiftTerm integration. Localized strings live under `Sources/ThreadBay/Resources/<locale>.lproj/`.

Tests mirror the package targets in `Tests/ThreadBayCoreTests/` and `Tests/ThreadBayTests/`. Documentation is in `docs/`, while `scripts/build-app.sh` assembles the release executable into `ThreadBay.app`. Treat `.build/` and `ThreadBay.app/` as generated outputs.

## Build, Test, and Development Commands

- `swift build` compiles the package in debug mode.
- `swift test` runs all XCTest unit and offline Git integration tests.
- `swift run ThreadBay` builds and launches the app from a terminal.
- `./scripts/build-app.sh` creates and ad-hoc signs a release `ThreadBay.app` bundle.

Open `Package.swift` directly in Xcode when working with previews or macOS UI tooling.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, opening braces on the declaration line, and trailing commas in multiline lists. Use `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and filenames matching their primary type (for example, `SpaceService.swift`). Keep SwiftUI views small and place reusable business logic in `ThreadBayCore`. No formatter or linter is configured, so minimize unrelated formatting changes.

## Testing Guidelines

Tests use XCTest and `@testable import`. Name test methods `test<Behavior>` (for example, `testSlugifyCollapsesRunsAndTrims`). Add focused unit coverage for core behavior and integration tests only where filesystem or Git interactions are essential. Run `swift test` before submitting changes; no numeric coverage threshold is currently enforced.

## Commit & Pull Request Guidelines

Recent commits use concise Conventional Commit subjects such as `feat: add terminal theme and shortcuts` and `refactor: rename app to ThreadBay`. Continue with an imperative, scoped summary and keep each commit focused. Pull requests should explain the user-visible outcome, list verification performed, and link relevant issues. Include screenshots or a short recording for SwiftUI changes, and call out changes to localization, persisted YAML, hooks, or migration behavior.
