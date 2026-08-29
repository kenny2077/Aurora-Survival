#!/usr/bin/env bash
set -euo pipefail

runtime_commit="aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3"
runtime_release="b9637"
repo_url="https://github.com/ggml-org/llama.cpp.git"
script_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${script_root}/Runtime/AuroraLlamaRuntime/Artifacts"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/aurora-mtmd.XXXXXX")"
trap 'rm -rf "${work_root}"' EXIT
minimum_free_kib=$((30 * 1024 * 1024))

available_kib="$(df -Pk "${script_root}" | awk 'NR == 2 { print $4 }')"
if [[ ! "${available_kib}" =~ ^[0-9]+$ ]] || (( available_kib < minimum_free_kib )); then
    echo "At least 30 GiB of free disk space is required for the pinned iOS XCFramework build." >&2
    exit 1
fi

for command_name in git cmake xcrun python3 nm; do
    command -v "${command_name}" >/dev/null || {
        echo "Missing required command: ${command_name}" >&2
        exit 1
    }
done

mkdir -p "${work_root}/llama.cpp"
git -C "${work_root}/llama.cpp" init
git -C "${work_root}/llama.cpp" remote add origin "${repo_url}"
fetch_complete=false
for attempt in 1 2 3; do
    if git -c http.version=HTTP/1.1 -C "${work_root}/llama.cpp" fetch \
        --depth=1 origin "${runtime_commit}"; then
        fetch_complete=true
        break
    fi
    echo "Pinned runtime fetch attempt ${attempt} failed; retrying." >&2
    sleep 5
done
if [[ "${fetch_complete}" != true ]]; then
    echo "Could not fetch pinned llama.cpp commit after three attempts." >&2
    exit 1
fi
git -C "${work_root}/llama.cpp" checkout --detach FETCH_HEAD
resolved_commit="$(git -C "${work_root}/llama.cpp" rev-parse HEAD)"
test "${resolved_commit}" = "${runtime_commit}"

python3 - "${work_root}/llama.cpp/build-xcframework.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "LLAMA_BUILD_COMMON=OFF": "LLAMA_BUILD_COMMON=ON",
    "LLAMA_BUILD_TOOLS=OFF": "LLAMA_BUILD_TOOLS=ON",
    "    -DGGML_OPENMP=${GGML_OPENMP}\n": (
        "    -DGGML_OPENMP=${GGML_OPENMP}\n"
        "    -DMTMD_VIDEO=OFF\n"
    ),
    "        \"${base_dir}/${build_dir}/src/${release_dir}/libllama.a\"\n": (
        "        \"${base_dir}/${build_dir}/src/${release_dir}/libllama.a\"\n"
        "        \"${base_dir}/${build_dir}/tools/mtmd/${release_dir}/libmtmd.a\"\n"
    ),
    "    cp include/llama.h             ${header_path}\n": (
        "    cp include/llama.h             ${header_path}\n"
        "    cp tools/mtmd/mtmd.h            ${header_path}\n"
        "    cp tools/mtmd/mtmd-helper.h     ${header_path}\n"
    ),
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"Pinned build script contract changed: {old!r}")
    text = text.replace(old, new, 1)

# Aurora ships only on iPhone and iPad. Retain the upstream iOS device and
# simulator builds, then replace the unused macOS, visionOS, and tvOS tail with
# an iOS-only XCFramework assembly.
marker = 'echo "Building for macOS..."\n'
if marker not in text:
    raise SystemExit("Pinned build script iOS tail contract changed")
text = text.split(marker, 1)[0] + r'''echo "Setting up iOS framework structures..."
setup_framework_structure "build-ios-sim" ${IOS_MIN_OS_VERSION} "ios"
setup_framework_structure "build-ios-device" ${IOS_MIN_OS_VERSION} "ios"

echo "Creating iOS dynamic libraries..."
combine_static_libraries "build-ios-sim" "Release-iphonesimulator" "ios" "true"
combine_static_libraries "build-ios-device" "Release-iphoneos" "ios" "false"

echo "Creating iOS XCFramework..."
xcrun xcodebuild -create-xcframework \
    -framework $(pwd)/build-ios-sim/framework/llama.framework \
    -debug-symbols $(pwd)/build-ios-sim/dSYMs/llama.dSYM \
    -framework $(pwd)/build-ios-device/framework/llama.framework \
    -debug-symbols $(pwd)/build-ios-device/dSYMs/llama.dSYM \
    -output $(pwd)/build-apple/llama.xcframework
'''
path.write_text(text)
PY

(
    cd "${work_root}/llama.cpp"
    bash ./build-xcframework.sh
)

xcframework="${work_root}/llama.cpp/build-apple/llama.xcframework"
test -n "${xcframework}"
test -d "${xcframework}"
binaries=(
    "${xcframework}/ios-arm64/llama.framework/llama"
    "${xcframework}/ios-arm64_x86_64-simulator/llama.framework/llama"
)
for binary in "${binaries[@]}"; do
    test -f "${binary}"
    exported_symbols="$(nm -gU "${binary}")"
    grep -q ' _mtmd_init_from_file$' <<<"${exported_symbols}"
    grep -q ' _mtmd_helper_eval_chunks$' <<<"${exported_symbols}"
    grep -q ' _ggml_backend_metal_init$' <<<"${exported_symbols}"
    framework_dir="$(dirname "${binary}")"
    test -f "${framework_dir}/Headers/mtmd.h"
    test -f "${framework_dir}/Headers/mtmd-helper.h"
done

python3 - "${xcframework}/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    libraries = plistlib.load(stream).get("AvailableLibraries", [])
identifiers = {item.get("LibraryIdentifier") for item in libraries}
expected = {"ios-arm64", "ios-arm64_x86_64-simulator"}
if identifiers != expected:
    raise SystemExit(f"Unexpected XCFramework slices: {sorted(identifiers)}")
PY

mkdir -p "${output_root}"
rm -rf "${output_root}/llama.xcframework"
cp -R "${xcframework}" "${output_root}/llama.xcframework"
(
    cd "${output_root}"
    find llama.xcframework -type f -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 shasum -a 256 \
        > llama.xcframework.sha256
)

echo "Built mtmd-capable llama.cpp ${runtime_release} (${runtime_commit})."
echo "Artifact: ${output_root}/llama.xcframework"
