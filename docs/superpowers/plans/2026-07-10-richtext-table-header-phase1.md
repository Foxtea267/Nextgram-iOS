# RichText Tables — Phase 1: per-cell header/highlight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the composer set a **per-cell** header/highlight flag (filled + bold cell), replacing the whole-row header concept as the source of truth, and round-trip it through the two composer models to the InstantPage/API layer (which already carries it).

**Architecture:** Add a per-cell `isHeader` field to both composer models (RichTextEditor Core `Cell`, TelegramCore `ChatInputTableCell`). Make each model's row-level `isHeader` a **computed** getter (`all cells header`) so the stored field is gone from serialization — with a decode migration that folds an old row-level `isHeader` into its cells, and an `isHeader:` init parameter retained as a convenience that seeds cells (keeps existing call sites compiling). Render the header fill+bold per-cell in `TableBlockBox`, add a `toggleSelectionHeader()` command mirroring `setSelectionAlignment`, and expose it via the structural menu. Thread the flag through the bridge and both `ChatInputContentInstantPage` directions. `colspan`/`rowspan` are untouched (Phase 2).

**Tech Stack:** Swift, SwiftPM (RichTextEditor package: `swift test` for Core on macOS, `Scripts/iostest.sh` for UIKit on the iOS simulator), Bazel (app build + `//submodules/TextFormat:TextFormatTests`).

**Spec:** `docs/superpowers/specs/2026-07-10-richtext-table-header-span-design.md` (§1, §2, §5).

---

## File structure

**Modify (production):**
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/TableBlock.swift` — `Cell.isHeader` + `Row` computed/init/Codable migration.
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/DocumentFragment.swift` — preserve per-cell fields on table paste-regenerate.
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/TableBlockBox.swift` — per-cell header array, per-cell fill+bold, round-trip, `isHeaderCell`/`isHeaderRow`.
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+Tables.swift` — `toggleSelectionHeader()`.
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/TableStructuralMenuRequest.swift` — `Header` descriptor.
- `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+TableControls.swift` — build the `Header` descriptor + pass it into both menu branches.
- `submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentModel.swift` — `ChatInputTableCell.isHeader` + `ChatInputTableRow` computed/migration.
- `submodules/TelegramUI/Components/Chat/ChatRichTextEditorComposer/Sources/DocumentChatInputContentBridge.swift` — map `isHeader` both directions.
- `submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentInstantPage.swift` — forward/reverse per-cell `isHeader`.

**Modify (tests):**
- `.../RichTextEditorUIKitTests/TableBlockBoxTests.swift` — replace the row-band header test.

**Create (tests):**
- `.../RichTextEditorCoreTests/TableCellHeaderModelTests.swift`
- `.../RichTextEditorUIKitTests/TableHeaderToggleTests.swift`
- Header round-trip cases added to `submodules/TextFormat/Tests/ChatInputContentInstantPageTests.swift`.

**Build/test commands (memorize):**
- Core tests: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter <ClassName>`
- UIKit tests: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh <Class/test>`
- TextFormat tests (Bazel): `source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache test --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --target //submodules/TextFormat:TextFormatTests`
- Full app build: the `Make.py build … --configuration=debug_sim_arm64` command from the repo `CLAUDE.md`.

---

## Task 1: Core model — `Cell.isHeader` + `Row` computed header with migration

**Files:**
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/TableBlock.swift`
- Create: `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorCoreTests/TableCellHeaderModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TableCellHeaderModelTests.swift`:

```swift
import XCTest
@testable import RichTextEditorCore

final class TableCellHeaderModelTests: XCTestCase {
    func test_cellHeaderDefaultsFalse() {
        XCTAssertFalse(Cell(id: BlockID("c")).isHeader)
    }

    func test_cellHeaderRoundTrips() throws {
        var cell = Cell(id: BlockID("c"))
        cell.isHeader = true
        let data = try JSONEncoder().encode(cell)
        XCTAssertTrue(try JSONDecoder().decode(Cell.self, from: data).isHeader)
    }

    func test_legacyCellWithoutHeader_decodesFalse() throws {
        let json = #"{"id":"c","blocks":[]}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(Cell.self, from: json).isHeader)
    }

    func test_rowIsHeaderIsDerivedFromCells() {
        let hdr = { (id: String) -> Cell in var c = Cell(id: BlockID(id)); c.isHeader = true; return c }
        XCTAssertTrue(Row(id: BlockID("r"), cells: [hdr("a"), hdr("b")]).isHeader)
        XCTAssertFalse(Row(id: BlockID("r"), cells: [hdr("a"), Cell(id: BlockID("b"))]).isHeader) // partial → not a header row
        XCTAssertFalse(Row(id: BlockID("r"), cells: []).isHeader)                                  // empty → not a header row
    }

    func test_initHeaderParamSeedsCells() {
        let row = Row(id: BlockID("r"), isHeader: true, cells: [Cell(id: BlockID("a")), Cell(id: BlockID("b"))])
        XCTAssertTrue(row.cells.allSatisfy { $0.isHeader })
        XCTAssertTrue(row.isHeader)
    }

    func test_legacyRowHeader_migratesIntoCells() throws {
        // A row written before per-cell header: row-level "isHeader":true, cells with no header field.
        let json = #"{"id":"r","cells":[{"id":"a","blocks":[]},{"id":"b","blocks":[]}],"isHeader":true}"#.data(using: .utf8)!
        let row = try JSONDecoder().decode(Row.self, from: json)
        XCTAssertTrue(row.cells.allSatisfy { $0.isHeader }, "legacy row header folds into every cell")
        XCTAssertTrue(row.isHeader)
    }

    func test_rowDoesNotEncodeIsHeaderKey() throws {
        let row = Row(id: BlockID("r"), isHeader: true, cells: [Cell(id: BlockID("a"))])
        let json = String(data: try JSONEncoder().encode(row), encoding: .utf8)!
        XCTAssertFalse(json.contains("\"isHeader\""), "row-level isHeader is not serialized (per-cell is the truth)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter TableCellHeaderModelTests`
Expected: FAIL to compile (`Cell` has no `isHeader`).

- [ ] **Step 3: Add `Cell.isHeader`**

In `TableBlock.swift`, replace the `Cell` struct's stored properties, memberwise init, `CodingKeys`, and custom decoder to include `isHeader`:

```swift
public struct Cell: Codable, Equatable {
    public var id: BlockID
    public var blocks: [Block]
    public var background: RGBAColor?
    public var horizontalAlignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    /// Per-cell header/highlight flag (fill + bold). Replaces the old whole-row header concept.
    public var isHeader: Bool

    public init(id: BlockID, blocks: [Block] = [], background: RGBAColor? = nil,
                horizontalAlignment: TextAlignment = .center, verticalAlignment: VerticalAlignment = .top,
                isHeader: Bool = false) {
        self.id = id
        self.blocks = blocks
        self.background = background
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.isHeader = isHeader
    }

    private enum CodingKeys: String, CodingKey { case id, blocks, background, horizontalAlignment, verticalAlignment, isHeader }

    // Custom decode so cells written before these fields existed still load (defaults applied).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(BlockID.self, forKey: .id)
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        background = try c.decodeIfPresent(RGBAColor.self, forKey: .background)
        horizontalAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .horizontalAlignment) ?? .center
        verticalAlignment = try c.decodeIfPresent(VerticalAlignment.self, forKey: .verticalAlignment) ?? .top
        isHeader = try c.decodeIfPresent(Bool.self, forKey: .isHeader) ?? false
    }
}
```

- [ ] **Step 4: Rework `Row` — computed header + seeding init + migration Codable**

In `TableBlock.swift`, replace the entire `Row` struct with:

```swift
public struct Row: Equatable {
    public var id: BlockID
    public var height: Double?
    public var cells: [Cell]

    /// Whether EVERY cell is a header cell (and the row is non-empty). Derived — there is no stored
    /// row-level header; per-cell `Cell.isHeader` is the single source of truth.
    public var isHeader: Bool { !cells.isEmpty && cells.allSatisfy { $0.isHeader } }

    /// `isHeader: true` seeds every cell as a header cell (convenience for callers/tests that think in
    /// whole rows). `false` leaves each cell's own flag untouched.
    public init(id: BlockID, height: Double? = nil, isHeader: Bool = false, cells: [Cell] = []) {
        self.id = id
        self.height = height
        self.cells = isHeader ? cells.map { var c = $0; c.isHeader = true; return c } : cells
    }
}

extension Row: Codable {
    private enum CodingKeys: String, CodingKey { case id, height, cells; case legacyIsHeader = "isHeader" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(BlockID.self, forKey: .id)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        var decodedCells = try c.decodeIfPresent([Cell].self, forKey: .cells) ?? []
        // Migration: a row written before per-cell header carried a row-level `isHeader`. Fold it in.
        if (try c.decodeIfPresent(Bool.self, forKey: .legacyIsHeader)) == true {
            decodedCells = decodedCells.map { var cell = $0; cell.isHeader = true; return cell }
        }
        cells = decodedCells
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encode(cells, forKey: .cells)
        // Deliberately does NOT encode `isHeader` — it is derived from the cells.
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter TableCellHeaderModelTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Run the existing Core table suites to confirm no regression**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter TableBlock`
Expected: PASS (existing `TableBlockTests`, `TableBlockEditingTests`, `TableBlockEmptyTests`, `TableCellAlignmentModelTests` all green — the retained `isHeader:` init param and computed getter keep them compiling and behaving).

- [ ] **Step 7: Commit**

```bash
git add submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/TableBlock.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorCoreTests/TableCellHeaderModelTests.swift
git commit -m "feat(richtext-core): per-cell Cell.isHeader; derive Row.isHeader with decode migration"
```

---

## Task 2: `DocumentFragment` — preserve per-cell fields on table paste-regenerate

The table-copy/paste ID-regeneration currently rebuilds cells with only `id`/`blocks`/`background`, silently dropping per-cell alignment (a latent bug) and — after Task 1 — would drop `isHeader`. Preserve all cell fields.

**Files:**
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/DocumentFragment.swift`
- Test: `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorCoreTests/DocumentFragmentTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `DocumentFragmentTests.swift` (inside the existing `final class DocumentFragmentTests: XCTestCase { … }`):

```swift
    func test_regeneratingIDs_preservesPerCellHeaderAndAlignment() {
        var h = Cell(id: BlockID("a"), blocks: [.paragraph(ParagraphBlock(id: BlockID("ap")))],
                     horizontalAlignment: .right, verticalAlignment: .bottom)
        h.isHeader = true
        let body = Cell(id: BlockID("b"), blocks: [.paragraph(ParagraphBlock(id: BlockID("bp")))])
        let table = TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
                               rows: [Row(id: BlockID("r"), cells: [h, body])])
        guard case .table(let out) = regeneratingIDs([.table(table)])[0] else { return XCTFail() }
        XCTAssertTrue(out.rows[0].cells[0].isHeader)
        XCTAssertEqual(out.rows[0].cells[0].horizontalAlignment, .right)
        XCTAssertEqual(out.rows[0].cells[0].verticalAlignment, .bottom)
        XCTAssertFalse(out.rows[0].cells[1].isHeader)
    }
```

If `regeneratingIDs` is not directly accessible from the test, replace the call with the public entry point the file already exposes (the existing tests in this file show the accessible name — use the same one they use). Keep the assertions identical.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter DocumentFragmentTests/test_regeneratingIDs_preservesPerCellHeaderAndAlignment`
Expected: FAIL (`isHeader` false / alignment reset to defaults).

- [ ] **Step 3: Preserve all cell fields**

In `DocumentFragment.swift`, change the `.table` cell map (currently lines 35–38) to:

```swift
            return .table(TableBlock(id: .generate(), columns: t.columns, rows: t.rows.map { row in
                Row(id: .generate(), height: row.height, cells: row.cells.map { cell in
                    Cell(id: .generate(), blocks: regeneratingIDs(cell.blocks), background: cell.background,
                         horizontalAlignment: cell.horizontalAlignment, verticalAlignment: cell.verticalAlignment,
                         isHeader: cell.isHeader)
                })
            }))
```

(The `Row` no longer passes `isHeader:` — per-cell `isHeader` on the mapped cells is authoritative.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test --filter DocumentFragmentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/DocumentFragment.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorCoreTests/DocumentFragmentTests.swift
git commit -m "fix(richtext-core): preserve per-cell header + alignment on table paste-regenerate"
```

---

## Task 3: `TableBlockBox` — per-cell header render + round-trip

**Files:**
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/TableBlockBox.swift`
- Modify (test): `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableBlockBoxTests.swift`
- Test: `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/CanvasTableHeaderTests.swift`

- [ ] **Step 1: Write the failing test (per-cell header, incl. a partial-header row)**

Append to `CanvasTableHeaderTests.swift` (inside the class, before the final `}`):

```swift
    func test_perCellHeader_partialRow_fillsAndBoldsOnlyHeaderCells() {
        func hcell(_ id: String, _ t: String) -> Cell {
            var c = cell(id, t); c.isHeader = true; return c
        }
        let v = DocumentCanvasView()
        // Row 0: cell (0,0) header, cell (0,1) NOT header — a partial-header row (impossible under the old model).
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 140), ColumnSpec(width: 140)],
            rows: [Row(id: BlockID("r0"), cells: [hcell("a", "H"), cell("b", "x")]),
                   Row(id: BlockID("r1"), cells: [cell("c", "y"), cell("d", "z")])]))], width: 340)
        v.frame = CGRect(x: 0, y: 0, width: 340, height: 400); v.layoutIfNeeded()
        let t = v.boxes[0] as! TableBlockBox
        XCTAssertTrue(t.isHeaderCell(0, 0))
        XCTAssertFalse(t.isHeaderCell(0, 1))
        XCTAssertFalse(t.isHeaderRow(0), "a partially-header row is not a header row")
        func bold(_ r: Int, _ c: Int) -> Bool {
            let s = t.cells[r][c].boxes[0] as! BlockBox
            let f = s.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! UIFont
            return f.fontDescriptor.symbolicTraits.contains(.traitBold)
        }
        XCTAssertTrue(bold(0, 0))   // header cell → bold
        XCTAssertFalse(bold(0, 1))  // non-header cell → not bold
        // model round-trips the per-cell flag and stays clean (no synthetic bold persisted)
        guard case .table(let tb) = t.currentBlock() else { return XCTFail() }
        XCTAssertTrue(tb.rows[0].cells[0].isHeader)
        XCTAssertFalse(tb.rows[0].cells[1].isHeader)
        if case .paragraph(let p) = tb.rows[0].cells[0].blocks[0] { XCTAssertFalse(p.runs[0].attributes.bold) }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh CanvasTableHeaderTests/test_perCellHeader_partialRow_fillsAndBoldsOnlyHeaderCells`
Expected: FAIL to compile (`isHeaderCell` undefined) then FAIL (row-0 bold logic).

- [ ] **Step 3: Add the per-cell header array + accessors**

In `TableBlockBox.swift`:

Replace the stored property declaration `var rowIsHeader: [Bool]` (line 13) with:
```swift
    var cellIsHeader: [[Bool]]
```

In `init(table:mapper:width:)`, replace the line `rowIsHeader = table.rows.map { $0.isHeader }` (line 60) with:
```swift
        cellIsHeader = table.rows.map { $0.cells.map { $0.isHeader } }
```

Replace `isHeaderRow(_:)` (line 367) and add `isHeaderCell`:
```swift
    /// Whether cell (r, c) is a header/highlight cell.
    func isHeaderCell(_ r: Int, _ c: Int) -> Bool {
        cellIsHeader.indices.contains(r) && cellIsHeader[r].indices.contains(c) && cellIsHeader[r][c]
    }

    /// Whether row `r` is a full header row (every cell a header). Derived from per-cell flags.
    func isHeaderRow(_ r: Int) -> Bool {
        cellIsHeader.indices.contains(r) && !cellIsHeader[r].isEmpty && cellIsHeader[r].allSatisfy { $0 }
    }
```

- [ ] **Step 4: Round-trip the flag in `currentBlock()`**

Replace the body of `currentBlock()` (lines 186–200) with:
```swift
    func currentBlock() -> Block {
        var rows: [Row] = []
        for (r, row) in cells.enumerated() {
            var outCells: [Cell] = []
            for (c, stack) in row.enumerated() {
                var blocks = stack.boxes.map { $0.currentBlock() }
                if isHeaderCell(r, c) { blocks = blocks.map { TableBlockBox.strippingBold($0) } }
                outCells.append(Cell(id: cellIDs[r][c], blocks: blocks, background: cellBackgrounds[r][c],
                                     horizontalAlignment: cellHAlign[r][c], verticalAlignment: cellVAlign[r][c],
                                     isHeader: cellIsHeader[r][c]))
            }
            rows.append(Row(id: rowIDs[r], height: rowMinHeights[r] > 0 ? Double(rowMinHeights[r]) : nil,
                            cells: outCells))
        }
        return .table(TableBlock(id: id, columns: columns, rows: rows))
    }
```

- [ ] **Step 5: Drive bold per-cell in `applyRenderOverrides()`**

Replace `applyRenderOverrides()` (lines 204–213) with:
```swift
    /// Re-applies the render-only overrides to every cell's display layout: per-cell alignment and,
    /// for header cells, bold. Idempotent; called at build and on each recompute so it survives edits.
    private func applyRenderOverrides() {
        for (r, row) in cells.enumerated() {
            for (c, stack) in row.enumerated() {
                let alignment = cellHAlign[r][c]
                for box in stack.boxes {
                    (box as? BlockBox)?.applyDisplayOverride(alignment: alignment, forceBold: isHeaderCell(r, c), mapper: mapper)
                }
            }
        }
    }
```

- [ ] **Step 6: Per-cell header fill in `draw`; remove the row-0 band**

Delete `headerRowBackgroundRect()` (lines 337–345) entirely.

In `draw(in:imageProvider:)`, delete the row-band fill block (lines 379–384):
```swift
        // Header-row tint, clipped to the rounded border so the top corners round with the table.
        if let headerRect = headerRowBackgroundRect() {
            ctx.saveGState(); outer.addClip()
            mapper.theme.tableHeaderBackground.setFill(); ctx.fill(headerRect)
            ctx.restoreGState()
        }
```

Replace it with a per-cell fill pass (header OR explicit background), clipped to the rounded outer path so corner cells round:
```swift
        // Per-cell fills (explicit background wins over the header highlight), clipped to the rounded outer
        // border so header/background cells at the table corners round with the table.
        ctx.saveGState(); outer.addClip()
        var fy = frame.minY + TableBlockBox.border
        for (r, row) in cells.enumerated() {
            var fx = frame.minX + TableBlockBox.border
            for (c, _) in row.enumerated() {
                let fill = cellBackgrounds[r][c]?.uiColor ?? (isHeaderCell(r, c) ? mapper.theme.tableHeaderBackground : nil)
                if let fill { fill.setFill(); ctx.fill(CGRect(x: fx, y: fy, width: columnWidths[c], height: rowHeights[r])) }
                fx += columnWidths[c] + TableBlockBox.border
            }
            fy += rowHeights[r] + TableBlockBox.border
        }
        ctx.restoreGState()
```

Then, in the existing content loop below it, delete the now-duplicated per-cell background fill line (line 390):
```swift
                if let bg = cellBackgrounds[r][c] { bg.uiColor.setFill(); ctx.fill(cellRect) }
```
and the now-unused `let cellRect = …` on line 389 if it becomes unused (keep it only if `cellRect` is still referenced later in that loop — it is not; remove it to silence the warning).

- [ ] **Step 7: Set the header array in `appendRow()`**

In `appendRow()`, replace the line `rowIDs.append(BlockID.generate()); rowIsHeader.append(false); rowMinHeights.append(0)` (line 363) with:
```swift
        cellIsHeader.append(Array(repeating: false, count: n))
        rowIDs.append(BlockID.generate()); rowMinHeights.append(0)
```

- [ ] **Step 8: Replace the obsolete row-band test**

In `TableBlockBoxTests.swift`, replace `test_headerRowBackground_coversFirstRowOnly_withGrayTint()` (lines 126–140) with a per-cell header test:
```swift
    func test_perCellHeader_flagsFirstRowCells_withTranslucentTint() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(headerTable())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutIfNeeded()
        let t = box(v)
        XCTAssertTrue(t.isHeaderCell(0, 0)); XCTAssertTrue(t.isHeaderCell(0, 1))   // header row cells flagged
        XCTAssertFalse(t.isHeaderCell(1, 0))                                        // body row not
        var alpha: CGFloat = 1
        RichTextEditorTheme.default.tableHeaderBackground.getWhite(nil, alpha: &alpha)
        XCTAssertLessThan(alpha, 1)                                                 // a translucent gray tint
    }
```
(`headerTable()` and `box(_:)` are the file's existing helpers.)

- [ ] **Step 9: Run the UIKit header tests to verify they pass**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh CanvasTableHeaderTests` then `Scripts/iostest.sh TableBlockBoxTests`
Expected: PASS (including the pre-existing `test_headerRowFlagAndRendersNonBlank`, `test_firstRowBold_othersNot_modelStaysClean`, and the `TableBlockBoxTests` bold test — a full header row still flags all its cells and renders bold).

- [ ] **Step 10: Commit**

```bash
git add submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/TableBlockBox.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/CanvasTableHeaderTests.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableBlockBoxTests.swift
git commit -m "feat(richtext-ui): render per-cell table header fill + bold"
```

---

## Task 4: `toggleSelectionHeader()` command

**Files:**
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+Tables.swift`
- Create: `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableHeaderToggleTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TableHeaderToggleTests.swift`:

```swift
#if canImport(UIKit)
import XCTest
import RichTextEditorCore
@testable import RichTextEditorUIKit

@available(iOS 13.0, *)
final class TableHeaderToggleTests: XCTestCase {
    private func cell(_ id: String, _ text: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), style: .body, runs: [TextRun(text: text)]))])
    }

    private func makeView() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a","A"), cell("b","B")]),
                   Row(id: BlockID("r1"), cells: [cell("c","C"), cell("d","D")])]))], width: 390)
        v.frame = CGRect(x: 0, y: 0, width: 390, height: 400); v.layoutIfNeeded()
        return v
    }

    func test_toggleHeader_onSelectedColumn_setsThenClearsThoseCells() {
        let v = makeView()
        let t = v.boxes[0] as! TableBlockBox
        v.head = t.cellTextStart(row: 1, column: 1)!; v.anchor = v.head
        v.selectTableColumn(1)
        // Column 1 is mixed (r0 header, r1 body) → first toggle turns ALL on.
        v.toggleSelectionHeader()
        guard case .table(let on) = v.boxes[0].currentBlock() else { return XCTFail() }
        XCTAssertTrue(on.rows[0].cells[1].isHeader)
        XCTAssertTrue(on.rows[1].cells[1].isHeader)
        XCTAssertFalse(on.rows[1].cells[0].isHeader, "column 0 untouched")
        // Now all-on → next toggle turns them all off.
        v.selectTableColumn(1)
        v.toggleSelectionHeader()
        guard case .table(let off) = v.boxes[0].currentBlock() else { return XCTFail() }
        XCTAssertFalse(off.rows[0].cells[1].isHeader)
        XCTAssertFalse(off.rows[1].cells[1].isHeader)
    }

    func test_toggleHeader_caretCellOnly_whenNoStructuralSelection() {
        let v = makeView()
        let t = v.boxes[0] as! TableBlockBox
        v.head = t.cellTextStart(row: 1, column: 0)!; v.anchor = v.head   // body cell, no structural selection
        v.toggleSelectionHeader()
        guard case .table(let out) = v.boxes[0].currentBlock() else { return XCTFail() }
        XCTAssertTrue(out.rows[1].cells[0].isHeader)
        XCTAssertFalse(out.rows[1].cells[1].isHeader)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh TableHeaderToggleTests`
Expected: FAIL to compile (`toggleSelectionHeader` undefined).

- [ ] **Step 3: Implement the command**

In `DocumentCanvasView+Tables.swift`, add this method inside the `extension DocumentCanvasView` (e.g. right after `setSelectionAlignment(horizontal:vertical:)`):

```swift
    /// Toggles the header/highlight flag on every cell of the current structural selection (or the caret's
    /// single cell when there is none). Mixed/none → all ON; all-header → all OFF. One undo step; preserves
    /// the structural selection. Mirrors `setSelectionAlignment`.
    func toggleSelectionHeader() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(var t) = a.box.currentBlock() else { return }
            let coords = selectedCellCoords(in: a.box).filter { t.rows.indices.contains($0.row) && t.rows[$0.row].cells.indices.contains($0.column) }
            guard !coords.isEmpty else { return }
            let newValue = !coords.allSatisfy { t.rows[$0.row].cells[$0.column].isHeader }
            for (r, c) in coords { t.rows[r].cells[c].isHeader = newValue }
            replaceTable(at: a.index, with: t, caretRow: a.row, caretCol: a.col)
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh TableHeaderToggleTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+Tables.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableHeaderToggleTests.swift
git commit -m "feat(richtext-ui): toggleSelectionHeader command (per-cell header over structural selection)"
```

---

## Task 5: Structural menu — `Header` descriptor

**Files:**
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/TableStructuralMenuRequest.swift`
- Modify: `submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+TableControls.swift`
- Modify (test): `submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableControlsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `TableControlsTests.swift` (inside the class):

```swift
    func test_structuralMenu_carriesHeaderDescriptor_reflectingMixedState() {
        func cell(_ id: String) -> Cell { Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p")))]) }
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a"), cell("b")]),
                   Row(id: BlockID("r1"), cells: [cell("c"), cell("d")])]))], width: 390)
        v.frame = CGRect(x: 0, y: 0, width: 390, height: 400); v.layoutIfNeeded()
        let t = v.boxes[0] as! TableBlockBox
        v.head = t.cellTextStart(row: 0, column: 0)!; v.anchor = v.head
        v.selectTableColumn(0)   // column 0: r0 header, r1 body → mixed
        let req = v.tableStructuralMenuRequest()
        XCTAssertNotNil(req?.header)
        XCTAssertNil(req?.header?.isHeader, "mixed selection reports nil (indeterminate)")
        // Applying flips the mixed column ON.
        req?.header?.apply()
        guard case .table(let out) = v.boxes[0].currentBlock() else { return XCTFail() }
        XCTAssertTrue(out.rows[0].cells[0].isHeader && out.rows[1].cells[0].isHeader)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh TableControlsTests/test_structuralMenu_carriesHeaderDescriptor_reflectingMixedState`
Expected: FAIL to compile (`header` property absent on the request).

- [ ] **Step 3: Add the `Header` descriptor to the request**

In `TableStructuralMenuRequest.swift`, add a stored property + init param + nested struct.

Add the property after `public let alignment: Alignment?`:
```swift
    /// The header/highlight toggle for the selected cells (present for both row and column selections).
    public let header: Header?
```

Change the initializer to:
```swift
    public init(view: UIView?, sourceRect: CGRect, actions: [Action], alignment: Alignment?, header: Header?) {
        self.view = view
        self.sourceRect = sourceRect
        self.actions = actions
        self.alignment = alignment
        self.header = header
    }
```

Add the nested struct after the `Alignment` struct (before the closing `}` of the class):
```swift
    /// The header/highlight toggle for the selected cells: the uniform current value (nil = the cells
    /// disagree, "mixed"/indeterminate), and `apply` to toggle every selected cell. Present for both
    /// row and column selections.
    public struct Header {
        public let isHeader: Bool?
        public let apply: () -> Void
        public init(isHeader: Bool?, apply: @escaping () -> Void) {
            self.isHeader = isHeader
            self.apply = apply
        }
    }
```

- [ ] **Step 4: Build the descriptor and pass it into both menu branches**

In `DocumentCanvasView+TableControls.swift`, add a builder next to `structuralAlignmentDescriptor()`:
```swift
    /// The header descriptor for the current structural selection: the uniform per-cell header value
    /// (nil if the selected cells disagree) + an `apply` that toggles it on all selected cells.
    private func structuralHeaderDescriptor() -> TableStructuralMenuRequest.Header? {
        guard let a = activeTable() else { return nil }
        guard case .table(let t) = a.box.currentBlock() else { return nil }
        let coords = selectedCellCoords(in: a.box).filter { t.rows.indices.contains($0.row) && t.rows[$0.row].cells.indices.contains($0.column) }
        guard !coords.isEmpty else { return nil }
        let flags = Set(coords.map { t.rows[$0.row].cells[$0.column].isHeader })
        return TableStructuralMenuRequest.Header(
            isHeader: flags.count == 1 ? flags.first : nil,
            apply: { [weak self] in self?.toggleSelectionHeader() })
    }
```

In `tableStructuralMenuRequest()`, pass the header into BOTH `return TableStructuralMenuRequest(...)` sites. Change the `.columns` return (line 319) to:
```swift
            return TableStructuralMenuRequest(view: self, sourceRect: sourceRect, actions: actions, alignment: alignment, header: structuralHeaderDescriptor())
```
and the `.rows` return (line 331) to:
```swift
            return TableStructuralMenuRequest(view: self, sourceRect: sourceRect, actions: actions, alignment: structuralAlignmentDescriptor(), header: structuralHeaderDescriptor())
```

- [ ] **Step 5: Fix the other `TableStructuralMenuRequest(...)` construction sites**

Run: `cd /Users/isaac/build/telegram/telegram-ios && grep -rn "TableStructuralMenuRequest(" submodules/TelegramUI/Components/RichTextEditor/ submodules/TelegramUI --include=*.swift`
For every construction call other than the two above (production or test), add `header: nil` (or an appropriate descriptor) so it compiles. Expected non-test sites: none beyond the two above; add `header: nil` to any test-side constructions found.

- [ ] **Step 6: Run to verify it passes**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh TableControlsTests`
Expected: PASS (existing `TableControlsTests` + the new case).

- [ ] **Step 7: Commit**

```bash
git add submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/TableStructuralMenuRequest.swift \
        submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+TableControls.swift \
        submodules/TelegramUI/Components/RichTextEditor/Tests/RichTextEditorUIKitTests/TableControlsTests.swift
git commit -m "feat(richtext-ui): expose per-cell header toggle in the table structural menu"
```

---

## Task 6: Full editor SwiftPM suite green

**Files:** none (verification + any compile fallout from Tasks 1–5).

- [ ] **Step 1: Run the full Core suite**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && swift test`
Expected: PASS. If a test fails to compile because it constructed `Row`/`Cell` positionally, fix it minimally (add `isHeader:` where intended, or seed cells). Do NOT change behavior assertions unless the new per-cell semantics genuinely changed the expected value; if one did, update it and note why in the commit.

- [ ] **Step 2: Run the full UIKit suite**

Run: `cd submodules/TelegramUI/Components/RichTextEditor && Scripts/iostest.sh`
Expected: PASS (~690 tests). Address any compile fallout the same way.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A submodules/TelegramUI/Components/RichTextEditor
git commit -m "test(richtext): fixups for per-cell header model change"
```
(Skip if there were none.)

---

## Task 7: Composer currency — `ChatInputTableCell.isHeader` + `ChatInputTableRow` migration

**Files:**
- Modify: `submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentModel.swift`
- Test: `submodules/TextFormat/Tests/ChatInputContentModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `ChatInputContentModelTests.swift` (inside the existing test class):

```swift
    func test_chatInputTableRow_headerIsDerivedFromCells_andNotEncoded() throws {
        let hdr = ChatInputTableCell(runs: [ChatInputRun(text: "H")], isHeader: true)
        let body = ChatInputTableCell(runs: [ChatInputRun(text: "B")])
        XCTAssertTrue(ChatInputTableRow(cells: [hdr]).isHeader)
        XCTAssertFalse(ChatInputTableRow(cells: [hdr, body]).isHeader)
        let json = String(data: try JSONEncoder().encode(ChatInputTableRow(isHeader: true, cells: [ChatInputTableCell(runs: [])])), encoding: .utf8)!
        XCTAssertFalse(json.contains("\"isHeader\""))
    }

    func test_chatInputTableRow_legacyHeader_migratesIntoCells() throws {
        let json = #"{"cells":[{"runs":[]},{"runs":[]}],"isHeader":true}"#.data(using: .utf8)!
        let row = try JSONDecoder().decode(ChatInputTableRow.self, from: json)
        XCTAssertTrue(row.cells.allSatisfy { $0.isHeader })
        XCTAssertTrue(row.isHeader)
    }

    func test_chatInputTableRow_initHeaderParam_seedsCells() {
        let row = ChatInputTableRow(isHeader: true, cells: [ChatInputTableCell(runs: []), ChatInputTableCell(runs: [])])
        XCTAssertTrue(row.cells.allSatisfy { $0.isHeader })
    }
```

- [ ] **Step 2: Run to verify it fails**

Run the TextFormat Bazel test command (see File structure).
Expected: FAIL to compile (`ChatInputTableCell` has no `isHeader`).

- [ ] **Step 3: Add `ChatInputTableCell.isHeader`**

In `ChatInputContentModel.swift`, replace the `ChatInputTableCell` struct (lines 877–897) with:
```swift
public struct ChatInputTableCell: Equatable, Codable {
    public var runs: [ChatInputRun]
    public var background: ChatInputColor?
    public var horizontalAlignment: ChatInputTextAlignment
    public var verticalAlignment: ChatInputTableVerticalAlignment
    /// Per-cell header/highlight flag (replaces the old whole-row header).
    public var isHeader: Bool
    public init(runs: [ChatInputRun] = [], background: ChatInputColor? = nil,
                horizontalAlignment: ChatInputTextAlignment = .center, verticalAlignment: ChatInputTableVerticalAlignment = .top,
                isHeader: Bool = false) {
        self.runs = runs
        self.background = background
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.isHeader = isHeader
    }
    private enum CodingKeys: String, CodingKey { case runs, background, horizontalAlignment, verticalAlignment, isHeader }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runs = try c.decodeIfPresent([ChatInputRun].self, forKey: .runs) ?? []
        background = try c.decodeIfPresent(ChatInputColor.self, forKey: .background)
        horizontalAlignment = try c.decodeIfPresent(ChatInputTextAlignment.self, forKey: .horizontalAlignment) ?? .center
        verticalAlignment = try c.decodeIfPresent(ChatInputTableVerticalAlignment.self, forKey: .verticalAlignment) ?? .top
        isHeader = try c.decodeIfPresent(Bool.self, forKey: .isHeader) ?? false
    }
}
```

- [ ] **Step 4: Rework `ChatInputTableRow` (computed header + migration)**

Replace the `ChatInputTableRow` struct (lines 900–909) with:
```swift
/// A table row. `isHeader` is derived from the cells (per-cell is the source of truth).
public struct ChatInputTableRow: Equatable {
    public var height: Double?
    public var cells: [ChatInputTableCell]
    public var isHeader: Bool { !cells.isEmpty && cells.allSatisfy { $0.isHeader } }
    /// `isHeader: true` seeds every cell as a header cell; `false` leaves each cell's own flag untouched.
    public init(height: Double? = nil, isHeader: Bool = false, cells: [ChatInputTableCell] = []) {
        self.height = height
        self.cells = isHeader ? cells.map { var c = $0; c.isHeader = true; return c } : cells
    }
}

extension ChatInputTableRow: Codable {
    private enum CodingKeys: String, CodingKey { case height, cells; case legacyIsHeader = "isHeader" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        var decodedCells = try c.decodeIfPresent([ChatInputTableCell].self, forKey: .cells) ?? []
        if (try c.decodeIfPresent(Bool.self, forKey: .legacyIsHeader)) == true {
            decodedCells = decodedCells.map { var cell = $0; cell.isHeader = true; return cell }
        }
        cells = decodedCells
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encode(cells, forKey: .cells)
        // Deliberately omits `isHeader` — derived from cells.
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run the TextFormat Bazel test command.
Expected: PASS (the new model tests + the pre-existing `ChatInputContentModelTests` table case — `ChatInputTableRow(isHeader: true/false, …)` still compiles and behaves).

- [ ] **Step 6: Commit**

```bash
git add submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentModel.swift \
        submodules/TextFormat/Tests/ChatInputContentModelTests.swift
git commit -m "feat(telegramcore): per-cell ChatInputTableCell.isHeader; derive row header with migration"
```

---

## Task 8: Bridge + InstantPage conversion — thread `isHeader` per cell

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatRichTextEditorComposer/Sources/DocumentChatInputContentBridge.swift`
- Modify: `submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentInstantPage.swift`
- Modify (tests): `submodules/TextFormat/Tests/ChatInputContentInstantPageTests.swift`, `submodules/TextFormat/Tests/ChatInputContentConversionTests.swift`

- [ ] **Step 1: Write the failing round-trip test (per-cell header, incl. a partial-header row)**

In `ChatInputContentInstantPageTests.swift`, append a new test after `test_table()`:

```swift
    // 13b. Per-cell header: a table whose header cells do NOT form a whole row still round-trips each cell's
    //      `isHeader` independently (the InstantPage layer carries per-cell `header`).
    func test_table_perCellHeader() {
        func c(_ t: String, header: Bool) -> ChatInputTableCell {
            ChatInputTableCell(runs: [ChatInputRun(text: t)], background: nil, horizontalAlignment: .left, verticalAlignment: .top, isHeader: header)
        }
        let table = ChatInputTable(
            columns: [ChatInputColumnSpec(width: 0.0), ChatInputColumnSpec(width: 0.0)],
            rows: [
                ChatInputTableRow(height: nil, cells: [c("H", header: true), c("x", header: false)]),  // partial header row
                ChatInputTableRow(height: nil, cells: [c("y", header: false), c("z", header: true)])
            ])
        assertRoundTrips(ChatInputContent(blocks: [.table(table)]), "2x2 table with per-cell (non-row-aligned) header cells")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run the TextFormat Bazel test command.
Expected: FAIL — the forward conversion currently writes `header: row.isHeader` (a whole-row value), so cell `(0,0)` header and `(0,1)` non-header both collapse to the row's derived header (false), and the round-trip differs.

- [ ] **Step 3: Fix the InstantPage conversion — forward (per-cell header)**

In `ChatInputContentInstantPage.swift`, in the `.table(t)` forward case, change the cell construction (line 160) from `header: row.isHeader` to `header: cell.isHeader`:
```swift
                    return InstantPageTableCell(text: richText(from: cell.runs), header: cell.isHeader, alignment: alignment, verticalAlignment: vAlignment, colspan: 1, rowspan: 1)
```
Update the block comment just above (lines 136–139) to say header is now forwarded per-cell (drop the "header flag" wording that implied row-level); `colspan`/`rowspan` remain fixed at 1 (Phase 2).

- [ ] **Step 4: Fix the InstantPage conversion — reverse (per-cell header)**

In the `.table` reverse case (lines 359–376), delete the `let isHeader = row.cells.first?.header ?? false` line (360), set the per-cell flag on the produced `ChatInputTableCell`, and drop the row-level `isHeader:` argument:
```swift
            let outRows = rows.map { row -> ChatInputTableRow in
                let cells = row.cells.map { cell -> ChatInputTableCell in
                    let alignment: ChatInputTextAlignment
                    switch cell.alignment {
                    case .left: alignment = .left
                    case .center: alignment = .center
                    case .right: alignment = .right
                    }
                    let vAlignment: ChatInputTableVerticalAlignment
                    switch cell.verticalAlignment {
                    case .top: vAlignment = .top
                    case .middle: vAlignment = .middle
                    case .bottom: vAlignment = .bottom
                    }
                    return ChatInputTableCell(runs: chatInputRuns(fromRichText: cell.text ?? .empty), background: nil, horizontalAlignment: alignment, verticalAlignment: vAlignment, isHeader: cell.header)
                }
                return ChatInputTableRow(height: nil, cells: cells)
            }
```
Update the block comment (lines 349–354) to reflect that per-cell `header` now round-trips (it is no longer dropped); `colspan`/`rowspan`/`background`/column `width`/`title` remain non-representable.

- [ ] **Step 5: Thread `isHeader` through the bridge (both directions)**

In `DocumentChatInputContentBridge.swift`:

In `chatInputTable(fromTable:)`, change the `ChatInputTableCell(...)` construction (lines 193–198) to add `isHeader: cell.isHeader`, and drop the row-level `isHeader:` from the row (line 200):
```swift
            ChatInputTableCell(
                runs: chatInputRuns(fromRuns: cellRuns(fromBlocks: cell.blocks), resolveEmoji: resolveEmoji),
                background: cell.background.map(chatInputColor(fromColor:)),
                horizontalAlignment: chatInputTextAlignment(fromAlignment: cell.horizontalAlignment),
                verticalAlignment: chatInputTableVerticalAlignment(fromCore: cell.verticalAlignment),
                isHeader: cell.isHeader
            )
```
```swift
        return ChatInputTableRow(height: row.height, cells: cells)
```

In `tableBlock(fromChatInputTable:)`, change the `Cell(...)` construction (lines 447–457) to add `isHeader: cell.isHeader`, and drop the row-level `isHeader:` (line 459):
```swift
            Cell(
                id: BlockID.generate(),
                blocks: [.paragraph(ParagraphBlock(
                    id: BlockID.generate(),
                    style: .body,
                    runs: runs(fromChatInputRuns: cell.runs, registerEmoji: registerEmoji)
                ))],
                background: cell.background.map(color(fromChatInputColor:)),
                horizontalAlignment: textAlignment(fromChatInputAlignment: cell.horizontalAlignment),
                verticalAlignment: verticalAlignment(fromChatInput: cell.verticalAlignment),
                isHeader: cell.isHeader
            )
```
```swift
        return Row(id: BlockID.generate(), height: row.height, cells: cells)
```

- [ ] **Step 6: Update the existing `test_table` for the new model shape**

In `ChatInputContentInstantPageTests.swift`, the existing `test_table()` builds `ChatInputTableRow(isHeader: true/false, …)`. This still compiles (seeding init) and still round-trips (a full header row → all cells header → per-cell forward/reverse reproduces it), so **leave it as-is unless it fails**. If it fails, it is because a cell was built without `isHeader` and the reverse now sets it — reconcile by giving the header row's cells `isHeader: true` explicitly and dropping the row-level arg. Run and only edit if red.

The `ChatInputContentConversionTests.swift` table case (line 308) uses `ChatInputTableRow(isHeader: false, …)` — unaffected (no header), leave as-is.

- [ ] **Step 7: Run the conversion tests to verify they pass**

Run the TextFormat Bazel test command.
Expected: PASS (`test_table`, new `test_table_perCellHeader`, and the whole `TextFormatTests` target).

- [ ] **Step 8: Commit**

```bash
git add submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentInstantPage.swift \
        submodules/TelegramUI/Components/Chat/ChatRichTextEditorComposer/Sources/DocumentChatInputContentBridge.swift \
        submodules/TextFormat/Tests/ChatInputContentInstantPageTests.swift
git commit -m "feat(chatinput): round-trip per-cell table header through bridge + InstantPage conversion"
```

---

## Task 9: Full app build + runtime verification

**Files:** none (verification only).

- [ ] **Step 1: Full app build**

Run the repo `CLAUDE.md` build command (append `--continueOnError` to surface all errors in one pass):
```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```
Expected: BUILD SUCCEEDED. Fix any consumer that constructed `ChatInputTableRow`/`Cell` positionally (add `isHeader:`/seed cells) or read a removed stored `isHeader` (it is now computed — reads are unaffected).

- [ ] **Step 2: Install onto the K3 sim + launch**

Use the whole-`.app` copy procedure from the repo `CLAUDE.md` ("Updating the running simulator after a rebuild"), targeting `K3=FA6F7462-AA97-42FE-9E57-8DA0593CE756`.

- [ ] **Step 3: Runtime verification — composer (setting)**

In the RichText composer: insert a table; select a column (handle) and toggle **Header** from the structural menu; confirm the selected cells get the fill + bold and non-selected cells do not; toggle a single caret cell; confirm a partial-header row shows only the flagged cells highlighted. Send the message.

- [ ] **Step 4: Runtime verification — viewer (viewing)**

Confirm the sent message renders in the chat as an InstantPage rich-message table with the same header cells highlighted (the V2 renderer path). Edit the message and re-send; confirm the header cells survive the round-trip.

- [ ] **Step 5: Record the verification outcome**

Update the module `CLAUDE.md` (or the spec's §5 checklist) with the runtime-verification result. Commit:
```bash
git add -A
git commit -m "docs(richtext): record Phase-1 per-cell header runtime verification"
```

---

## Self-review notes (author)

- **Spec coverage:** §1(a) Core `Cell.isHeader` + `Row` migration → Task 1; §1(b) composer currency → Task 7; §1(c) bridge → Task 8; §1(d) forward/reverse conversion → Task 8; §2 rendering/toggle/menu/deletion → Tasks 3–5 (deletion protection is preserved by the computed `isHeader`, exercised by the retained editing tests in Task 6); §5 testing → the per-task tests + Tasks 6/9. RTF (§2) needs **no** change: export keys off the computed whole-row `isHeader` and import seeds via the retained `Row(isHeader:)` param — verified by leaving `RTFConversion`/`RTFImport` untouched and relying on the Task 6 suite.
- **Deferred to Phase 2 (out of this plan):** `colspan`/`rowspan` fields, merge/split, rectangle selection, sparse-grid geometry.
- **Type consistency:** `isHeaderCell(_:_:)` / `isHeaderRow(_:)` used consistently (Tasks 3–5); `toggleSelectionHeader()` defined in Task 4, referenced in Task 5; `TableStructuralMenuRequest.Header` defined + threaded in Task 5.
