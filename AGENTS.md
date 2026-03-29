# Repository Guidelines

## Project Structure & Module Organization
`cmd/api/main.go` is the application entrypoint and router bootstrap. Business code lives under `internal/`: `handler/` exposes Gin endpoints, `service/` contains use-case logic, `repository/` wraps persistence, `model/entity` and `model/dto` define data structures, `middleware/` holds auth and token refresh, and `util/` contains Redis locks, cache helpers, and Lua scripts. Global clients for MySQL, Redis, RocketMQ, and logging are initialized in `internal/global/`. Runtime configuration is in `config/`, and `hmdp.sql` seeds the database schema.

## Build, Test, and Development Commands
Use `go mod tidy` to sync dependencies. Run the API locally with `go run ./cmd/api/main.go`; it reads `config/config.yaml` and starts on the configured port. Use `go test ./...` for the full test suite, or target a package such as `go test ./internal/test -run TestRedisIdWorker`. Format code with `gofmt -w ./...` before submitting changes.

## Coding Style & Naming Conventions
Follow standard Go formatting: tabs for indentation, exported identifiers in `PascalCase`, unexported helpers in `camelCase`, and package names in short lowercase nouns. Keep handlers thin and push business rules into `service/`. Place persistence-specific queries in `repository/` rather than `handler/` or `util/`. Prefer file names that match the main domain object, such as `shop.go` or `voucher_order.go`.

## Testing Guidelines
Tests live in `internal/test` and use Go’s built-in `testing` package. Name tests with the `TestXxx` pattern and keep them focused on one behavior. Several tests touch Redis or other configured services, so make sure MySQL, Redis, and RocketMQ settings in `config/config.yaml` are valid before running integration-style checks. Add or update tests when changing cache logic, ID generation, or voucher order flows.

## Commit & Pull Request Guidelines
Recent history shows short, imperative subjects and brief `update` commits. Prefer concise, specific messages describing the behavior changed. For pull requests, include a summary of affected modules, any config or schema updates, commands you ran (for example `go test ./...`), and sample requests/responses when API behavior changes.

## Security & Configuration Tips
Do not commit real credentials in `config/config.yaml`. Keep local overrides out of version control when possible. When changing Redis, RocketMQ, or MySQL integration, document new topics, ports, or required seed data in `README.md` and verify shutdown behavior through `cmd/api/main.go`.
