#!/bin/sh
set -eu

mode="${1:---check}"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
design_root="$repository_root/design/brand"
assets_root="$repository_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets"
design_parent="$repository_root/design"
assets_parent="$repository_root/apps/ios/BodyFlow/BodyFlow/Resources"
scripts_package="$repository_root/scripts/package.json"
workspace_lock="$repository_root/pnpm-lock.yaml"

case "$mode" in
  --check | --write) ;;
  *)
    printf 'Usage: %s [--check|--write]\n' "$0" >&2
    exit 64
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required for the canonical BodyFlow brand renderer.\n' >&2
  exit 69
fi
if ! command -v node >/dev/null 2>&1; then
  printf 'Node.js is required for transactional brand promotion.\n' >&2
  exit 69
fi
if ! command -v ps >/dev/null 2>&1; then
  printf 'The host ps utility is required for renderer lock identity.\n' >&2
  exit 69
fi

repository_key=$(printf '%s' "$repository_root" | cksum | awk '{ print $1 }')
lock_directory="/tmp/bodyflow-brand-renderer.${repository_key}.lock"

temporary_directory=""
design_transaction=""
assets_transaction=""
design_quarantine=""
assets_quarantine=""
design_captured=0
assets_captured=0
design_installed=0
assets_installed=0
promotion_committed=0
lock_acquired=0
owner_start=""

rename_path() {
  node -e '
    const { renameSync } = require("node:fs");
    renameSync(process.argv[1], process.argv[2]);
  ' "$1" "$2"
}

process_start_time() {
  LC_ALL=C TZ=UTC ps -p "$1" -o lstart= 2>/dev/null \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

assert_no_recovery_transactions() {
  recovery_found=0
  for recovery_path in \
    "$design_parent"/.bodyflow-brand-transaction.* \
    "$assets_parent"/.bodyflow-assets-transaction.*; do
    if [ -e "$recovery_path" ]; then
      printf 'Preserved brand recovery transaction requires inspection: %s\n' \
        "$recovery_path" >&2
      recovery_found=1
    fi
  done
  if [ "$recovery_found" -ne 0 ]; then
    exit 74
  fi
}

assert_no_uninspected_quarantines() {
  quarantine_found=0
  for quarantine_path in \
    "$design_parent"/.bodyflow-brand-recovery.* \
    "$assets_parent"/.bodyflow-assets-recovery.*; do
    if [ -e "$quarantine_path" ]; then
      printf 'Uninspected BodyFlow brand quarantine requires inspection: %s\n' \
        "$quarantine_path" >&2
      quarantine_found=1
    fi
  done
  if [ "$quarantine_found" -ne 0 ]; then
    exit 74
  fi
}

snapshot_tooling_matches_live() {
  diff -qr "$baseline_root/scripts/brand" "$repository_root/scripts/brand" \
    >/dev/null && \
    cmp -s "$baseline_root/scripts/package.json" "$scripts_package" && \
    cmp -s "$baseline_root/pnpm-lock.yaml" "$workspace_lock"
}

snapshot_inputs_match_live() {
  diff -qr "$baseline_root/design/brand" "$design_root" >/dev/null && \
    diff -qr \
      "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
      "$assets_root" >/dev/null && \
    snapshot_tooling_matches_live
}

acquire_renderer_lock() {
  if mkdir "$lock_directory" 2>/dev/null; then
    lock_acquired=1
    return
  fi

  existing_pid=""
  existing_start=""
  if [ -f "$lock_directory/pid" ]; then
    existing_pid=$(cat "$lock_directory/pid")
  fi
  if [ -f "$lock_directory/start" ]; then
    existing_start=$(cat "$lock_directory/start")
  fi
  case "$existing_pid" in
    "" | *[!0-9]*)
      printf 'Renderer lock has invalid ownership metadata: %s\n' \
        "$lock_directory" >&2
      exit 73
      ;;
  esac
  if kill -0 "$existing_pid" 2>/dev/null; then
    current_start=$(process_start_time "$existing_pid")
    if [ -z "$existing_start" ] || [ -z "$current_start" ] || \
      [ "$existing_start" = "$current_start" ]; then
      printf 'Another canonical BodyFlow brand render (pid %s) holds %s\n' \
        "$existing_pid" "$lock_directory" >&2
      exit 73
    fi
  fi
  assert_no_recovery_transactions
  assert_no_uninspected_quarantines
  lock_entries=$(ls -A "$lock_directory")
  expected_entries=$(printf 'pid\nstart')
  if [ "$lock_entries" != "pid" ] && [ "$lock_entries" != "$expected_entries" ]; then
    printf 'Dead renderer lock contains unexpected recovery data: %s\n' \
      "$lock_directory" >&2
    exit 73
  fi

  stale_lock="${lock_directory}.stale.$$"
  if ! rename_path "$lock_directory" "$stale_lock"; then
    printf 'Renderer lock changed during stale-lock recovery: %s\n' \
      "$lock_directory" >&2
    exit 73
  fi
  if ! mkdir "$lock_directory" 2>/dev/null; then
    rm -f "$stale_lock/pid"
    rm -f "$stale_lock/start"
    rmdir "$stale_lock"
    printf 'Another renderer won stale-lock recovery for %s\n' \
      "$lock_directory" >&2
    exit 73
  fi
  lock_acquired=1
  rm -f "$stale_lock/pid"
  rm -f "$stale_lock/start"
  if ! rmdir "$stale_lock"; then
    printf 'Recovered lock quarantine could not be removed: %s\n' \
      "$stale_lock" >&2
    exit 74
  fi
  printf 'Recovered stale BodyFlow renderer lock owned by dead pid %s.\n' \
    "$existing_pid" >&2
}

cleanup() {
  exit_status=$?
  set +e
  trap - EXIT
  trap '' HUP INT TERM
  rollback_failed=0
  cleanup_failed=0
  preserve_recovery=0

  if [ "$promotion_committed" -ne 1 ]; then
    if [ "$assets_installed" -eq 1 ]; then
      if [ -e "$assets_root" ] && [ ! -e "$assets_transaction/new" ] && \
        rename_path "$assets_root" "$assets_transaction/failed-new"; then
        if ! diff -qr \
          "$temporary_directory/probe/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
          "$assets_transaction/failed-new" >/dev/null; then
          preserve_recovery=1
        fi
        assets_installed=0
      elif [ ! -e "$assets_root" ] && [ -e "$assets_transaction/new" ]; then
        assets_installed=0
      else
        rollback_failed=1
      fi
    fi
    if [ "$design_installed" -eq 1 ]; then
      if [ -e "$design_root" ] && [ ! -e "$design_transaction/new" ] && \
        rename_path "$design_root" "$design_transaction/failed-new"; then
        if ! diff -qr \
          "$temporary_directory/probe/design/brand" \
          "$design_transaction/failed-new" >/dev/null; then
          preserve_recovery=1
        fi
        design_installed=0
      elif [ ! -e "$design_root" ] && [ -e "$design_transaction/new" ]; then
        design_installed=0
      else
        rollback_failed=1
      fi
    fi
    if [ "$assets_captured" -eq 1 ]; then
      if [ -e "$assets_transaction/old" ] && [ ! -e "$assets_root" ] && \
        rename_path "$assets_transaction/old" "$assets_root"; then
        assets_captured=0
      elif [ ! -e "$assets_transaction/old" ] && [ -e "$assets_root" ]; then
        assets_captured=0
      else
        rollback_failed=1
      fi
    fi
    if [ "$design_captured" -eq 1 ]; then
      if [ -e "$design_transaction/old" ] && [ ! -e "$design_root" ] && \
        rename_path "$design_transaction/old" "$design_root"; then
        design_captured=0
      elif [ ! -e "$design_transaction/old" ] && [ -e "$design_root" ]; then
        design_captured=0
      else
        rollback_failed=1
      fi
    fi
  fi

  if [ "$rollback_failed" -eq 0 ] && [ "$preserve_recovery" -eq 0 ]; then
    if [ -n "$design_transaction" ] && ! rm -rf "$design_transaction"; then
      cleanup_failed=1
    fi
    if [ "$cleanup_failed" -eq 0 ] && [ -n "$assets_transaction" ] && \
      ! rm -rf "$assets_transaction"; then
      cleanup_failed=1
    fi
    if [ "$cleanup_failed" -eq 0 ] && [ -n "$temporary_directory" ] && \
      ! rm -rf "$temporary_directory"; then
      cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
      printf 'Brand cleanup failed; recovery paths were preserved.\n' >&2
      if [ -n "$design_transaction" ]; then
        printf 'Design transaction: %s\n' "$design_transaction" >&2
      fi
      if [ -n "$assets_transaction" ]; then
        printf 'Asset transaction: %s\n' "$assets_transaction" >&2
      fi
      if [ -n "$temporary_directory" ]; then
        printf 'Render snapshot: %s\n' "$temporary_directory" >&2
      fi
    fi
  else
    printf 'Brand promotion recovery data was preserved.\n' >&2
    if [ -n "$design_transaction" ]; then
      printf 'Design transaction: %s\n' "$design_transaction" >&2
    fi
    if [ -n "$assets_transaction" ]; then
      printf 'Asset transaction: %s\n' "$assets_transaction" >&2
    fi
    if [ -n "$temporary_directory" ]; then
      printf 'Render snapshot: %s\n' "$temporary_directory" >&2
    fi
  fi

  if [ "$rollback_failed" -eq 0 ] && [ "$cleanup_failed" -eq 0 ] && \
    [ "$lock_acquired" -eq 1 ]; then
    lock_owner=""
    lock_start=""
    if [ -f "$lock_directory/pid" ]; then
      lock_owner=$(cat "$lock_directory/pid")
    fi
    if [ -f "$lock_directory/start" ]; then
      lock_start=$(cat "$lock_directory/start")
    fi
    if { [ -n "$lock_owner" ] && [ "$lock_owner" != "$$" ]; } || \
      { [ -n "$lock_start" ] && [ "$lock_start" != "$owner_start" ]; }; then
      printf 'Renderer lock ownership changed; lock preserved at %s\n' \
        "$lock_directory" >&2
      exit 74
    fi
    rm -f "$lock_directory/pid"
    rm -f "$lock_directory/start"
    if ! rmdir "$lock_directory"; then
      printf 'Renderer lock could not be released at %s\n' "$lock_directory" >&2
      exit 74
    fi
  elif [ "$rollback_failed" -ne 0 ]; then
    printf 'Rollback was incomplete; lock preserved at %s\n' "$lock_directory" >&2
    exit 74
  elif [ "$cleanup_failed" -ne 0 ]; then
    printf 'Cleanup was incomplete; lock preserved at %s\n' "$lock_directory" >&2
    if [ "$exit_status" -eq 0 ]; then exit 74; fi
  fi
  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_renderer_lock
assert_no_recovery_transactions
if [ "$mode" = "--write" ]; then
  assert_no_uninspected_quarantines
fi
owner_start=$(process_start_time "$$")
if [ -z "$owner_start" ]; then
  printf 'Unable to record renderer lock process identity.\n' >&2
  exit 74
fi
printf '%s\n' "$owner_start" > "$lock_directory/start"
printf '%s\n' "$$" > "$lock_directory/pid"

temporary_directory=$(mktemp -d "/tmp/bodyflow-brand-render.XXXXXX")
image_id_file="$temporary_directory/image-id"
baseline_root="$temporary_directory/baseline"
probe_root="$temporary_directory/probe"

mkdir -p \
  "$baseline_root/design" \
  "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources" \
  "$baseline_root/scripts" \
  "$probe_root/design" \
  "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources" \
  "$probe_root/scripts"
cp -R "$design_root" "$baseline_root/design/brand"
cp -R "$assets_root" \
  "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets"
cp -R "$repository_root/scripts/brand" "$baseline_root/scripts/brand"
cp "$scripts_package" "$baseline_root/scripts/package.json"
cp "$workspace_lock" "$baseline_root/pnpm-lock.yaml"

if ! snapshot_inputs_match_live; then
  printf 'Renderer inputs changed while the immutable snapshot was created.\n' >&2
  exit 73
fi

container_context="$baseline_root/scripts/brand/canonical-renderer"
docker build \
  --platform linux/amd64 \
  --file "$container_context/Dockerfile" \
  --iidfile "$image_id_file" \
  "$container_context" >/dev/null

image_id=$(tr -d "\r\n" < "$image_id_file")
case "$image_id" in
  sha256:*) ;;
  *)
    printf 'Docker returned an invalid canonical renderer image ID: %s\n' "$image_id" >&2
    exit 70
    ;;
esac

cp -R "$baseline_root/design/brand" "$probe_root/design/brand"
cp -R \
  "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
  "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets"
cp -R "$baseline_root/scripts/brand" "$probe_root/scripts/brand"
cp "$baseline_root/scripts/package.json" "$probe_root/scripts/package.json"
cp "$baseline_root/pnpm-lock.yaml" "$probe_root/pnpm-lock.yaml"

mkdir -p "$probe_root/scripts/node_modules"
docker run --rm \
  --network none \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$probe_root,dst=/workspace" \
  --tmpfs /workspace/scripts/node_modules:rw,mode=1777 \
  --workdir /workspace \
  "$image_id" \
  sh -eu -c '
    ln -s /opt/bodyflow-brand-renderer/node_modules/sharp /workspace/scripts/node_modules/sharp
    node scripts/brand/render-bodyflow-brand-assets.mjs
    node scripts/brand/render-bodyflow-brand-review.mjs
    node scripts/brand/bodyflow-brand-contract.mjs --check
  '

if ! snapshot_inputs_match_live; then
  printf 'Renderer inputs changed after the immutable snapshot; result refused.\n' >&2
  exit 73
fi

if [ "$mode" = "--check" ]; then
  if ! diff -qr "$design_root" "$probe_root/design/brand"; then
    printf 'Canonical render differs from the approved design/brand tree.\n' >&2
    exit 1
  fi
  if ! diff -qr \
    "$assets_root" \
    "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets"; then
    printf 'Canonical render differs from the approved asset catalog.\n' >&2
    exit 1
  fi
  printf 'Canonical BodyFlow brand render is byte-identical.\n'
  exit 0
fi

design_transaction=$(mktemp -d "$design_parent/.bodyflow-brand-transaction.XXXXXX")
assets_transaction=$(mktemp -d "$assets_parent/.bodyflow-assets-transaction.XXXXXX")
mkdir "$design_transaction/new" "$assets_transaction/new"
cp -R "$probe_root/design/brand/." "$design_transaction/new/"
cp -R \
  "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/." \
  "$assets_transaction/new/"

if ! diff -qr "$probe_root/design/brand" "$design_transaction/new" >/dev/null || \
  ! diff -qr \
    "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
    "$assets_transaction/new" >/dev/null; then
  printf 'Prepared brand promotion candidates are incomplete.\n' >&2
  exit 74
fi

if ! snapshot_inputs_match_live; then
  printf 'Renderer inputs changed after the render snapshot; promotion refused.\n' >&2
  exit 73
fi

design_captured=1
if ! rename_path "$design_root" "$design_transaction/old"; then
  printf 'Unable to capture the current design tree for promotion.\n' >&2
  exit 74
fi
if ! diff -qr "$baseline_root/design/brand" "$design_transaction/old" >/dev/null; then
  printf 'Concurrent design edit captured during promotion; rolling back.\n' >&2
  exit 73
fi

assets_captured=1
if ! rename_path "$assets_root" "$assets_transaction/old"; then
  printf 'Unable to capture the current asset catalog for promotion.\n' >&2
  exit 74
fi
if ! diff -qr \
  "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
  "$assets_transaction/old" >/dev/null || \
  ! diff -qr "$baseline_root/design/brand" "$design_transaction/old" >/dev/null; then
  printf 'Concurrent asset edit captured during promotion; rolling back.\n' >&2
  exit 73
fi

design_installed=1
if ! rename_path "$design_transaction/new" "$design_root"; then
  printf 'Unable to install the rendered design tree.\n' >&2
  exit 74
fi
assets_installed=1
if ! rename_path "$assets_transaction/new" "$assets_root"; then
  printf 'Unable to install the rendered asset catalog.\n' >&2
  exit 74
fi

if ! diff -qr "$probe_root/design/brand" "$design_root" >/dev/null || \
  ! diff -qr \
    "$probe_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
    "$assets_root" >/dev/null; then
  printf 'Installed brand outputs failed post-promotion verification.\n' >&2
  exit 74
fi

if ! diff -qr "$baseline_root/design/brand" "$design_transaction/old" >/dev/null || \
  ! diff -qr \
    "$baseline_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets" \
    "$assets_transaction/old" >/dev/null || \
  ! snapshot_tooling_matches_live; then
  printf 'Captured brand inputs changed during promotion; rolling back.\n' >&2
  exit 73
fi

quarantine_token=${temporary_directory##*.}
design_recovery="$design_parent/.bodyflow-brand-recovery.${quarantine_token}.$$"
assets_recovery="$assets_parent/.bodyflow-assets-recovery.${quarantine_token}.$$"
if [ -e "$design_recovery" ] || [ -e "$assets_recovery" ]; then
  printf 'Unable to reserve unique BodyFlow recovery quarantine paths.\n' >&2
  exit 74
fi
printf '%s\n' \
  'BodyFlow original design tree retained after a successful promotion.' \
  'Inspect before removal for writes made through descriptors opened before promotion.' \
  "Promoted path: $design_root" \
  "Paired asset quarantine: $assets_recovery" \
  > "$design_transaction/RECOVERY.txt"
printf '%s\n' \
  'BodyFlow original asset tree retained after a successful promotion.' \
  'Inspect before removal for writes made through descriptors opened before promotion.' \
  "Promoted path: $assets_root" \
  "Paired design quarantine: $design_recovery" \
  > "$assets_transaction/RECOVERY.txt"

trap '' HUP INT TERM
if ! rename_path "$design_transaction" "$design_recovery"; then
  printf 'Unable to quarantine the original design tree; rolling back.\n' >&2
  exit 74
fi
design_transaction="$design_recovery"
if ! rename_path "$assets_transaction" "$assets_recovery"; then
  printf 'Unable to quarantine the original asset tree; rolling back.\n' >&2
  exit 74
fi
assets_transaction="$assets_recovery"
printf 'promotion committed; manual inspection required before removal\n' \
  > "$design_transaction/PROMOTION-COMMITTED"
printf 'promotion committed; manual inspection required before removal\n' \
  > "$assets_transaction/PROMOTION-COMMITTED"
design_quarantine="$design_transaction"
assets_quarantine="$assets_transaction"
design_transaction=""
assets_transaction=""
promotion_committed=1
printf 'Canonical BodyFlow brand render promoted after staged validation.\n'
printf 'Original design quarantine (inspect before removal): %s\n' \
  "$design_quarantine"
printf 'Original asset quarantine (inspect before removal): %s\n' \
  "$assets_quarantine"
