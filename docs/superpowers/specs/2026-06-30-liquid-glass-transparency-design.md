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

## Settings UI

In `NagramSettingsController`, add a row under `General -> Interface`, near `Control Highlight`:

- `Glass Transparency`: disclosure row with options `Follow System` and `Custom`.
- When mode is `Custom`, show a `Glass Transparency` slider from `0...100`.

The existing slider row type can be reused. To avoid hard-coding `Sticker Size`, extend the slider row model so it carries a title key. Existing sticker size behavior remains unchanged.

Add localization keys in all existing Nagram locales:

- `Nagram.GlassTransparency`
- `Nagram.GlassTransparency.system`
- `Nagram.GlassTransparency.custom`
- `Nagram.GlassTransparency.Footer`

## Rendering Behavior

Create a small Nagram helper in `Nagram/Settings`, for example:

```swift
public func nagramAdjustedGlassAlpha(_ alpha: CGFloat) -> CGFloat
public func nagramAdjustedGlassColor(_ color: UIColor) -> UIColor
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

Custom mode should not disable blur. A value of `0%` means the color/tint overlay becomes fully transparent while the native glass effect can still render where the platform supports it.

## Error Handling

Invalid stored mode falls back to `.system`.

Invalid stored percentage is clamped to `0...100` when read through helpers. The raw stored value does not need migration.

## Verification

There are no project tests. Verification should include:

- `jj diff --git` review for scoped Nagram annotations on upstream file edits.
- Build syntax verification through the normal full-project build if practical.
- If full build is too expensive, at minimum run targeted Swift/Bazel analysis commands available in the repo and report the limitation.
- Manual simulator check after build: setting row appears, mode choice persists, custom slider appears only in custom mode, visible glass surfaces update after changing the percentage.

## Decision

Use the default `100%` custom value so switching to custom starts from current visual behavior.
