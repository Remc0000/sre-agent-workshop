#!/usr/bin/env bash
# Pre-workshop validation — checks that required tools and config are in place.
set -euo pipefail

PASS="✅"
FAIL="❌"
WARN="⚠️ "
errors=0

header() { echo -e "\n── $1 ──"; }
ok()     { echo "  ${PASS} $1"; }
fail()   { echo "  ${FAIL} $1"; errors=$((errors + 1)); }
warn()   { echo "  ${WARN} $1"; }

echo "========================================"
echo "  SRE Agent Workshop — Setup Check"
echo "========================================"

# ── Azure CLI ──────────────────────────────
header "Azure CLI"
if command -v az &>/dev/null; then
  ok "az CLI installed ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'unknown'))"
else
  fail "az CLI not found — install: https://aka.ms/install-azure-cli"
fi

# ── Azure login ────────────────────────────
header "Azure Authentication"
if az account show &>/dev/null; then
  ACCOUNT=$(az account show --query '{name:name, id:id}' -o tsv 2>/dev/null)
  ok "Logged in — ${ACCOUNT}"
else
  fail "Not logged in — run: az login"
fi

# ── Azure subscription ────────────────────
header "Azure Subscription"
if az account show &>/dev/null; then
  SUB_ID=$(az account show --query id -o tsv)
  ok "Subscription: ${SUB_ID}"
else
  fail "No active subscription"
fi

# ── kubectl ────────────────────────────────
header "kubectl"
if command -v kubectl &>/dev/null; then
  ok "kubectl installed ($(kubectl version --client --short 2>/dev/null || kubectl version --client -o yaml 2>/dev/null | head -1))"
else
  fail "kubectl not found — install: https://kubernetes.io/docs/tasks/tools/"
fi

# ── GitHub CLI (optional) ─────────────────
header "GitHub CLI"
if command -v gh &>/dev/null; then
  ok "gh CLI installed ($(gh --version | head -1))"
else
  warn "gh CLI not found (optional) — install: https://cli.github.com"
fi

# ── Region check ──────────────────────────
header "Supported Regions"
echo "  The workshop supports: eastus2, swedencentral, australiaeast"
echo "  Set your preferred region when running the deploy-infra workflow."

# ── Summary ───────────────────────────────
echo ""
echo "========================================"
if [ "$errors" -eq 0 ]; then
  echo "  All checks passed — you're ready! 🚀"
else
  echo "  ${errors} issue(s) found — please fix before starting."
fi
echo "========================================"
exit "$errors"
