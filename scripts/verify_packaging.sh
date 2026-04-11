#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="${repo_root}/build/DerivedData/packaging"
project_path="${repo_root}/AIIslandApp.xcodeproj"
scheme="AIIslandApp"
configuration="Debug"
app_path="${derived_data_path}/Build/Products/${configuration}/AIIslandApp.app"
framework_path="${app_path}/Contents/Frameworks/AIIslandCore.framework/Versions/A/AIIslandCore"
app_dylib_path="${app_path}/Contents/MacOS/AIIslandApp.debug.dylib"
expected_framework_id="@rpath/AIIslandCore.framework/Versions/A/AIIslandCore"

echo "Building ${scheme} into ${derived_data_path}"
rm -rf "${derived_data_path}"
xcodebuild \
  -project "${project_path}" \
  -scheme "${scheme}" \
  -configuration "${configuration}" \
  -derivedDataPath "${derived_data_path}" \
  build \
  >/tmp/aiisland-packaging-build.log

echo "Build log: /tmp/aiisland-packaging-build.log"

if [[ ! -f "${framework_path}" ]]; then
  echo "error: embedded framework missing at ${framework_path}" >&2
  exit 1
fi

framework_id="$(otool -D "${framework_path}" | tail -n 1)"
if [[ "${framework_id}" != "${expected_framework_id}" ]]; then
  echo "error: unexpected framework install id: ${framework_id}" >&2
  exit 1
fi

if ! otool -L "${app_dylib_path}" | grep -Fq "${expected_framework_id}"; then
  echo "error: app debug dylib does not link ${expected_framework_id}" >&2
  exit 1
fi

echo "Packaging verification passed."
echo "Embedded framework:"
echo "  ${framework_path}"
echo "Framework install id:"
echo "  ${framework_id}"
