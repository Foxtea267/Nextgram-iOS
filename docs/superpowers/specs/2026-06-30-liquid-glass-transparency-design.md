# Liquid Glass Transparency Settings Design

## Goal

Add a Nagram appearance setting for Liquid Glass / glass transparency with two modes:

- Follow system: keep Telegram's native glass behavior and respect iOS Reduce Transparency.
- Custom: let the user choose a glass transparency percentage.

The feature should affect Nagram-visible liquid/glass surfaces without introducing a broader theme rewrite.

## Non-Goals

- Do not redesign Telegram themes or change normal opaque list/chat backgrounds.
- Do not replace Apple's `UIGlassEffect` on supported iOS versions.
- Do not add new settings storage outside `Nagram/Settings`.
- Do not change existing `Control Highlight` semantics; it remains only an interaction highlight toggle.

## Current Context

Nagram settings are stored in `Nagram/Settings/NagramSettings.swift` using `@NagramDefault`.

The main settings UI is data-driven in `Nagram/SettingsUI/NagramSettingsController.swift`. It already supports `choice` rows and percent-style slider rows through `NagramSliderItem`.

Glass rendering is concentrated in:

- `submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`
- `submodules/Display/Source/NavigationBackgroundView.swift`

`NavigationBackgroundView` already respects `UIAccessibility.isReduceTransparencyEnabled`. `GlassBackgroundComponent` uses `UIGlassEffect` on iOS 26+ and falls back to a legacy custom glass implementation elsewhere. Apple documents Liquid Glass as a system material and `isReduceTransparencyEnabled` as the system Reduce Transparency state, so follow-system mode must avoid overriding either one.

## Data Model

Add:

```swift
public enum NagramGlassTransparencyMode: String {
    case system
    case custom
}
```

Add stored settings:

```swift
@NagramDefault("nagram.glassTransparencyMode", NagramGlassTransparencyMode.system.rawValue)
public var glassTransparencyMode: String

@NagramDefault("nagram.glassTransparencyPercent", Int32(100))
public var glassTransparencyPercent: Int32
```

Add helpers:

- `glassTransparencyModeValue`
- `glassTransparencyFactor`

`glassTransparencyFactor` clamps custom values to `0...100` and returns `percent / 100`. In follow-system mode it returns `1.0`; platform accessibility and future platform glass defaults still handle transparency separately.

Keep `Nagram/Settings` pure Foundation. It must not import UIKit or expose `UIColor` / `CGFloat` helpers. UI modules can convert the returned numeric factor into `CGFloat` locally.

## Settings UI

In `NagramSettingsController`, add a row under `General -> Interface`, near `Control Highlight`:

- `Glass Transparency`: disclosure row with options `Follow System` and `Custom`.
- When mode is `Custom`, show a `Glass Overlay Opacity` slider from `0...100`.

The existing slider row type can be reused. To avoid hard-coding `Sticker Size`, extend the slider row model so it carries a title key. Existing sticker size behavior remains unchanged.

Add localization keys in all existing Nagram locales:

- `Nagram.GlassTransparency`
- `Nagram.GlassTransparency.system`
- `Nagram.GlassTransparency.custom`
- `Nagram.GlassTransparency.OverlayOpacity`
- `Nagram.GlassTransparency.Footer`

Suggested footer copy: follow-system keeps Apple's native Liquid Glass behavior and iOS Reduce Transparency behavior; custom adjusts Nagram's glass overlay opacity.

## Rendering Behavior

Use the pure numeric factor from `NagramSettings.shared.glassTransparencyFactor`. Color adjustment helpers stay local to modules that already import UIKit, for example:

```swift
private func nagramAdjustedGlassAlpha(_ alpha: CGFloat) -> CGFloat
private func nagramAdjustedGlassColor(_ color: UIColor) -> UIColor
```

The helper applies only custom mode. It leaves system mode unchanged so native iOS glass and Reduce Transparency keep their current behavior.

Apply the helper at the lowest shared glass points:

- `GlassBackgroundComponent`:
  - legacy `foregroundView` / `shadowView` alpha
  - native `UIGlassEffect.tintColor` alpha where a tint exists
  - `innerBackgroundView.backgroundColor`
- `NavigationBackgroundView`:
  - `NavigationBackgroundNode.updateColor`
  - `BlurredBackgroundView.updateColor`

Do not import `NagramSettings` into `Display`. For `NavigationBackgroundView`, add a generic provider in `Display`, defaulting to follow-system and factor `1.0`, and assign it from a TelegramUI startup point that already imports Nagram settings. The provider must be named generically and must not mention Nagram.

The provider needs both pieces of information:

- Whether the caller follows system transparency.
- The custom overlay opacity factor.

`NavigationBackgroundView` should compute its effective Reduce Transparency flag as system Reduce Transparency enabled **and** the provider says it follows system transparency. This keeps custom mode independent from the system setting.

Custom mode should not disable blur. The slider controls glass overlay opacity, not total blur strength. A value of `0%` means Nagram-applied color/tint/shadow overlays become transparent while the native glass or blur effect can still render where the platform supports it.

## Follow-System Behavior

Follow-system mode means Nagram does not apply its custom opacity factor and lets system Reduce Transparency win.

Custom mode means Nagram applies the custom opacity factor even when iOS Reduce Transparency is enabled. Existing UIKit internals may still adapt native `UIGlassEffect`, but Nagram should not add its own follow-system override in custom mode.

For `NavigationBackgroundView`, preserve the existing Reduce Transparency behavior: it disables blur and uses an opaque background color.

For `GlassBackgroundComponent`, native `UIGlassEffect` should be left to UIKit in follow-system mode. Legacy/custom glass paths must explicitly check the existing accessibility helper and avoid rendering custom translucent shadows or overlays when Reduce Transparency is enabled. If a solid fallback is needed, derive it from the current tint kind and `isDark` instead of introducing theme dependencies into the component.

## Refresh Strategy

Changing the mode or custom percentage should make visible surfaces update without requiring app restart.

Use the existing `UserDefaults.didChangeNotification` path as the trigger. The settings controller already rebuilds its list through `bump()`. Rendering components must:

- Recompute the factor on their next normal `update(...)` pass, and
- Have at least one global invalidation hook from TelegramUI when Nagram settings change for long-lived surfaces such as root navigation/tab/input backgrounds.

The implementation should avoid per-frame reads beyond existing update passes.

## Error Handling

Invalid stored mode falls back to `.system`.

Invalid stored percentage is clamped to `0...100` when read through helpers. The raw stored value does not need migration.

## Verification

There are no project tests. Verification should include:

- `jj diff --git` review for scoped Nagram annotations on upstream file edits.
- Full-project build if practical.
- If full build is too expensive, at minimum run `bazel query` / target analysis for touched targets and report the limitation.
- Manual simulator check after build: setting row appears, mode choice persists, custom slider appears only in custom mode, visible glass surfaces update after changing the percentage.

## Decision

Use the default `100%` custom value so switching to custom starts from current visual behavior.
