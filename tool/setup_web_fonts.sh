#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter 未安装或不在 PATH 中" >&2
  exit 1
fi

flutter_bin="$(readlink -f "$(command -v flutter)")"
flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
fallback_data="$flutter_root/bin/cache/flutter_web_sdk/lib/_engine/engine/font_fallback_data.dart"
output_root="web/font-fallback"
base_url="https://fonts.gstatic.com/s"

if [[ ! -f "$fallback_data" ]]; then
  echo "找不到 Flutter Web 字体回退清单: $fallback_data" >&2
  exit 1
fi

mkdir -p "$output_root"
paths_file="$(mktemp)"
trap 'rm -f "$paths_file"' EXIT

perl -0777 -ne '
  while (/NotoFont\(\s*\x27(?:Noto Color Emoji|Noto Sans Symbols 2|Noto Sans SC) \d+\x27,\s*\x27([^\x27]+\.woff2)\x27/g) {
    print "$1\n";
  }
' "$fallback_data" > "$paths_file"
echo "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2" >> "$paths_file"
sort -u -o "$paths_file" "$paths_file"

font_count="$(wc -l < "$paths_file")"
if (( font_count < 100 )); then
  echo "Flutter 字体清单解析异常，仅找到 $font_count 个文件" >&2
  exit 1
fi

while IFS= read -r relative_path; do
  target="$output_root/$relative_path"
  mkdir -p "$(dirname "$target")"
  if [[ ! -s "$target" ]]; then
    echo "下载 $relative_path"
    curl --fail --location --retry 3 --silent --show-error \
      "$base_url/$relative_path" --output "$target"
  fi
done < "$paths_file"

echo "Web 字体资源已准备完成，共 $font_count 个文件。"
