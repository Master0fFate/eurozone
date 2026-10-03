#!/bin/bash
# Double-click on macOS, or run from Terminal. Keep the bundle files together.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
exec /bin/bash "$SCRIPT_DIR/eurozone" "$@"
