#!/bin/bash

# Desired settings and thresholds
declare -A limits=(
  [fs.inotify.max_user_watches]="655360:20000"
  [fs.inotify.max_user_instances]="1280:1000"
  [kernel.keys.maxkeys]="20000:1000"
  [kernel.keys.maxbytes]="500000:250000"
)

SYSCTL_CONF_FILE="/etc/sysctl.d/99-custom-tuning.conf"
TMP_FILE="$(mktemp)"
CHANGES_MADE=0
CHANGES_OUTPUT=()
KEY_ENTRIES=()
INOTIFY_ENTRIES=()
SYSCTL_APPLY_COMMAND=()

# Check current values and prepare entries
for key in "${!limits[@]}"; do
  current=$(cat /proc/sys/$(echo "$key" | tr '.' '/'))
  desired="${limits[$key]%%:*}"
  threshold="${limits[$key]##*:}"

  if (( current < threshold )); then
    CHANGES_MADE=1
    CHANGES_OUTPUT+=("$key: $current -> $desired")
    line="$key=$desired"

    # Prepare for temporary sysctl -w
    SYSCTL_APPLY_COMMAND+=("$line")

    if [[ $key == kernel.keys.* ]]; then
      KEY_ENTRIES+=("$line")
    else
      INOTIFY_ENTRIES+=("$line")
    fi
  fi
done

if (( CHANGES_MADE == 0 )); then
  echo "No changes required. All values meet or exceed thresholds."
  rm -f "$TMP_FILE"
  exit 0
fi

# Show proposed changes
echo "The following sysctl parameter changes are proposed:"
for change in "${CHANGES_OUTPUT[@]}"; do
  echo "  - $change"
done

# Non-interactive: apply with sysctl -w and exit
if ! [ -t 0 ]; then
  echo "Non-interactive session detected. Applying changes temporarily (not persisted)..."
  sudo sysctl -w "${SYSCTL_APPLY_COMMAND[@]}"
  rm -f "$TMP_FILE"
  exit 0
fi

# Prompt user
echo -e "\nChoose how to apply these changes:"
echo "  [1] Persist and apply (recommended)"
echo "  [2] Apply temporarily only (until reboot)"
echo "  [3] Do not apply"

read -rp "Your choice (1/2/3): " choice
choice=${choice:-1}

if [[ "$choice" == "1" ]]; then
  # Clean low-value entries from sysctl.conf and other files (but not from our custom file)
  for key in "${!limits[@]}"; do
    key_escaped=$(echo "$key" | sed 's/\./\\./g')
    desired="${limits[$key]%%:*}"
    threshold="${limits[$key]##*:}"

    # Remove from /etc/sysctl.conf
    if grep -qE "^\s*${key_escaped}\s*=" /etc/sysctl.conf 2>/dev/null; then
      current_val=$(grep -E "^\s*${key_escaped}\s*=" /etc/sysctl.conf | head -n1 | cut -d= -f2 | tr -d ' ')
      if [[ "$current_val" =~ ^[0-9]+$ ]] && (( current_val < threshold )); then
        sudo sed -i "/^\s*${key_escaped}\s*=/d" /etc/sysctl.conf
      fi
    fi

    # Remove from other sysctl.d files
    find /etc/sysctl.d /usr/lib/sysctl.d -type f ! -name '99-custom-tuning.conf' 2>/dev/null | while read -r file; do
      if grep -qE "^\s*${key_escaped}\s*=" "$file"; then
        current_val=$(grep -E "^\s*${key_escaped}\s*=" "$file" | head -n1 | cut -d= -f2 | tr -d ' ')
        if [[ "$current_val" =~ ^[0-9]+$ ]] && (( current_val < threshold )); then
          sudo sed -i "/^\s*${key_escaped}\s*=/d" "$file"
        fi
      fi
    done
  done

  # Build new config
  {
    echo "# Custom sysctl tuning"
    for line in "${INOTIFY_ENTRIES[@]}"; do
      echo "$line"
    done
    if (( ${#KEY_ENTRIES[@]} > 0 )); then
      echo -e "\n# See https://github.com/moby/moby/issues/22865"
      for line in "${KEY_ENTRIES[@]}"; do
        echo "$line"
      done
    fi
  } > "$TMP_FILE"

  sudo mv "$TMP_FILE" "$SYSCTL_CONF_FILE"
  sudo chmod 644 "$SYSCTL_CONF_FILE"

  echo -e "\nApplying and persisting changes..."
  sudo sysctl --system >/dev/null
  for key in "${!limits[@]}"; do
    sysctl "$key"
  done

  echo "Changes persisted in $SYSCTL_CONF_FILE"
  exit 0

elif [[ "$choice" == "2" ]]; then
  echo "Applying changes temporarily with sysctl -w..."
  sudo sysctl -w "${SYSCTL_APPLY_COMMAND[@]}"
  exit 0

else
  echo -e "\n\033[1;31mWARNING:\033[0m"
  echo -e "\033[1;31mYou chose not to apply the recommended kernel parameter updates.\033[0m"
  echo -e "\033[1;31mThis may cause failures in Kind or CloudNativePG clusters due to insufficient kernel limits.\033[0m"
  read -rp "Are you sure you want to continue without applying these settings? (y/N): " confirm
  confirm=${confirm:-N}
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Re-running script to apply settings..."
    exec "$0"
  else
    echo "No changes applied."
    exit 1
  fi
fi
