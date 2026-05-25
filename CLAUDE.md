# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project type

This is a **Flutter package** published to pub.dev (`any_image_view`), not an application. The package itself is a single public widget; the `example/` directory is a demo app that consumes it via `path: ..`.

## Common commands

Run from the repo root:

```bash
flutter pub get                          # install package deps
flutter analyze                          # lints (config: analysis_options.yaml)
flutter test                             # run all tests
flutter test test/any_image_view_test.dart  # run a single test file
flutter test --plain-name 'network SVG URL'  # run tests matching a name
```

For the example app (run from `example/`):

```bash
cd example && flutter pub get && flutter run
```

When bumping the published version: update `version:` in `pubspec.yaml`, prepend an entry to `CHANGELOG.md`, then `flutter pub publish --dry-run`.

## Architecture

The entire public API lives in **`lib/any_image_view.dart`** (~630 LOC, single file). It exports:

- `AnyImageView` — the one widget users instantiate. `imagePath` is typed `Object?` and accepts `String` (URL / asset / `file://` / absolute path) or `XFile` (from `image_picker`).
- `ImageType` enum + `ImageTypeExtension on String` — format detection from the path string.
- `Shimmer` — the loading placeholder widget (public, reusable).
- `_SafeSvgLoader` — private SVG loader (see below).

### Routing flow (the part that needs reading multiple files to get)

`AnyImageView._buildImage()` dispatches in this order:

1. `imagePath == null` or empty → `errorFallback()`.
2. `imagePath is XFile` → `_buildFileImage()` (uses `dart:io File` — won't work on web for XFile paths).
3. `imagePath is String` → `_buildStringImage()`, which switches on `path.imageType`:
   - `svg` → `_SafeSvgLoader` (asset mode)
   - `avif` → `AvifImage.asset()` (asset AVIFs; network AVIFs are detected within the `network` branch below)
   - `json` / `zip` → `Lottie.asset()`
   - `network` → if `_isSvgUrl(path)` then `_SafeSvgLoader` (network mode); else if `_isAvifUrl(path)` then `CachedNetworkAvifImage`; else `CachedNetworkImage`
   - `file` → `_buildFileImage()` (routes `.avif` paths to `AvifImage.file`, everything else to `Image.file`)
   - everything else → `Image.asset()`

### Detection-order invariant (don't break this)

`ImageTypeExtension.imageType` checks **URL protocol before file extension**. A `https://...something.svg` URL must return `ImageType.network`, not `ImageType.svg` — the SVG-vs-raster split for network URLs happens later via `_isSvgUrl()`. There are explicit regression tests for this in `test/any_image_view_test.dart` under `URL vs extension order` and `network SVG URL returns ImageType.network`. The CHANGELOG 1.9.0 entry is the historical bug — keep the order.

### `_SafeSvgLoader` exists to prevent crashes

`SvgPicture` can throw on invalid SVG data. `_SafeSvgLoader` pre-loads the raw SVG **string** (via `rootBundle.loadString` for assets or `http.get` for network), then renders with `SvgPicture.string()` inside try/catch. Any load or parse failure routes to the caller's `errorFallback` widget. If you touch SVG handling, preserve this pattern — see CHANGELOG 2.1.0 ("Invalid SVG data crash" fix).

### `CachedNetworkImage` cache sizing is intentionally unset

In `_buildStringImage()` the `CachedNetworkImage` config explicitly sets `memCacheHeight: null`, `memCacheWidth: null`, `maxHeightDiskCache: null`, `maxWidthDiskCache: null`. This is the "best resolution" guarantee from CHANGELOG 2.0 — don't add cache dimensions to "optimize" it. (`filterQuality: FilterQuality.high` is part of the same guarantee.)

### SVG color tinting

`svgColor` and `svgColorFilter` are both supported; `_effectiveSvgColorFilter` picks `svgColorFilter` when both are set, otherwise builds a `ColorFilter.mode(svgColor, BlendMode.srcIn)`. Both paths feed `_SafeSvgLoader.colorFilter` — so tinting works for asset and network SVGs alike.

### Shape clipping

`shape: BoxShape.circle` clips with `ClipOval`; otherwise `ClipRRect` with `borderRadius`. `borderRadius` is intentionally **not** applied to the decoration when shape is circle (Flutter rejects that combo).

## Testing notes

- Tests live in `test/any_image_view_test.dart`. They cover (a) every `ImageType` extension branch and (b) widget routing — asserting the widget tree contains the expected loader (`CachedNetworkImage`, `LottieBuilder`, `Image`, broken-image icon).
- Network SVG widget rendering is **not** tested directly (HTTP 400 in test env); the extension-level test covers the routing.
- `tester.pumpAndSettle()` is required for `_SafeSvgLoader` tests because they wait on a `Future` that fails (no asset in test package), then assert the fallback icon appears.
- Every bug fix must include a regression test that would have caught the original bug (per the user's global standards).

## Production code standards apply

The user's global `~/.claude/CLAUDE.md` applies in full — most notably: no stubs, no no-op handlers, no TODOs, no silent error swallowing, no unsafe response parsing. Surface every error to the UI via `errorWidget` / `errorFallback`. The existing `_SafeSvgLoader` and `CachedNetworkImage` `errorListener` are the in-codebase examples of how errors get surfaced.
