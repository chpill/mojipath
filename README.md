# Mojipath

Abbreviate `/nix/store/…` paths in terminal output: the 32-char hash becomes a
colored symbol derived from the hash, leaving the package name readable.

For example, you want to clarify output of some zig incremental build:

```bash
zig build --color=on --watch -fincremental 2>&1 | mojipath --color=always
```

```console
$ nix build 2>&1 | mojipath --color=always
⬡ ↧-libmnl-1.0.5.drv
```

Colors are 24-bit terminal escapes. `--color=auto` (the default) enables them
only when stdout is a terminal; force them with `--color=always` when piping.

## Shell integration

Wrap individual noisy commands. Stdout is a pipe here, so `always` is needed:

```bash
# bash/zsh
n() { nix "$@" 2>&1 | mojipath --color=always; }
```

```fish
# fish (in ~/.config/fish/functions/n.fish, autoloaded)
function n
    nix $argv 2>&1 | mojipath --color=always
end
```

To keep the wrapped tool's *own* colors even though it is piped, run it under a
pseudo-terminal (`script` also needs `-e` to propagate the exit code; `2>&1` is
implicit there, and `$*` is a naive space-join):

```bash
# bash/zsh
n() { script -qec "nix $*" /dev/null | mojipath --color=always; }
```

Many tools also have explicit switches, which are simpler when available:
`cargo build --color=always`, `ls --color=always`,
`git -c color.ui=always`, or `FORCE_COLOR=1` / `CLICOLOR_FORCE=1` for tools
that honor them.

To filter everything a shell prints:

```bash
exec > >(mojipath --color=always) 2> >(mojipath --color=always)
```

At your own risk: other programs see pipes instead of a terminal, so they may
disable colors, hide progress bars, or misbehave (vim, less), and stdout/stderr
interleaving can shift. Not available in fish, which has no `exec > >(...)`.

## Development

- Build: `zig build`
- Test: `zig build test`
- Palette: `zig run src/emoji_range_viz.zig`
