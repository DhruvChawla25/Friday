#!/usr/bin/env bash
# Copyright (c) 2026 Dhruv Chawla · SPDX-License-Identifier: MIT
# Fails if Friday's source uses networking APIs or requests a network entitlement.
# Friday must stay fully offline: see docs/PRIVACY.md.
set -euo pipefail
cd "$(dirname "$0")/.."

pattern='URLSession|URLRequest|NWConnection|NWPathMonitor|import Network|import WebKit|WKWebView|CFStream|CFNetwork|Socket'
if grep -rnE "$pattern" Friday/; then
  echo "✘ Networking API found in Friday/ (see above). Friday must not use the network." >&2
  exit 1
fi
if grep -q "com.apple.security.network" project.yml Friday/App/Friday.entitlements; then
  echo "✘ A network entitlement is present. Remove it." >&2
  exit 1
fi
echo "✔ No networking APIs or network entitlements."
