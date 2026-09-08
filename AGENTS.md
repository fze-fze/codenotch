# Repository Guidelines

## Project Structure & Module Organization

Application code lives in `Sources/`, grouped by responsibility: `App/` owns lifecycle and panels, `Notch/` contains the edge UI and geometry, `Providers/` reads usage data, `Sessions/` monitors agent activity, and `Skills/` manages shared skills. Reusable styling belongs in `DesignSystem/`; images and icons live in `Sources/Assets.xcassets`. XCTest suites are in `Tests/` and generally mirror the production type they cover. Product decisions and implementation notes are kept under `docs/specs/` and `docs/plans/`, while reference images live in `docs/design/`.

## Build, Test, and Development Commands

- `brew install xcodegen`: install the one required project generator.
- `make gen`: regenerate `Codenotch.xcodeproj` from `project.yml`. Do not edit the generated project directly.
- `make build`: generate the project and compile a Debug macOS build.
- `make run`: build, stop any running Codenotch process, and launch the new app.
- `make test`: regenerate the project and run the complete XCTest suite.
- `make clean`: remove generated project and local build artifacts.

The active Xcode selected by `xcode-select -p` is used. Local signing settings, including `DEVELOPMENT_TEAM`, are defined in `project.yml`.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API design conventions. Name types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and test methods as `testExpectedBehavior`. Keep one primary concept per file and place it in the matching feature directory. Prefer small value types, explicit state handling, and Swift concurrency annotations where UI isolation matters. There is no repository-wide formatter or linter; match nearby code and let Xcode indentation guide formatting. UI dimensions derived from the design reference should use `Design.px(...)` rather than unexplained constants.

## Testing Guidelines

Add or update XCTest coverage for behavioral changes, parsing edge cases, geometry, and provider failure states. Put tests in `Tests/<TypeOrFeature>Tests.swift`, use deterministic fixtures, and avoid live credentials or network dependencies. Run `make test` before opening a pull request; use Xcode's test navigator for a focused suite during development.

## Commit & Pull Request Guidelines

Follow the existing history: concise, imperative commit subjects such as `Add make install` or `Strip unused features`. Keep each commit focused. Pull requests should explain the user-visible effect, identify affected providers or surfaces, report test results, and link relevant specs or issues. Include before/after screenshots for notch, tooltip, settings, or Skills UI changes. Never commit credentials, keychain exports, generated `.xcodeproj` files, or build output.
