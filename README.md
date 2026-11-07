# Hypermed (stripped build)

A cut-down copy of the Hypermed system: the Flutter client from
`bobrasta/bien-hyper` (desktop and phone/tablet from one codebase) plus its
Laravel backend from `bobrasta/hypermed-api`.

## Modules

**Included:** inventory and stock movements, purchases, procurement
(tenders, NeST tenders, shipments), finance and accounting, expenses,
revenue, sales, customers, HR, approvals, email/chat/meetings/letters,
settings. Travel plans (per diem) are kept as an expense flow ("New travel
plan" on My Travel Plans). The admin "Command Centre" dashboard shows
finance, sales, inventory and people.

**Removed:** machines (equipment fleet), service tickets (technician field
service), hospitals directory/map, flagged units, spare parts, and the CTO
and technician dashboards.

## Layout

| Path | What |
|---|---|
| `/` (`lib/`, `test/`, platform folders) | Flutter app (package `bienhypermed`) |
| `backend/` | Laravel API — see `backend/README.md` and `backend/LARAVEL_CLAUDE.md` |

## Run the app

```sh
flutter pub get
flutter run -d windows        # or -d linux / -d macos
```

The API URL is set with `API_BASE_URL` (default
`https://api.hypermed.co.tz/api/v1`, the production Hypermed API). For a
local backend:

```sh
flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8002/api/v1
```

Checks: `flutter analyze` and `flutter test` (see `CLAUDE.md` for the
expected baseline).

## Run the backend

```sh
cd backend
composer install
cp .env.example .env          # set DB_* (production uses PostgreSQL)
php artisan key:generate
php artisan migrate
php artisan serve --port=8002
```

`composer setup` does install/.env/key/migrate plus the npm build in one go;
`composer dev` runs the server, queue listener, logs and Vite together;
`composer test` runs the test suite. The NeST tender sync also needs
`php artisan schedule:run` every minute and a queue worker (see
`backend/README.md`).

## Notes

- **Database:** migrations are unchanged, so the old machine, service-ticket,
  spare-part etc. tables and FK columns are still created; nothing uses them.
- **Customers** are still the backend's `hospitals` table: the app calls
  `/hospitals` through `lib/models/client.dart` and
  `lib/services/client_service.dart`.
- **Auto-update:** `UPDATE_FEED_URL` defaults to
  `https://app.hypermed.co.tz/updates/latest.json` — the full Hypermed
  release feed (`lib/services/update_service.dart`; the release workflow
  falls back to the same host when `vars.UPDATE_BASE_URL` is unset). An
  installed release build of this app polls that feed and would update
  itself to the **full** Hypermed app. Before releasing the stripped build,
  point it at its own feed (`--dart-define=UPDATE_FEED_URL=…` /
  `UPDATE_BASE_URL` in the workflow) and keep its releases off the main feed.
