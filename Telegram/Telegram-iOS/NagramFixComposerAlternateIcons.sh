#!/usr/bin/env bash
set -euo pipefail

if [ -f "$1/Payload/Telegram.app/Info.plist" ]; then
	APP_DIR="$1/Payload/Telegram.app"
else
	APP_DIR="$1/Telegram.app"
fi

INFO_PLIST="${APP_DIR}/Info.plist"
RUNFILES_ROOT="${0}.runfiles/_main"
if [ ! -d "${RUNFILES_ROOT}" ]; then
	RUNFILES_ROOT="${0}.runfiles/__main__"
fi

ACTOOL="${NAGRAM_ACTOOL:-/Applications/Xcode-beta.app/Contents/Developer/usr/bin/actool}"
if [ ! -x "${ACTOOL}" ]; then
	echo "Nagram Icon Composer export requires Xcode 27 actool at ${ACTOOL}" >&2
	exit 1
fi

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
NAGRAM_ICON="$(real_file_dir "${RUNFILES_ROOT}/Telegram/Telegram-iOS/Nagram.icon")"
NAGRAM_BLOCK_ICON="$(real_file_dir "${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramBlock.icon")"
NAGRAM_COLORFUL_ICON="$(real_file_dir "${RUNFILES_ROOT}/Telegram/Telegram-iOS/NagramColorful.icon")"

mkdir -p "${WORK_DIR}/out"
"${ACTOOL}" \
	--compile "${WORK_DIR}/out" \
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

ditto "${WORK_DIR}/out" "${APP_DIR}"

ensure_dict() {
	local path="$1"
	/usr/libexec/PlistBuddy -c "Print ${path}" "${INFO_PLIST}" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add ${path} dict" "${INFO_PLIST}"
}

reset_primary_icon() {
	local root="$1"
	local ipad="$2"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundlePrimaryIcon" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles array" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles:0 string Nagram60x60" "${INFO_PLIST}"
	if [ "${ipad}" = "true" ]; then
		/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles:1 string Nagram76x76" "${INFO_PLIST}"
	fi
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

reset_primary_icon ":CFBundleIcons" false
reset_primary_icon ":CFBundleIcons~ipad" true

for icon in NagramBlock NagramColorful; do
	set_icon_name ":CFBundleIcons" "${icon}"
	set_icon_name ":CFBundleIcons~ipad" "${icon}"
done
