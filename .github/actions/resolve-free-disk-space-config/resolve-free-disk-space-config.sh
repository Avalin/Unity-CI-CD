#!/bin/bash
set -euo pipefail

echo "🔍 Resolving which build targets need to have a free space check before being built..."

# Paths to defaults
PROJECT_DEFAULTS_FILE="${PROJECT_DEFAULTS_FILE:-.github/config/defaults.json}"
ACTION_DEFAULTS_FILE="${ACTION_DEFAULTS_FILE:-$GITHUB_ACTION_PATH/defaults.json}"

# Load project defaults if present
if [[ -f "$PROJECT_DEFAULTS_FILE" ]]; then
  PROJECT_DEFAULTS="$(cat "$PROJECT_DEFAULTS_FILE")"
else
  echo "⚠️ Project defaults not found at ${PROJECT_DEFAULTS_FILE}"
  PROJECT_DEFAULTS="{}"
fi

# Load action-fallback defaults (must exist)
if [[ ! -f "$ACTION_DEFAULTS_FILE" ]]; then
  echo "❌ Action defaults not found at ${ACTION_DEFAULTS_FILE}"
  exit 1
fi
ACTION_DEFAULTS="$(cat "$ACTION_DEFAULTS_FILE")"

# Extract candidate values
PROJECT_MODE="$(echo "$PROJECT_DEFAULTS" | jq -r '.build.checkFreeDiskSpace // empty')"
ACTION_MODE="$(echo "$ACTION_DEFAULTS" | jq -r '.build.checkFreeDiskSpace // empty')"

PROJECT_CUSTOM_TARGETS_RAW="$(echo "$PROJECT_DEFAULTS" | jq -c '.build.checkFreeDiskSpaceCustomTargets // empty')"
ACTION_CUSTOM_TARGETS_RAW="$(echo "$ACTION_DEFAULTS" | jq -c '.build.checkFreeDiskSpaceCustomTargets // empty')"

# Helper: validate mode
is_valid_mode() {
  local val="${1,,}"
  case "$val" in
    custom|always|never) return 0 ;;
    *) return 1 ;;
  esac
}

# Helper: validate targets array JSON (array of strings), return compact JSON or empty
normalize_targets_array() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "null" ]]; then
    echo ""
    return 0
  fi

  if echo "$raw" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
    echo "$raw" | jq -c '.'
  else
    echo ""
  fi
}

# Resolve mode: project -> action
FREE_DISK_SPACE=""

if [[ -n "$PROJECT_MODE" ]]; then
  if is_valid_mode "$PROJECT_MODE"; then
    FREE_DISK_SPACE="${PROJECT_MODE,,}"
  else
    echo "⚠️ Invalid build.checkFreeDiskSpace in project defaults: ${PROJECT_MODE} (expected: custom|always|never)"
  fi
fi

if [[ -z "$FREE_DISK_SPACE" ]]; then
  if [[ -n "$ACTION_MODE" ]]; then
    if is_valid_mode "$ACTION_MODE"; then
      FREE_DISK_SPACE="${ACTION_MODE,,}"
    else
      echo "⚠️ Invalid build.checkFreeDiskSpace in action defaults: ${ACTION_MODE} (expected: custom|always|never)"
    fi
  fi
fi

if [[ -z "$FREE_DISK_SPACE" ]]; then
  echo "❌ No valid build.checkFreeDiskSpace found in project defaults or action defaults."
  echo "💡 Please define it in defaults.json as one of: custom, always, never"
  exit 1
fi

# Resolve custom targets ONLY when mode is custom
FREE_DISK_SPACE_CUSTOM_TARGETS="[]"

if [[ "$FREE_DISK_SPACE" == "custom" ]]; then
  PROJECT_CUSTOM_TARGETS="$(normalize_targets_array "$PROJECT_CUSTOM_TARGETS_RAW")"
  ACTION_CUSTOM_TARGETS="$(normalize_targets_array "$ACTION_CUSTOM_TARGETS_RAW")"

  if [[ -n "$PROJECT_CUSTOM_TARGETS" ]]; then
    FREE_DISK_SPACE_CUSTOM_TARGETS="$PROJECT_CUSTOM_TARGETS"
  elif [[ -n "$ACTION_CUSTOM_TARGETS" ]]; then
    FREE_DISK_SPACE_CUSTOM_TARGETS="$ACTION_CUSTOM_TARGETS"
  fi

  if [[ -z "$FREE_DISK_SPACE_CUSTOM_TARGETS" || "$FREE_DISK_SPACE_CUSTOM_TARGETS" == "[]" ]]; then
    echo "❌ checkFreeDiskSpace is set to 'custom', but no valid build.checkFreeDiskSpaceCustomTargets were found."
    echo "💡 Please define it in defaults.json as a JSON array of strings (e.g. [\"Android\",\"WebGL\"])."
    exit 1
  fi
fi

echo "✅ Resolved build.checkFreeDiskSpace: ${FREE_DISK_SPACE}"
echo "✅ Resolved build.checkFreeDiskSpaceCustomTargets: ${FREE_DISK_SPACE_CUSTOM_TARGETS}"

# Export outputs
{
  echo "checkFreeDiskSpace=${FREE_DISK_SPACE}"
  echo "checkFreeDiskSpaceCustomTargets=${FREE_DISK_SPACE_CUSTOM_TARGETS}"
} >> "$GITHUB_OUTPUT"

echo "✅ Free disk space config resolved."