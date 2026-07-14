#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/router1_app_mvp}"
WEB_DIR="${WEB_DIR:-/var/www/html/app}"
APK_SOURCE="${APK_SOURCE:-$PROJECT_DIR/build-output/router1_app_mvp.apk}"
NOTES="${1:-Обновление приложения Router1.}"

if [[ ! -s "$APK_SOURCE" ]]; then
  echo "APK не найден или пуст: $APK_SOURCE" >&2
  exit 1
fi

version_line="$(awk '/^version:/ {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
if [[ ! "$version_line" =~ ^([^+]+)\+([0-9]+)$ ]]; then
  echo "Некорректная версия в pubspec.yaml: $version_line" >&2
  exit 1
fi

version="${BASH_REMATCH[1]}"
build="${BASH_REMATCH[2]}"
sha256="$(sha256sum "$APK_SOURCE" | awk '{print $1}')"
size="$(stat -c '%s' "$APK_SOURCE")"
timestamp="$(date -u +%Y%m%d_%H%M%S)"

install -d -m 0755 "$WEB_DIR/backups"
if [[ -s "$WEB_DIR/router1.apk" ]]; then
  backup_dir="$WEB_DIR/backups/before_${version}+${build}_${timestamp}"
  install -d -m 0755 "$backup_dir"
  cp -a "$WEB_DIR/router1.apk" "$backup_dir/router1.apk"
  [[ -f "$WEB_DIR/version.json" ]] && cp -a "$WEB_DIR/version.json" "$backup_dir/version.json"
fi

apk_tmp="$(mktemp "$WEB_DIR/.router1.apk.XXXXXX")"
json_tmp="$(mktemp "$WEB_DIR/.version.json.XXXXXX")"
trap 'rm -f "$apk_tmp" "$json_tmp"' EXIT

install -m 0644 "$APK_SOURCE" "$apk_tmp"
cat >"$json_tmp" <<JSON
{
  "version": "$version",
  "build": $build,
  "url": "https://router1.tech/app/router1.apk",
  "sha256": "$sha256",
  "size": $size,
  "notes": "${NOTES//\"/\\\"}"
}
JSON
chmod 0644 "$json_tmp"
mv -f "$apk_tmp" "$WEB_DIR/router1.apk"
mv -f "$json_tmp" "$WEB_DIR/version.json"
trap - EXIT

echo "Опубликован Router1 $version+$build ($size bytes, $sha256)"
