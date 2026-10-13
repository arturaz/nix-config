#!/usr/bin/env bash
# Updates the flake inputs (nixpkgs) and deploys the result; commit flake.lock afterwards.
# Usage: ./upgrade.sh <name> [switch|boot|test|dry-activate|build]   (default: switch)
# Same arguments and env vars as deploy.sh, which does the work (with UPDATE=1).
set -euo pipefail

cd "$(dirname "$0")"

UPDATE=1 exec ./deploy.sh "$@"
