# Third-party notices

InkNest Notes depends on third-party software and fonts. Those components
remain under their own licenses; the project's AGPL license does not replace
them.

## Bundled fonts

| Font | License notice |
| --- | --- |
| Long Cang | `assets/fonts/handwriting/OFL-LongCang.txt` |
| Zhi Mang Xing | `assets/fonts/handwriting/OFL-ZhiMangXing.txt` |
| Liu Jian Mao Cao | `assets/fonts/handwriting/OFL-LiuJianMaoCao.txt` |

These font files are licensed under the SIL Open Font License 1.1.

## Software dependencies

The dependency manifests and lockfiles are the authoritative inventory:

- Flutter/Dart: `pubspec.yaml` and `pubspec.lock`
- Python: `server/pyproject.toml` and `server/uv.lock`
- Native generated dependencies: platform lockfiles where present

The resolved Flutter dependencies and direct Python dependencies reviewed on
2026-08-12 use permissive or reciprocal licenses including MIT, BSD,
Apache-2.0, MPL-2.0, Unlicense, and LGPL-3.0-only. No obvious blocking
incompatibility with `AGPL-3.0-only` was identified. This is an engineering
inventory, not a substitute for preserving each dependency's own copyright
and license notice in distributed builds.

Before every public binary release, regenerate the dependency inventory,
review newly introduced licenses, and include all notices required by the
target platform and dependency licenses.
