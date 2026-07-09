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

find_composer_actool() {
	local candidate

	for candidate in \
		/Applications/Xcode-beta.app/Contents/Developer/usr/bin/actool \
		/Applications/Xcode_27*.app/Contents/Developer/usr/bin/actool
	do
		if [ -x "${candidate}" ]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done
}

ACTOOL=""
if [ -n "${NAGRAM_ACTOOL:-}" ]; then
	if [ -x "${NAGRAM_ACTOOL}" ]; then
		ACTOOL="${NAGRAM_ACTOOL}"
	else
		echo "NAGRAM_ACTOOL is not executable: ${NAGRAM_ACTOOL}; falling back to legacy PNG icons" >&2
	fi
else
	ACTOOL="$(find_composer_actool)"
	if [ -z "${ACTOOL}" ]; then
		echo "Nagram Icon Composer export requires Xcode 27 actool; falling back to legacy PNG icons" >&2
	fi
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

if [ -n "${ACTOOL}" ]; then
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
fi

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

set_icon_files() {
	local root="$1"
	local icon="$2"
	shift 2
	ensure_dict "${root}:CFBundleAlternateIcons"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundleAlternateIcons:${icon}" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon} dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconFiles array" "${INFO_PLIST}"
	local index=0
	local icon_file
	for icon_file in "$@"; do
		/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconFiles:${index} string ${icon_file}" "${INFO_PLIST}"
		index=$((index + 1))
	done
}

require_legacy_icon_pngs() {
	local icon="$1"
	local missing=0
	local file
	for file in "${icon}@2x.png" "${icon}@3x.png" "${icon}Ipad.png" "${icon}Ipad@2x.png" "${icon}LargeIpad@2x.png"; do
		if [ ! -f "${APP_DIR}/${file}" ]; then
			echo "Missing legacy Nagram icon PNG: ${APP_DIR}/${file}" >&2
			missing=1
		fi
	done
	if [ "${missing}" -ne 0 ]; then
		exit 1
	fi
}

if [ -n "${ACTOOL}" ]; then
	reset_primary_icon ":CFBundleIcons" Nagram60x60
	reset_primary_icon ":CFBundleIcons~ipad" Nagram60x60 Nagram76x76

	for icon in NagramBlock NagramColorful; do
		set_icon_name ":CFBundleIcons" "${icon}"
		set_icon_name ":CFBundleIcons~ipad" "${icon}"
	done
else
	for icon in NagramBlock NagramColorful; do
		require_legacy_icon_pngs "${icon}"
	done

	for icon in NagramBlock NagramColorful; do
		set_icon_files ":CFBundleIcons" "${icon}" "${icon}"
		set_icon_files ":CFBundleIcons~ipad" "${icon}" "${icon}" "${icon}Ipad" "${icon}LargeIpad"
	done
fi
