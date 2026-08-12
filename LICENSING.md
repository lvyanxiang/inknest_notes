# InkNest Notes licensing policy

Copyright (C) 2026 Lv. All rights not expressly granted are reserved.

This file defines which licenses apply to the different kinds of material in
this repository. A license notice located next to a file takes precedence for
that file.

## Software

Unless a file says otherwise, the source code, build scripts, database
migrations, API definitions, tests, and other software in this repository are
licensed under the **GNU Affero General Public License version 3 only**
(`AGPL-3.0-only`). The complete license is in [LICENSE](LICENSE).

This includes the Flutter client and the Python/FastAPI server. Distributing a
covered executable requires providing its complete corresponding source under
the AGPL. An operator that modifies covered server software and lets users
interact with it over a network must prominently offer those users the
corresponding source as required by AGPL section 13.

The AGPL permits commercial use. It does not grant permission to make a
proprietary derivative or to use InkNest branding as if a fork were an official
release.

## Commercial licensing

Organizations that cannot comply with `AGPL-3.0-only` may request a separate
commercial license from the copyright holder. See
[COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md). No commercial license is
granted merely by that document or by contacting the maintainer.

## Documentation

Original documentation under `docs/` is licensed under
**Creative Commons Attribution-ShareAlike 4.0 International**
(`CC-BY-SA-4.0`), except:

- `docs/academic/`, including its source documents and images, is not offered
  under CC BY-SA and remains **All Rights Reserved**;
- source-code extracts remain governed by the license applicable to that code;
- third-party material remains governed by its own notice or license.

The complete CC BY-SA 4.0 legal code is in
[LICENSES/CC-BY-SA-4.0.txt](LICENSES/CC-BY-SA-4.0.txt).

## Fonts, trademarks, and other assets

The bundled handwriting fonts remain under the SIL Open Font License 1.1. Their
font-specific notices are stored beside them in `assets/fonts/handwriting/`.

The InkNest and InkNest Notes names, logos, icons, and other source-identifying
brand assets are not licensed under the AGPL or CC BY-SA. See
[TRADEMARKS.md](TRADEMARKS.md). Other third-party assets remain under their own
licenses.

## User content and secrets

These repository licenses do not claim rights over notebooks, PDFs, audio,
images, handwriting, or other content created or imported by users.
Credentials, signing keys, production configuration, private customer data,
and user data are not corresponding source and must not be committed to the
repository.

## Contributions

Contributions are accepted only under [CONTRIBUTING.md](CONTRIBUTING.md) and
the [Contributor License Agreement](CLA.md). The contributor agreement is
needed so the public AGPL edition and separately licensed official editions can
continue to share one maintained codebase.

