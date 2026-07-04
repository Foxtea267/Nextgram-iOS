#!/usr/bin/env bash
set -euo pipefail

if [ -f "$1/Payload/Telegram.app/Info.plist" ]; then
	INFO_PLIST="$1/Payload/Telegram.app/Info.plist"
else
	INFO_PLIST="$1/Telegram.app/Info.plist"
fi

ensure_dict() {
	local path="$1"
	/usr/libexec/PlistBuddy -c "Print ${path}" "${INFO_PLIST}" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add ${path} dict" "${INFO_PLIST}"
}

set_icon_name() {
	local root="$1"
	local icon="$2"
	ensure_dict "${root}:CFBundleAlternateIcons"
	ensure_dict "${root}:CFBundleAlternateIcons:${icon}"
	/usr/libexec/PlistBuddy -c "Set ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconName ${icon}" "${INFO_PLIST}" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconName string ${icon}" "${INFO_PLIST}"
}

for icon in NagramBlock NagramColorful; do
	set_icon_name ":CFBundleIcons" "${icon}"
	set_icon_name ":CFBundleIcons~ipad" "${icon}"
done
