#!/usr/bin/env bash

# Configure the GitHub secrets used to sign and notarize macOS release
# artifacts in .github/workflows/release.yml. That workflow consumes exactly
# five values:
#
#   APPLE_CERTIFICATE_P12           base64 of the Developer ID Application .p12
#   APPLE_CERTIFICATE_PASSWORD      password used when exporting the .p12
#   APPLE_NOTARIZATION_KEY_P8       base64 of the App Store Connect API key (.p8)
#   APPLE_NOTARIZATION_KEY_ID       App Store Connect API Key ID (10 chars)
#   APPLE_NOTARIZATION_ISSUER_ID    App Store Connect Issuer ID (UUID)
#
# Secrets are uploaded with the GitHub CLI. Secret values are read
# interactively so they do not appear in shell history or the process list.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-macos-signing-secrets.sh [options]

Options:
  --environment NAME   Store the secrets under a GitHub environment instead of
                       the repository level (default: repository level, which
                       is what .github/workflows/release.yml expects).
  --issuer-id ID       App Store Connect Issuer ID (UUID).
  --key-id ID          App Store Connect API Key ID (10 alphanumeric chars).
  --p12 PATH           Exported Developer ID Application .p12 file.
  --p8 PATH            App Store Connect API key (.p8) file.
  --repo OWNER/REPO    GitHub repository (default: detect from current checkout).
  --yes                Skip the final confirmation prompt.
  -h, --help           Show this help.

The script securely prompts for the .p12 password. It intentionally does not
accept that value as a command-line argument, where it could be exposed in
shell history or the process list.

Example:
  ./.github/scripts/setup-macos-signing-secrets.sh --repo wangyuling93/kimi-code

Notes:
  - .github/workflows/release.yml reads secrets.APPLE_* directly, so the
    secrets must live at repository level unless the workflow jobs declare
    an environment.
  - The release job only runs for github.repository_owner == 'MoonshotAI';
    remove or adjust that condition in .github/workflows/release.yml to run
    it from a fork.
EOF
}

repository=""
environment_name=""
p12_path=""
p8_path=""
apple_key_id=""
apple_issuer_id=""
skip_confirmation="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment)
      environment_name="${2:-}"
      shift 2
      ;;
    --issuer-id)
      apple_issuer_id="${2:-}"
      shift 2
      ;;
    --key-id)
      apple_key_id="${2:-}"
      shift 2
      ;;
    --p12)
      p12_path="${2:-}"
      shift 2
      ;;
    --p8)
      p8_path="${2:-}"
      shift 2
      ;;
    --repo)
      repository="${2:-}"
      shift 2
      ;;
    --yes)
      skip_confirmation="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This setup script must run on macOS." >&2
  exit 1
fi

for command_name in base64 gh openssl sed tr; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command was not found: $command_name" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

if [[ -z "$repository" ]]; then
  if ! repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
    echo "Could not detect the GitHub repository. Pass --repo OWNER/REPO." >&2
    exit 1
  fi
fi

if [[ ! "$repository" =~ ^[^/]+/[^/]+$ ]]; then
  echo "--repo must use the OWNER/REPO format, got: $repository" >&2
  exit 2
fi

# ---- Developer ID Application certificate (.p12) ----

if [[ -z "$p12_path" ]]; then
  if command -v osascript >/dev/null 2>&1; then
    echo "Select the exported Developer ID Application .p12 file."
    if ! p12_path="$(osascript -e 'POSIX path of (choose file with prompt "Select Developer ID Application .p12")')"; then
      echo "No .p12 file was selected." >&2
      exit 1
    fi
  else
    read -r -p "Path to Developer ID Application .p12: " p12_path
  fi
fi

if [[ "$p12_path" == "~/"* ]]; then
  p12_path="${HOME}/${p12_path#\~/}"
fi

if [[ ! -f "$p12_path" ]]; then
  echo ".p12 file does not exist: $p12_path" >&2
  exit 1
fi

if [[ ! -s "$p12_path" ]]; then
  echo ".p12 file is empty: $p12_path" >&2
  exit 1
fi

read -r -s -p "Password used when exporting the .p12: " p12_password
echo
if [[ -z "$p12_password" ]]; then
  echo ".p12 password cannot be empty." >&2
  exit 2
fi

cleanup() {
  if [[ -n "${p12_error_path:-}" ]]; then
    rm -f "$p12_error_path"
  fi
  unset p12_password 2>/dev/null || true
}
trap cleanup EXIT

read_certificate_subject() {
  local legacy_mode="$1"
  local -a pkcs12_args
  pkcs12_args=(
    pkcs12
    -in "$p12_path"
    -passin stdin
    -clcerts
    -nokeys
  )
  if [[ "$legacy_mode" == "true" ]]; then
    pkcs12_args+=(-legacy)
  fi

  printf '%s\n' "$p12_password" |
    openssl "${pkcs12_args[@]}" |
    openssl x509 -noout -subject -nameopt RFC2253
}

certificate_subject=""
p12_error_path="$(mktemp -t kimi-code-p12-error)"

report_p12_error() {
  local error_text="$1"
  if grep -Eqi 'invalid password|MAC verify|mac verify failure|bad password' <<<"$error_text"; then
    echo "The .p12 rejected the supplied password." >&2
  else
    echo "Could not extract a certificate from the .p12." >&2
  fi
  echo "OpenSSL diagnostic:" >&2
  printf '%s\n' "$error_text" >&2
  echo "Try exporting the Developer ID Application certificate from Xcode again." >&2
  exit 1
}

if certificate_subject="$(read_certificate_subject false 2>"$p12_error_path")"; then
  :
elif openssl version | grep -q "OpenSSL 3"; then
  # OpenSSL 3 needs -legacy for pre-10.15 exported p12s.
  if certificate_subject="$(read_certificate_subject true 2>"$p12_error_path")"; then
    echo "The .p12 uses legacy encryption; compatibility mode succeeded."
  else
    report_p12_error "$(<"$p12_error_path")"
  fi
else
  # LibreSSL (stock macOS) does not support -legacy but accepts legacy PBE
  # algorithms natively, so there is no separate compatibility attempt.
  report_p12_error "$(<"$p12_error_path")"
fi

if [[ "$certificate_subject" != *"CN=Developer ID Application:"* ]]; then
  echo "The selected .p12 does not contain a Developer ID Application certificate." >&2
  echo "Certificate subject: $certificate_subject" >&2
  exit 1
fi

# The workflow discovers the signing identity itself and does not need the
# team ID, but showing it here confirms the certificate matches the account.
apple_team_id="$(printf '%s\n' "$certificate_subject" | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p')"

# ---- App Store Connect API key (.p8) ----

if [[ -z "$p8_path" ]]; then
  if command -v osascript >/dev/null 2>&1; then
    echo "Select the App Store Connect API key (.p8) file."
    if ! p8_path="$(osascript -e 'POSIX path of (choose file with prompt "Select App Store Connect API Key (.p8)")')"; then
      echo "No .p8 file was selected." >&2
      exit 1
    fi
  else
    read -r -p "Path to App Store Connect API key (.p8): " p8_path
  fi
fi

if [[ "$p8_path" == "~/"* ]]; then
  p8_path="${HOME}/${p8_path#\~/}"
fi

if [[ ! -f "$p8_path" ]]; then
  echo ".p8 file does not exist: $p8_path" >&2
  exit 1
fi

if [[ ! -s "$p8_path" ]]; then
  echo ".p8 file is empty: $p8_path" >&2
  exit 1
fi

if ! head -1 "$p8_path" | grep -Eq '^-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
  echo "The selected file does not look like an App Store Connect API key (.p8)." >&2
  echo "It should start with a PRIVATE KEY PEM header." >&2
  exit 1
fi

# Derive the API Key ID from the standard AuthKey_<KEY_ID>.p8 file name when
# it was not passed explicitly.
if [[ -z "$apple_key_id" ]]; then
  if [[ "$(basename "$p8_path")" =~ ^AuthKey_([A-Za-z0-9]{10})\.p8$ ]]; then
    apple_key_id="${BASH_REMATCH[1]}"
    echo "Derived API Key ID from file name: $apple_key_id"
  fi
fi

if [[ -z "$apple_key_id" ]]; then
  read -r -p "App Store Connect API Key ID (10 alphanumeric characters): " apple_key_id
fi

# bash 3.2 (stock macOS) has no ${var^^}; uppercase via tr instead.
apple_key_id="$(printf '%s' "$apple_key_id" | tr '[:lower:]' '[:upper:]')"

if [[ ! "$apple_key_id" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "API Key ID must be 10 alphanumeric characters, got: $apple_key_id" >&2
  exit 2
fi

if [[ -z "$apple_issuer_id" ]]; then
  read -r -p "App Store Connect Issuer ID (UUID): " apple_issuer_id
fi

if [[ ! "$apple_issuer_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "Issuer ID must be a UUID (e.g. 57246542-96fe-1a63-bc06-0c88c9f0e2f6), got: $apple_issuer_id" >&2
  exit 2
fi

echo
echo "GitHub repository:  $repository"
if [[ -n "$environment_name" ]]; then
  echo "GitHub environment: $environment_name"
else
  echo "GitHub scope:       repository (workflow reads secrets.APPLE_* directly)"
fi
echo "Apple Team ID:      ${apple_team_id:-<not found in certificate subject>}"
echo "API Key ID:         $apple_key_id"
echo "Issuer ID:          $apple_issuer_id"
echo "Certificate:        $certificate_subject"
echo

if [[ "$skip_confirmation" != "true" ]]; then
  read -r -p "Upload these signing settings to GitHub? [y/N] " confirmation
  case "$confirmation" in
    y|Y|yes|YES) ;;
    *)
      echo "Cancelled. No GitHub settings were changed."
      exit 0
      ;;
  esac
fi

if [[ -n "$environment_name" ]]; then
  echo "Creating GitHub environment '$environment_name' if necessary..."
  gh api \
    --method PUT \
    "repos/${repository}/environments/${environment_name}" \
    >/dev/null
fi

# Helpers keep word expansion compatible with bash 3.2 (stock macOS), where
# "${empty_arr[@]}" under `set -u` raises "unbound variable" and can make a
# failing pipeline slip past `set -e`. The arrays here always hold --repo, so
# they are never empty.
list_secrets() {
  if [[ -n "$environment_name" ]]; then
    gh secret list --env "$environment_name" --repo "$repository"
  else
    gh secret list --repo "$repository"
  fi
}

set_secret() {
  local name="$1"
  local value="$2"
  local -a args=(--repo "$repository")
  if [[ -n "$environment_name" ]]; then
    args+=(--env "$environment_name")
  fi
  printf '%s' "$value" | gh secret set "$name" "${args[@]}"
}

echo "Uploading Developer ID certificate..."
set_secret APPLE_CERTIFICATE_P12 "$(base64 <"$p12_path" | tr -d '\r\n')"
set_secret APPLE_CERTIFICATE_PASSWORD "$p12_password"

echo "Uploading notarization API key..."
set_secret APPLE_NOTARIZATION_KEY_P8 "$(base64 <"$p8_path" | tr -d '\r\n')"
set_secret APPLE_NOTARIZATION_KEY_ID "$apple_key_id"
set_secret APPLE_NOTARIZATION_ISSUER_ID "$apple_issuer_id"

echo
echo "Configured GitHub secrets:"
secret_list="$(list_secrets 2>&1 || true)"
printf '%s\n' "$secret_list"

# Verify the upload actually landed. The pipe variant would be unreliable:
# under `set -o pipefail`, `grep -q` closing the pipe early makes the writer
# exit via SIGPIPE, which can falsely mark an uploaded secret as missing.
missing=""
for name in APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD \
            APPLE_NOTARIZATION_KEY_P8 APPLE_NOTARIZATION_KEY_ID \
            APPLE_NOTARIZATION_ISSUER_ID; do
  if ! grep -q "^$name" <<<"$secret_list"; then
    missing="$missing $name"
  fi
done

if [[ -n "$missing" ]]; then
  echo
  echo "ERROR: the following secrets were not created:$missing" >&2
  exit 1
fi

echo
echo "macOS signing settings are ready for the GitHub Actions workflow."
echo "Workflow:    .github/workflows/release.yml"
echo "Environment: ${environment_name:-repository level}"
echo "Trigger:     push to main"
echo
echo "Reminder: the release job in .github/workflows/release.yml is guarded by"
echo "'if: github.repository_owner == ''MoonshotAI''' and only runs from the"
echo "MoonshotAI organization; adjust that condition to run it from a fork."
