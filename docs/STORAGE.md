# InkNest Notes Storage

Local data is stored as readable JSON under the app documents directory.

```text
notebooks/
  index.json
  notebook-id/
    pages/
      page-1.json
    assets/
```

## `notebooks/index.json`

Stores notebook metadata:

- `id`
- `title`
- `createdAt`
- `updatedAt`

## `notebooks/<id>/pages/page-1.json`

Stores the first page:

- `id`
- `width`
- `height`
- `strokes`

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
