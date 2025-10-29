# Repository Guidelines

## Project Structure & Module Organization
- Rails domain code stays in `app/`; keep namespaces aligned with Zeitwerk folders such as `app/controllers/admin_controllers` and `app/services`.
- Shared Ruby helpers that do not depend on Rails belong in top-level `lib/`; keep migrations, seeds, and fixtures in `db/` and `test_data/`.
- Environment and initializer settings live in `config/`; documentation is kept in `docs/` and `doc/`.
- Automated tests mirror production structure inside `spec/` (RSpec); legacy system cases remain in `test/` until fully ported.

## Build, Test, and Development Commands
- `make setup` provisions Docker services, installs gems, and prepares the database—run it after cloning or major infra updates.
- `make up` starts the stack and health-checks `http://localhost:3000`; pair with `make down` or `make clean` to reset containers.
- `make rspec` (alias `make test`) executes the full suite; lean on `make test-fast`, `make test-models`, or `make test-requests` for focused iterations.
- `make test-coverage` produces SimpleCov output, while `make lint` and `make security-scan` wrap `bin/rubocop`, Brakeman, and bundle-audit.

## Coding Style & Naming Conventions
- Default to two-space indentation, snake_case filenames, and CamelCase constants that match directory paths to keep Zeitwerk stable.
- Run `bin/rubocop` (rubocop-rails-omakase) before commits; reserve `bin/rubocop -A` for intentional, reviewed auto-corrections.
- Name service objects `*Service`, jobs `*Job`, concerns under `app/models/concerns/`, and Stimulus controllers `*_controller.js` inside `app/javascript/controllers/`.

## Testing Guidelines
- Write specs under `spec/` with filenames ending `_spec.rb`, mirroring production paths; share factories and helpers via `spec/factories` and `spec/support`.
- Prefer RSpec for new work; keep `test/system` only for suites that still rely on Minitest.
- Run `make test` locally before pushing and capture coverage deltas with `make test-coverage`; the active initiative targets 70% coverage (baseline 19.49% on 2025-06-25 per `coverage_improvement_plan.md`).

## Commit & Pull Request Guidelines
- Follow the observed Conventional Commits pattern: `<type>: <summary>` (e.g., `feat: C1ブランチカバレッジ向上基盤実装`); common types are `feat`, `fix`, `test`, and `chore`.
- Keep commits scoped, reference tickets or docs when applicable, and write concise summaries in the dominant review language.
- PRs should explain context, approach, and validation (`make test`, `make security-scan`, screenshots for UI changes) and ensure CI pipelines succeed before requesting review.

## Security & Configuration Tips
- Duplicate `.env.example` for local secrets and never commit credentials or production data.
- `make services-health-check` confirms MySQL/Redis readiness; use `make diagnose` when reviewers need detailed container state.
- Store generated CSV fixtures in `test_data/` and confirm they remain synthetic.
