# flutter_avif Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AVIF rendering to `AnyImageView` so consumers can pass an `.avif` asset path, network URL, or local file and have it render — without any new `AnyImageView` parameters.

**Architecture:** Inline dispatch in the existing single-file `lib/any_image_view.dart` switch. One new `ImageType.avif` enum case; one new `_isAvifUrl()` static helper paralleling `_isSvgUrl()`; three new dispatch sites (asset / network / file) all routing errors through the existing `errorFallback()`. No wrapper widget — flutter_avif's `errorBuilder` parameter replaces the defensive role `_SafeSvgLoader` plays for SVG.

**Tech Stack:** Flutter package (publishable to pub.dev), Dart SDK ^3.9.0, Flutter ≥3.35.0. New dependency: `flutter_avif: ^3.1.0`. Tests use `flutter_test`.

**Reference spec:** `docs/superpowers/specs/2026-05-24-flutter-avif-support-design.md`

---

## File Structure

All work lives in the existing files — the spec calls out the single-file structure as deliberate, and this change is too small to break it.

| File | Responsibility | Action |
|---|---|---|
| `pubspec.yaml` | Package manifest | Modify: add dep, bump version, add topic |
| `lib/any_image_view.dart` | Entire public API + dispatch logic | Modify: 1 enum case + 1 helper + 3 dispatch additions |
| `test/any_image_view_test.dart` | All tests | Modify: 3 extension tests + 3 widget tests |
| `CHANGELOG.md` | Release notes | Modify: prepend 2.2.0 entry |
| `README.md` | Public docs | Modify: supported-formats line + usage example |
| `CLAUDE.md` | Future-Claude routing guide | Modify: one line in routing-flow section |
| `example/lib/main.dart` | Demo app | Modify: add AVIF example section |

---

## Task 1: Install flutter_avif and verify clean build

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

Edit `pubspec.yaml`. In the `dependencies:` block (currently lines 25-30), add `flutter_avif` alphabetically after `cross_file`:

```yaml
dependencies:
  lottie: ^3.3.2
  flutter_svg: ^2.2.4
  flutter_avif: ^3.1.0
  cached_network_image: ^3.4.1
  cross_file: ^0.3.5+2
  http: ^1.2.2

  flutter:
    sdk: flutter
```

- [ ] **Step 2: Resolve dependencies**

Run: `flutter pub get`
Expected: `Got dependencies!` with no error. If pub reports a Flutter SDK constraint conflict, escalate — flutter_avif may require a newer Flutter than 3.35.0.

- [ ] **Step 3: Verify the package imports cleanly**

Run: `flutter analyze`
Expected: `No issues found!` (the existing code doesn't reference flutter_avif yet — this just confirms the dep installs without breaking the lint config).

- [ ] **Step 4: Run the existing test suite as a smoke test**

Run: `flutter test`
Expected: all tests pass (we haven't touched any logic — this confirms the new dep doesn't break the existing tree).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add flutter_avif ^3.1.0"
```

---

## Task 2: Add `ImageType.avif` enum case and extension detection (TDD)

**Files:**
- Modify: `lib/any_image_view.dart` (enum at line ~453, extension at line ~510)
- Test: `test/any_image_view_test.dart` (groups starting line ~39 and ~93)

- [ ] **Step 1: Write the failing extension tests**

In `test/any_image_view_test.dart`, add to the `asset paths by extension` group (after the `.zip` test, around line 48):

```dart
test('.avif returns ImageType.avif', () {
  expect('assets/images/photo.avif'.imageType, ImageType.avif);
});
```

In the `URL vs extension order` group (after the existing tests, around line 99), add:

```dart
test('https URL ending in .avif is network (not avif asset)', () {
  expect('https://example.com/photo.avif'.imageType, ImageType.network);
});
test('https URL with .avif and query string returns ImageType.network', () {
  expect(
    'https://cdn.example.com/photo.avif?token=abc'.imageType,
    ImageType.network,
  );
});
```

In the `file paths` group (after the existing `.svg` file test, around line 36), add:

```dart
test('file path ending in .avif still returns ImageType.file', () {
  expect('/tmp/photo.avif'.imageType, ImageType.file);
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `flutter test --plain-name '.avif'`
Expected: the `.avif returns ImageType.avif` test fails to compile because `ImageType.avif` doesn't exist. The URL-order tests and the file path test will fail to compile (referencing the same missing enum) OR pass if compiled standalone — either way, the suite won't run cleanly.

- [ ] **Step 3: Add the enum case**

In `lib/any_image_view.dart`, in the `ImageType` enum (around line 453-507), add a new case. Place it alphabetically after `/// Bitmap image format. bmp,` (around line 486):

```dart
  /// AV1 Image File Format.
  avif,
```

Final ordering should keep the existing alphabetical-ish convention; if unsure, place it immediately after `bmp,`.

- [ ] **Step 4: Add the extension branch**

In `lib/any_image_view.dart`, in `ImageTypeExtension.imageType` (around lines 514-539), add the `.avif` check. Place it **after** the URL/file prefix checks and **alongside** the other extension checks. Specifically, insert it after the `.svg` line (around line 522):

```dart
    if (endsWith('.svg')) return ImageType.svg;
    if (endsWith('.avif')) return ImageType.avif;
    if (endsWith('.json')) return ImageType.json;
```

**Critical invariant:** the `.avif` branch must come **after** the `startsWith('http://') / startsWith('https://') → ImageType.network` check at line 516. The CLAUDE.md "URL-protocol-first" invariant depends on this ordering. The regression test added in Step 1 protects this.

- [ ] **Step 5: Run all the new tests to verify they pass**

Run: `flutter test --plain-name '.avif'`
Expected: all four new tests pass.

- [ ] **Step 6: Run the full suite to verify no regressions**

Run: `flutter test`
Expected: all tests pass — including every pre-existing extension and URL-order test.

- [ ] **Step 7: Commit**

```bash
git add lib/any_image_view.dart test/any_image_view_test.dart
git commit -m "feat: detect .avif paths as ImageType.avif"
```

---

## Task 3: Add asset-AVIF dispatch (TDD)

**Files:**
- Modify: `lib/any_image_view.dart` (imports near line 38; switch in `_buildStringImage()` around line 272)
- Test: `test/any_image_view_test.dart` (`AnyImageView widget builds correct child for format` group, around line 103)

- [ ] **Step 1: Write the failing widget test**

In `test/any_image_view_test.dart`, in the `AnyImageView widget builds correct child for format` group, add (place it near the other asset-dispatch tests, after the `asset JSON path builds Lottie` test):

```dart
testWidgets('asset AVIF path builds AvifImage', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AnyImageView(
          imagePath: 'assets/images/photo.avif',
          width: 100,
          height: 100,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(AvifImage), findsOneWidget);
});
```

This requires an import at the top of the test file (alongside the existing `cached_network_image` and `lottie` imports):

```dart
import 'package:flutter_avif/flutter_avif.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test --plain-name 'asset AVIF path builds AvifImage'`
Expected: the test fails. The likely failure is `find.byType(AvifImage)` returning zero matches because the `default:` arm of `_buildStringImage()` is currently dispatching to `Image.asset()` for the `ImageType.avif` enum value. (The default arm catches anything not explicitly switched.)

- [ ] **Step 3: Add the flutter_avif import in production code**

In `lib/any_image_view.dart`, in the imports block (around lines 32-40), add the import alphabetically with the other package imports:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
```

- [ ] **Step 4: Add the asset-AVIF dispatch arm**

In `lib/any_image_view.dart`, in `_buildStringImage()` (around lines 272-345), add a new `case ImageType.avif:` arm. Place it before `case ImageType.json:` so it sits alongside the other format-specific (non-network, non-file) arms:

```dart
      case ImageType.svg:
        // existing SVG handling unchanged
        return _SafeSvgLoader(
          // ...
        );
      case ImageType.avif:
        return AvifImage.asset(
          path,
          height: height,
          width: width,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (_, __, ___) => errorFallback(),
        );
      case ImageType.json:
      case ImageType.zip:
        // existing Lottie handling unchanged
```

**If `AvifImage.asset` does not accept `errorBuilder` with this signature**, adapt to the actual flutter_avif 3.1.0 signature (it mirrors `Image`, but verify). If the constructor takes no `errorBuilder` at all, the test still passes (we're only asserting `AvifImage` exists in the tree) — drop the `errorBuilder` parameter and note in the CHANGELOG that asset AVIF decode errors are not caught.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test --plain-name 'asset AVIF path builds AvifImage'`
Expected: PASS.

- [ ] **Step 6: Run the full suite to verify no regressions**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/any_image_view.dart test/any_image_view_test.dart
git commit -m "feat: render asset AVIF via AvifImage.asset"
```

---

## Task 4: Add network-AVIF dispatch with `_isAvifUrl` helper (TDD)

**Files:**
- Modify: `lib/any_image_view.dart` (static helper near `_isSvgUrl` around line 187; switch in `_buildStringImage()` network case around line 295)
- Test: `test/any_image_view_test.dart` (`AnyImageView widget builds correct child for format` group)

- [ ] **Step 1: Write the failing widget tests**

In `test/any_image_view_test.dart`, in the `AnyImageView widget builds correct child for format` group, add (place these after `network PNG URL builds CachedNetworkImage`):

```dart
testWidgets('network AVIF URL builds CachedNetworkAvifImage', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AnyImageView(
          imagePath: 'https://example.com/photo.avif',
          width: 100,
          height: 100,
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
          width: 100,
          height: 100,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(CachedNetworkAvifImage), findsOneWidget);
});
```

The `CachedNetworkAvifImage` import is already covered by the `package:flutter_avif/flutter_avif.dart` import added in Task 3.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test --plain-name 'network AVIF'`
Expected: both tests fail — the network case currently routes any non-SVG URL to `CachedNetworkImage`, so `find.byType(CachedNetworkAvifImage)` returns zero matches.

- [ ] **Step 3: Add the `_isAvifUrl` helper**

In `lib/any_image_view.dart`, immediately after the existing `_isSvgUrl` static method (around lines 187-191), add:

```dart
  /// True if the path is a network URL pointing to an AVIF file.
  static bool _isAvifUrl(String path) {
    final lower = path.toLowerCase();
    return (lower.startsWith('http://') || lower.startsWith('https://')) &&
        (lower.endsWith('.avif') || lower.contains('.avif?'));
  }
```

- [ ] **Step 4: Wire the helper into the network dispatch arm**

In `lib/any_image_view.dart`, in `_buildStringImage()`, locate the `case ImageType.network:` arm (around lines 295-331). Insert an AVIF check **immediately after** the existing `_isSvgUrl(path)` block and **before** the `CachedNetworkImage` fallback:

```dart
      case ImageType.network:
        if (_isSvgUrl(path)) {
          return _SafeSvgLoader(
            // ... existing SVG loader call unchanged
          );
        }
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
        return CachedNetworkImage(
          // ... existing CachedNetworkImage call unchanged
        );
```

**Verify the `CachedNetworkAvifImage` constructor signature against flutter_avif 3.1.0.** Likely parameter names: `headers` (matches Flutter conventions) and `errorBuilder` (mirrors `Image`). If they differ — for example if it's `httpHeaders` or `errorWidget` — adapt to the actual API and note any consumer-facing implications in the CHANGELOG.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test --plain-name 'network AVIF'`
Expected: both tests PASS.

- [ ] **Step 6: Run the full suite to verify no regressions**

Run: `flutter test`
Expected: every test passes — including `network image URL builds CachedNetworkImage` and `network PNG URL builds CachedNetworkImage` (the `_isAvifUrl` check must not catch non-AVIF URLs).

- [ ] **Step 7: Commit**

```bash
git add lib/any_image_view.dart test/any_image_view_test.dart
git commit -m "feat: render network AVIF via CachedNetworkAvifImage"
```

---

## Task 5: Add file-AVIF dispatch (no widget test — follows existing file pattern)

**Files:**
- Modify: `lib/any_image_view.dart` (`_buildFileImage()` around lines 240-268)

No new test. The existing test suite has no widget tests for file-path image rendering (file rendering requires a real file on disk, which isn't viable in the test environment). The `.avif`-file extension test added in Task 2 already covers the detection side; this task wires the dispatch.

- [ ] **Step 1: Add the AVIF branch in `_buildFileImage()`**

In `lib/any_image_view.dart`, in `_buildFileImage()` (around lines 240-268), modify the existing function. Currently it returns a `FutureBuilder` that builds `Image.file`. We need to choose `AvifImage.file` when the path ends in `.avif`. Replace the `return Image.file(...)` call inside the `FutureBuilder` with conditional logic:

```dart
  Widget _buildFileImage(String path, Widget Function() errorFallback) {
    final file = File(path);
    if (!file.existsSync()) {
      return errorFallback();
    }

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget();
        }

        if (snapshot.hasError || !(snapshot.data ?? false)) {
          return errorFallback();
        }

        if (path.toLowerCase().endsWith('.avif')) {
          return AvifImage.file(
            file,
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            errorBuilder: (_, __, ___) => errorFallback(),
          );
        }

        return Image.file(
          file,
          height: height,
          width: width,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => errorFallback(),
        );
      },
    );
  }
```

**Verify the `AvifImage.file` constructor signature.** Same caveat as Task 3 — adapt if `errorBuilder` is absent or differently named.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!` — the change introduces no new lints (no `avoid_print`, no unused imports, no missing return types).

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: all tests pass. The file-path AVIF extension test from Task 2 already passes (detection), and no existing test exercises `_buildFileImage` for AVIF specifically — but `flutter analyze` confirms the new branch compiles cleanly.

- [ ] **Step 4: Commit**

```bash
git add lib/any_image_view.dart
git commit -m "feat: render local-file AVIF via AvifImage.file"
```

---

## Task 6: Update example app with AVIF demo (manual verification of autoplay behavior)

**Files:**
- Modify: `example/lib/main.dart`
- Create: `example/assets/avif/sample.avif` (a small still AVIF) and `example/assets/avif/sample_animated.avif` (a small animated AVIF) — sourced manually by the engineer

This task verifies the **open question from the spec**: does animated AVIF auto-play by default? It also gives consumers a working demo.

- [ ] **Step 1: Add AVIF test assets**

Obtain two small AVIF files (each ideally < 100 KB):
- A still image: save as `example/assets/avif/sample.avif`
- An animated AVIF: save as `example/assets/avif/sample_animated.avif`

A reliable source for small sample AVIFs: the official AOM test corpus, or any public CDN that serves AVIFs (e.g., a Wikipedia AVIF). If no sample is readily available, generate one with `cwebp` → AVIF conversion via `flutter_avif.encodeAvif()` in a throwaway script, or skip the animated test and document "animated AVIF behavior not verified manually" in the CHANGELOG.

Create the directory:

```bash
mkdir -p example/assets/avif
```

- [ ] **Step 2: Register the assets in `example/pubspec.yaml`**

Edit `example/pubspec.yaml`. In the `flutter > assets:` list (currently lines 22-27), add the new directory:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/png/
    - assets/svg/
    - assets/lottie/
    - assets/avif/
```

- [ ] **Step 3: Add an AVIF section to the demo screen**

Edit `example/lib/main.dart`. In the `ListView` (around line 63), add two new sections paralleling the existing "Local Asset Image" and "Lottie Animation" sections. Insert after the existing "SVG from Network with Custom Color" section (around line 192):

```dart
          const SizedBox(height: 24),
          _buildSection(
            'AVIF (Local Asset, Still)',
            AnyImageView(
              imagePath: 'assets/avif/sample.avif',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(
            'AVIF (Animated, Auto-Play)',
            AnyImageView(
              imagePath: 'assets/avif/sample_animated.avif',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
```

- [ ] **Step 4: Run the example app and verify behavior**

```bash
cd example && flutter run -d <your-device-id>
```

Where `<your-device-id>` is your simulator/device (`flutter devices` to list). Verify:
- The still AVIF section renders the image correctly.
- The animated AVIF section auto-plays the animation without any additional code.
- Scroll through the rest of the demo — no regressions in existing sections (PNG, SVG, Lottie, network image, etc.).

**If the animated AVIF does NOT auto-play** (only shows the first frame), this is the open question's negative resolution. Either:
- (a) Update the CHANGELOG entry in Task 7 to clarify that animated AVIFs render as stills (matches current AVIF Image behavior; consumers can use flutter_avif directly for animation control), or
- (b) Investigate flutter_avif's `AvifImage` constructor for an `autoplay` parameter or similar, and add it to all three dispatch sites. Escalate to the maintainer before choosing (b).

- [ ] **Step 5: Commit**

```bash
cd ..
git add example/pubspec.yaml example/lib/main.dart example/assets/avif/
git commit -m "example: demo AVIF still + animated rendering"
```

---

## Task 7: Update CHANGELOG, README, CLAUDE.md, and bump version

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump the package version**

In `pubspec.yaml`, change line 2 from `version: 2.1.0` to:

```yaml
version: 2.2.0
```

Also add `avif` to the topics list (lines 5-10):

```yaml
topics:
  - flutter
  - image
  - image-viewer
  - svg
  - lottie
  - avif
```

- [ ] **Step 2: Prepend the CHANGELOG entry**

In `CHANGELOG.md`, prepend a new `## 2.2.0` section above the existing `## 2.1.0` entry. Match the prose style of the existing entries:

```markdown
## 2.2.0
- Added: **AVIF support** — `.avif` asset paths, network URLs (e.g. `https://example.com/photo.avif`), local files, and XFile sources now render via `flutter_avif`. Animated AVIFs auto-play by default, matching GIF behavior.
- Added: `ImageType.avif` enum case for AVIF format detection.
- Known: Network AVIFs do not show the built-in shimmer loading placeholder — `CachedNetworkAvifImage` does not expose a placeholder hook the way `CachedNetworkImage` does. The `errorWidget` fallback works normally.
- Dependency: added `flutter_avif: ^3.1.0` (libavif via FFI; bundles native plugins for Android, iOS, Web, macOS, Windows, Linux).

---
```

**If Task 6 Step 4 revealed that animated AVIFs do NOT auto-play**, replace the first bullet with: "Animated AVIFs currently render as still images (first frame only). Future release will add animation control if needed."

- [ ] **Step 3: Update the README supported-formats line and add a usage example**

In `README.md`, line 74, change:

```markdown
PNG, JPG, WebP, GIF, SVG, Lottie (.json), TIFF, RAW, HEIC, BMP, ICO
```

to:

```markdown
PNG, JPG, WebP, GIF, AVIF, SVG, Lottie (.json), TIFF, RAW, HEIC, BMP, ICO
```

Add an AVIF example to the usage block. After the `// Lottie` example (around line 36), insert:

```dart
// AVIF (asset, network, or file — animated AVIFs auto-play)
AnyImageView(imagePath: 'assets/photo.avif', height: 200, width: 200)
AnyImageView(imagePath: 'https://example.com/photo.avif', height: 200, width: 200)
```

- [ ] **Step 4: Update CLAUDE.md routing notes**

In `CLAUDE.md`, in the "Routing flow" section (around lines 38-49), replace the bulleted list under step 3 so AVIF is documented. The current block:

```markdown
3. `imagePath is String` → `_buildStringImage()`, which switches on `path.imageType`:
   - `svg` → `_SafeSvgLoader` (asset mode)
   - `json` / `zip` → `Lottie.asset()`
   - `network` → if `_isSvgUrl(path)` then `_SafeSvgLoader` (network mode), else `CachedNetworkImage`
   - `file` → `_buildFileImage()`
   - everything else → `Image.asset()`
```

becomes:

```markdown
3. `imagePath is String` → `_buildStringImage()`, which switches on `path.imageType`:
   - `svg` → `_SafeSvgLoader` (asset mode)
   - `avif` → `AvifImage.asset()` (asset AVIFs; network AVIFs are detected within the `network` branch below)
   - `json` / `zip` → `Lottie.asset()`
   - `network` → if `_isSvgUrl(path)` then `_SafeSvgLoader` (network mode); else if `_isAvifUrl(path)` then `CachedNetworkAvifImage`; else `CachedNetworkImage`
   - `file` → `_buildFileImage()` (routes `.avif` paths to `AvifImage.file`, everything else to `Image.file`)
   - everything else → `Image.asset()`
```

The "Detection-order invariant" paragraph below it covers `.svg` URLs. No edit needed — the invariant is the same for `.avif` URLs, and the regression test added in Task 2 reinforces it.

- [ ] **Step 5: Verify everything**

Run all three checks:

```bash
flutter analyze
flutter test
flutter pub publish --dry-run
```

Expected:
- `flutter analyze`: `No issues found!`
- `flutter test`: all tests pass.
- `flutter pub publish --dry-run`: `Package has 0 warnings.` (Or a small number of expected-and-acceptable warnings about README badges, etc. — anything else, investigate.)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml CHANGELOG.md README.md CLAUDE.md
git commit -m "release: 2.2.0 — flutter_avif support"
```

---

## Task 8: Final pre-publish verification

**Files:** none modified — verification only.

- [ ] **Step 1: Clean rebuild**

```bash
flutter clean && flutter pub get
```

Expected: no errors.

- [ ] **Step 2: Re-run all checks from a clean state**

```bash
flutter analyze && flutter test && flutter pub publish --dry-run
```

Expected: all green. If any step fails, fix and commit a follow-up before proceeding.

- [ ] **Step 3: Verify the example app one more time**

```bash
cd example && flutter pub get && flutter run -d <device>
```

Smoke-test every section in the demo. Verify the new AVIF sections render correctly and existing sections show no regressions.

- [ ] **Step 4: Confirm git history is clean**

```bash
git log --oneline -10
```

Expected to see commits roughly in this order (most recent first):
- `release: 2.2.0 — flutter_avif support`
- `example: demo AVIF still + animated rendering`
- `feat: render local-file AVIF via AvifImage.file`
- `feat: render network AVIF via CachedNetworkAvifImage`
- `feat: render asset AVIF via AvifImage.asset`
- `feat: detect .avif paths as ImageType.avif`
- `deps: add flutter_avif ^3.1.0`

Run: `git status`
Expected: `nothing to commit, working tree clean`.

The feature is now ready for the maintainer to `flutter pub publish` (a manual, deliberate step — not part of this plan).

---

## Notes for the implementer

- **TDD discipline:** every code change is preceded by a failing test (where the test environment supports it). Skip steps only when explicitly noted (file dispatch in Task 5 has no widget test by design — the existing pattern doesn't test file rendering).
- **Detection-order invariant:** the URL-protocol-first invariant in `ImageTypeExtension.imageType` is load-bearing. Task 2 adds a regression test that protects it. If you ever need to reorder the checks in that method, the test must continue to pass.
- **Single-file structure:** all production changes land in `lib/any_image_view.dart`. Don't split into multiple files — the package CLAUDE.md explicitly calls this out as deliberate.
- **flutter_avif API verification:** the spec and this plan assume `AvifImage.asset/network/file` and `CachedNetworkAvifImage` constructors accept `errorBuilder`, `headers`, `height`, `width`, `fit`. Verify against the actual flutter_avif 3.1.0 source when wiring up — adapt parameter names if needed and note any consumer-facing changes in the CHANGELOG.
- **Production code standards apply** (per `~/.claude/CLAUDE.md`): no stubs, no TODOs, no silent error swallowing. Every dispatch site routes errors through `errorFallback()` so failures land in the user's `errorWidget`.
