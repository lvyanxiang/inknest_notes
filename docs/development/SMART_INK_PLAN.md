# Smart Ink Plan

Smart Ink is a planned interaction layer for users who write with a finger or
rough handwriting. It converts selected handwriting into recognized text, lets
the user confirm or correct the result, and re-renders it as neat
handwriting-style editable text.

This is a planning document only. The current active roadmap remains
Post-MVP 3 PDF Study Workflow. Smart Ink should start after the editor has
text boxes, lasso selection, and handwriting-style text rendering.

## Product Goal

Users without a stylus should still be able to create notes that look natural
and polished:

1. Write roughly with a finger.
2. Select the rough handwriting.
3. Recognize it as text.
4. Confirm or fix the recognized text.
5. Insert or replace it with neat handwriting-style editable text.

The product value is not only prettier notes. The recognized text can later
support search, summaries, export, and knowledge-base workflows.

## Principles

- Keep the original handwriting safe by default; never silently replace it.
- Require user confirmation before converting handwriting into text.
- Make the result editable, not just a flattened image.
- Preserve notebook feeling by rendering text in handwriting-style fonts.
- Keep the first version local-first where possible; cloud recognition can be
  an optional future capability.
- Treat Smart Ink as an editor command, not a background surprise.

## Related Concepts

### Finger Writing Assist

Finger Writing Assist improves rough finger strokes directly. It should reduce
jitter, smooth curves, and make finger input less awkward before recognition.
It does not convert handwriting into text.

### Smart Ink Beautify

Smart Ink Beautify recognizes selected handwriting as text and creates a neat
handwriting-style text object. This is the core feature covered by this plan.

### Handwriting Recognition Search

Handwriting recognition for search can reuse part of the recognition pipeline,
but it is a different user experience. Search indexing can happen in the
background; Smart Ink conversion should be explicit and user-confirmed.

## MVP Flow

1. User selects handwriting with lasso.
2. A contextual command shows `Smart Ink`.
3. InkNest builds a recognition payload from selected strokes and bounds.
4. A recognition provider returns one or more text candidates.
5. InkNest shows a confirmation sheet with editable recognized text.
6. User confirms, edits, cancels, replaces original ink, or inserts a new
   handwriting-style text object.
7. The result is placed near the selected handwriting and remains editable.
8. Undo restores the page to the previous state.

## MVP Scope

- Single-page selected handwriting only.
- Text recognition only; math, diagrams, tables, and shapes are out of scope.
- Keep original strokes by default.
- Allow an explicit replace action after confirmation.
- Render the output as a text object using a bundled handwriting-style font.
- Use the selected ink color as the initial text color.
- Export Smart Ink text objects to PDF.

## Out Of Scope For MVP

- Personal handwriting style cloning.
- Automatic conversion while the user is writing.
- Math formula recognition.
- Multi-page selection.
- Real-time collaborative Smart Ink.
- Full offline/on-device recognition guarantee across all platforms.

## Dependencies

- Lasso selection for choosing strokes.
- A page element model that can store text objects, not only strokes.
- Text box editing and persistence.
- Handwriting-style font rendering and font licensing.
- PDF export support for text objects.
- A recognition provider abstraction.
- Undo/redo support for converting and replacing selected ink.

## Suggested Data Model Direction

The current `NotePage` model stores strokes. Smart Ink needs a broader element
model later, for example:

- `StrokeElement`: existing handwriting strokes.
- `TextElement`: editable text with bounds, style, font, color, and alignment.
- `ImageElement`: future inserted images.
- `ShapeElement`: future shape tool output.

A Smart Ink output can be represented as a `TextElement` with metadata:

- `source`: `smartInk`
- `sourceStrokeIds`: original selected stroke IDs
- `recognizedText`: confirmed text
- `style`: handwriting font, size, color, line height
- `bounds`: page-space rectangle

Original strokes should remain unless the user chooses replace.

## Recognition Provider

Create an abstraction before choosing a provider:

```dart
abstract class HandwritingRecognitionProvider {
  Future<HandwritingRecognitionResult> recognize(
    HandwritingRecognitionRequest request,
  );
}
```

The request should include:

- Selected stroke geometry.
- A rendered image crop for OCR providers.
- Page scale and bounds.
- Locale hints.
- Writing direction hints when available.

Potential provider families to evaluate later:

- On-device platform text recognition.
- Cloud OCR or handwriting recognition.
- A custom model if Smart Ink becomes a major differentiator.

The provider should return candidates, confidence, and language metadata. The
UI should handle low-confidence recognition with a stronger confirmation step.

## UX Details

- Command name: `Smart Ink`.
- Entry point: lasso selection toolbar.
- Confirmation UI: bottom sheet or compact popover near selection.
- Default action: insert neat text while keeping original ink.
- Secondary action: replace original ink.
- Cancel action: keep the page unchanged.
- Error state: show a short failure message and keep the selected ink.
- Empty result: let user type the desired text manually and still render it as
  handwriting-style text.

## Privacy And Monetization

Smart Ink can be valuable for paid tiers if cloud recognition is used, but the
basic product promise should not depend on cloud sync.

Possible packaging:

- Free: local text boxes and handwriting-style fonts.
- Free or trial-limited: manual Smart Ink attempts.
- Subscription: higher quality cloud recognition, batch conversion, advanced
  languages, personal handwriting styles, and cross-device Smart Ink search.

Always disclose when handwriting content leaves the device.

## Implementation Milestones

### Smart Ink 0: Product And Technical Design

- Finalize UX flow and failure states.
- Choose MVP recognition provider strategy.
- Choose handwriting-style font approach.
- Define page element model changes.

### Smart Ink 1: Text Objects

- Add persistent text objects to `NotePage`.
- Render, edit, move, resize, and export text objects.
- Add handwriting-style font option.

### Smart Ink 2: Lasso Selection

- Select strokes by lasso.
- Move, delete, and recolor selected strokes.
- Compute selected stroke bounds and payload.

### Smart Ink 3: Recognition Pipeline

- Add `HandwritingRecognitionProvider`.
- Convert selected strokes into recognition input.
- Return editable recognition candidates.

### Smart Ink 4: Beautify Command

- Add contextual `Smart Ink` command.
- Show confirmation UI.
- Insert handwriting-style text result.
- Support replace original ink.
- Support undo/redo.

### Smart Ink 5: Search And Knowledge

- Index recognized text for notebook search.
- Include Smart Ink text in exports.
- Feed recognized text into future Web knowledge-base and AI features.

## Acceptance Criteria

- A user can select rough handwriting, run Smart Ink, confirm the recognized
  text, and get a neat editable handwriting-style result.
- Canceling or failure never destroys original handwriting.
- Replacing original ink is explicit and undoable.
- Smart Ink output persists after app restart.
- Exported PDF includes Smart Ink output.
- Existing handwritten stroke performance is not degraded.

## Open Questions

- Which recognition provider should be used first on iPadOS?
- Should Smart Ink be free, trial-limited, or subscription-only?
- Should the first result be handwriting-style text or a generated vector ink
  path?
- How should Chinese, English, punctuation, and line breaks be corrected in the
  confirmation UI?
- Should users be able to define favorite handwriting styles?
