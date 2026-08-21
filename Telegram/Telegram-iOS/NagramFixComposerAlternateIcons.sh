#!/usr/bin/env bash
set -euo pipefail

if [ -f "$1/Payload/Telegram.app/Info.plist" ]; then
	APP_DIR="$1/Payload/Telegram.app"
else
	APP_DIR="$1/Telegram.app"
fi

INFO_PLIST="${APP_DIR}/Info.plist"
RUNFILES_ROOT="${NAGRAM_RUNFILES_ROOT:-${0}.runfiles/_main}"
if [ ! -d "${RUNFILES_ROOT}" ]; then
	RUNFILES_ROOT="${0}.runfiles/__main__"
fi

XCODE_VERSION_OUTPUT="$(/usr/bin/xcodebuild -version)"
XCODE_VERSION_LINE="${XCODE_VERSION_OUTPUT%%$'\n'*}"
case "${XCODE_VERSION_LINE}" in
	"Xcode "*)
		XCODE_VERSION="${XCODE_VERSION_LINE#Xcode }"
		;;
	*)
		echo "Unable to determine the active Xcode version: ${XCODE_VERSION_LINE}" >&2
		exit 1
		;;
esac

XCODE_MAJOR="${XCODE_VERSION%%.*}"
if [[ ! "${XCODE_MAJOR}" =~ ^[0-9]+$ ]]; then
	echo "Unable to determine the active Xcode major version from: ${XCODE_VERSION}" >&2
	exit 1
fi

ACTOOL="$(/usr/bin/xcrun --find actool)"
if [ ! -x "${ACTOOL}" ]; then
	echo "Unable to find actool in the active Xcode toolchain: ${ACTOOL}" >&2
	exit 1
fi

if (( XCODE_MAJOR == 26 )); then
	NAGRAM_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/Nagram26.icon"
	NAGRAM_BLOCK_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramBlock26.icon"
	NAGRAM_COLORFUL_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramColorful26.icon"
elif (( XCODE_MAJOR >= 27 )); then
	NAGRAM_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/Nagram.icon"
	NAGRAM_BLOCK_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramBlock.icon"
	NAGRAM_COLORFUL_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramColorful.icon"
else
	echo "Unsupported Xcode version for Nagram Icon Composer assets: ${XCODE_VERSION}" >&2
	exit 1
fi

MISSING_ICON_SOURCE=0
for icon_source in "${NAGRAM_ICON_SOURCE}" "${NAGRAM_BLOCK_ICON_SOURCE}" "${NAGRAM_COLORFUL_ICON_SOURCE}"; do
	if [ ! -f "${icon_source}/icon.json" ]; then
		echo "Missing Nagram Icon Composer source for Xcode ${XCODE_MAJOR}: ${icon_source}" >&2
		MISSING_ICON_SOURCE=1
	fi
done
if (( MISSING_ICON_SOURCE == 1 )); then
	if (( XCODE_MAJOR == 26 )); then
		echo "Add the Xcode 26 exports as Nagram26.icon, NagramBlock26.icon, and NagramColorful26.icon." >&2
	fi
	exit 1
fi

echo "Compiling Nagram icons with Xcode ${XCODE_VERSION}: ${ACTOOL}"

case "${APPLE_SDK_PLATFORM:-iPhoneOS}" in
	*iPhoneSimulator*|*iphonesimulator*)
		ACTOOL_PLATFORM="iphonesimulator"
		;;
	*)
		ACTOOL_PLATFORM="iphoneos"
		;;
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nagram-icons.XXXXXX")"
cleanup() {
	rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

real_dir() {
	local path="$1"
	cd "${path}"
	pwd -P
}

real_file_dir() {
	local path="$1"
	dirname "$(realpath "${path}/icon.json")"
}

ICONS_XCASSETS="$(real_dir "${RUNFILES_ROOT}/Telegram/Telegram-iOS/Icons.xcassets")"
LEGACY_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/LegacyComponents/LegacyImages.xcassets")"
PASSWORD_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/PasswordSetupUI/PasswordSetupUIImages.xcassets")"
TELEGRAM_UI_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/TelegramUI/Images.xcassets")"
CALL_SCREEN_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/TelegramUI/Components/Calls/CallScreen/CallScreenAssets.xcassets")"

# Keep the compiled icon names stable even though their sources vary by Xcode.
NAGRAM_ICON="${WORK_DIR}/Nagram.icon"
NAGRAM_BLOCK_ICON="${WORK_DIR}/NagramBlock.icon"
NAGRAM_COLORFUL_ICON="${WORK_DIR}/NagramColorful.icon"
ditto "$(real_file_dir "${NAGRAM_ICON_SOURCE}")" "${NAGRAM_ICON}"
ditto "$(real_file_dir "${NAGRAM_BLOCK_ICON_SOURCE}")" "${NAGRAM_BLOCK_ICON}"
ditto "$(real_file_dir "${NAGRAM_COLORFUL_ICON_SOURCE}")" "${NAGRAM_COLORFUL_ICON}"

COMPILED_ICONS_DIR="${WORK_DIR}/out"
mkdir -p "${COMPILED_ICONS_DIR}"
"${ACTOOL}" \
	--compile "${COMPILED_ICONS_DIR}" \
	--errors --warnings --notices \
	--output-format human-readable-text \
	--platform "${ACTOOL_PLATFORM}" \
	--minimum-deployment-target 15.0 \
	--compress-pngs \
	--app-icon Nagram \
	--alternate-app-icon NagramBlock \
	--alternate-app-icon NagramColorful \
	--target-device iphone \
	--target-device ipad \
	--output-partial-info-plist "${WORK_DIR}/xcassets-info.plist" \
	"${ICONS_XCASSETS}" \
	"${LEGACY_XCASSETS}" \
	"${PASSWORD_XCASSETS}" \
	"${TELEGRAM_UI_XCASSETS}" \
	"${CALL_SCREEN_XCASSETS}" \
	"${NAGRAM_ICON}" \
	"${NAGRAM_BLOCK_ICON}" \
	"${NAGRAM_COLORFUL_ICON}"

ditto "${COMPILED_ICONS_DIR}" "${APP_DIR}"

ensure_dict() {
	local path="$1"
	/usr/libexec/PlistBuddy -c "Print ${path}" "${INFO_PLIST}" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add ${path} dict" "${INFO_PLIST}"
}

reset_primary_icon() {
	local root="$1"
	shift
	ensure_dict "${root}"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundlePrimaryIcon" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles array" "${INFO_PLIST}"
	local index=0
	local icon_file
	for icon_file in "$@"; do
		/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles:${index} string ${icon_file}" "${INFO_PLIST}"
		index=$((index + 1))
	done
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconName string Nagram" "${INFO_PLIST}"
}

set_icon_name() {
	local root="$1"
	local icon="$2"
	ensure_dict "${root}:CFBundleAlternateIcons"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundleAlternateIcons:${icon}" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon} dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconName string ${icon}" "${INFO_PLIST}"
}

reset_primary_icon ":CFBundleIcons" Nagram60x60
reset_primary_icon ":CFBundleIcons~ipad" Nagram60x60 Nagram76x76

for icon in NagramBlock NagramColorful; do
	set_icon_name ":CFBundleIcons" "${icon}"
	set_icon_name ":CFBundleIcons~ipad" "${icon}"
done
