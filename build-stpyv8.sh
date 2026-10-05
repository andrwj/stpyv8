#!/usr/bin/env bash
# Linux ARM64 / Python 3.13. Based on successful workflow 19518500387.
# Usage: ./build-stpyv8.sh   (without sudo)
# Optional: JOBS=1 PYTHON=/opt/python3.13/bin/python3.13 BUILD_ROOT=/path
set -Eeuo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ROOT="${BUILD_ROOT:-$SCRIPT_DIR/../stpyv8}"
PYTHON="${PYTHON:-/opt/python3.13/bin/python3.13}"
PEBBLE_PYTHON="${PEBBLE_PYTHON:-$HOME/.local/share/uv/tools/pebble-tool/bin/python}"
JOBS="${JOBS:-1}"
STAGE=preflight
for cmd in uv git curl tar make g++ pkg-config ninja flock; do
    command -v "$cmd" >/dev/null || { echo "Missing command: $cmd"; exit 1; }
done
if ! pkg-config --exists glib-2.0 gmodule-2.0 gobject-2.0 gthread-2.0; then
    echo 'Install required development files: sudo apt-get install libglib2.0-dev'
    exit 1
fi
[[ $(uname -m) == aarch64 ]] || { echo 'Linux ARM64 is required.'; exit 1; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer.'; exit 1; }
for py in "$PYTHON" "$PEBBLE_PYTHON"; do
    "$py" -c 'import sys; assert sys.version_info[:2] == (3,13), sys.version'
done
mkdir -p "$ROOT"
cd "$ROOT"
ROOT="$PWD"
WORK="$ROOT/.build313"
BOOST="$WORK/boost"
mkdir -p "$WORK/logs" "$WORK/tmp"
export TMPDIR="$WORK/tmp"
LOG="$WORK/logs/build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'rc=$?; echo "FAILED: stage=$STAGE line=$LINENO exit=$rc"; echo "Log: $LOG"; exit "$rc"' ERR
trap 'echo "Interrupted. Re-run to resume. Log: $LOG"; exit 130' INT TERM
exec 9>"$WORK/build.lock"
flock -n 9 || { echo 'Another build is running.'; exit 1; }
stage() { STAGE="$1"; printf '\n[%s] %s\n' "$(date -Is)" "$STAGE"; }
check_space() {
    local available
    available=$(df -B1 --output=avail "$ROOT" | tail -n1 | tr -d ' ')
    if (( available < $1 * 1024 * 1024 * 1024 )); then
        echo "Need at least $1 GiB free for this stage."
        df -h "$ROOT"
        exit 1
    fi
}
df -h "$ROOT"
free -h
echo "Parallel jobs: $JOBS; log: $LOG"

stage 'Obtain STPyV8 source'
if [[ ! -f setup.py ]]; then
    SOURCE="$WORK/source"
    if [[ ! -d "$SOURCE/.git" ]]; then
        git clone --depth 1 --branch v13.1.201.22 https://github.com/cloudflare/stpyv8.git "$SOURCE"
    fi
    cp -a "$SOURCE/." "$ROOT/"
fi

stage 'Apply final Linux ARM64 build configuration'
"$PYTHON" - <<'PY'
from pathlib import Path
p = Path('settings.py')
s = p.read_text()
marker = '# Local Linux ARM64 build settings (build-stpyv8.sh)'
if marker not in s:
    s = s.replace('source_files = [', marker + '''
if platform.system() == "Linux" and platform.machine() == "aarch64":
    gn_args["is_clang"] = "false"
    gn_args["use_sysroot"] = "false"
    gn_args["use_custom_libcxx"] = "false"
    gn_args["symbol_level"] = "0"

source_files = [''', 1)
    p.write_text(s)
p = Path('setup.py')
s = p.read_text()
s = s.replace('f"-C {os.path.join(\'out.gn\', \'x64.release.sample\')} v8_monolith",',
              'f"-j{os.environ.get(\'STPYV8_BUILD_JOBS\', \'1\')} -C {os.path.join(\'out.gn\', \'x64.release.sample\')} v8_monolith",')
p.write_text(s)
PY

stage 'Prepare Python 3.13 build environment'
if [[ ! -x .venv-build313/bin/python ]]; then
    uv venv --python "$PYTHON" .venv-build313
fi
.venv-build313/bin/python -c 'import sys; assert sys.version_info[:2] == (3,13)'
uv pip install --python .venv-build313/bin/python setuptools wheel pytest pytest-order auditwheel patchelf
export PATH="$ROOT/.venv-build313/bin:$PATH"
export V8_DEPS_LINUX=0 STPYV8_BOOST_PYTHON=boost_python3.13
export STPYV8_BUILD_JOBS="$JOBS"
export CFLAGS="-I$BOOST/include" CXXFLAGS="-I$BOOST/include"
export LDFLAGS="-L$BOOST/lib -Wl,-rpath,$BOOST/lib"
export LD_LIBRARY_PATH="$BOOST/lib:${LD_LIBRARY_PATH:-}"

stage 'Build Boost 1.87.0 for Python 3.13'
if [[ ! -f "$WORK/boost.done" ]]; then
    if [[ ! -f "$WORK/boost.tar.bz2" ]]; then
        curl --fail --location --retry 3 https://archives.boost.io/release/1.87.0/source/boost_1_87_0.tar.bz2 -o "$WORK/boost.tar.bz2.part"
        mv "$WORK/boost.tar.bz2.part" "$WORK/boost.tar.bz2"
    fi
    if [[ ! -f "$WORK/boost-extracted.done" ]]; then
        tar -xjf "$WORK/boost.tar.bz2" -C "$WORK"
        touch "$WORK/boost-extracted.done"
    fi
    pushd "$WORK/boost_1_87_0"
    ./bootstrap.sh --with-python="$ROOT/.venv-build313/bin/python" --prefix="$BOOST"
    PY_INCLUDE=$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')
    PY_LIBDIR=$(python -c 'import sys; print(sys.base_prefix + "/lib")')
    test -f "$PY_INCLUDE/Python.h"
    test -f "$PY_INCLUDE/pyconfig.h"
    printf 'using python : 3.13 : "%s" : "%s" : "%s" ;\n' \
        "$ROOT/.venv-build313/bin/python" "$PY_INCLUDE" "$PY_LIBDIR" > "$WORK/user-config.jam"
    ./b2 --user-config="$WORK/user-config.jam" install python=3.13 -j"$JOBS" --with-system --with-python --with-filesystem --with-iostreams --with-date_time --with-thread
    popd
    test -f "$BOOST/lib/libboost_python313.so"
    touch "$WORK/boost.done"
fi

stage 'Fetch V8 13.1.201.22 and dependencies'
if [[ ! -f "$WORK/v8-checkout.done" ]]; then
    check_space 12
    python setup.py checkout_v8
    touch "$WORK/v8-checkout.done"
fi

stage 'Build V8 with GCC (longest step)'
if [[ ! -f "$WORK/v8.done" ]]; then
    check_space 6
    python - <<'PY'
import os, subprocess, settings
out = 'out.gn/x64.release.sample'
subprocess.run([os.path.join(settings.DEPOT_HOME, 'gn'), 'gen', out,
                '--args=' + settings.GN_ARGS], cwd=settings.V8_HOME, check=True)
subprocess.run(['ninja', '-j' + os.environ['STPYV8_BUILD_JOBS'], '-C', out,
                'v8_monolith'], cwd=settings.V8_HOME, check=True)
PY
    test -f v8/out.gn/x64.release.sample/obj/libv8_monolith.a
    touch "$WORK/v8.done"
fi

stage 'Build and repair wheel'
if [[ ! -f "$WORK/wheel.done" ]]; then
    check_space 3
    python setup.py bdist_wheel --skip-build-v8 -d dist-python313
    auditwheel repair -w dist-python313-repaired dist-python313/*.whl
    touch "$WORK/wheel.done"
fi

stage 'Install in build environment and test'
uv pip install --python .venv-build313/bin/python dist-python313-repaired/*.whl
python -m pytest --import-mode=importlib -v

stage 'Install in Pebble CLI environment'
uv pip install --python "$PEBBLE_PYTHON" dist-python313-repaired/*.whl
pushd "$WORK"
"$PEBBLE_PYTHON" - <<'PY'
import STPyV8
with STPyV8.JSContext() as context:
    assert context.eval('21 * 2') == 42
print('STPyV8 JavaScript execution: OK')
PY
popd
cp -a dist-python313-repaired/*.whl "$SCRIPT_DIR/"
pebble --version
echo 'SUCCESS: STPyV8 installed in Pebble CLI environment.'
echo "Package copy: $SCRIPT_DIR"
echo "Log: $LOG"
