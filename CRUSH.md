# CRUSH.md

## Build/Lint/Test Commands
- **Build**: `mix compile`
- **Format**: `mix format`
- **Lint**: `mix credo` (install via `mix deps.get`)
- **Test**: `mix test`
- **Single Test**: `mix test test/ex_jexl_test.exs`

## Code Style Guidelines
- **Imports**: Group and sort `use`/`import` statements alphabetically.
- **Formatting**: Use `mix format` for consistent code style (configured in `.formatter.exs`).
- **Types**: Define types with `@type` annotations.
- **Naming**: `snake_case` for functions/atoms, `CamelCase` for modules.
- **Error Handling**: Prefer `try/rescue` over `rescue` clauses; use `with/1` for chained operations.
- **Docs**: Use `@doc` for public APIs; follow the `ex_doc` format for documentation.