#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for required_command in curl perl python3 rg sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is missing: $required_command" >&2
    exit 1
  fi
done

font_url="https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
font_sha256="a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"
license_url="https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/OFL.txt"
license_sha256="1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

source_font="$temp_dir/NotoSansSC-wght.ttf"
source_license="$temp_dir/OFL.txt"

if [[ -n "${FOCUS_UI_FONT_SOURCE:-}" ]]; then
  cp "$FOCUS_UI_FONT_SOURCE" "$source_font"
else
  curl --fail --location --retry 3 --silent --show-error \
    "$font_url" --output "$source_font"
fi

if [[ -n "${FOCUS_UI_FONT_LICENSE_SOURCE:-}" ]]; then
  cp "$FOCUS_UI_FONT_LICENSE_SOURCE" "$source_license"
else
  curl --fail --location --retry 3 --silent --show-error \
    "$license_url" --output "$source_license"
fi

printf '%s  %s\n' "$font_sha256" "$source_font" | sha256sum --check --status
printf '%s  %s\n' "$license_sha256" "$source_license" | sha256sum --check --status

python3 -m venv "$temp_dir/venv"
venv_python="$temp_dir/venv/bin/python"
if [[ ! -f "$venv_python" ]]; then
  venv_python="$temp_dir/venv/Scripts/python.exe"
fi
"$venv_python" -m pip install --quiet --disable-pip-version-check \
  'fonttools==4.60.2'

character_file="$temp_dir/ui-characters.txt"
rg --no-heading --no-filename --text \
  -g '*.dart' -g '*.ts' '[^[:ascii:]]' lib server/src \
  | perl -CSD -ne '
      while (/(.)/sg) {
        $characters{$1} = 1 if ord($1) > 127;
      }
      END { print sort keys %characters; }
    ' > "$character_file"

output_font="$temp_dir/FocusNotoSansSC-UI.ttf"
"$venv_python" -m fontTools.subset "$source_font" \
  --output-file="$output_font" \
  --text-file="$character_file" \
  --unicodes='U+0000-00FF,U+2000-206F,U+3000-303F' \
  --layout-features='*' \
  --glyph-names \
  --symbol-cmap \
  --legacy-cmap \
  --notdef-glyph \
  --notdef-outline \
  --recommended-glyphs \
  --name-IDs='*' \
  --name-legacy \
  --name-languages='*' \
  --no-hinting

mkdir -p assets/fonts
cp -f "$output_font" assets/fonts/FocusNotoSansSC-UI.ttf
cp -f "$source_license" assets/fonts/OFL-1.1.txt

echo "Generated assets/fonts/FocusNotoSansSC-UI.ttf"
