# AVIF Support via `flutter_avif`

**Date:** 2026-05-24
**Status:** Approved design — ready for implementation planning
**Target version:** `any_image_view` 2.2.0

## Goal

Add AVIF rendering to `AnyImageView` so any consumer can pass an `.avif` asset path, network URL, or local file and have it Just Work — matching the library's "one widget for all image types" promise. Network-served AVIFs are the priority use case (CDN adoption is the reason this matters now), but parity across all sources is required for consistency with the rest of the package.

## Non-goals

- Manual animation controls (pause/seek/loop count). Animated AVIFs auto-play, same as GIFs do today. A future minor release can add a controller-based API if anyone asks.
- AVIF encoding. The library is a viewer; `flutter_avif.encodeAvif()` exists but is not exposed.
- Cleaning up the misleading `ImageType.heic / heif / tiff / raw / bmp / ico / exr / hdr` enum cases. Those fall through to `Image.asset()` and don't actually decode on most platforms — but they're load-bearing for any consumer who references the enum by name, so removing them is breaking. We accept the inconsistency for v2.2.0 and document the gap in the README.

## Decisions (resolved during brainstorming)

| Decision | Choice | Reason |
|---|---|---|
| Distribution | Hard dependency on `flutter_avif: ^3.1.0` | Matches the library's "one widget for all formats" promise. Bundle-size cost (libavif native binaries shipped via per-platform plugins) accepted as a tradeoff. |
| Animation in v1 | Auto-play, no controls | Mirrors existing GIF behavior in the library. No new API surface. |
| Code structure | Inline dispatch in `_buildStringImage()` and `_buildFileImage()` — no wrapper widget | flutter_avif reports decode errors through `errorBuilder` rather than throwing, so the `_SafeSvgLoader`-style defensive wrapper isn't justified. Building one anyway would be cargo-culting the SVG pattern. |
| Network caching | `CachedNetworkAvifImage` (not `AvifImage.network`) | Preserves disk-caching parity with the existing `CachedNetworkImage` path for non-AVIF network images. |
| File layout | Stay in single `lib/any_image_view.dart` | Deliberate single-file structure per `CLAUDE.md`. ~30 LOC of production change doesn't justify breaking it. |
| Misleading enum cases (HEIC/HEIF/TIFF/RAW/etc.) | Document the gap in README, do not remove | Removing would break consumers who reference the enum by name. Out of scope for this change. |

## Public API impact

**None on `AnyImageView`.** No new constructor parameters. Existing parameters (`imagePath`, `height`, `width`, `fit`, `httpHeaders`, `placeholderWidget`, `errorWidget`, `enableZoom`, `borderRadius`, `shape`, `boxShadow`, `border`, `margin`, `padding`) all apply to AVIF unchanged.

**One enum case added:** `ImageType.avif`.

This is an additive change. No deprecations, no breaking changes.

## Architecture

### Detection — `ImageTypeExtension.imageType`

One new branch added to the existing switch ladder, placed **after** the URL/file prefix checks and **before** the existing extension checks (matching the position of the other extension branches):

```dart
if (endsWith('.avif')) return ImageType.avif;
```

**Invariant preserved:** URLs are detected by protocol *before* extension. A URL like `https://cdn.example.com/photo.avif` returns `ImageType.network`, not `ImageType.avif`. The CLAUDE.md detection-order invariant is unchanged. The network arm then re-detects AVIF-ness via a new helper.

### Network AVIF helper

New static method on `AnyImageView`, paralleling `_isSvgUrl`:

```dart
static bool _isAvifUrl(String path) {
  final lower = path.toLowerCase();
  return (lower.startsWith('http://') || lower.startsWith('https://')) &&
      (lower.endsWith('.avif') || lower.contains('.avif?'));
}
```

The `.contains('.avif?')` guard handles signed-CDN URLs with query strings (e.g. `https://cdn.example.com/photo.avif?token=abc`), matching the SVG helper's behavior.

### Dispatch — three call sites

**Asset case** — new `case ImageType.avif:` branch in `_buildStringImage()`:

```dart
case ImageType.avif:
  return AvifImage.asset(
    path,
    height: height,
    width: width,
    fit: fit ?? BoxFit.cover,
    errorBuilder: (_, __, ___) => errorFallback(),
  );
```

**Network case** — `_isAvifUrl()` check inserted inside the existing `case ImageType.network:`, immediately after the `_isSvgUrl()` check and before the `CachedNetworkImage` fallback:

```dart
if (_isAvifUrl(path)) {
  return CachedNetworkAvifImage(
    path,
    height: height,
    width: width,
    fit: fit ?? BoxFit.cover,
    headers: httpHeaders,
    errorBuilder: (_, __, ___) => errorFallback(),
  );
}
```

**File case** — `_buildFileImage()`, inserted after the file-exists check, before the existing `Image.file`:

```dart
if (path.toLowerCase().endsWith('.avif')) {
  return AvifImage.file(
    file,
    height: height,
    width: width,
    fit: fit ?? BoxFit.cover,
    errorBuilder: (_, __, ___) => errorFallback(),
  );
}
```

XFile flows through `_buildFileImage()` already, so XFile-sourced AVIFs are handled automatically by the same branch.

### Error handling

Every dispatch site routes failures through `errorBuilder` into the existing `errorFallback()` closure built in `_buildImage()`. That closure already returns the user's `errorWidget` if provided, otherwise the gray-box broken-image icon. No new error paths, no silent swallowing. Consistent with the production code standard from `~/.claude/CLAUDE.md`.

## Known gaps (documented, not fixed in v2.2.0)

### Shimmer gap on network AVIFs

`CachedNetworkAvifImage` does not expose a `placeholder` builder the way `CachedNetworkImage` does. Network AVIFs will render with the widget's own default loading state, not the library's `Shimmer`. Asset and file AVIFs use Flutter's standard frame-builder behavior — no shimmer either, matching how the existing `Image.asset()` path works for PNG/JPG.

**Mitigation considered and rejected for v2.2.0:**

- *Pre-fetch via `http` then render via `AvifImage.memory`*: gives us the shimmer but loses `CachedNetworkAvifImage`'s disk cache, and duplicates HTTP fetch logic.
- *Wrap with `FutureBuilder` watching for first frame*: fragile, no clean signal for "decoded and visible."

**Decision:** ship the gap, document it, revisit if anyone files an issue. Animated AVIFs are typically small enough that perceived delay is brief.

### Animation autoplay verification

flutter_avif docs state the `AvifImage` widget "has a similar API as Flutter Image widget" — implying animated AVIFs auto-play by default, but this is not explicitly confirmed in the docs we read. Implementation must verify behavior and add a regression test if a default parameter is required to opt into autoplay.

## Testing

All new tests go in `test/any_image_view_test.dart`, slotting into the existing groups (no new test file).

### `ImageType extension > asset paths by extension`

```dart
test('.avif returns ImageType.avif', () {
  expect('assets/images/photo.avif'.imageType, ImageType.avif);
});
```

### `ImageType extension > URL vs extension order` (regression guard)

```dart
test('https URL ending in .avif is network (not avif asset)', () {
  expect('https://example.com/photo.avif'.imageType, ImageType.network);
});
```

This is the test that would have caught any future bug that reordered the checks in `imageType` and broke the URL-protocol-first invariant.

### `ImageType extension > file paths`

```dart
test('file path ending in .avif still returns ImageType.file', () {
  expect('/tmp/photo.avif'.imageType, ImageType.file);
});
```

### `AnyImageView widget builds correct child for format`

```dart
testWidgets('asset AVIF path builds AvifImage', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AnyImageView(
          imagePath: 'assets/images/photo.avif',
          width: 100, height: 100,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(AvifImage), findsOneWidget);
});

testWidgets('network AVIF URL builds CachedNetworkAvifImage', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AnyImageView(
          imagePath: 'https://example.com/photo.avif',
          width: 100, height: 100,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(CachedNetworkAvifImage), findsOneWidget);
});

testWidgets('network AVIF URL with query string builds CachedNetworkAvifImage', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AnyImageView(
          imagePath: 'https://cdn.example.com/photo.avif?token=abc',
          width: 100, height: 100,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(CachedNetworkAvifImage), findsOneWidget);
});
```

We do **not** widget-test actual AVIF decode — there are no real AVIF bytes in the test environment, and the equivalent network-SVG decode test is already skipped for the same reason. The widget tests verify *dispatch*; the extension tests verify *detection*. Together they cover the contract.

## File-level changes

| File | Change |
|---|---|
| `lib/any_image_view.dart` | Add `import 'package:flutter_avif/flutter_avif.dart'`. Add `ImageType.avif` enum case (with doc comment). Add `.avif` branch to `ImageTypeExtension.imageType`. Add `_isAvifUrl()` static helper. Add `case ImageType.avif` arm in `_buildStringImage()`. Add `_isAvifUrl()` check in network arm. Add `.avif` branch in `_buildFileImage()`. |
| `test/any_image_view_test.dart` | Add tests listed above. |
| `pubspec.yaml` | Bump `version: 2.2.0`. Add `flutter_avif: ^3.1.0` to `dependencies`. Add `avif` to `topics`. |
| `CHANGELOG.md` | Prepend 2.2.0 entry following the existing prose style — call out the new format, autoplay behavior for animated AVIFs, the known network shimmer gap, and the new dependency. |
| `README.md` | Add `AVIF` to the supported-formats line. Add an `// AVIF` example to the usage block. |
| `CLAUDE.md` | Add a one-line note in the routing flow section that `.avif` URLs are detected post-network via `_isAvifUrl()`, mirroring `_isSvgUrl()`. |
| `example/pubspec.yaml` | No change required (uses `path: ..` and will pick up the new transitive dep). |
| `example/lib/main.dart` | Optional: add an AVIF example section so consumers exploring the demo see it work. |

**Estimated diff size:** ~30 LOC production + ~40 LOC tests + docs.

## Build order (per production code standards)

1. Add `flutter_avif` dependency and run `flutter pub get`.
2. Add `ImageType.avif` and `_isAvifUrl()` (detection layer).
3. Add the three dispatch sites (rendering layer).
4. Add tests (verify each detection branch + each widget dispatch).
5. Run `flutter analyze` and `flutter test` — both must pass before any docs change.
6. Update CHANGELOG, README, CLAUDE.md, pubspec version.
7. (Optional) Add example app section.
8. `flutter pub publish --dry-run` to verify the release is clean.

No layer N+1 before layer N — the dependency must be installed before code references `AvifImage`, the detection must work before the dispatch sites can route correctly, tests must pass before docs reflect "supported."

## Open questions for implementation

- **Animation autoplay default**: verify experimentally during step 3. If `AvifImage.asset` does not auto-play animated AVIFs by default, decide between (a) accepting still-only behavior and updating the CHANGELOG, or (b) adding an explicit autoplay parameter — escalate to maintainer if (b).
- **`AvifImage` constructor signatures**: verify the exact parameter names (`errorBuilder`, `fit`, `headers`) match those used in the dispatch snippets above — flutter_avif's API mirrors `Image`, but constructor signatures can differ in subtle ways. If any signature differs, adapt the snippet and note it inline.
