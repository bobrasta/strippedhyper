# CLAUDE.md — bien-hyper

Hypermed (medical-equipment service, sales, finance, HR) Flutter client —
desktop (Windows/Linux/macOS) and phone/tablet from one codebase.

## Repos

| Repo | Role |
|---|---|
| `bobrasta/bien-hyper` (this, `master`) | The Flutter app. Mobile layouts were built in `bobrasta/bien-hyper-mobile` (branch `mobile-ui-layout`) and merged here on 2026-10-04; new work, mobile included, goes on `master` here. |
| `bobrasta/hypermed-api` | Laravel backend. Dashboard endpoints live in `DashboardController`. |
| `bobrasta/hypermed-web` | Blade web client. |

When a change touches a screen that has a phone layout, check both
branches of it — e.g. the per-line TSh discount changed `line_items.dart`
after the phone row was written.

## Mobile layout conventions

- **Shell breakpoints** (`widgets/common/app_shell.dart`): < 720 phone
  (page-title top bar, role-aware bottom tabs + "More" drawer), 720–1099
  tablet (icon rail), ≥ 1100 desktop.
- **Screen breakpoint**: `isPhoneWidth(width)` / `kPhoneBreakpoint = 600`,
  measured on the screen's own content width (LayoutBuilder), not the window.
- **Desktop layouts stay as they were** — every phone change is a branch
  taken only below the breakpoint.
- Shared phone widgets in `widgets/common/phone_layout.dart`:
  `PhonePageHeader` (title, primary action, ⋮ menu, search, swipeable
  filters, `bottom` slot), `PhoneRecordCard` (table row → card), `PhonePill`,
  `PhoneStatGrid` / `statStrip` (4–5-up KPI strips → 2 per row),
  `TitleWithActions`, `sideBySideOrStacked`, `fitOnPhone`,
  `pushPhoneDetail`, `PhoneModalBox` (in-screen modals dock as a bottom
  sheet; `scroll: false` for cards that already scroll inside).
- List + detail screens: detail opens as a pushed page, or replaces the
  list in place when it reloads data after opening; wrap the in-place form
  in `PopScope` so Android back closes the detail first.
- Bottom tabs come from the role's allowed screens (`_mobileTabs`), never a
  fixed list; `navEntryFor(key)` in `sidebar.dart` gives labels/icons.
- `AppShell(initialScreenKey: …)` opens a given screen (used by tests).

## Verifying changes

- `flutter analyze` — baseline is **56 info-level** notes (all pre-existing,
  2 of them in upstream's CTO code). New warnings/errors are not OK.
- `flutter test` — all pass except **`test/widget_test.dart` App smoke
  test, which fails on the original too** (trialNotifier never initialised).
- `test/phone_layout_audit_test.dart` opens all 59 menu screens at 390×844
  and 12 "new …" forms, failing on any overflow. It uses the test font
  (wider than real fonts), so it also guards larger Text Size settings.
- Empty-data audits miss row/content overflows: for dashboards, render with
  realistic data (stub `ApiClient.instance.dio` with an interceptor keyed by
  path) and check at 390 px **and** 1440 px. Keep sample data out of the repo.
- Screenshots: `matchesGoldenFile` + `--update-goldens`, after loading real
  fonts with `FontLoader` (TildaSans from assets, MaterialSymbols from the
  pub cache, Roboto from the Flutter SDK; google_fonts' Inter/JetBrainsMono
  must be downloaded and registered as `Inter_700`, `JetBrainsMono_regular`, …).

## Local store, caching and alerts

- `services/local_db.dart` — SQLite (package `sqlite3`, FFI, bundled by
  build hooks; no plugin). `kv` (scope = user id or `'app'`), `responses`
  (disk cache), `outbox` (failed email sends). `LocalDb.instance` is null
  when it can't open — in widget tests unless a test sets
  `LocalDb.instance = LocalDb.openInMemory()`. `wipeLocalUserData()`
  (main.dart) runs on logout / 401 / own password change.
- `services/disk_cache.dart` — first request per key per session is served
  from disk and revalidated; `AppShell` remounts the screen or shows the
  "Updated data available" chip. Polling calls must pass `noCache`.
- `services/background_sync.dart` — pop-ups diffed by id with last-seen
  markers in kv; `handle*` methods are unit-tested with an injected toaster.

## Traps

- Running `flutter test`/`analyze` regenerates
  `macos/Flutter/GeneratedPluginRegistrant.swift` — restore it with
  `git checkout --` before committing.
- In widget tests, restore `FlutterError.onError` in a `finally` before any
  `expect`, or one failure hangs the remaining tests.
- Widget tests that send requests through `ApiClient` must set
  `authTokenNotifier` (it's `late`, normally set by `main()`), and should
  pump rather than `runAsync`: real async lets google_fonts' font fetch fail
  mid-test.
- `flutter_secure_storage` needs a mock method channel in tests, or screens
  that call `AuthService.getProfile()` sit on their skeleton forever.
- A `Text` in a `Row` beside a `Spacer`/buttons must be `Expanded`/`Flexible`
  with `maxLines` + `overflow` — the most common phone overflow here.
- Fixed `childAspectRatio` grids make tiles absurdly tall on tablets; prefer
  `mainAxisExtent`.

## Open items (as of 2026-10-04)

- Never tested on a physical device; no Android APK has been built yet.
- CTO approval detail screen not exercised at phone size.
