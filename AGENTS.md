# Repository Guidelines

## Project Structure & Module Organization
- `start.sh`, `restart.sh`, `shutdown.sh`, `health_check.sh`: primary operational scripts for starting, restarting, stopping, and checking the Mihomo (Clash) service.
- `conf/`: runtime configuration and data (e.g., `config.yaml`, `template.yaml`, `geo*`, and the bundled dashboard under `conf/dashboard/`).
- `bin/`: bundled binaries (`mihomo`, `yq`) downloaded/used by scripts.
- `logs/`: runtime logs (e.g., `logs/mihomo.log`).
- `image/`: reference screenshots used by documentation.

## Build, Test, and Development Commands
- `source ./start.sh`: bootstrap and start Mihomo; downloads needed binaries, validates config, and injects helper shell functions.
- `source ./restart.sh`: restart Mihomo with the latest config.
- `source ./shutdown.sh`: stop Mihomo and remove injected shell helpers.
- `source ./health_check.sh`: verify outbound connectivity through the proxy.
- `./converter.sh`: convert/normalize subscription content into a Clash config (writes into `conf/`).

## Coding Style & Naming Conventions
- Shell scripts are Bash-compatible; follow existing patterns (4-space indentation, uppercase environment variables like `CLASH_URL`).
- Prefer descriptive, snake_case function names in scripts (e.g., `validate_subscription_url`).
- No formatter or linter is configured; keep changes small and consistent with neighboring code.

## Testing Guidelines
- No automated test suite is present. Use manual verification:
  - Start the service, check `logs/mihomo.log`, and confirm the dashboard loads at `http://<server-ip>:9090/ui`.
  - Run `source ./health_check.sh` after config changes.

## Commit & Pull Request Guidelines
- Recent history shows short, imperative messages (e.g., `update`, `add ip address`). Keep commit subjects concise and action-focused.
- PRs should include: a brief description, the motivation for changes, and any operational steps to validate (commands used, expected output).
- If changes affect config or scripts, include screenshots or log excerpts when helpful (e.g., dashboard access or health check output).

## Security & Configuration Tips
- Store secrets in `.env` (e.g., `CLASH_URL`, `CLASH_SECRET`) and avoid committing them.
- Treat `conf/config.yaml` as sensitive; do not share provider URLs or credentials in PRs.
