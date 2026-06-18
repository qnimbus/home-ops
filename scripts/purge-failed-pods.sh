#!/usr/bin/env bash
# Deletes Failed pods whose owning controller (Deployment/DaemonSet/StatefulSet) is currently
# healthy (desired == ready). Defaults to dry-run; pass --delete to actually remove pods.
set -Eeuo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()   { error "$*"; exit 1; }

check_tools() {
  local -a missing=()
  for tool in "$@"; do
    command -v "${tool}" &>/dev/null || missing+=("${tool}")
  done
  (( ${#missing[@]} == 0 )) || die "Missing tools: ${missing[*]} — run: mise install"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

DRY_RUN=true
for arg in "$@"; do
  case "$arg" in
    --delete) DRY_RUN=false ;;
    --help|-h)
      printf "\n${BOLD}Usage:${NC} %s [--delete]\n\n" "$0"
      printf "  (no flag)   Dry-run: report which Failed pods would be deleted\n"
      printf "  --delete    Actually delete Failed pods whose owner is healthy\n\n"
      printf "A controller is considered healthy when:\n"
      printf "  Deployment   — Available condition is True\n"
      printf "  DaemonSet    — numberReady == desiredNumberScheduled\n"
      printf "  StatefulSet  — readyReplicas == replicas\n\n"
      exit 0 ;;
    *) die "Unknown argument: $arg (use --delete to enable live mode)" ;;
  esac
done

check_tools kubectl jq

if [[ $DRY_RUN == true ]]; then
  printf "\n${YELLOW}${BOLD}DRY-RUN mode${NC} — pass --delete to actually remove pods\n\n"
else
  printf "\n${RED}${BOLD}LIVE mode${NC} — will delete Failed pods with healthy owners\n\n"
fi

# ── Health checks ─────────────────────────────────────────────────────────────

is_deployment_healthy() {
  local ns="$1" name="$2"
  local status
  status=$(kubectl get deployment -n "$ns" "$name" \
           -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
  [[ $status == True ]]
}

is_daemonset_healthy() {
  local ns="$1" name="$2"
  local chk r d
  chk=$(kubectl get daemonset -n "$ns" "$name" \
        -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null)
  r="${chk%/*}"; d="${chk#*/}"
  [[ -n $d && $d -gt 0 && "${r:-0}" -eq "$d" ]]
}

is_statefulset_healthy() {
  local ns="$1" name="$2"
  local chk r d
  chk=$(kubectl get statefulset -n "$ns" "$name" \
        -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null)
  r="${chk%/*}"; d="${chk#*/}"
  [[ -n $d && $d -gt 0 && "${r:-0}" -eq "$d" ]]
}

# ── Main loop ─────────────────────────────────────────────────────────────────

deleted=0
skipped=0
errors=0

while IFS=$'\t' read -r ns pod kind owner; do
  # Walk ReplicaSet → Deployment (pods are owned by RS, not Deployment directly)
  if [[ $kind == ReplicaSet ]]; then
    ref=$(kubectl get rs -n "$ns" "$owner" \
          -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}' \
          2>/dev/null || true)
    kind="${ref%/*}"; owner="${ref#*/}"
  fi

  # Evaluate controller health
  healthy=false
  case "$kind" in
    Deployment)   is_deployment_healthy   "$ns" "$owner" && healthy=true || true ;;
    DaemonSet)    is_daemonset_healthy    "$ns" "$owner" && healthy=true || true ;;
    StatefulSet)  is_statefulset_healthy  "$ns" "$owner" && healthy=true || true ;;
    *)
      warn "Skipping $ns/$pod — unhandled owner kind '${kind:-<none>}'"
      (( skipped++ )) || true
      continue ;;
  esac

  if [[ $healthy == true ]]; then
    if [[ $DRY_RUN == true ]]; then
      printf "${CYAN}[DRY-RUN]${NC}  would delete  %-50s  ← %s/%s\n" "$ns/$pod" "$kind" "$owner"
    else
      if kubectl delete pod -n "$ns" "$pod" --wait=false 2>/dev/null; then
        printf "${GREEN}[DELETED]${NC}              %-50s  ← %s/%s\n" "$ns/$pod" "$kind" "$owner"
        (( deleted++ )) || true
      else
        printf "${RED}[ERROR]${NC}    delete failed  %-50s\n" "$ns/$pod"
        (( errors++ )) || true
      fi
    fi
    [[ $DRY_RUN == true ]] && (( deleted++ )) || true
  else
    printf "${YELLOW}[SKIP]${NC}     owner not healthy  %-38s  ← %s/%s\n" "$ns/$pod" "$kind" "$owner"
    (( skipped++ )) || true
  fi

done < <(kubectl get pods -A --field-selector=status.phase=Failed -o json \
  | jq -r '.items[] | [
      .metadata.namespace,
      .metadata.name,
      (.metadata.ownerReferences[0].kind // "Orphan"),
      (.metadata.ownerReferences[0].name // "")
    ] | @tsv')

# ── Summary ───────────────────────────────────────────────────────────────────

printf "\n${BOLD}Summary:${NC}"
if [[ $DRY_RUN == true ]]; then
  printf "  %d pod(s) would be deleted,  %d skipped\n\n" "$deleted" "$skipped"
  (( deleted > 0 )) && info "Re-run with --delete to apply." || info "Nothing to do."
else
  printf "  %d deleted,  %d skipped,  %d errors\n\n" "$deleted" "$skipped" "$errors"
  (( errors > 0 )) && warn "Some deletes failed — check output above."
fi
