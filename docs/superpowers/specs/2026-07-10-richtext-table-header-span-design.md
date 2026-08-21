# RichText tables — per-cell header/highlight + colspan/rowspan

**Date:** 2026-07-10
**Status:** Design approved; ready for implementation planning.

## Goal

Support the InstantPage table features that the client model and API already carry but the composer
cannot yet produce, and confirm the viewer renders them:

- **Highlights** — a per-cell "header" flag (API `pageTableCell.header:flags.0?true`), rendered as a
  filled + bold cell.
- **Cell merging** — `colspan` / `rowspan` (API `pageTableCell.colspan:flags.1?int` /
  `rowspan:flags.2?int`).

Both must be **settable** in the RichTextEditor composer and **viewable** in the InstantPage V2
renderer, round-tripping losslessly through send / edit / draft persistence.

Reference API:
```
pageTableCell#34566b6a flags:# header:flags.0?true align_center:flags.3?true align_right:flags.4?true
  valign_middle:flags.5?true valign_bottom:flags.6?true text:flags.7?RichText colspan:flags.1?int
  rowspan:flags.2?int = PageTableCell;
```

## The "already done" boundary (what this work is NOT)

The lower half of the stack already carries all three fields — this is verified, not assumed:

- `Api.PageTableCell` (`submodules/TelegramApi/Sources/Api20.swift`) — full `header`/`colspan`/`rowspan`.
- Core `InstantPageTableCell` (`submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift`,
  line 1242) — full fields, with Postbox + FlatBuffers + API round-trip.
- `ApiUtils/InstantPage.swift` (line 115) — API ↔ Core round-trip already reads/writes every flag.
- **InstantPage V2 renderer** — already renders viewing:
  - Header fill: `InstantPageV2Layout.swift` computes `isFilled` from `cell.header` (line 1502) →
    `backgroundColor` (`tableHeaderColor`, line 1576); `InstantPageRenderer.swift` draws it as a stripe
    layer (lines 2231–2246).
  - Colspan/rowspan: the ported `awaitingSpanCells` resolution (`InstantPageV2Layout.swift`
    lines 1439–1662) lays out spans; border-line construction skips interior dividers.

**Therefore the renderer work is verify-and-polish, not build** (see §5). The build work is entirely in
the composer and the two conversions between the composer and the InstantPage model.

## Data pipeline

```
RichTextEditor Core  Cell / Row / TableBlock    (RichTextEditorCore/Model/TableBlock.swift)
   ↕  DocumentChatInputContentBridge            (ChatRichTextEditorComposer/.../DocumentChatInputContentBridge.swift)
TelegramCore         ChatInputTableCell / Row    (TelegramCore/.../ChatInputContent/ChatInputContentModel.swift)
   ↕  ChatInputContentInstantPage               (TelegramCore/.../ChatInputContent/ChatInputContentInstantPage.swift)
Core InstantPage     InstantPageTableCell        (SyncCore_InstantPage.swift)   ✅ already full
   ↕  ApiUtils/InstantPage.swift                                                 ✅ already full
API                  Api.PageTableCell                                           ✅ already full

Editor WYSIWYG render:  RichTextEditorUIKit/Canvas/TableBlockBox.swift
Viewer render:          InstantPageUI/Sources/InstantPageV2Layout.swift + InstantPageRenderer.swift  ✅ already full
```

## Scope & phasing

One spec, two implementation phases behind it:

- **Phase 1 — per-cell header/highlight** (low structural risk; mirrors the existing per-cell
  `horizontalAlignment` seam). Ships and verifies independently.
- **Phase 2 — colspan/rowspan cell merging** (high structural risk; breaks the editor's rectangular-grid
  invariant). Lands on top of Phase 1.

---

## 1. Data model changes & migration

Two composer models change identically. Both use `Codable` with `decodeIfPresent`, so old drafts /
`.rtdoc` files keep loading.

### (a) RichTextEditor Core — `RichTextEditorCore/Model/TableBlock.swift`

- `Cell` gains:
  - `isHeader: Bool = false` (Phase 1)
  - `colspan: Int = 1`, `rowspan: Int = 1` (Phase 2)

  Each added exactly as `horizontalAlignment` was: stored property + `CodingKeys` case +
  `decodeIfPresent(...) ?? default` in the custom `Cell.init(from:)`.
- **`Row.isHeader` is removed** (per decision: per-cell replaces row-level).
- **Migration (decode-only shim):** `Row.init(from:)` still *reads* the legacy `"isHeader"` key; when
  `true`, it seeds each of its cells' `isHeader = true` unless the cell already carries its own value.
  Writing stops emitting the row key. Preserves every existing header row on first load.

### (b) TelegramCore composer currency — `ChatInputContent/ChatInputContentModel.swift`

- `ChatInputTableCell` gains the same `isHeader` / `colspan` / `rowspan` (`decodeIfPresent`, same
  defaults).
- `ChatInputTableRow.isHeader` removed, with the same decode-shim migration. This matters for
  cross-device draft sync + re-login restore (old drafts on the wire keep their header).

### (c) Bridge — `ChatRichTextEditorComposer/.../DocumentChatInputContentBridge.swift`

- `chatInputTable(fromTable:)` (line 181) and `tableBlock(fromChatInputTable:)` (line 436) map the three
  new fields cell-to-cell; the `Row.isHeader` plumbing (lines 200, 459) is dropped on both sides.

### (d) Conversion — `ChatInputContent/ChatInputContentInstantPage.swift`

- **Forward** (`.table` case, line 135): stop hardcoding `header: row.isHeader, colspan: 1, rowspan: 1`
  (line 160) → forward `cell.isHeader`, `cell.colspan`, `cell.rowspan`.
- **Reverse** (`.table` case, line 348): stop inferring `isHeader` from `row.cells.first?.header`
  (line 360) and stop dropping spans (line 374) → set them per-cell.
- Correct the now-stale round-trip comments in both directions (they currently document these fields as
  "not representable").
- **Span default convention (avoid an off-by-one/zero bug):** the editor models use `colspan`/`rowspan`
  **= 1** as the natural "no span" default, whereas the InstantPage/API layer uses **0** to mean
  unset/1 (`InstantPageTableCell` defaults to 0; `inputPageTableCell()` only sets the flag when the value
  `!= 0`; the V2 layout treats `> 1` as a span, else 1). Forward conversion passes the editor value
  through (1 is tolerated end-to-end); reverse maps an InstantPage `0` **or** `1` back to editor `1`.
  Covered by the `colspan`/`rowspan` round-trip test.

### Phase boundary — what each phase touches

- **Phase 1 adds `isHeader` only**, end-to-end (both composer models + bridge + both conversion
  directions + editor UI/render). It does **not** touch `colspan`/`rowspan` anywhere; the
  `ChatInputContentInstantPage` forward keeps emitting `colspan: 1, rowspan: 1` and the reverse keeps
  dropping spans, exactly as today.
- **Phase 2 adds `colspan`/`rowspan`** to both composer models, the bridge, both conversion directions,
  and the editor geometry together — because the composer's live `TableBlockBox` is a dense grid that
  cannot represent a merge until Phase 2's sparse-grid work lands. There is no partial "data-only" span
  support in the composer: a value that can't survive the editor box is not worth persisting through it.

**Independent of both phases:** received rich **messages** carrying merged/header InstantPage tables
already render correctly via the V2 renderer today (§4) — that path never goes through the editor, so it
is unaffected by the composer's phasing.

Everything below the ChatInputContent layer (`InstantPageTableCell`, API, Postbox/FlatBuffers, V2 layout)
is untouched throughout — it already carries all three fields.

---

## 2. Phase 1 — per-cell header/highlight (editor)

### Rendering — `RichTextEditorUIKit/Canvas/TableBlockBox.swift`

Today the header is a hardcoded row-0 band (`headerRowBackgroundRect()` fills `rowHeights[0]`,
lines 340–345; `draw(in:)` fills it lines 380–384) plus render-only bold forced on `r == 0`
(`applyRenderOverrides()` lines 204–213). This becomes per-cell:

- Add a `cellIsHeader: [[Bool]]` parallel array (mirrored from the model like `cellBackgrounds` /
  `cellHAlign`).
- Delete the row-0 band; move the header fill into the **per-cell draw loop** (lines 386–399, beside the
  existing `cellBackgrounds` fill), using `mapper.theme.tableHeaderBackground`.
- **Precedence:** an explicit `cell.background` wins over the header fill (header is a semantic flag;
  background is an explicit color — distinct concepts).
- `applyRenderOverrides()` passes `forceBold:` **per cell** (`cellIsHeader[r][c]`) instead of `r == 0`.
  `strippingBold` / `currentBlock` stay as-is (bold is render-only; the model stays clean).

### Toggle command — `RichTextEditorUIKit/Canvas/DocumentCanvasView+Tables.swift`

- New `toggleSelectionHeader()` modeled verbatim on `setSelectionAlignment(...)` (lines 209–230): read
  `currentBlock()`, walk `selectedCellCoords(in:)` (lines 197–207), flip
  `t.rows[r].cells[c].isHeader`, `replaceTable(...)` inside `editing { }`.
- **Toggle semantics over a mixed selection:** if any selected cell is non-header → set all on; if all
  are already header → set all off.

### Menu — `RichTextEditorUIKit/TableStructuralMenuRequest.swift` + `tableStructuralMenuRequest()`

- Add a `Header` action: new `Kind` case + a descriptor carrying current uniform/mixed state and an
  `apply` closure → `toggleSelectionHeader`. Appears for row and column structural selections and for the
  caret's single cell. **No new selection kind in Phase 1** (that arrives in Phase 2).

### Deletion logic

- The header-protection in `removingRows` / `deleteTableRow` (never deletes a header row) is re-expressed
  per-cell: a row is header-protected iff **all** its cells are header (preserves today's whole-header-row
  behavior); a partially-highlighted row is freely deletable.
- `TableBlock.empty(...)` seeds the first row's *cells* as `isHeader` (replacing the `r == 0` row flag).

### RTF — `RTFConversion.swift` / `RTFImport.swift`

- Export emits `\trhdr` + bold only when a row is *fully* header (preserves current fidelity); a
  partially-highlighted row exports as plain cells — a documented lossy edge, consistent with existing RTF
  limitations (dropped cell backgrounds). Import maps `\trhdr` → all-cells-header.

---

## 3. Phase 2 — colspan/rowspan (cell merging)

High-risk: the editor table stack assumes a strict rectangular grid
(`columnCount == every row's cells.count`, enforced by `TableBlock+Editing.swift`). Merging breaks it.

### (a) Model & covering map

- A merged region is **one anchor `Cell`** (top-left) carrying `colspan`/`rowspan`; the covered grid slots
  hold **no** `Cell`. A row's `cells.count` may be `< columnCount`. The rectangular invariant becomes a
  **span-coverage invariant** (every grid slot covered exactly once — by an anchor or a span).
- `TableMap` (`RichTextEditorCore/Selection/TableMap.swift`) grows a ProseMirror-style **`map: [Int]`**
  (one entry per `row×column` slot → flat index of its owning anchor) + per-anchor `(colspan, rowspan)`.
  - `cellsInRect` **dedupes** to distinct anchors.
  - `rectBetween` **expands** to the smallest rectangle whose edges don't bisect any merged cell (so a
    selection/merge always covers whole cells).
  - This map is the single source of truth all geometry consults.

### (b) Structural transforms — `RichTextEditorCore/Model/TableBlock+Editing.swift`

- New `mergeCells(in: TableRect)`: normalize the rect via the map; the top-left cell becomes the anchor
  with spans set to rect size; covered cells' content is **concatenated into the anchor** (row-major,
  blocks appended) and removed.
- New `splitCell(at:)`: reset the anchor's spans to 1 and re-materialize covered slots as empty cells
  (content stays in the anchor).
- Insert/remove row/column become span-aware: inserting inside a span **grows** it; removing a line a span
  crosses **shrinks** it (deleting the anchor's last line re-homes the anchor).

### (c) Rectangle selection — `RichTextEditorUIKit/Canvas/DocumentCanvasView+TableControls.swift`

- New `TableStructuralSelection.cells(TableRect)` kind alongside `.rows` / `.columns`.
- Entry: drag across cells, or extend a knob from a single cell.
- Selection outline / knobs / hit-testing read the *expanded* rect from the map (never bisects a merge).

### (d) `TableBlockBox` geometry — span-aware

- The dense `cells: [[BlockStack]]` becomes sparse (anchor-keyed).
- Every method assuming `width = columnWidths[c]` / `height = rowHeights[r]` / one-cell-per-slot is
  rewritten to consult the map: `cellRect` sums spanned widths/heights + interior borders; grid-line
  drawing **skips dividers interior to a merged cell**; row-height distribution spreads a rowspan cell's
  height across its rows (mirroring the V2 layout's `awaitingSpanCells` resolution — the proven
  reference); `closestPosition`, `rowIndex`/`columnIndex`, `cellStack(containing:)` resolve through the
  anchor.
- Per the module CLAUDE.md caveat, use the container-aware `activeStack` / `leafRegion` resolvers, **not**
  the brittle `resolveBox`.

### (e) Menu & conversion

- Menu gains **Merge** (shown when a `.cells` selection covers ≥2 cells) and **Split** (shown on a merged
  anchor).
- Both conversion directions already carry `colspan`/`rowspan` from Phase 1's data-model work — Phase 2
  just makes the editor produce non-1 values.

### Merge content default (confirm at planning)

Concatenate covered cells' content into the anchor (nothing lost); Split leaves content in the anchor and
re-creates empty cells. The one behavior to reconfirm during planning.

---

## 4. Viewer (InstantPage V2) — verify + polish

No new rendering code planned; confirm on-device and fix only genuine gaps:

- **Header fill** renders for `cell.header` (`isFilled` → `backgroundColor` → stripe). Verify fill color +
  rounded-corner masking (`tableStripeCornerMask`) for header cells at the grid's rounded outer corners,
  in both themes and RTL.
- **Colspan/rowspan** geometry (`awaitingSpanCells` + border-line construction). Verify interior grid
  lines don't draw through a merged cell and row-span height distribution matches the editor.
- **Round-trip parity:** a table composed in the editor (header + merges) → sent → rendered by V2 is
  visually equivalent to the editor's WYSIWYG. This ties both phases together.
- Any defect found becomes a scoped fix; if none, the renderer work is a verification checklist only.

---

## 5. Testing strategy

Module TDD convention: SwiftPM suite (`swift test` for Core, `Scripts/iostest.sh` for UIKit); app-side
conversion via `//submodules/TextFormat:TextFormatTests` (Bazel `Make.py test --target`).

### Phase 1

- **Core:** extend the `TableCellAlignmentModelTests` pattern → per-cell `isHeader` Codable +
  `decodeIfPresent` back-compat; a dedicated **migration test** (old doc with `Row.isHeader:true` → cells
  load as header). Extend `TableBlockEditingTests` for header-aware row deletion.
- **UIKit:** mirror `TableCellAlignmentTests` → `toggleSelectionHeader` end-to-end; extend
  `CanvasTableHeaderTests` (per-cell fill+bold, not the row-0 band); `TableControlsTests` /
  `CanvasTableMenuActionsTests` for the new Header menu action.
- **Conversion:** extend `ChatInputContentInstantPageTests` for header round-trip (editor → ChatInput →
  InstantPage → API and back), plus the §1 lossless `colspan`/`rowspan` data pass-through criterion.

### Phase 2

- **Core:** `TableMapTests` → covering-map, `rectBetween` expansion, `cellsInRect` dedupe;
  `TableBlockEditingTests` → `mergeCells`/`splitCell` + span-aware insert/remove;
  `TableSelectionConversionTests` → `.cells` selection.
- **UIKit:** `TableBlockBoxTests` / `TableMeasureTests` → span geometry (`cellRect`, row-height
  distribution, skipped interior borders); `TableControlsTests` → rectangle selection + Merge/Split menu;
  nav/selection/backspace suites (`CanvasTableNavTests`, `CanvasTableSelectionTests`,
  `CanvasCrossCellEditTests`, …) updated for merged cells.
- **Conversion:** span round-trip through all four model layers.

### Runtime verification

Logged-in-sim pass on the **iPhone 17 Pro K3** sim (per the testing-sim convention) for both the composer
(create header + merge, send) and the viewer (receive + render) — the SwiftPM suite does not exercise the
app-side bridge/conversion.

## Out of scope

- Arbitrary per-cell background *colors* in the composer UI (the `background` field exists but is not part
  of this feature; only the semantic header/highlight flag is exposed).
- RTF fidelity for merges and partial-header rows (documented lossy edges).
- Nested tables inside cells (pre-existing v1 restriction).
