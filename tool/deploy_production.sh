#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

production_url="${FOCUS_PRODUCTION_URL:-https://focus.dluserver.cn}"
site_root="${FOCUS_SITE_ROOT:-/www/wwwroot/focus.dluserver.cn}"
server_root="${FOCUS_SERVER_ROOT:-/root/focus-timer-sync}"
flutter_bin="${FLUTTER_BIN:-/opt/flutter/bin/flutter}"
verify_only=false
skip_tests=false

usage() {
  echo "Usage: tool/deploy_production.sh [--verify-only] [--skip-tests]"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --verify-only)
      verify_only=true
      ;;
    --skip-tests)
      skip_tests=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

for command_name in curl flock gh git jq nginx node npm pm2 sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Missing command: $command_name"
done
[[ -x "$flutter_bin" ]] || fail "Flutter executable not found: $flutter_bin"
[[ -d "$site_root/releases" ]] || fail "Site releases directory not found: $site_root/releases"
[[ -d "$server_root" ]] || fail "Server directory not found: $server_root"

lock_file="${FOCUS_DEPLOY_LOCK:-/var/lock/focusmytime-deploy.lock}"
exec 9>"$lock_file"
flock -n 9 || fail "Another FocusMyTime deployment is running"

version_line="$(sed -n 's/^version: *//p' pubspec.yaml)"
app_version="${version_line%%+*}"
build_number="${version_line##*+}"
server_version="$(node -p "require('./server/package.json').version")"
installer_version="$(sed -n 's/^AppVersion=//p' windows/packaging/inno_setup.iss)"
readme_version="$(sed -n 's/^当前版本：v\([^ ]*\).*/\1/p' README.md)"
release_tag="v$app_version"

[[ -n "$app_version" && "$build_number" != "$version_line" ]] || fail "Invalid pubspec version: $version_line"
[[ "$server_version" == "$app_version" ]] || fail "Server version $server_version does not match $app_version"
[[ "$installer_version" == "$app_version" ]] || fail "Installer version $installer_version does not match $app_version"
[[ "$readme_version" == "$app_version" ]] || fail "README version $readme_version does not match $app_version"

gh release view "$release_tag" --json tagName --jq '.tagName' 2>/dev/null |
  grep -Fxq "$release_tag" || fail "GitHub Release $release_tag does not exist"
git rev-parse --verify "$release_tag^{}" >/dev/null 2>&1 || fail "Local tag $release_tag does not exist"

runtime_paths=(assets lib pubspec.lock pubspec.yaml server web)
git diff --quiet "$release_tag" -- "${runtime_paths[@]}" ||
  fail "Runtime files differ from $release_tag; create a new release before deploying"

verify_online() {
  local online_version online_build pm2_version pm2_status health_status
  local local_main_hash remote_main_hash wasm_content_type

  online_version="$(curl -fsS --max-time 15 "$production_url/version.json" | jq -r '.version')"
  online_build="$(curl -fsS --max-time 15 "$production_url/version.json" | jq -r '.build_number')"
  [[ "$online_version" == "$app_version" ]] || fail "Online Web version is $online_version, expected $app_version"
  [[ "$online_build" == "$build_number" ]] || fail "Online Web build is $online_build, expected $build_number"

  pm2_version="$(pm2 jlist | jq -r '.[] | select(.name == "focus-timer-sync") | .pm2_env.version')"
  pm2_status="$(pm2 jlist | jq -r '.[] | select(.name == "focus-timer-sync") | .pm2_env.status')"
  [[ "$pm2_version" == "$app_version" ]] || fail "PM2 version is $pm2_version, expected $app_version"
  [[ "$pm2_status" == "online" ]] || fail "PM2 status is $pm2_status"

  health_status="$(curl -fsS --max-time 15 "$production_url/api/health" | jq -r '.status')"
  [[ "$health_status" == "ok" ]] || fail "Production API health check failed"

  [[ -s build/web/main.dart.js ]] || fail "Local Web build is missing"
  local_main_hash="$(sha256sum build/web/main.dart.js | awk '{print $1}')"
  remote_main_hash="$(curl -fsS --max-time 60 "$production_url/main.dart.js" | sha256sum | awk '{print $1}')"
  [[ "$remote_main_hash" == "$local_main_hash" ]] || fail "Online main.dart.js does not match the local build"

  wasm_content_type="$(curl -fsSI --max-time 15 "$production_url/sqlite3.wasm" |
    awk -F ': *' 'tolower($1) == "content-type" {print tolower($2)}' | tr -d '\r')"
  [[ "$wasm_content_type" == application/wasm* ]] || fail "Unexpected Wasm content type: $wasm_content_type"

  echo "Production verified: Web $app_version+$build_number, PM2 $pm2_version, API healthy."
}

if $verify_only; then
  verify_online
  exit 0
fi

[[ -z "$(git status --porcelain)" ]] || fail "Working tree must be clean before deployment"
git fetch origin master --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/master)" ]] ||
  fail "HEAD is not the pushed origin/master commit"

export PATH="$(dirname "$flutter_bin"):$PATH"
flutter pub get
if ! $skip_tests; then
  flutter analyze
  flutter test
  npm --prefix server test
else
  npm --prefix server run build
fi

rm -rf build/web
tool/setup_web_fonts.sh
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define="SYNC_SERVER_URL=$production_url"

for required_file in \
  index.html flutter_bootstrap.js main.dart.js sqlite3.wasm sqflite_sw.js \
  flutter_service_worker.js version.json; do
  [[ -s "build/web/$required_file" ]] || fail "Web build is missing $required_file"
done

[[ "$(jq -r '.version' build/web/version.json)" == "$app_version" ]] || fail "Built Web version is incorrect"
[[ "$(jq -r '.build_number' build/web/version.json)" == "$build_number" ]] || fail "Built Web build number is incorrect"
grep -Fq "$production_url" build/web/main.dart.js || fail "Production sync URL is missing from Web build"
nginx -t

timestamp="$(date +%Y%m%d%H%M%S)"
backup_dir="$server_root/backups/pre-$release_tag-$timestamp"
release_dir="$site_root/releases/$timestamp"
next_link="$site_root/.current-$timestamp"

mkdir -p "$backup_dir"
cp -a \
  "$server_root/package.json" \
  "$server_root/package-lock.json" \
  "$server_root/tsconfig.json" \
  "$server_root/ecosystem.config.js" \
  "$server_root/src" \
  "$server_root/dist" \
  "$backup_dir/"

server_db="$server_root/data/sync-server.db"
if [[ -f "$server_db" ]]; then
  SERVER_ROOT="$server_root" SOURCE_DB="$server_db" BACKUP_DB="$backup_dir/sync-server.db" \
    node <<'NODE'
const path = require('path')
const Database = require(path.join(process.env.SERVER_ROOT, 'node_modules/better-sqlite3'))
const database = new Database(process.env.SOURCE_DB, { readonly: true, fileMustExist: true })

database.backup(process.env.BACKUP_DB)
  .then(() => database.close())
  .catch((error) => {
    database.close()
    console.error(error)
    process.exit(1)
  })
NODE
  [[ -s "$backup_dir/sync-server.db" ]] || fail "SQLite backup was not created"
fi

cp -a server/src/. "$server_root/src/"
install -m 644 server/package.json "$server_root/package.json"
install -m 644 server/package-lock.json "$server_root/package-lock.json"
install -m 644 server/tsconfig.json "$server_root/tsconfig.json"
install -m 644 server/ecosystem.config.js "$server_root/ecosystem.config.js"
npm --prefix "$server_root" run build
pm2 restart "$server_root/ecosystem.config.js" --only focus-timer-sync --update-env
pm2 save

for attempt in 1 2 3 4 5; do
  if curl -fsS --max-time 5 "http://127.0.0.1:6677/api/health" >/dev/null; then
    break
  fi
  ((attempt < 5)) || fail "Local API did not recover; restore $backup_dir"
  sleep 1
done

install -d -o www -g www -m 755 "$release_dir"
cp -a build/web/. "$release_dir/"
chown -R www:www "$release_dir"
cmp -s build/web/index.html "$release_dir/index.html" || fail "Deployed index.html differs from build"
cmp -s build/web/main.dart.js "$release_dir/main.dart.js" || fail "Deployed main.dart.js differs from build"
ln -s "releases/$timestamp" "$next_link"
mv -Tf "$next_link" "$site_root/current"

verify_online
echo "Deployment complete. Web: $release_dir"
echo "Server backup: $backup_dir"
