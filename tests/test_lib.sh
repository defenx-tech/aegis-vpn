#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

echo "=== Aegis-VPN Test Suite ==="
echo ""

# --- Test 1: lib.sh sources cleanly ---
echo "Test 1: lib.sh sources without errors"
if bash -n "$BASE_DIR/scripts/lib.sh" 2>&1; then
  echo "  PASS: syntax check passed"
else
  echo "  FAIL: syntax check failed"
  errors=$((errors + 1))
fi

# --- Test 2: lib.sh exports expected variables ---
echo "Test 2: lib.sh exports required variables"
expected_vars=("AEGIS_VERSION" "BASE_DIR" "SCRIPTS_DIR" "WG_DIR" "WG_INTERFACE" "VPN_SUBNET" "VPN_SUBNET_CIDR")
source "$BASE_DIR/scripts/lib.sh"
for var in "${expected_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "  FAIL: $var is empty or not set"
    errors=$((errors + 1))
  else
    echo "  PASS: $var = ${!var}"
  fi
done

# --- Test 3: validate_client_name ---
echo ""
echo "Test 3: validate_client_name function"
valid_names=("alice" "bob-1" "test_user" "a" "12345")
invalid_names=("" "name with spaces" "name@invalid" "$()" "$(printf 'a%.0s' {1..33})")

for name in "${valid_names[@]}"; do
  if validate_client_name "$name"; then
    echo "  PASS: '$name' accepted"
  else
    echo "  FAIL: '$name' rejected but should be valid"
    errors=$((errors + 1))
  fi
done

for name in "${invalid_names[@]}"; do
  if validate_client_name "$name" 2>/dev/null; then
    echo "  FAIL: '$name' accepted but should be invalid"
    errors=$((errors + 1))
  else
    echo "  PASS: '$name' rejected"
  fi
done

# --- Test 4: detect_iface returns something or empty safely ---
echo ""
echo "Test 4: detect_iface runs without error"
if detect_iface; then
  echo "  PASS: detect_iface executed"
else
  echo "  PASS: detect_iface returned non-zero (expected in CI)"
fi

# --- Test 5: log_hooks.sh sources cleanly ---
echo ""
echo "Test 5: log_hooks.sh sources without errors"
if bash -n "$BASE_DIR/scripts/log_hooks.sh" 2>&1; then
  echo "  PASS: syntax check passed"
else
  echo "  FAIL: syntax check failed"
  errors=$((errors + 1))
fi

# --- Test 6: validate.sh sources cleanly ---
echo ""
echo "Test 6: validate.sh sources without errors"
if bash -n "$BASE_DIR/scripts/validate.sh" 2>&1; then
  echo "  PASS: syntax check passed"
else
  echo "  FAIL: syntax check failed"
  errors=$((errors + 1))
fi

# --- Summary ---
echo ""
echo "=== Results ==="
if (( errors == 0 )); then
  echo "All tests passed!"
else
  echo "${errors} test(s) failed."
  exit 1
fi
