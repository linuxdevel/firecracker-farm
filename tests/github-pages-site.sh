#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_public_preview_artifacts_are_removed() (
  local preview_path
  preview_path="$REPO_ROOT/docs/preview.html"

  if [[ -f "$preview_path" ]]; then
    fail "public preview page still exists in docs output"
  fi
)

test_homepage_has_sticky_header_navigation() (
  local index_path
  index_path="$REPO_ROOT/docs/index.html"

  grep -q 'class="site-header"' "$index_path" || fail "homepage missing site header"
  grep -q 'href="#features"' "$index_path" || fail "homepage missing features anchor"
  grep -q 'href="#security"' "$index_path" || fail "homepage missing security anchor"
  grep -q 'href="#architecture"' "$index_path" || fail "homepage missing architecture anchor"
  grep -q 'href="#quickstart"' "$index_path" || fail "homepage missing quickstart anchor"
  grep -q 'href="#openclaw"' "$index_path" || fail "homepage missing openclaw anchor"
  grep -q 'href="#roadmap"' "$index_path" || fail "homepage missing roadmap anchor"
  grep -q 'href="#faq"' "$index_path" || fail "homepage missing faq anchor"
)

test_homepage_surfaces_top_level_trust_strip() (
  local index_path
  index_path="$REPO_ROOT/docs/index.html"

  grep -q 'class="trust-strip"' "$index_path" || fail "homepage missing trust strip"
  grep -q 'KVM isolated' "$index_path" || fail "homepage missing KVM isolated proof point"
  grep -q 'Persistent rootfs' "$index_path" || fail "homepage missing persistent rootfs proof point"
  grep -q 'LAN bridged' "$index_path" || fail "homepage missing LAN bridged proof point"
  grep -q 'systemd managed' "$index_path" || fail "homepage missing systemd managed proof point"
)

test_homepage_copy_avoids_overclaim_and_counts_steps_correctly() (
  local index_path
  index_path="$REPO_ROOT/docs/index.html"

  grep -q 'From zero to a running microVM in five steps\.' "$index_path" || fail "homepage quickstart subtitle does not match rendered step count"
  if grep -q 'Even malicious code cannot cross the KVM hardware boundary\.' "$index_path"; then
    fail "homepage still makes an absolute KVM isolation claim"
  fi
)

test_live_homepage_stays_single_direction() (
  local index_path
  index_path="$REPO_ROOT/docs/index.html"

  if grep -q 'Compare Visual Directions' "$index_path"; then
    fail "homepage still links to the design comparison flow"
  fi
)

main() {
  test_public_preview_artifacts_are_removed || return 1
  test_homepage_has_sticky_header_navigation || return 1
  test_homepage_surfaces_top_level_trust_strip || return 1
  test_homepage_copy_avoids_overclaim_and_counts_steps_correctly || return 1
  test_live_homepage_stays_single_direction || return 1
  printf 'PASS: github pages site checks\n'
}

main "$@"
