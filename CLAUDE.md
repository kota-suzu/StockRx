# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Starting the Application
```bash
make up          # Start all containers (Rails, MySQL, Redis, Sidekiq)
make server      # Alias for 'make up' with health check
make logs        # View logs (follow mode)
make ps          # Check container status
```

### Database Operations
```bash
make db-setup    # Create database, run migrations, and seed data
make db-migrate  # Run pending migrations
make db-reset    # Drop, create, migrate, and seed database
make db-seed     # Load seed data
```

### Running Tests
```bash
# Quick tests (recommended for development)
make test-unit-only    # Models, helpers, decorators only (~3.5s)
make test-models       # Model tests only
make test-fast         # Models, controllers, and units

# Comprehensive tests
make test              # Run all tests (alias: make rspec)
make test-coverage     # Run tests with coverage report
make test-integration  # Feature and job tests

# Test utilities
make test-failed       # Re-run only failed tests
make test-profile      # Show 10 slowest tests
make test-parallel     # Run tests in parallel
```

### Code Quality
```bash
make lint              # Run RuboCop
make lint-fix          # Auto-fix safe issues
make lint-fix-unsafe   # Auto-fix all issues (use with caution)
make security-scan     # Run Brakeman security scan
```

### Utilities
```bash
make console           # Rails console
make routes           # Show all routes
docker-compose exec web bundle exec sidekiq  # Start Sidekiq worker
```

## Architecture Overview

### Namespace Structure
The application uses specific namespace patterns to avoid conflicts with model names:

- **Controllers**: `AdminControllers` module for admin-related controllers
  - Located in `app/controllers/admin_controllers/`
  - Example: `AdminControllers::DashboardController`
  
- **Helpers**: Standard helper naming convention
  - Admin helpers: `app/helpers/admin_controllers/`
  - Example: `AdminControllers::InventoriesHelper`

- **Views**: Match controller namespace structure
  - Admin views: `app/views/admin_controllers/`

### Key Models and Relationships

```ruby
# Core inventory management
Inventory (has_many :batches, :inventory_logs)
  ├── Batch (belongs_to :inventory) - Lot/batch tracking
  ├── InventoryLog - Audit trail for all changes
  ├── Receipt - Incoming stock records  
  └── Shipment - Outgoing stock records

# Authentication
Admin (Devise with :lockable, :timeoutable)
  └── AdminNotificationSetting - Email preferences
```

### Background Job Processing
The application uses Sidekiq for background jobs with Redis:

- **ImportInventoriesJob**: CSV import with progress tracking via ActionCable
- **Job monitoring**: Sidekiq Web UI at `/sidekiq` (admin auth required)
- **Progress tracking**: Real-time updates through ActionCable channels

### Error Handling
Modular error handling system with `config.exceptions_app = routes`:

- **ErrorHandlers** concern for consistent API/HTML responses
- **ErrorsController** for rendering error pages
- **Custom error classes** in `app/lib/custom_error.rb`
- Static error pages for 400, 403, 404, 422, 429, 500

### Security Considerations

- **CSV Import**: File size limit (10MB), MIME type validation
- **Authentication**: Devise with password strength validation (12+ chars)
- **Session timeout**: 30 minutes of inactivity
- **Failed login lockout**: 5 attempts → 15 minute lock
- **Current class**: Thread-local request/user context (use `Current.reset` in tests)

### Testing Strategy

- **RSpec** with FactoryBot for test data
- **Coverage tracking** with SimpleCov
- **Shared examples** for common patterns
- **Known issues**: 
  - Job tests may fail due to Redis/ActionCable setup
  - Feature tests need Capybara configuration
  - Auditable concern has error handling issues

### Performance Optimizations

- **N+1 detection**: Bullet gem in development
- **CSV import**: Batch processing (1000 records/batch)
- **Database indexes**: On foreign keys and search fields
- **Decorators**: Draper for view logic separation

## Common Development Tasks

### Adding a New Feature
1. Check namespace conventions (avoid model name conflicts)
2. Use `Current` class for request context
3. Add appropriate error handling
4. Write tests (aim for >90% coverage)
5. Run linting before committing

### Working with Background Jobs
1. Inherit from `ApplicationJob`
2. Include `ProgressNotifier` for progress tracking
3. Use appropriate Sidekiq queue (default, critical, low)
4. Add error handling and retries
5. Write both unit and integration tests

### Database Migrations
1. Use strong constraints and foreign keys
2. Add indexes for foreign keys and search fields
3. Consider data migration needs
4. Test rollback scenarios

## Important Notes

- **Docker required**: All commands run through Docker Compose
- **Port 3000**: Default Rails server port
- **Development URL**: http://localhost:3000 (not https)
- **Default admin**: admin@example.com / Password1234!
- **Time zone**: Application uses UTC internally
- **File uploads**: Currently stored locally, S3 integration planned

常にメタ認知を誘発して、ステップバイステップで実行して。

横展開確認して修正も行なってください。

ベストプラクティスで実装して

残タスクについてはドキュメントを参考にして、TODOなどのコメントを追加してください。