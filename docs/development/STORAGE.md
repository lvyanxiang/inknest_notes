# InkNest Notes Storage

Local data is stored as readable JSON under the app documents directory.

```text
notebooks/
  index.json
  notebook-id/
    pages/
      page-1.json
      page-2.json
    assets/
      imported.pdf
      pdfs/
        source-name.pdf
        source-name-2.pdf
```

## `notebooks/index.json`

Stores notebook metadata:

- `id`
- `title`
- `createdAt`
- `updatedAt`
- `pageIds`

## `notebooks/<id>/pages/<page-id>.json`

Stores one notebook page:

- `id`
- `width`
- `height`
- `pdfBackground`
- `strokes`

`pdfBackground` is optional and stores:

- `assetPath`
- `pageNumber`

The library-level single-PDF import keeps its source at
`assets/imported.pdf` for backward compatibility. PDFs appended from an open
notebook are copied to `assets/pdfs/`; sanitized same-name collisions receive
numeric suffixes so every imported document remains independent.

Each stroke stores:

- `id`
- `tool`
- `color`
- `width`
- `points`

Each point stores:

- `x`
- `y`
- `pressure`
- `time`
