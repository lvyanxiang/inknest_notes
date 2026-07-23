# InkNest Notes

InkNest Notes is a Flutter note-taking app inspired by GoodNotes and Notability.

## Roadmap

Development is tracked in [docs/ROADMAP.md](docs/ROADMAP.md).

The current focus is building a strong handwriting-first MVP:

- Notebook library
- Paged editor
- Low-latency handwriting
- Local persistence
- PDF annotation

## Run locally

From the project root, install dependencies:

```sh
flutter pub get
```

On macOS, start the iOS Simulator:

```sh
open -a Simulator
```

Then run the app:

```sh
flutter run
```

If more than one device is available, list the devices and select one by ID:

```sh
flutter devices
flutter run -d <device-id>
```

Run the test suite with:

```sh
flutter test
```
