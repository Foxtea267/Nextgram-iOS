# Liquid Glass Transparency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Nagram settings for follow-system or custom Liquid Glass overlay opacity.

**Architecture:** Keep `Nagram/Settings` pure Foundation and expose only mode/percent/factor values. UI modules convert the numeric factor to UIKit colors locally. `Display` receives generic transparency settings through a non-Nagram provider; TelegramUI wires that provider to Nagram settings and triggers refreshes.

**Tech Stack:** Swift, Bazel Swift libraries, UserDefaults, SwiftSignalKit, UIKit glass/blur components.

---

## File Structure

- Modify `Nagram/Settings/NagramSettings.swift`: add mode enum, stored defaults, clamped helpers.
- Modify `Nagram/SettingsSignal/Sources/NagramSettingsSignal.swift`: add signal for glass transparency changes.
- Modify `Nagram/SettingsUI/NagramSettingsController.swift`: add choice row and conditional slider row; make slider row title configurable.
- Modify `Nagram/Strings/Strings/{en,zh-hans,zh-hant,ja}.lproj/NagramLocalizable.strings`: add labels.
- Modify `submodules/Display/Source/NavigationBackgroundView.swift`: add generic transparency provider and apply overlay factor without importing Nagram.
- Modify `submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`: apply custom factor locally and respect Reduce Transparency on legacy glass.
- Modify `submodules/TelegramUI/Sources/TelegramRootController.swift`: wire provider and subscribe to Nagram glass transparency changes.

## Test Strategy

This repository has no Nagram unit-test target. Do not create a new testing infrastructure for this feature. Verification uses:

- `bazel query` / touched-target analysis for dependency sanity.
- Swift compilation through the normal full app build if practical.
- Manual simulator checks after build.

## Tasks

### Task 1: Settings Model

**Files:**
- Modify: `Nagram/Settings/NagramSettings.swift`

- [ ] **Step 1: Add pure Foundation data model**

Add `NagramGlassTransparencyMode`, stored defaults, and helpers:

```swift
public enum NagramGlassTransparencyMode: String {
    case system
    case custom
}

@NagramDefault("nagram.glassTransparencyMode", NagramGlassTransparencyMode.system.rawValue)
public var glassTransparencyMode: String

@NagramDefault("nagram.glassTransparencyPercent", Int32(100))
public var glassTransparencyPercent: Int32

var glassTransparencyModeValue: NagramGlassTransparencyMode
var glassTransparencyFactor: Double
var glassTransparencyFollowsSystem: Bool
```

- [ ] **Step 2: Verify no UIKit leak**

Run: `rg -n "import UIKit|UIColor|CGFloat" Nagram/Settings`

Expected: no output.

### Task 2: Settings Signal

**Files:**
- Modify: `Nagram/SettingsSignal/Sources/NagramSettingsSignal.swift`

- [ ] **Step 1: Add signal**

Add `nagramGlassTransparencySignal() -> Signal<Int32, NoError>` backed by `UserDefaults.didChangeNotification`, incrementing a version value.

- [ ] **Step 2: Verify symbol**

Run: `rg -n "nagramGlassTransparencySignal" Nagram/SettingsSignal`

Expected: function definition appears once.

### Task 3: Settings UI

**Files:**
- Modify: `Nagram/SettingsUI/NagramSettingsController.swift`

- [ ] **Step 1: Make slider row title configurable**

Change the slider row case so it carries `titleKey: String?`; `nil` keeps existing sticker-size min/current/max layout, non-nil passes a row title to `NagramSliderItem`.

- [ ] **Step 2: Add glass rows**

Under General -> Interface, add:

```swift
.choice(titleKey: "Nagram.GlassTransparency", prefix: "Nagram.GlassTransparency", options: ["system", "custom"], current: { NagramSettings.shared.glassTransparencyModeValue.rawValue }, set: { NagramSettings.shared.glassTransparencyMode = $0 }),
.slider(titleKey: "Nagram.GlassTransparency.OverlayOpacity", minValue: 0, maxValue: 100, get: { NagramSettings.shared.glassTransparencyPercent }, set: { NagramSettings.shared.glassTransparencyPercent = $0 }, isVisible: { NagramSettings.shared.glassTransparencyModeValue == .custom }),
```

- [ ] **Step 3: Verify old sticker row still maps to `Nagram.StickerSize`**

Run: `rg -n "case .*slider|Nagram.StickerSize|GlassTransparency" Nagram/SettingsUI/NagramSettingsController.swift`

Expected: both sticker and glass slider paths exist.

### Task 4: Localization

**Files:**
- Modify: `Nagram/Strings/Strings/en.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/zh-hans.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/zh-hant.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/ja.lproj/NagramLocalizable.strings`

- [ ] **Step 1: Add keys**

Add these keys in every locale:

```text
Nagram.GlassTransparency
Nagram.GlassTransparency.system
Nagram.GlassTransparency.custom
Nagram.GlassTransparency.OverlayOpacity
Nagram.GlassTransparency.Footer
```

- [ ] **Step 2: Verify all locales**

Run: `for f in Nagram/Strings/Strings/*/NagramLocalizable.strings; do echo "$f"; rg -n "Nagram.GlassTransparency" "$f"; done`

Expected: each locale prints all five keys.

### Task 5: Display Provider

**Files:**
- Modify: `submodules/Display/Source/NavigationBackgroundView.swift`

- [ ] **Step 1: Add generic provider**

Add a public generic struct and provider, with no Nagram naming:

```swift
public struct GlassOverlayTransparencySettings: Equatable {
    public let followsSystemTransparency: Bool
    public let overlayOpacity: CGFloat
}

public var currentGlassOverlayTransparencySettings: () -> GlassOverlayTransparencySettings = {
    return GlassOverlayTransparencySettings(followsSystemTransparency: true, overlayOpacity: 1.0)
}
```

- [ ] **Step 2: Apply provider in background updates**

Use `systemReduceTransparency && settings.followsSystemTransparency` for the effective reduce-transparency flag. Apply `overlayOpacity` only to the rendered background color, not to the stored base color that controls blur.

- [ ] **Step 3: Verify Display has no Nagram dependency**

Run: `rg -n "Nagram" submodules/Display`

Expected: no output.

### Task 6: Glass Background Component

**Files:**
- Modify: `submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`

- [ ] **Step 1: Add local UIKit helpers**

Add local helpers that read `NagramSettings.shared.glassTransparencyFactor` and adjust alpha only in custom mode.

- [ ] **Step 2: Apply overlay opacity**

Apply to legacy shadow/foreground alpha, legacy fill color, native `UIGlassEffect.tintColor`, and `innerBackgroundView.backgroundColor`.

- [ ] **Step 3: Respect Reduce Transparency on legacy paths**

When follow-system mode is active and `isReduceTransparencyEnabled()` is true, suppress legacy translucent shadows/overlays and use a solid local fallback where needed.

- [ ] **Step 4: Verify Nagram annotations**

Run: `rg -n "MARK: NAGRAM|NagramSettings" submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`

Expected: import and changed blocks are marked.

### Task 7: Provider Wiring and Refresh

**Files:**
- Modify: `submodules/TelegramUI/Sources/TelegramRootController.swift`

- [ ] **Step 1: Wire Display provider**

Assign `currentGlassOverlayTransparencySettings` from `NagramSettings.shared` using existing Nagram imports.

- [ ] **Step 2: Subscribe to settings changes**

Add a disposable for `nagramGlassTransparencySignal()`, update provider, refresh root tab theme/presentation hooks, and dispose it in `deinit`.

- [ ] **Step 3: Verify references**

Run: `rg -n "nagramGlassTransparency|GlassOverlayTransparency|currentGlassOverlay" submodules/TelegramUI/Sources/TelegramRootController.swift`

Expected: provider setup, disposable, and deinit cleanup are present.

### Task 8: Build/Analysis Verification

**Files:**
- No edits.

- [ ] **Step 1: Dependency query**

Run: `bazel query 'deps(//Nagram/SettingsUI:NagramSettingsUI)' --noshow_progress >/tmp/nagram-settingsui-deps.txt`

Expected: command exits 0.

- [ ] **Step 2: Target query**

Run: `bazel query '//Nagram/Settings:all + //Nagram/SettingsSignal:all + //Nagram/SettingsUI:all + //submodules/TelegramUI/Components/GlassBackgroundComponent:all + //submodules/Display:all' --noshow_progress`

Expected: command exits 0.

- [ ] **Step 3: Full build if practical**

Run the simulator build from `AGENTS.md` when local signing/config permits. If skipped, report the exact blocker.

- [ ] **Step 4: Review diff**

Run: `jj diff --git`

Expected: only planned files changed, upstream edits marked with `// MARK: NAGRAM`.
