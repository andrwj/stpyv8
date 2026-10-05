#!/usr/bin/env bash
# Install the bundled STPyV8 wheel into Pebble CLI's Python environment.
set -Eeuo pipefail
ROOT="$(dirname "$(readlink -f "$0")")"
WHEEL="$ROOT/stpyv8-13.1.201.22-cp313-cp313-manylinux_2_39_aarch64.whl"
PYTHON="${PEBBLE_PYTHON:-$HOME/.local/share/uv/tools/pebble-tool/bin/python}"
command -v uv >/dev/null || { echo 'uv 명령을 찾을 수 없습니다.' >&2; exit 1; }
[[ -f "$WHEEL" ]] || { echo "패키지를 찾을 수 없습니다: $WHEEL" >&2; exit 1; }
[[ -x "$PYTHON" ]] || { echo "Pebble Python 환경을 찾을 수 없습니다: $PYTHON" >&2; exit 1; }
"$PYTHON" - <<'PY'
import platform, sys
if sys.version_info[:2] != (3, 13):
    sys.exit('Python 3.13 환경이 필요합니다.')
if platform.system() != 'Linux' or platform.machine() != 'aarch64':
    sys.exit('Linux ARM64 환경이 필요합니다.')
libc, version = platform.libc_ver()
if libc != 'glibc' or tuple(map(int, version.split('.')[:2])) < (2, 39):
    sys.exit('glibc 2.39 이상이 필요합니다.')
PY
uv pip install --python "$PYTHON" "$WHEEL"
# Verify the installed module outside the source tree.
cd "$ROOT"
"$PYTHON" - <<'PY'
import importlib.metadata
import STPyV8
with STPyV8.JSContext() as context:
    assert context.eval('21 * 2') == 42
print('설치 및 JavaScript 실행 확인 완료: STPyV8 ' + importlib.metadata.version('stpyv8'))
print('설치 위치: ' + STPyV8.__file__)
PY
