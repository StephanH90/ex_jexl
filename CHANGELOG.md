# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking changes
- Built-in transform error semantics now match Caluma pyjexl: nil-on-error rather than raising or returning `0`.
  - `length` on numbers/booleans/nil now returns `nil` (was `0`).
  - `first`/`last` on non-list now return `nil` (previously raised).
  - `abs` on non-number now returns `nil` (previously raised).
- `floor`/`ceil` are now correct for negative numbers (use `:math.floor` / `:math.ceil` rather than `trunc`).
- `round` is now half-up (matches Caluma / JS `Math.round`), not half-to-even (banker's). Always returns float. Accepts an optional decimal-places argument: `n|round(2)`.
- Elixir `~> 1.18` / OTP 27+ required (uses stdlib `:json`).

### Added
- New built-in transforms: `mapby`, `stringify`, `min`, `max`, `sum`, `avg`, `debug`.
- `ExJexl.AST` module — `prewalk/3`, `postwalk/3`, `walk/3`, `find_transforms/2` for downstream analyzers and dependency extraction.
- `ExJexl.Validator` module — pluggable validator API. `validate/2` and `validate_ast/2`. Zero default validators; host applications register their own.
- `use ExJexl` accepts a `validators: [...]` option; module-level validators merge with per-call ones.
- Documented public AST format in `ExJexl.AST` module documentation.

## [0.1.0] - 2024-08-06

### Added
- Initial release of ExJexl
- Complete JEXL expression language support
- Arithmetic operations (`+`, `-`, `*`, `/`, `%`)
- Comparison operations (`==`, `!=`, `>`, `<`, `>=`, `<=`)
- Logical operations (`&&`, `||`, `!`)
- Property access with dot notation (`user.name`)
- Property access with bracket notation (`user["name"]`, `user[key]`)
- Array access (`items[0]`)
- Nested property access (`data.users[0].name`)
- Membership testing with `in` operator
- Transform system with pipe operator (`items|length`)
- Chained transforms (`items|reverse|first`)
- Built-in functions (`length()`, `keys()`, `values()`, `type()`)
- Support for all JSON data types (numbers, strings, booleans, arrays, objects, null)
- Context support with both string and atom keys
- Comprehensive error handling and reporting
- High-performance parsing with NimbleParsec
- Extensive test suite with 100% coverage
- Performance benchmarking suite

### Performance
- ~960K operations/second for simple expressions
- ~780K operations/second for property access
- ~460K operations/second for arithmetic operations
- ~122K operations/second for complex business logic
- Microsecond-level latencies for most operations

### Available Transforms
- **Array**: `length`, `first`, `last`, `reverse`, `sort`, `unique`, `flatten`, `join`
- **String**: `upper`, `lower`, `trim`, `split`
- **Object**: `keys`, `values`
- **Utility**: `type`

### Documentation
- Comprehensive README with examples
- API documentation
- Performance analysis
- Benchmarking suite
- Usage examples for common patterns

### Technical Details
- Built with NimbleParsec for high-performance parsing
- Recursive descent parser with proper operator precedence
- AST-based evaluation for flexibility and performance
- Safe expression evaluation (sandboxed, no code execution)
- Memory-efficient implementation
- Support for short-circuit logical evaluation