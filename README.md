# InkNest Notes

InkNest Notes is a Flutter note-taking app inspired by GoodNotes and Notability.

The Flutter client and Python server are open source under
**AGPL-3.0-only**. InkNest names, logos, and application icons are not included
in that grant. See [Licensing](#licensing) before distributing a build or
operating a modified server.

## Roadmap

Development is tracked in
[docs/development/ROADMAP.md](docs/development/ROADMAP.md).

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

If a previous debug session left behind dead `iproxy` tunnels or a hung
CoreDevice helper (`Error connecting to the service protocol`), clear them and
relaunch from the repository root:

```sh
make restart
```

Use `make stop` when you only need to clear those helpers.

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

## Contributing

Contributions are welcome under [CONTRIBUTING.md](CONTRIBUTING.md). Accepted
contributions require agreement to the [Contributor License Agreement](CLA.md)
so the public AGPL edition and separately licensed official editions can share
one maintained codebase.

## Licensing

- Software: [GNU AGPL version 3 only](LICENSE)
- Commercial licensing: [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md)
- Documentation and asset boundaries: [LICENSING.md](LICENSING.md)
- InkNest branding: [TRADEMARKS.md](TRADEMARKS.md)
- Third-party components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

Commercial use is allowed when it complies with the AGPL. Organizations that
need proprietary distribution or hosted modifications without AGPL obligations
must obtain a separate written commercial license from the copyright holder.
