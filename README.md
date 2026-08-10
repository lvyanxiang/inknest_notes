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

To point the Flutter API client at the local FastAPI service, copy the example
env file and set your own origin. `.env.flutter` is gitignored, so each
developer keeps a private address:

```sh
cp .env.flutter.example .env.flutter
```

Then run:

```sh
make run
```

That calls `scripts/run_app.sh`, which is equivalent to
`flutter run --dart-define-from-file=.env.flutter`. Extra Flutter flags can be
passed through the script, for example:

```sh
./scripts/run_app.sh -d <device-id>
```

In Cursor or VS Code, choose the `inknest_notes (.env.flutter)` launch
configuration. Without `.env.flutter`, the committed default is
`http://127.0.0.1:8000`.

Typical values:

- iOS Simulator / macOS desktop: `http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`
- Physical device: `http://<your-lan-ip>:8000`

The value is only the origin; do not append `/api/v1`. The API client owns the
versioned route prefix. You can still pass a one-off override with
`--dart-define=INKNEST_API_BASE_URL=<origin>`.

With the FastAPI service running, open the Account button in the library header
to create an account or sign in. The App stores the session in platform secure
storage, refreshes expired access tokens centrally, and keeps local notebooks
available when signed out or offline. Sign out removes only the cloud session.

For a manual local check:

1. Create an account from Account → Create account.
2. Return to the library and confirm the Account tooltip shows the email.
3. Restart the App and confirm the account is restored.
4. Sign out and confirm existing local notebooks are still present.

If more than one device is available, list the devices and select one by ID:

```sh
flutter devices
flutter run -d <device-id>
```

Run the test suite with:

```sh
flutter test
```
