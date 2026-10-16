# AGENTS.md

Instructions for coding agents working in this repository.

## Environment

- opencode is launched from inside the Nix dev shell, so all dev tools (Zig,
  Chromium, etc.) are directly on `PATH`. Run commands directly (e.g.
  `zig build`); do **not** use the `nix develop -c` prefix.
- Zig version: `0.17.0`. Do not assume docs or examples for older Zig versions
  apply.
- Standard library source (useful reference for current APIs):
  `zg-lib/std` (a symlink to the std lib of the Zig pinned above). Verify it
  still matches `zig version` before relying on it; re-create
  the symlink if the flake bumps Zig.

## Commands

- Build: `zig build`
- Test: `zig build test`

All commands must pass before finishing a task.

## Zig 0.17-dev API notes

- `main` signature is `pub fn main(init: std.process.Init) !void`. The `Io`
  instance comes from `init.io`; an arena covering process lifetime is
  `init.arena.allocator()`.
- I/O uses the new `std.Io` interface: writers are
  `std.Io.File.Writer` with an explicit buffer, and require explicit `flush()`.
- `std.ArrayList` is unmanaged: start from `.empty` and pass an allocator to
  every method.
- For the webserver: `std.net` provides TCP listeners/connections, and
  `std.http.Server` implements HTTP/1.1 on top of a connection. Verify exact
  signatures against the std source linked above rather than from memory.
- The `**` has been deleted in this version of this. Use the `@splat` operator
  instead. for example, instead of:
  `var fields_seen = [_]bool{false} ** structInfo.fields.len;`,
  write `var fields_seen: [structInfo.fields.len]bool = @splat(false);`

## Code style

- Run `zig fmt` on all changed files.
- No comments unless they explain non-obvious rationale (matches Zig std style).

## File access policy

- Only read/write files inside the current working directory (your worktree) or
  temp directories (`/tmp/opencode`). Never touch user files or configs
  elsewhere (e.g. `~/.config`, `~/.cache`, other projects).
- Read-only access by nix tooling itself (`/nix/store`, nix/npm caches) is
  unavoidable and allowed; prefer flags that keep tool artifacts in the
  workspace or temp dirs where practical.
- If a task genuinely requires access outside these paths, explain to the
  operator why **before** doing it.
