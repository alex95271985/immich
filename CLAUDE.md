# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Immich is a self-hosted photo and video management solution (AGPLv3). Monorepo components:

| Component | Path | Stack |
| --- | --- | --- |
| Server | `server/` | NestJS (ESM TypeScript), Postgres via Kysely, Redis/BullMQ |
| Web app | `web/` | SvelteKit + Svelte 5 runes, Tailwind v4, Vite |
| Mobile app | `mobile/` | Flutter + Riverpod, Rust core from `native/` |
| Machine learning | `machine-learning/` | Python FastAPI (CLIP, facial recognition, OCR), uv |
| E2E tests | `e2e/` | Vitest (API) + Playwright (web) |
| Packages | `packages/` | `sdk` (generated TS API client), `cli`, `plugin-core`/`plugin-sdk` (WASM plugins), `scripts` (release tooling), `e2e-auth-server` (local OIDC provider) |
| OpenAPI | `open-api/` | checked-in generated spec + Dart SDK generation templates |
| Rust core | `native/` | crates compiled into the mobile app (`native_core_ffi` C ABI + ffigen bindings) |
| Docs | `docs/` | Docusaurus |
| Translations | `i18n/` | JSON source files for web + mobile |

## Tooling

[mise](https://mise.jdx.dev) manages all tool versions (Node, pnpm, Flutter, Rust, Java, uv) and all tasks. First run: `mise trust && mise install`. List tasks with `mise tasks ls --all`.

Tasks are namespaced per directory and runnable from the repo root as `mise //server:test` (same as `cd server && mise run test`). pnpm workspaces: install per-package with filters, e.g. `pnpm install --filter immich --frozen-lockfile`.

## Commands

### Full dev stack (Docker Compose, hot reload)

```bash
cp docker/example.env docker/.env   # set UPLOAD_LOCATION
mise x -- pnpm i                    # one-time install
mise dev                            # up; web at http://localhost:3000 (proxies /api)
mise dev-down                       # also dev-update / dev-scale (3 server replicas)
```

Postgres is exposed on `localhost:5432` (postgres:postgres, db `immich`). Web-only dev against the hosted demo: `mise //web:start-demo`.

### Server (`mise //server:<task>` or `cd server && pnpm <script>`)

- `checklist` — format + lint + `tsc` + unit tests + medium tests (full local gate)
- `test` / `test:cov` — vitest unit tests (`src/**/*.spec.ts`, colocated)
- `test-medium` — vitest against a real Postgres via testcontainers (`test/medium/**`; needs Docker)
- Single test: `cd server && pnpm test --run src/services/asset.service.spec.ts` (add `-t 'name'` to filter by test name)
- `lint` / `lint:fix`, `format` / `format:fix`, `check` (tsc)

### Web (`mise //web:<task>` or `cd web && pnpm <script>`)

- `check:code` — format + lint + svelte-check + tsc; `checklist` adds unit tests
- Single test: `cd web && pnpm test --run src/lib/<path>.spec.ts`

### Mobile (`mise //mobile:<task>`)

- `checkout` — run **after every branch switch** (pub get, pods, all codegen)
- `codegen` — regenerate everything (build_runner, drift, pigeon, ffigen, translations, Dart SDK)
- `lint` (dart analyze + dcm), `lint-fix`, `format`, `test`
- Single test: `cd mobile && flutter test test/<path>` or `flutter test --name 'pattern'`

### Machine learning (`mise //machine-learning:<task>`)

- `checklist` — format + ruff lint + mypy (strict) + pytest
- Single test: `cd machine-learning && uv run pytest -k TestName`

### E2E

```bash
mise e2e                     # start test stack (one-time: mise //e2e:ci-setup && mise open-api)
mise //e2e:test              # API/CLI/immich-admin specs (vitest, e2e/src/specs/server)
mise //e2e:test-web          # Playwright (--project=web|maintenance|ui)
```

Single tests: `cd e2e && pnpm test src/specs/server/<file>.e2e-spec.ts` (vitest) or `pnpm exec playwright test --project=web <file>` / `-g 'name'`.

### Cross-cutting workflows

- **API endpoints changed** → `mise open-api`: rebuilds server, regenerates `open-api/immich-openapi-specs.json`, the TS SDK (`packages/sdk/src/fetch-client.ts`, via oazapfts) and the Dart SDK (`mobile/generated/openapi`). Never hand-edit the spec or generated clients; CI checks for breaking API changes.
- **Schema changed** (`server/src/schema/`) → `mise //server:migrations generate <name>`, move the file into `server/src/schema/migrations/`, then `mise //server:migrations sync-order` (updates the committed `ORDER` manifest that prevents out-of-order merge conflicts). Revert with `migrations revert`; reset dev DB with `mise //server:schema-reset`.
- **Repository queries changed** → regenerate SQL snapshots for review: `mise //server:sql` (logs SQL of methods tagged `@GenerateSql(...)` into `server/src/queries/*.sql`).
- **New translation string** → add to `i18n/en.json`, then `mise //mobile:translation`. Translations themselves go through Weblate, not PRs.

## Architecture

### Server process model and layering

`server/src/main.ts` is a supervisor that boots workers from `src/workers/`: **api** (HTTP via Express, global prefix `/api`, also serves the built web app) and **microservices** (BullMQ workers + socket.io gateway). Selected with `IMMICH_WORKERS_INCLUDE`/`_EXCLUDE`. Both boot the same Nest modules; api adds controllers and the AuthGuard.

Request flow: **controllers → services → repositories**. Controllers are thin and inject one service. All services extend `BaseService` (`src/services/base.service.ts`), which injects *all* ~55 repositories at once — **services never inject each other**; cross-service coordination happens through the event bus or job queue only.

- **Jobs**: queue and job names are enums in `src/enum.ts`. Handlers are service methods decorated `@OnJob({ name, queue })` (`src/decorators.ts`), discovered reflectively at bootstrap. Enqueue with `jobRepository.queue(...)` / `queueAll(...)`.
- **Events**: typed in-process bus (`EventRepository`, `EventMap`); `@OnEvent({ name, server: true })` also emits to websocket clients.
- **DB**: Kysely + postgres.js (`@InjectKysely() db: Kysely<DB>`). Schema is declared with `@immich/sql-tools` decorators on classes in `src/schema/tables/*.table.ts`; migrations live in `src/schema/migrations/`. Shared query builders and chunking helpers are in `src/utils/database.ts` (`@Chunked` splits large ID lists under the 65535 bind-param limit).
- **DTOs**: zod schemas wrapped with `createZodDto` (nestjs-zod) in `src/dtos/`; validation runs through a global `ZodValidationPipe`, serialization via `ZodSerializerInterceptor`. OpenAPI metadata comes from `.describe()`/`.meta()` and `@nestjs/swagger` decorators.
- **Auth**: every route must declare `@Authenticated({ admin | permission | sharedLink | public | setup })` — the `AuthGuard` rejects any route without it. Current user arrives via the `@Auth()` param decorator. Object-level checks: `this.requireAccess({ auth, permission, ids })` from `BaseService`, backed by `AccessRepository` and the `Permission` enum.
- **Plugins**: WebAssembly modules run via Extism; authored against `packages/plugin-sdk`, reference implementation in `packages/plugin-core`.
- `src/cores/` is legacy (only `storage.core.ts` remains) — don't add to it. Imports use ESM `.js` specifiers throughout.

### Server testing model

Unit tests colocated as `*.spec.ts`. `test/utils.ts` provides `automock()` (reflectively mocks every method, strict by default) and `newTestService()` (builds a service with all repos auto-mocked); hand-written mocks for key repos live in `test/repositories/`. Medium tests (`test/medium/`) start a real Postgres container once and give each spec a fresh template-cloned DB; `newMediumService` (`test/medium.factory.ts`) picks which repos are real vs mocked. Shared factories: `test/small.factory.ts` and `mediumFactory`.

### Web

SvelteKit routes in `web/src/routes` (grouped `(user)`, `admin`, `auth`, `link`, `maintenance`); feature code in `web/src/lib` (`components/`, `stores/`, `managers/`, `utils/`). Stateful managers use Svelte 5 runes in `.svelte.ts` files. All API access goes through the generated `@immich/sdk`; live updates via socket.io (`src/lib/stores/websocket.ts`, path `/api/socket.io`). Typed route builder: `src/lib/route.ts`. Styling is Tailwind v4 + the external `@immich/ui` kit; i18n via svelte-i18n reading root `i18n/*.json`.

### Mobile

Riverpod providers in `mobile/lib/providers/`; the codebase mixes legacy layers (`pages/`, `services/`, `repositories/`) with newer `domain/`, `presentation/`, `infrastructure/`, `data/db` (Drift). Never hand-edit generated files (`*.g.dart`, `*.drift.dart`, `*.freezed.dart`, `routing/router.gr.dart`, `generated/openapi/`, `lib/generated/`) — regenerate with `mise //mobile:codegen`. Local DB is Drift with schema snapshots in `drift_schemas/`.

### Machine learning

FastAPI app in `machine-learning/immich_ml/` with pipelines for CLIP, facial recognition, and OCR (`pipeline.py`, `models/`, inference sessions in `sessions/`). Called by the server over HTTP (port 3003). `ann/` is ArmNN acceleration (compiled C++ `libann.so`) for ARM, not nearest-neighbor search. Managed with uv (`uv sync --locked`, extras: cpu/cuda/rocm/openvino).

## Repo policies (from CONTRIBUTING.md)

- Feature freezes — no feature PRs for **Sharing/Asset ownership** and **(External) libraries**.
- Upstream does not accept LLM-generated PRs; LLM use on `good first issue` issues is explicitly forbidden. Keep this in mind when preparing upstream contributions from this repo.
- PRs should do exactly one thing; large/impactful changes should be discussed with maintainers (Discord `#contributing`) first.
