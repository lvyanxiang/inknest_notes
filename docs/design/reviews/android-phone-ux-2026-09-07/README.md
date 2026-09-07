# Android Phone UX Audit — 2026-09-07

- Device: vivo V2309A (`1260 × 2800`, density `560`, approximately `360dp` wide)
- App: `com.example.inknestnotes`, debug build
- Scope: local Android phone flows only

## Coverage

The physical-device pass exercised library search/sort, folder creation,
archive/restore/delete/duplicate/move/rename, account sign-in/registration/legal
views, PDF picker, paged and infinite notebook creation, page navigation/actions,
bookmarks, outline, export, audio library/permission recovery, insert
text/image/shape, pen/highlighter/eraser/lasso, undo/redo, finger modes, zoom, and
canvas background.

## Findings

| Priority | Finding | Evidence | Resolution |
|---|---|---|---|
| P0 | Lasso action bar overflows by 72px on the right | `screenshots/41-lasso-selection.png` | Compact phone actions and grouped palette; verified in `screenshots/49-after-lasso-selection.png` |
| P0 | Export choices wrap labels letter-by-letter | `screenshots/25-export-sheet.png` | Whole-word wrapping choice chips; verified in `screenshots/48-after-export-sheet.png` |
| P1 | Narrow spines reduce direct title scanning, but replacing the bookshelf weakens the intended library identity | `screenshots/01-library.png`, `screenshots/53-after-library-clean.png` | Card-grid experiment rolled back after user review; original bookshelf retained |
| P1 | Text object toolbar scales to roughly 18dp with fitted paper | `screenshots/37-text-editing.png` | Screen-stable controls and zoom avoidance; verified in `screenshots/51-after-text-toolbar-final.png` |
| P1 | Header title/summary collapse to fragments in archived view | `screenshots/12-archive-empty.png` | Compact phone heading hierarchy; verified in `screenshots/54-after-archived-header.png` |
| P2 | Empty names appear submittable without visible validation | `screenshots/04-new-folder-dialog.png` | Disable Save until trimmed name is non-empty |
| P2 | Permanent Delete uses ordinary primary color | `screenshots/19-delete-confirmation.png` | Error/danger styling; verified in `screenshots/52-after-delete-danger.png` |
| P2 | Create-account CTA begins below the first viewport | `screenshots/08-create-account.png` | Reduce compact account spacing while retaining scroll |
| P3 | Blank notebooks expose a PDF Outline action that only reports an empty state | `screenshots/32-outline-empty.png` | Deferred: feature parity/navigation policy needs broader editor decision |
| P3 | Pages sheet uses substantial empty space with one page | `screenshots/27-pages-sheet.png` | Deferred: useful growth space and not blocking |

## Notes

- Denied microphone permission returns to the editor with a clear Snackbar.
- External PDF/image pickers open and cancel safely.
- Page duplication, bookmarks, archive/restore, undo/redo, tool property sheets,
  and infinite-canvas background selection behaved correctly.
- Test-created notebooks were removed after regression; the pre-existing
  `Notebook 1` remains.
- Screenshots 47/53 are historical evidence of the rejected phone card-grid
  experiment; they are not the current phone library presentation.

## Verification Result

- `flutter analyze`: passed with no issues.
- `test/widget_test.dart` plus `test/features/editor/editor_workspace_test.dart`:
  53 tests passed, including four new 360dp regressions.
- Full `flutter test`: all 293 tests passed.
- Physical-device checks confirmed no Flutter overflow stripe in the repaired
  export, lasso, or text-object states.
