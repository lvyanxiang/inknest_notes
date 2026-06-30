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
