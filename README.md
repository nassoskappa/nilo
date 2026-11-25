# Nilo

Blink, and it's done.

A native assistant for Mac, iPhone and iPad that finishes whole jobs across your apps, and shows you its plan before it acts.

## First run on your Mac

1. Install XcodeGen once: `brew install xcodegen`
2. The app ID prefix in `project.yml` is `com.bitniks`. Change `NILO_BUNDLE_ID_PREFIX` only if you move it to another developer account.
3. Generate the project: double-click `Setup.command`, or run `xcodegen generate`
4. Open it: `open Nilo.xcodeproj`
5. In Xcode, select each target, open Signing & Capabilities, and pick your team.
6. Run **Nilo-macOS**. A cursor icon appears in the menu bar. Click it to see the mark and step through its states (Space for next).
7. Run **Nilo-iOS** in the simulator or on your iPhone. Tap anywhere to step through the states.

Run the package tests with `cd Packages/NiloKit && swift test`.

See `CLAUDE.md` for the rules Claude Code follows in this repo.
