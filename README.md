# STPyV8

Prebuilt STPyV8 package and build scripts for **Linux ARM64 and Python 3.13**, prepared for the Pebble SDK's PebbleKit JS emulator runtime.

STPyV8 provides Python bindings for Google's V8 JavaScript engine. The included wheel was built on Ubuntu 26.04 ARM64 and passed all **57 upstream tests**, followed by a JavaScript execution check in the Pebble CLI environment.

## Included Files

| File | Description |
| --- | --- |
| `stpyv8-13.1.201.22-cp313-cp313-manylinux_2_39_aarch64.whl` | Prebuilt STPyV8 13.1.201.22 wheel with bundled runtime libraries. |
| `install-stpyv8.sh` | Installs the bundled wheel into the Pebble CLI environment and verifies JavaScript execution. |
| `build-stpyv8.sh` | Downloads sources, builds V8 and Boost, creates a wheel, runs tests, and installs it into the Pebble CLI environment. |

## Install the Prebuilt Package

Requirements:

- Linux ARM64 (`aarch64`).
- CPython 3.13.
- glibc 2.39 or newer.
- `uv` and an existing Python 3.13-based Pebble CLI installation.

Run from this directory:

```bash
bash ./install-stpyv8.sh
```

The default installation target is:

```text
~/.local/share/uv/tools/pebble-tool/lib/python3.13/site-packages/
```

To install into a different Python 3.13 environment:

```bash
PEBBLE_PYTHON=/path/to/venv/bin/python bash ./install-stpyv8.sh
```

The installer checks Python, architecture, and glibc compatibility before installation, then evaluates `21 * 2` in V8 to verify the installed package.

## Build from Source

The build uses **V8 13.1.201.22**, **Boost 1.87.0**, and **Python 3.13**. Its ARM64 GCC configuration is based on a successful [Linux ARM64 workflow](https://github.com/gbougakov/stpyv8/actions/runs/19518500387).

### Prerequisites

Install the required build tools on Ubuntu:

```bash
sudo apt-get install --no-install-recommends \
  build-essential git curl xz-utils bzip2 pkg-config ninja-build libglib2.0-dev
```

You also need `uv`, Python 3.13 with development headers, and the Pebble CLI environment. The build script defaults to `/opt/python3.13/bin/python3.13` for its build interpreter.

### Run

```bash
bash ./build-stpyv8.sh
```

To specify paths or parallelism:

```bash
PYTHON=/path/to/python3.13 \
PEBBLE_PYTHON=/path/to/pebble/venv/bin/python \
BUILD_ROOT=/path/to/stpyv8-build \
JOBS=1 \
bash ./build-stpyv8.sh
```

Defaults:

| Setting | Default |
| --- | --- |
| `PYTHON` | `/opt/python3.13/bin/python3.13` |
| `PEBBLE_PYTHON` | `$HOME/.local/share/uv/tools/pebble-tool/bin/python` |
| `BUILD_ROOT` | `../stpyv8`, relative to the script directory |
| `JOBS` | `1` |

Run the script as a regular user. A single compilation job is the default for memory-constrained systems. Building V8 can take several hours on a small machine; use the prebuilt wheel when its platform requirements match your environment.

### Build Behavior

- Explicitly configures Python 3.13 header and library paths for Boost.Python.
- Uses GCC on ARM64, disables sysroot use, and sets V8's `symbol_level=0` to reduce disk usage.
- Places temporary files on disk under `.build313/tmp`, rather than a potentially small RAM-backed `/tmp`.
- Checks free disk space before V8 checkout (12 GiB), V8 compilation (6 GiB), and wheel packaging (3 GiB). These thresholds are checks, not guarantees of peak usage; ample additional free space is recommended.
- Records completed stages so subsequent runs skip them. Ninja reuses existing compilation outputs after an interrupted build.
- Repairs the wheel with `auditwheel`, runs upstream tests, installs into the Pebble CLI environment, and verifies JavaScript execution.
- Copies the resulting repaired wheel into this directory. The generated wheel's glibc compatibility tag depends on the build environment.

Logs are saved under:

```text
<BUILD_ROOT>/.build313/logs/build-YYYYMMDD-HHMMSS.log
```

Failures report the stage, line number, exit status, and log path. After fixing a problem, run the same command again to resume.

## Upstream Resources

- [STPyV8 source repository](https://github.com/cloudflare/stpyv8)
- [STPyV8 on PyPI](https://pypi.org/project/stpyv8/)
- [Linux ARM64 wheel request](https://github.com/cloudflare/stpyv8/issues/116)
- [Successful ARM64 build workflow](https://github.com/gbougakov/stpyv8/actions/runs/19518500387)

## License

STPyV8 is distributed under its upstream Apache-2.0 license. V8, Boost, and bundled dependencies retain their respective licenses; consult the upstream projects for license details.
