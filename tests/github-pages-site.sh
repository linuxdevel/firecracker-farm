#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_preview_page_exposes_variant_switcher() (
  local preview_path
  preview_path="$REPO_ROOT/docs/preview.html"

  [[ -f "$preview_path" ]] || fail "preview page missing"
  grep -q 'Refined Product' "$preview_path" || fail "preview page missing Refined Product option"
  grep -q 'Console Product' "$preview_path" || fail "preview page missing Console Product option"
  grep -q 'Editorial Product' "$preview_path" || fail "preview page missing Editorial Product option"
  grep -q 'class="site-header"' "$preview_path" || fail "preview page missing shared site header"
  grep -q 'class="trust-strip"' "$preview_path" || fail "preview page missing shared trust strip"
  grep -q 'id="features"' "$preview_path" || fail "preview page missing features section"
  grep -q 'id="security"' "$preview_path" || fail "preview page missing security section"
  grep -q 'id="architecture"' "$preview_path" || fail "preview page missing architecture section"
  grep -q 'id="quickstart"' "$preview_path" || fail "preview page missing quickstart section"
  grep -q 'id="openclaw"' "$preview_path" || fail "preview page missing use case section"
  grep -q 'id="roadmap"' "$preview_path" || fail "preview page missing roadmap section"
  grep -q 'id="faq"' "$preview_path" || fail "preview page missing faq section"
  if grep -q 'role="tablist"' "$preview_path"; then
    fail "preview page still uses tablist semantics for button group"
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

main() {
  test_preview_page_exposes_variant_switcher || return 1
  test_homepage_has_sticky_header_navigation || return 1
  test_homepage_surfaces_top_level_trust_strip || return 1
  test_homepage_copy_avoids_overclaim_and_counts_steps_correctly || return 1
  printf 'PASS: github pages site checks\n'
}

main "$@"
