# Embedded Python runtimes

Macro Wheel ships **two isolated Python environments** (spec section 13.2,
rules 25–31). They are populated out-of-band; the runtime trees themselves are
not committed to the repository because they are large binaries.

```
resources/python/
├── command_runtime/     locked, application-owned
└── script_runtime/      user-facing, configurable
```

## Command Runtime

Used only by Macro Wheel-owned built-in commands that genuinely need the
DaVinci Resolve scripting API.

- Managed and locked by Macro Wheel.
- Not user-selectable, not user-configurable.
- No `pip`, no `setuptools`, no writable package location.
- Isolated from the Script Runtime.

The Menu never points the Command Runtime at a user-supplied interpreter.

## Script Runtime

Runs user-authored `.py` files from the fixed Scripts folder.

- Contains Python 3 plus the DaVinci Resolve external scripting components.
- Ships a bundled package set under `site-packages/bundled`.
- User-installed packages go to `site-packages/user`, kept separate from the
  bundled set so a user operation can never silently replace or downgrade a
  Macro Wheel-managed dependency (spec 13.2.5, rule 29).
- Resetting the Script Runtime clears `site-packages/user` and restores the
  bundled baseline. It never touches user scripts, Script IDs, wheel
  assignments, or the Command Runtime (spec 13.2.7).

## Populating the runtimes

```powershell
pwsh -File menu/tools/fetch-python-runtimes.ps1
```

This downloads a `python-build-standalone` release, verifies its checksum when
one is published, installs the full tree as the Script Runtime, and installs a
stripped copy as the Command Runtime. Use `-Force` to re-fetch.

Optional parameters:

| Parameter | Default | Meaning |
|---|---|---|
| `-PythonVersion` | `3.12` | Python series to fetch |
| `-BuildTag` | newest matching release | Pin a specific `python-build-standalone` tag |
| `-Force` | off | Re-download and re-extract |

Until the runtimes are present, the Menu still builds and runs. Commands that
rely on the Resolve scripting API report that the runtime is unavailable, and
user scripts cannot be launched; keystroke-based built-in commands and Add
Effects continue to work because they are performed natively.

## Why the trees are not committed

A full `python-build-standalone` tree is tens of megabytes per platform. The
fetch script makes the build reproducible from a clean checkout and keeps the
repository small.