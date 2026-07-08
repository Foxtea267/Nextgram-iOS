You are an experienced, pragmatic software engineering AI agent. Do not over-engineer a solution when a simple one is possible. Keep edits minimal. If you want an exception to ANY rule, you MUST stop and get permission first.

# AGENTS.md

This file guides AI agents working in this repository. It is specific to Nagram-iOS and should be kept in sync with the repo, not with generic Telegram-iOS assumptions.

## Project Overview

Nagram-iOS is a third-party enhancement fork of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), targeting Chinese users and aligning selected features with Android [Nagram](https://github.com/NextAlone/Nagram). The goal is to keep the fork easy to rebase onto upstream Telegram while adding Nagram-specific settings, UI, translation, privacy, and interaction features.

Technology stack:

- iOS app code in Swift, Objective-C, Objective-C++, C, and C++.
- Bazel workspace (`WORKSPACE`, `MODULE.bazel`) with a custom Python wrapper at `build-system/Make/Make.py`.
- Xcode/iOS SDK toolchains; expected versions are tracked in `versions.json`, while local build caveats live in `docs/build.md`.
- Telegram modules under `submodules/` (`TelegramCore`, `TelegramUI`, `Display`, `SwiftSignalKit`, `Postbox`, etc.) plus vendored native dependencies under `third-party/`.

## Reference

Important directories:

- `Nagram/` — all new Nagram feature code. Main modules are `Settings/`, `SettingsSignal/`, `SettingsUI/`, `Strings/`, and `Translate/`.
- `Telegram/` — main app target, app extensions, app plist fragments, icons, and app-level Bazel rules.
- `submodules/` — upstream Telegram libraries. Modify only when a feature must integrate with upstream code, and mark the edit.
- `third-party/` — vendored dependencies. Avoid style-only or opportunistic changes here.
- `Tests/` — Bazel test/demo targets; `Tests/AllTests/BUILD` currently includes `//submodules/TgVoipWebrtc:TgCallsTests`.
- `Telegram/Tests/Sources/` — XCUITest sources for the generated Xcode project.
- `docs/` — build notes, UI testing notes, and the Postbox-to-TelegramEngine migration log.

Important files:

- `README.md` and `docs/build.md` — signing modes, build commands, and current local toolchain pitfalls.
- `.bazelrc` — imports gitignored `local.bazelrc`; local signing/provisioning flags belong there.
- `build-system/Make/Make.py` — supported build/test/clean/query entry point.
- `Telegram/BUILD` — app target, plist fragments, Nagram app name, strings, and icon integration.
- `Nagram/Settings/NagramSettings.swift` — central Nagram settings store.
- `Nagram/SettingsSignal/Sources/NagramSettingsSignal.swift` — reactive settings bridge.
- `Nagram/SettingsUI/NagramSettingsController.swift` — Nagram settings UI entry controller.
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` — Settings screen Nagram entry point (`SettingsSection.nagram`, item id `50`).
- `docs/superpowers/postbox-refactor-log.md` — source of truth for the Postbox migration waves.

## Essential Commands

Full app builds are the only reliable validation path for app changes. There is no supported per-module build workflow for this fork.

### Build

Simulator-only, codesigning-free setup:

```sh
cat > local.bazelrc <<'EOF'
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
EOF

python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

Full/formal device signing needs app plus all 6 extension profiles (`Share`, `NotificationContent`, `NotificationService`, `Intents`, `Widget`, `BroadcastUpload`). Do not disable extensions in that mode:

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

Free Apple ID device signing may disable extensions, but must not disable provisioning profiles. See `docs/build.md` before changing signing flags.

### Install

Simulator install must uninstall first; `simctl install` does not replace existing Frameworks dylibs reliably:

```sh
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim
xcrun simctl uninstall booted ph.telegra.Telegraph 2>/dev/null
xcrun simctl install booted /tmp/tg-sim/Payload/Telegram.app
```

Device install:

```sh
xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <UDID> /tmp/tg-device/Payload/Telegram.app
```

### Test

Bazel test wrapper (`debug_sim_arm64`, target `Tests/AllTests`):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  test \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning
```

UI tests require a generated `Telegram/Telegram.xcodeproj` and a matching simulator. Always pass `--ui-test`; see `docs/ui-testing.md`.

```sh
xcodebuild test \
  -project Telegram/Telegram.xcodeproj \
  -scheme iOSAppUITestSuite \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
```

### Format and lint

No dedicated repo-wide formatter or lint command was found. Follow local Swift style, keep imports sorted, and rely on Bazel/Swift warnings-as-errors for touched targets. Do not run broad auto-formatting over upstream files.

### Clean

```sh
python3 build-system/Make/Make.py clean
```

`Make.py clean` runs `bazel clean --expunge`; recreate `local.bazelrc` afterward if it disappears.

### Development server

There is no development server. Build the app, then run it in a simulator or install it on a device.

### Other scripts

List shell scripts before using one:

```sh
find . -path './.jj' -prune -o -type f -name '*.sh' -print | sort
```

Prefer `build-system/Make/Make.py` for app build/test/clean. Use `build-system/generate-xcode-project.sh`, `build-system/verify.sh`, `Telegram/*Icon*.sh`, and `third-party/*/build-*-bazel.sh` only when the task specifically calls for them.

## Nagram Fork Patterns

- Put new Nagram-only code under `Nagram/`. Keep `Nagram/Settings` as the low-level data layer and `Nagram/SettingsUI` as the UI layer.
- When upstream files must change, annotate the modification site with `// MARK: NAGRAM`. This is required for upstream rebases.
- The Nagram settings entry appears below “我的资料” (My Profile) in `PeerInfoSettingsItems.swift`; long press opens Nagram debug settings.
- Main app display name is `Nagram` in `Telegram/BUILD` (`CFBundleDisplayName` / `CFBundleName`). Extension plist targets remain `Telegram` unless a task explicitly changes that behavior.
- App icon integration is in `Telegram/BUILD`: `alternate_icon_folders` includes `Nagram`, and Composer source icons include `Nagram`, `NagramBlock`, and `NagramColorful`.
- Settings defaults should preserve native Telegram behavior unless the feature explicitly requires a different default. Existing settings use `@NagramDefault` and sync through local `UserDefaults` plus iCloud KVS.
- Use `NagramSettingsSignal` helpers when UI must react live to setting changes. Do not add ad-hoc polling.

## Postbox → TelegramEngine Refactor

A gradual upstream migration is eliminating direct `import Postbox` from consumer submodules. Read `docs/superpowers/postbox-refactor-log.md` before touching this area.

Rules:

1. `TelegramCore` does not `@_exported import Postbox`; migrated modules must use engine typealiases for Postbox-type references.
2. Never typealias `Postbox`, `Account`, or `MediaBox`. Narrow utility typealiases such as `MemoryBuffer`, `PostboxDecoder`, and `PostboxEncoder` are allowed.
3. Do not add new engine wrapper structs unless the wave spec allows it. Prefer typealiases and thin forwarding methods.
4. Search `submodules/TelegramCore/Sources/TelegramEngine/` for existing equivalents before adding a wrapper.
5. `TelegramCore` must not import UIKit or Display. UIKit-dependent helpers stay in consumer-side submodules.

Common mappings:

```text
PeerId              → EnginePeer.Id          MessageId           → EngineMessage.Id
MessageIndex        → EngineMessage.Index    MessageTags         → EngineMessage.Tags
MessageAttribute    → EngineMessage.Attribute MessageFlags       → EngineMessage.Flags
MessageForwardInfo  → EngineMessage.ForwardInfo MediaId           → EngineMedia.Id
PreferencesEntry    → EnginePreferencesEntry TempBox             → EngineTempBox
PinnedItemId        → EngineChatList.PinnedItem.Id
MemoryBuffer        → EngineMemoryBuffer     PostboxDecoder      → EnginePostboxDecoder
PostboxEncoder      → EnginePostboxEncoder   AdaptedPostboxDecoder → EngineAdaptedPostboxDecoder
ItemCollectionId    → EngineItemCollectionId FetchResourceSourceType → EngineFetchResourceSourceType
FetchResourceError  → EngineFetchResourceError
```

`EngineMediaResource` is a wrapper class, not a typealias. It wraps/unwraps via `EngineMediaResource(rawResource)` and `._asResource()`. Use it when a pure type reference is enough; use raw `MediaResource` only for protocol conformance or `isEqual(to:)`.

## Anti-Patterns

- Do not put Nagram-only feature code into upstream `submodules/` when it can live in `Nagram/`.
- Do not edit upstream files without a nearby `// MARK: NAGRAM` marker.
- Do not pass `--disableExtensions` or `--disableProvisioningProfiles` to `Make.py build`; those are Bazel flags for `local.bazelrc`, not Make.py build arguments.
- Do not use `disableProvisioningProfiles` for device builds.
- Do not disable extensions when full/formal provisioning profiles are present.
- Do not mix functional changes with whitespace cleanup.
- Do not treat stale-submodule errors (`tgcalls` missing files, WebRTC/FFmpeg API mismatches) as app code failures; verify submodule state first. The upstream README uses Git commands for this, so ask for explicit authorization before running them in a jj-only agent workspace.
- Do not add production-data UI tests. XCUITests must launch with `--ui-test` so they use isolated data and Telegram test servers.

## Code Style

- Follow existing Swift conventions: PascalCase types, camelCase members, sorted imports, clear names over abbreviations.
- Keep changes localized and boring. Prefer existing Telegram/Nagram helpers over new abstractions.
- New Nagram Bazel modules should use `swift_library`, public visibility only when needed, and `copts = ["-warnings-as-errors"]` like the existing Nagram targets.
- Boundary code should fail loudly with actionable errors; avoid silent fallback paths unless the product behavior explicitly requires one.
- Do not commit debug prints, `debugger`, temporary TODOs, or commented-out old implementations.

## Commit and Pull Request Guidelines

Use `jj` in this workspace. The upstream `.github/CONTRIBUTING.md` is Git-oriented human guidance; AI agents should not run Git commands unless the user explicitly authorizes a concrete command in the current turn.

Before editing:

```sh
jj st
jj log -r @ -n 1 --no-graph
```

Before committing:

- Re-read the request and confirm the change scope did not drift.
- Run the narrowest useful validation, then a full app build when the touched area can affect compilation or runtime behavior.
- For docs-only changes, at minimum inspect the Markdown and run `jj diff --git`.
- Do not modify tests to fit a broken implementation.

Commit messages in recent history use `type: summary`, especially `feat:`, `fix:`, `chore:`, and `docs:`. Prefer one focused change per commit:

```sh
jj commit -m "docs: improve agent guide"
```

Pull request descriptions should include:

- Summary of user-visible or developer-visible changes.
- Validation commands and whether they passed, failed, or were skipped with a reason.
- Screenshots or screen recordings for UI changes.
- Signing/build mode used for validation (`debug_sim_arm64`, `debug_arm64`, full profiles, free Apple ID, etc.).
- Rebase or upstream-touch notes for every modified upstream file with `// MARK: NAGRAM`.

Do not create or open a PR unless the user explicitly asks for it.
