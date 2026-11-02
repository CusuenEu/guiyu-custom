#!/bin/zsh
set -e
cd "${0:A:h}"
# Register the installed application, never a dist or temporary test copy.
python3 scripts/clean-finder-services.py --apply "$@"
