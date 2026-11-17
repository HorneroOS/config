# Source to point hornero-fetch at the fixture state (tests and renders).
F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_STATE_HOME="$F/state" HORNERO_SYSTEM_PROFILE_FILE="$F/system-profile.json" \
  HORNERO_PACMAN_DB="$F/pacman" HORNERO_OS_RELEASE="$F/os-release"
