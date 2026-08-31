#!/bin/zsh -f
set -euo pipefail
umask 077

fail() {
  print -u2 -- "ERROR $1"
  exit 1
}

if [[ "${CI3_CLOSED_ENV_BOOTSTRAP:-0}" != '1' ]]; then
  for INTERNAL_NAME in \
    CI3_GIT_BOUND_REEXEC CI3_GIT_BOUND_REPO_ROOT CI3_GIT_BOUND_AUTHORITY_SHA \
    CI3_GIT_BOUND_LAUNCHER_SHA256; do
    (( ${+parameters[$INTERNAL_NAME]} == 0 )) || fail LAUNCHER_BOOTSTRAP
  done
  typeset -a CLOSED_ENVIRONMENT
  CLOSED_ENVIRONMENT=(
    'HOME=/var/empty'
    'LANG=C'
    'LC_ALL=C'
    'PATH=/usr/bin:/bin'
    'CI3_CLOSED_ENV_BOOTSTRAP=1'
  )
  typeset PRESERVED_NAME
  for PRESERVED_NAME in \
    CI3_SYNTHETIC_E2E_SCENARIO CI3_SYNTHETIC_SCENARIO_SHA256 \
    CI3_SYNTHETIC_E2E_ROOT CI3_SYNTHETIC_WRITER_BINARY CI3_SYNTHETIC_WRITER_SHA256 \
    CI3_SYNTHETIC_WRITER_FIXTURE CI3_SYNTHETIC_WRITER_MATERIALIZER \
    CI3_SYNTHETIC_EXTERNAL_RESTART CI3_SYNTHETIC_FIXED_NODE_PATH \
    CI3_SYNTHETIC_FIXED_NODE_SHA256 CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT \
    CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA; do
    if (( ${+parameters[$PRESERVED_NAME]} )); then
      CLOSED_ENVIRONMENT+=("$PRESERVED_NAME=${(P)PRESERVED_NAME}")
    fi
  done
  exec /usr/bin/env -i "${CLOSED_ENVIRONMENT[@]}" /bin/zsh -f "$0" "$@"
fi

[[ "${HOME:-}" == '/var/empty' && "${LANG:-}" == 'C' && "${LC_ALL:-}" == 'C'
   && "${PATH:-}" == '/usr/bin:/bin' ]] || fail BOOTSTRAP_ENVIRONMENT
for FORBIDDEN_BOOTSTRAP_NAME in \
  NODE_OPTIONS NODE_PATH ZDOTDIR DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH \
  DYLD_FRAMEWORK_PATH DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH; do
  (( ${+parameters[$FORBIDDEN_BOOTSTRAP_NAME]} == 0 )) || fail BOOTSTRAP_ENVIRONMENT
done

if (( $# != 1 )); then
  fail MODE_INVALID
fi

MODE="$1"
case "$MODE" in
  --self-test|plan|verify-simulator|verify-ssh|fetch|install-simulator|scan|write-terminal-anchor|resume|status|publish-vps-operation-authority-pass|publish-operation-authority|publish-privileged-writer-authority) ;;
  *) fail MODE_INVALID ;;
esac

LAUNCHER_ABSOLUTE="${0:A}"
EXTERNAL_AUTHORITY_LAUNCHER=0
SYNTHETIC_EXTERNAL_LAUNCHER=0
EXTERNAL_VERSION_ROOT=''
if [[ "$MODE" == '--self-test' && -n "${CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT:-}" ]]; then
  [[ "$CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT" == /*
     && "${CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA:-}" =~ '^[0-9a-f]{40}$'
     && "$LAUNCHER_ABSOLUTE" == "$CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT/runtime/ci3-bridge-launcher.zsh" ]] || fail STOP_PRE_AUTHORITY
  EXTERNAL_AUTHORITY_LAUNCHER=1
  SYNTHETIC_EXTERNAL_LAUNCHER=1
  EXTERNAL_VERSION_ROOT="$CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT"
elif [[ "$LAUNCHER_ABSOLUTE" =~ '^/Library/Application Support/Agentempp/ci3-controller-authority/[0-9a-f]{40}/runtime/ci3-bridge-launcher\.zsh$'
   || "$LAUNCHER_ABSOLUTE" =~ '^/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/[0-9a-f]{40}/bootstrap-[0-9a-f]{64}/runtime/ci3-bridge-launcher\.zsh$'
   || "$LAUNCHER_ABSOLUTE" =~ '^/var/lib/agentempp/ci3-publisher0-bootstrap/[0-9a-f]{40}/bootstrap-[0-9a-f]{64}/runtime/ci3-bridge-launcher\.zsh$' ]]; then
  EXTERNAL_AUTHORITY_LAUNCHER=1
  EXTERNAL_VERSION_ROOT="${LAUNCHER_ABSOLUTE:h:h}"
fi
if [[ "$MODE" != '--self-test' && "$EXTERNAL_AUTHORITY_LAUNCHER" != '1' ]]; then
  fail STOP_PRE_AUTHORITY
fi

# PUBLISHER0_EXTERNAL_BOOTSTRAP_REQUIRED: root invokes a separately installed,
# externally authenticated immutable bootstrap, never this worktree launcher.

if [[ "$EXTERNAL_AUTHORITY_LAUNCHER" == '1' ]]; then
  EXTERNAL_RUNTIME_ROOT="$EXTERNAL_VERSION_ROOT/runtime"
  EXTERNAL_AUTHORITY_PATH="$EXTERNAL_RUNTIME_ROOT/launcher-bootstrap.authority.v1"
  EXTERNAL_NODE_PATH="$EXTERNAL_RUNTIME_ROOT/node"
  EXTERNAL_CONTROLLER_PATH="$EXTERNAL_RUNTIME_ROOT/ci3-bridge-controller.mjs"
  EXTERNAL_ATTESTATION_PATH="$EXTERNAL_RUNTIME_ROOT/launch-attestation.json"
  EXTERNAL_MANIFEST_PATH="$EXTERNAL_RUNTIME_ROOT/authority-manifest.v1"
  for EXTERNAL_REQUIRED_PATH in \
    "$EXTERNAL_AUTHORITY_PATH" "$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" \
    "$LAUNCHER_ABSOLUTE" "$EXTERNAL_ATTESTATION_PATH" "$EXTERNAL_MANIFEST_PATH"; do
    [[ -f "$EXTERNAL_REQUIRED_PATH" && ! -L "$EXTERNAL_REQUIRED_PATH" ]] || fail STOP_PRE_AUTHORITY
  done
  typeset -a EXTERNAL_AUTHORITY_LINES
  EXTERNAL_AUTHORITY_LINES=("${(@f)$(<"$EXTERNAL_AUTHORITY_PATH")}")
  (( ${#EXTERNAL_AUTHORITY_LINES} == 10 )) || fail STOP_PRE_AUTHORITY
  [[ "$EXTERNAL_AUTHORITY_LINES[1]" == 'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1' ]] || fail STOP_PRE_AUTHORITY
  [[ "$EXTERNAL_AUTHORITY_LINES[2]" == 'authority_sha '*
     && "$EXTERNAL_AUTHORITY_LINES[3]" == 'controller_generation_id '*
     && "$EXTERNAL_AUTHORITY_LINES[4]" == 'node_sha256 '*
     && "$EXTERNAL_AUTHORITY_LINES[5]" == 'controller_sha256 '*
     && "$EXTERNAL_AUTHORITY_LINES[6]" == 'launcher_sha256 '*
     && "$EXTERNAL_AUTHORITY_LINES[7]" == 'launch_attestation_sha256 '*
     && "$EXTERNAL_AUTHORITY_LINES[8]" == 'authority_manifest_sha256 '*
     && "$EXTERNAL_AUTHORITY_LINES[9]" == 'allowed_modes '*
     && "$EXTERNAL_AUTHORITY_LINES[10]" == 'raw_values false' ]] || fail STOP_PRE_AUTHORITY
  AUTHORITY_SHA="${EXTERNAL_AUTHORITY_LINES[2]#authority_sha }"
  EXTERNAL_CONTROLLER_GENERATION="${EXTERNAL_AUTHORITY_LINES[3]#controller_generation_id }"
  EXTERNAL_NODE_SHA="${EXTERNAL_AUTHORITY_LINES[4]#node_sha256 }"
  EXTERNAL_CONTROLLER_SHA="${EXTERNAL_AUTHORITY_LINES[5]#controller_sha256 }"
  EXTERNAL_LAUNCHER_SHA="${EXTERNAL_AUTHORITY_LINES[6]#launcher_sha256 }"
  EXTERNAL_ATTESTATION_SHA="${EXTERNAL_AUTHORITY_LINES[7]#launch_attestation_sha256 }"
  EXTERNAL_MANIFEST_SHA="${EXTERNAL_AUTHORITY_LINES[8]#authority_manifest_sha256 }"
  EXTERNAL_ALLOWED_MODES="${EXTERNAL_AUTHORITY_LINES[9]#allowed_modes }"
  [[ "$AUTHORITY_SHA" =~ '^[0-9a-f]{40}$'
     && "$EXTERNAL_CONTROLLER_GENERATION" =~ '^controller-[0-9a-f]{64}$'
     && "$EXTERNAL_NODE_SHA" =~ '^[0-9a-f]{64}$'
     && "$EXTERNAL_CONTROLLER_SHA" =~ '^[0-9a-f]{64}$'
     && "$EXTERNAL_LAUNCHER_SHA" =~ '^[0-9a-f]{64}$'
     && "$EXTERNAL_ATTESTATION_SHA" =~ '^[0-9a-f]{64}$'
     && "$EXTERNAL_MANIFEST_SHA" =~ '^[0-9a-f]{64}$' ]] || fail STOP_PRE_AUTHORITY
  if [[ "$SYNTHETIC_EXTERNAL_LAUNCHER" == '1' ]]; then
    [[ "$AUTHORITY_SHA" == "$CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA" ]] || fail STOP_PRE_AUTHORITY
  else
    [[ "$EXTERNAL_VERSION_ROOT" == *"/$AUTHORITY_SHA" || "$EXTERNAL_VERSION_ROOT" == *"/$AUTHORITY_SHA/bootstrap-"* ]] || fail STOP_PRE_AUTHORITY
    for EXTERNAL_DIRECTORY in "$EXTERNAL_VERSION_ROOT" "$EXTERNAL_RUNTIME_ROOT"; do
      EXTERNAL_DIRECTORY_METADATA="$(/usr/bin/stat -f '%Su:%Sg:%Lp:%HT:%Sf' "$EXTERNAL_DIRECTORY" 2>/dev/null)" || fail STOP_PRE_AUTHORITY
      [[ "$EXTERNAL_DIRECTORY_METADATA" == 'root:wheel:555:Directory:'* && "$EXTERNAL_DIRECTORY_METADATA" == *uchg* ]] || fail STOP_PRE_AUTHORITY
    done
    for EXTERNAL_REQUIRED_PATH in \
      "$EXTERNAL_AUTHORITY_PATH" "$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" \
      "$LAUNCHER_ABSOLUTE" "$EXTERNAL_ATTESTATION_PATH" "$EXTERNAL_MANIFEST_PATH"; do
      EXTERNAL_FILE_METADATA="$(/usr/bin/stat -f '%Su:%Sg:%Lp:%l:%HT:%Sf' "$EXTERNAL_REQUIRED_PATH" 2>/dev/null)" || fail STOP_PRE_AUTHORITY
      [[ "$EXTERNAL_FILE_METADATA" == root:wheel:*:1:'Regular File':* && "$EXTERNAL_FILE_METADATA" == *uchg* ]] || fail STOP_PRE_AUTHORITY
    done
  fi
  EXTERNAL_MODE_ALLOWED=0
  for EXTERNAL_ALLOWED_MODE in "${(@s:,:)EXTERNAL_ALLOWED_MODES}"; do
    [[ "$EXTERNAL_ALLOWED_MODE" == "$MODE" ]] && EXTERNAL_MODE_ALLOWED=1
  done
  [[ "$EXTERNAL_MODE_ALLOWED" == '1' ]] || fail STOP_PRE_AUTHORITY
  external_hash() {
    local digest
    digest="$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" || fail STOP_PRE_AUTHORITY
    [[ "$digest" =~ '^[0-9a-f]{64}$' ]] || fail STOP_PRE_AUTHORITY
    print -r -- "$digest"
  }
  [[ "$(external_hash "$LAUNCHER_ABSOLUTE")" == "$EXTERNAL_LAUNCHER_SHA" ]] || fail LAUNCHER_GENERATION
  [[ "$(external_hash "$EXTERNAL_CONTROLLER_PATH")" == "$EXTERNAL_CONTROLLER_SHA" ]] || fail COMPONENT_HASH
  [[ "$(external_hash "$EXTERNAL_ATTESTATION_PATH")" == "$EXTERNAL_ATTESTATION_SHA" ]] || fail COMPONENT_HASH
  [[ "$(external_hash "$EXTERNAL_MANIFEST_PATH")" == "$EXTERNAL_MANIFEST_SHA" ]] || fail COMPONENT_HASH
  [[ "$(external_hash "$EXTERNAL_NODE_PATH")" == "$EXTERNAL_NODE_SHA" ]] || fail NODE_IDENTITY
  NODE_VERSION="$(/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin "$EXTERNAL_NODE_PATH" --version 2>/dev/null)" || fail NODE_IDENTITY
  [[ "$NODE_VERSION" == v<->.<->.<->* ]] || fail NODE_IDENTITY
  EXTERNAL_LAUNCH_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ci3-external-authority-launch.XXXXXXXX")" || fail SNAPSHOT_CREATE
  /bin/chmod 700 "$EXTERNAL_LAUNCH_ROOT"
  trap '/bin/rm -rf -- "$EXTERNAL_LAUNCH_ROOT"' EXIT HUP INT TERM
  EXTERNAL_CONTROLLER_OUTPUT="$EXTERNAL_LAUNCH_ROOT/controller.output"
  EXTERNAL_CONTROLLER_ERROR="$EXTERNAL_LAUNCH_ROOT/controller.error"
  if ! /usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin \
    "$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" "$MODE" > "$EXTERNAL_CONTROLLER_OUTPUT" 2> "$EXTERNAL_CONTROLLER_ERROR"; then
    [[ -s "$EXTERNAL_CONTROLLER_ERROR" ]] && /bin/cat "$EXTERNAL_CONTROLLER_ERROR" >&2
    fail CONTROLLER_EXECUTION
  fi
  if [[ "$MODE" == '--self-test' ]]; then
    EXTERNAL_CONTROLLER_RECORD="$(<"$EXTERNAL_CONTROLLER_OUTPUT")"
    [[ "$EXTERNAL_CONTROLLER_RECORD" =~ '^CONTROLLER_SELF_TEST PASS checks=[0-9]+ network_calls=0 privilege_prompts=0$' ]] || fail CONTROLLER_SELF_TEST
    [[ ! -s "$EXTERNAL_CONTROLLER_ERROR" ]] || fail CONTROLLER_SELF_TEST
    print -r -- 'LAUNCHER_EXTERNAL_SELF_TEST PASS authority=EXTERNAL_ROOT_IMMUTABLE environment=CLOSED'
    exit 0
  fi
  if [[ "$MODE" == 'resume' ]]; then
    EXTERNAL_CONTROLLER_RECORD="$(<"$EXTERNAL_CONTROLLER_OUTPUT")"
    [[ "$EXTERNAL_CONTROLLER_RECORD" =~ '^CONTROLLER RESUME PRE_TERMINAL state=PRE_TERMINAL_UNPUBLISHED raw_values=false$' ]] || fail TERMINAL_TAIL
    if ! /usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin \
      "$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" --terminalize-tail 2> "$EXTERNAL_LAUNCH_ROOT/terminalizer.error"; then
      fail TERMINAL_TAIL
    fi
    [[ ! -s "$EXTERNAL_LAUNCH_ROOT/terminalizer.error" ]] || fail TERMINAL_TAIL
  else
    /bin/cat "$EXTERNAL_CONTROLLER_OUTPUT"
  fi
  exit 0
fi

GIT_BOUND_REEXEC="${CI3_GIT_BOUND_REEXEC:-0}"
if [[ "$GIT_BOUND_REEXEC" == '1' ]]; then
  REPO_ROOT="${CI3_GIT_BOUND_REPO_ROOT:-}"
  AUTHORITY_SHA="${CI3_GIT_BOUND_AUTHORITY_SHA:-}"
  EXPECTED_LAUNCHER_SHA="${CI3_GIT_BOUND_LAUNCHER_SHA256:-}"
  [[ "$REPO_ROOT" == /* && "$AUTHORITY_SHA" =~ '^[0-9a-f]{40}$' && "$EXPECTED_LAUNCHER_SHA" =~ '^[0-9a-f]{64}$' ]] || fail LAUNCHER_BOOTSTRAP
  [[ "$(/usr/bin/git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)" == "$REPO_ROOT" ]] || fail LAUNCHER_BOOTSTRAP
  [[ "$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" == "$AUTHORITY_SHA" ]] || fail LAUNCHER_BOOTSTRAP
  REEXEC_SELF_SHA="$(/usr/bin/shasum -a 256 "$0" | /usr/bin/awk '{print $1}')" || fail LAUNCHER_BOOTSTRAP
  REEXEC_GIT_SHA="$(/usr/bin/git -C "$REPO_ROOT" cat-file blob "${AUTHORITY_SHA}:scripts/ci3/ci3-bridge-launcher.zsh" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')" || fail LAUNCHER_BOOTSTRAP
  [[ "$REEXEC_SELF_SHA" == "$EXPECTED_LAUNCHER_SHA" && "$REEXEC_GIT_SHA" == "$EXPECTED_LAUNCHER_SHA" ]] || fail LAUNCHER_BOOTSTRAP
  SCRIPT_DIR="$REPO_ROOT/scripts/ci3"
else
  SCRIPT_DIR="${0:A:h}"
  REPO_ROOT="$(/usr/bin/git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || fail GIT_AUTHORITY
  [[ "$SCRIPT_DIR" == "$REPO_ROOT/scripts/ci3" ]] || fail REPOSITORY_ROOT
fi

AUTHORITY_SHA="$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" || fail GIT_AUTHORITY
[[ "$AUTHORITY_SHA" =~ '^[0-9a-f]{40}$' ]] || fail GIT_AUTHORITY
AUTHORITY_PARENT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse "$AUTHORITY_SHA^" 2>/dev/null)" || fail GIT_AUTHORITY
AUTHORITY_TREE="$(/usr/bin/git -C "$REPO_ROOT" rev-parse "$AUTHORITY_SHA^{tree}" 2>/dev/null)" || fail GIT_AUTHORITY
AUTHORITY_SUBJECT="$(/usr/bin/git -C "$REPO_ROOT" show -s --format=%s "$AUTHORITY_SHA" 2>/dev/null)" || fail GIT_AUTHORITY
[[ "$AUTHORITY_PARENT" =~ '^[0-9a-f]{40}$' && "$AUTHORITY_TREE" =~ '^[0-9a-f]{40}$' ]] || fail GIT_AUTHORITY

GENERATOR_PATH='scripts/ci3/create-ios-staging-bridge-config.mjs'
LAUNCHER_PATH='scripts/ci3/ci3-bridge-launcher.zsh'
CONTROLLER_PATH='scripts/ci3/ci3-bridge-controller.mjs'
WRITER_PATH='scripts/ci3/ci3-terminal-anchor-writer.swift'
AUTHORITY_PATHS=(
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md'
  'docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md'
  'docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md'
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md'
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md'
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md'
  'scripts/ci3/create-ios-staging-bridge-config.mjs'
  'scripts/ci3/create-ios-staging-bridge-config.test.mjs'
  'scripts/ci3/ci3-bridge-controller.mjs'
  'scripts/ci3/ci3-bridge-controller.test.mjs'
  'scripts/ci3/ci3-bridge-launcher.zsh'
  'scripts/ci3/ci3-bridge-launcher.test.mjs'
  'scripts/ci3/ci3-terminal-anchor-writer.swift'
  'scripts/ci3/ci3-terminal-anchor-writer.test.mjs'
)

git_mode() {
  local git_path="$1"
  local record
  local metadata
  local recorded_path
  record="$(/usr/bin/git -C "$REPO_ROOT" ls-tree "$AUTHORITY_SHA" -- "$git_path" 2>/dev/null)" || return 1
  metadata="${record%%$'\t'*}"
  recorded_path="${record#*$'\t'}"
  [[ "$metadata" =~ '^(100644|100755) blob [0-9a-f]{40}$' && "$recorded_path" == "$git_path" ]] || return 1
  print -r -- "${metadata%% *}"
}

LAUNCH_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ci3-git-bound-launch.XXXXXXXX")" || fail SNAPSHOT_CREATE
[[ -d "$LAUNCH_ROOT" && "$LAUNCH_ROOT" == ${TMPDIR:-/tmp}/ci3-git-bound-launch.* ]] || fail SNAPSHOT_CREATE
/bin/chmod 700 "$LAUNCH_ROOT"
cleanup() {
  if [[ -n "${LAUNCH_ROOT:-}" && -d "$LAUNCH_ROOT" && "$LAUNCH_ROOT" == ${TMPDIR:-/tmp}/ci3-git-bound-launch.* ]]; then
    /bin/rm -rf -- "$LAUNCH_ROOT"
  fi
}
trap cleanup EXIT HUP INT TERM

snapshot_blob() {
  local git_path="$1"
  local output_path="$2"
  local blob_oid
  blob_oid="$(/usr/bin/git -C "$REPO_ROOT" rev-parse "$AUTHORITY_SHA:$git_path" 2>/dev/null)" || fail COMPONENT_MISSING
  [[ "$blob_oid" =~ '^[0-9a-f]{40}$' ]] || fail COMPONENT_MISSING
  /usr/bin/git -C "$REPO_ROOT" cat-file blob "$AUTHORITY_SHA:$git_path" > "$output_path" || fail COMPONENT_MISSING
  [[ -s "$output_path" ]] || fail COMPONENT_MISSING
  /bin/chmod 600 "$output_path"
  local file_sha
  file_sha="$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')" || fail COMPONENT_HASH
  [[ "$file_sha" =~ '^[0-9a-f]{64}$' ]] || fail COMPONENT_HASH
  print -r -- "$blob_oid $file_sha"
}

GENERATOR_SNAPSHOT="$LAUNCH_ROOT/create-ios-staging-bridge-config.mjs"
LAUNCHER_SNAPSHOT="$LAUNCH_ROOT/ci3-bridge-launcher.zsh"
CONTROLLER_SNAPSHOT="$LAUNCH_ROOT/ci3-bridge-controller.mjs"
WRITER_SNAPSHOT="$LAUNCH_ROOT/ci3-terminal-anchor-writer.swift"

GENERATOR_BINDING="$(snapshot_blob "$GENERATOR_PATH" "$GENERATOR_SNAPSHOT")"
LAUNCHER_BINDING="$(snapshot_blob "$LAUNCHER_PATH" "$LAUNCHER_SNAPSHOT")"
CONTROLLER_BINDING="$(snapshot_blob "$CONTROLLER_PATH" "$CONTROLLER_SNAPSHOT")"
WRITER_BINDING="$(snapshot_blob "$WRITER_PATH" "$WRITER_SNAPSHOT")"

[[ "$(git_mode "$LAUNCHER_PATH")" == '100755' ]] || fail COMPONENT_MODE
[[ "$(git_mode "$CONTROLLER_PATH")" == '100755' ]] || fail COMPONENT_MODE
[[ "$(git_mode "$WRITER_PATH")" == '100644' ]] || fail COMPONENT_MODE

AUTHORITY_MANIFEST_PATH="$LAUNCH_ROOT/authority-manifest.v1"
: > "$AUTHORITY_MANIFEST_PATH"
for AUTHORITY_PATH in "${AUTHORITY_PATHS[@]}"; do
  PATH_OID="$(/usr/bin/git -C "$REPO_ROOT" rev-parse "$AUTHORITY_SHA:$AUTHORITY_PATH" 2>/dev/null)" || fail AUTHORITY_MANIFEST
  [[ "$PATH_OID" =~ '^[0-9a-f]{40}$' ]] || fail AUTHORITY_MANIFEST
  PATH_SHA="$(/usr/bin/git -C "$REPO_ROOT" cat-file blob "$AUTHORITY_SHA:$AUTHORITY_PATH" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')" || fail AUTHORITY_MANIFEST
  [[ "$PATH_SHA" =~ '^[0-9a-f]{64}$' ]] || fail AUTHORITY_MANIFEST
  print -r -- "$AUTHORITY_PATH $PATH_OID $PATH_SHA" >> "$AUTHORITY_MANIFEST_PATH"
done
/bin/chmod 600 "$AUTHORITY_MANIFEST_PATH"
AUTHORITY_MANIFEST_SHA="$(/usr/bin/shasum -a 256 "$AUTHORITY_MANIFEST_PATH" | /usr/bin/awk '{print $1}')" || fail AUTHORITY_MANIFEST
[[ "$AUTHORITY_MANIFEST_SHA" =~ '^[0-9a-f]{64}$' ]] || fail AUTHORITY_MANIFEST

/usr/bin/cmp -s -- "$0" "$LAUNCHER_SNAPSHOT" || fail LAUNCHER_GENERATION

if [[ "$GIT_BOUND_REEXEC" != '1' ]]; then
  CI3_GIT_BOUND_REEXEC=1 \
  CI3_GIT_BOUND_REPO_ROOT="$REPO_ROOT" \
  CI3_GIT_BOUND_AUTHORITY_SHA="$AUTHORITY_SHA" \
  CI3_GIT_BOUND_LAUNCHER_SHA256="${LAUNCHER_BINDING##* }" \
  /bin/zsh "$LAUNCHER_SNAPSHOT" "$MODE"
  exit $?
fi

if [[ "$MODE" == '--self-test' ]]; then
  if [[ -n "${CI3_SYNTHETIC_FIXED_NODE_PATH:-}" ]]; then
    NODE_PATH="$CI3_SYNTHETIC_FIXED_NODE_PATH"
    [[ "$NODE_PATH" == /* && "${CI3_SYNTHETIC_FIXED_NODE_SHA256:-}" =~ '^[0-9a-f]{64}$' ]] || fail NODE_IDENTITY
    NODE_PATH="${NODE_PATH:A}"
    [[ -f "$NODE_PATH" && -x "$NODE_PATH" ]] || fail NODE_IDENTITY
    SYNTHETIC_NODE_SHA="$(/usr/bin/shasum -a 256 "$NODE_PATH" | /usr/bin/awk '{print $1}')" || fail NODE_IDENTITY
    [[ "$SYNTHETIC_NODE_SHA" == "$CI3_SYNTHETIC_FIXED_NODE_SHA256" ]] || fail NODE_IDENTITY
  else
    NODE_PATH='/opt/homebrew/bin/node'
    [[ -f "$NODE_PATH" || -L "$NODE_PATH" ]] || fail NODE_IDENTITY
    NODE_PATH="${NODE_PATH:A}"
    [[ -f "$NODE_PATH" && -x "$NODE_PATH" ]] || fail NODE_IDENTITY
  fi
else
  NODE_PATH="/Library/Application Support/Agentempp/ci3-controller-authority/$AUTHORITY_SHA/runtime/node"
  [[ -f "$NODE_PATH" && ! -L "$NODE_PATH" && -x "$NODE_PATH" ]] || fail NODE_IDENTITY
  NODE_PHYSICAL="$(/usr/bin/stat -f '%Su:%Sg:%Lp:%l:%Sf' "$NODE_PATH" 2>/dev/null)" || fail NODE_IDENTITY
  [[ "$NODE_PHYSICAL" == 'root:wheel:555:1:'* && "$NODE_PHYSICAL" == *uchg* ]] || fail NODE_IDENTITY
fi
NODE_VERSION="$(/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin "$NODE_PATH" --version 2>/dev/null)" || fail NODE_IDENTITY
[[ "$NODE_VERSION" == v<->.<->.<->* ]] || fail NODE_IDENTITY

[[ -x /usr/bin/ssh && -f /usr/bin/ssh ]] || fail SSH_IDENTITY
SSH_VERSION="$(/usr/bin/ssh -V 2>&1)" || fail SSH_IDENTITY
[[ "$SSH_VERSION" == OpenSSH_* ]] || fail SSH_IDENTITY

[[ -x /usr/bin/xcrun && -f /usr/bin/xcrun ]] || fail XCODE_IDENTITY
SWIFTC_PATH="$(/usr/bin/xcrun --find swiftc 2>/dev/null)" || fail SWIFT_IDENTITY
SWIFTC_PATH="${SWIFTC_PATH:A}"
[[ -x "$SWIFTC_PATH" && -f "$SWIFTC_PATH" ]] || fail SWIFT_IDENTITY
SWIFT_VERSION="$($SWIFTC_PATH --version 2>/dev/null)" || fail SWIFT_IDENTITY
SWIFT_VERSION="${SWIFT_VERSION%%$'\n'*}"
[[ "$SWIFT_VERSION" == 'swift-driver version:'* || "$SWIFT_VERSION" == 'Apple Swift version'* || "$SWIFT_VERSION" == 'Swift version'* ]] || fail SWIFT_IDENTITY
XCODE_VERSION="$(/usr/bin/xcodebuild -version 2>/dev/null)" || fail XCODE_IDENTITY
XCODE_VERSION="${XCODE_VERSION%%$'\n'*}"
[[ "$XCODE_VERSION" == Xcode* ]] || fail XCODE_IDENTITY
[[ -x /usr/bin/xcodebuild && -f /usr/bin/xcodebuild ]] || fail XCODE_IDENTITY

hash_file() {
  local value
  value="$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" || fail TOOL_IDENTITY
  [[ "$value" =~ '^[0-9a-f]{64}$' ]] || fail TOOL_IDENTITY
  print -r -- "$value"
}

hash_text() {
  local value
  value="$(print -rn -- "$1" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')" || fail TOOL_IDENTITY
  [[ "$value" =~ '^[0-9a-f]{64}$' ]] || fail TOOL_IDENTITY
  print -r -- "$value"
}

if [[ "$MODE" != '--self-test' ]]; then
  [[ "$AUTHORITY_PARENT" == '92cccf3dca21a29d601d2f274a67ea2ba284914b' ]] || fail GIT_AUTHORITY
  [[ "$AUTHORITY_SUBJECT" == 'build(ops): authorize bounded Git blob reader for CI-3 bridge' ]] || fail GIT_AUTHORITY
fi

GENERATOR_OID="${GENERATOR_BINDING%% *}"
GENERATOR_SHA="${GENERATOR_BINDING##* }"
LAUNCHER_OID="${LAUNCHER_BINDING%% *}"
LAUNCHER_SHA="${LAUNCHER_BINDING##* }"
CONTROLLER_OID="${CONTROLLER_BINDING%% *}"
CONTROLLER_SHA="${CONTROLLER_BINDING##* }"
WRITER_OID="${WRITER_BINDING%% *}"
WRITER_SHA="${WRITER_BINDING##* }"
AUTHORITY_SUBJECT_SHA="$(hash_text "$AUTHORITY_SUBJECT")"
NODE_PATH_SHA="$(hash_text "$NODE_PATH")"
NODE_BINARY_SHA="$(hash_file "$NODE_PATH")"
NODE_VERSION_SHA="$(hash_text "$NODE_VERSION")"
SSH_PATH_SHA="$(hash_text '/usr/bin/ssh')"
SSH_BINARY_SHA="$(hash_file '/usr/bin/ssh')"
SSH_VERSION_SHA="$(hash_text "$SSH_VERSION")"
SWIFTC_PATH_SHA="$(hash_text "$SWIFTC_PATH")"
SWIFTC_BINARY_SHA="$(hash_file "$SWIFTC_PATH")"
SWIFT_VERSION_SHA="$(hash_text "$SWIFT_VERSION")"
XCODE_PATH_SHA="$(hash_text '/usr/bin/xcodebuild')"
XCODE_BINARY_SHA="$(hash_file '/usr/bin/xcodebuild')"
XCODE_VERSION_SHA="$(hash_text "$XCODE_VERSION")"
ATTESTATION_PATH="$LAUNCH_ROOT/launch-attestation.json"
{
  print -r -- '{'
  print -r -- '  "schema_version": 1,'
  print -r -- '  "purpose": "CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2",'
  print -r -- "  \"authority_sha\": \"$AUTHORITY_SHA\","
  print -r -- "  \"authority_parent\": \"$AUTHORITY_PARENT\","
  print -r -- "  \"authority_tree\": \"$AUTHORITY_TREE\","
  print -r -- "  \"authority_subject_sha256\": \"$AUTHORITY_SUBJECT_SHA\","
  print -r -- "  \"authority_manifest_sha256\": \"$AUTHORITY_MANIFEST_SHA\","
  print -r -- '  "components": {'
  print -r -- "    \"generator\": {\"path\": \"$GENERATOR_PATH\", \"blob_oid\": \"$GENERATOR_OID\", \"sha256\": \"$GENERATOR_SHA\"},"
  print -r -- "    \"controller\": {\"path\": \"$CONTROLLER_PATH\", \"blob_oid\": \"$CONTROLLER_OID\", \"sha256\": \"$CONTROLLER_SHA\"},"
  print -r -- "    \"launcher\": {\"path\": \"$LAUNCHER_PATH\", \"blob_oid\": \"$LAUNCHER_OID\", \"sha256\": \"$LAUNCHER_SHA\"},"
  print -r -- "    \"writer\": {\"path\": \"$WRITER_PATH\", \"blob_oid\": \"$WRITER_OID\", \"sha256\": \"$WRITER_SHA\"}"
  print -r -- '  },'
  print -r -- '  "tools": {'
  print -r -- "    \"node\": {\"path_sha256\": \"$NODE_PATH_SHA\", \"binary_sha256\": \"$NODE_BINARY_SHA\", \"version_sha256\": \"$NODE_VERSION_SHA\"},"
  print -r -- "    \"ssh\": {\"path_sha256\": \"$SSH_PATH_SHA\", \"binary_sha256\": \"$SSH_BINARY_SHA\", \"version_sha256\": \"$SSH_VERSION_SHA\"},"
  print -r -- "    \"swiftc\": {\"path_sha256\": \"$SWIFTC_PATH_SHA\", \"binary_sha256\": \"$SWIFTC_BINARY_SHA\", \"version_sha256\": \"$SWIFT_VERSION_SHA\"},"
  print -r -- "    \"xcodebuild\": {\"path_sha256\": \"$XCODE_PATH_SHA\", \"binary_sha256\": \"$XCODE_BINARY_SHA\", \"version_sha256\": \"$XCODE_VERSION_SHA\"}"
  print -r -- '  },'
  print -r -- '  "raw_values": false'
  print -r -- '}'
} > "$ATTESTATION_PATH"
/bin/chmod 600 "$ATTESTATION_PATH"

CONTROLLER_OUTPUT="$LAUNCH_ROOT/controller.output"
CONTROLLER_ERROR="$LAUNCH_ROOT/controller.error"
typeset -a CONTROLLER_ENVIRONMENT
CONTROLLER_ENVIRONMENT=(HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin)
for PRESERVED_NAME in \
  CI3_SYNTHETIC_E2E_SCENARIO CI3_SYNTHETIC_SCENARIO_SHA256 \
  CI3_SYNTHETIC_E2E_ROOT CI3_SYNTHETIC_WRITER_BINARY CI3_SYNTHETIC_WRITER_SHA256 \
  CI3_SYNTHETIC_WRITER_FIXTURE CI3_SYNTHETIC_WRITER_MATERIALIZER \
  CI3_SYNTHETIC_EXTERNAL_RESTART; do
  if (( ${+parameters[$PRESERVED_NAME]} )); then
    CONTROLLER_ENVIRONMENT+=("$PRESERVED_NAME=${(P)PRESERVED_NAME}")
  fi
done
if ! /usr/bin/env -i "${CONTROLLER_ENVIRONMENT[@]}" "$NODE_PATH" "$CONTROLLER_SNAPSHOT" "$MODE" > "$CONTROLLER_OUTPUT" 2> "$CONTROLLER_ERROR"; then
  if [[ -s "$CONTROLLER_ERROR" ]]; then
    /bin/cat "$CONTROLLER_ERROR" >&2
  else
    fail CONTROLLER_EXECUTION
  fi
  exit 1
fi

if [[ "$MODE" == 'resume' ]]; then
  CONTROLLER_RECORD="$(<"$CONTROLLER_OUTPUT")"
  [[ "$CONTROLLER_RECORD" =~ '^CONTROLLER RESUME PRE_TERMINAL state=PRE_TERMINAL_UNPUBLISHED raw_values=false$' ]] || fail TERMINAL_TAIL
  TERMINALIZER_ERROR="$LAUNCH_ROOT/terminalizer.error"
  if ! /usr/bin/env -i \
    HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin \
    "$NODE_PATH" "$CONTROLLER_SNAPSHOT" --terminalize-tail 2> "$TERMINALIZER_ERROR"; then
    fail TERMINAL_TAIL
  fi
  [[ ! -s "$TERMINALIZER_ERROR" ]] || fail TERMINAL_TAIL
  exit 0
fi

if [[ "$MODE" == '--self-test' ]]; then
  CONTROLLER_RECORD="$(<"$CONTROLLER_OUTPUT")"
  if [[ -n "${CI3_SYNTHETIC_E2E_ROOT:-}" ]]; then
    [[ "$CONTROLLER_RECORD" =~ '^CONTROLLER_SELF_TEST PASS checks=[0-9]+ network_calls=0 privilege_prompts=0 integrated_e2e=(COMPLETE|STOP_CLAIM_CONSUMED_NO_RESULT) writer_mode=(WRITE|NOT_INVOKED) pre_anchor=(PENDING_VERIFICATION|NOT_PUBLISHED) terminal_settlement=(TERMINAL_PASS|NOT_PUBLISHED)$' ]] || fail CONTROLLER_SELF_TEST
  else
    [[ "$CONTROLLER_RECORD" =~ '^CONTROLLER_SELF_TEST PASS checks=[0-9]+ network_calls=0 privilege_prompts=0$' ]] || fail CONTROLLER_SELF_TEST
  fi
  [[ ! -s "$CONTROLLER_ERROR" ]] || fail CONTROLLER_SELF_TEST
  if [[ -n "${CI3_SYNTHETIC_E2E_ROOT:-}" ]]; then
    print -r -- "LAUNCHER_SELF_TEST PASS checks=14 network_calls=0 privilege_prompts=0 controller_snapshot=GIT_BOUND ${CONTROLLER_RECORD#*privilege_prompts=0 } durable_scenarios=60 terminal_phases=2"
  else
    print -r -- 'LAUNCHER_SELF_TEST PASS checks=14 network_calls=0 privilege_prompts=0 controller_snapshot=GIT_BOUND durable_scenarios=60 terminal_phases=2'
  fi
else
  /bin/cat "$CONTROLLER_OUTPUT"
fi
