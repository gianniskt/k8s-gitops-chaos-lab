#!/usr/bin/env bash
# compute_node_workers.sh
# Detects logical CPU cores per node and updates the chaos schedule's workers field
# Usage: ./scripts/compute_node_workers.sh [--use-max] [--manifest path]

set -euo pipefail
MANIFEST_DEFAULT="gitops/chaos-experiments/chaos-schedules.yaml"
MANIFEST=${2:-$MANIFEST_DEFAULT}
USE_MAX=false

if [ "${1:-}" = "--use-max" ]; then
  USE_MAX=true
fi

# Find the node CPU cores (logical CPUs) average across schedulable nodes
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "kubectl cannot reach cluster; please ensure kubectl is configured"
  exit 1
fi

# Get cpu allocatable for each schedulable node and convert to cores
mapfile -t cores_arr < <(kubectl get nodes -o jsonpath='{range .items[?(@.spec.unschedulable!=true)]}{.metadata.name} {.status.allocatable.cpu}\n{end}' | awk '{print $2}')

if [ ${#cores_arr[@]} -eq 0 ]; then
  echo "No schedulable nodes found"
  exit 1
fi

# Convert cpu quantities like "16" or "16000m" to numeric cores
convert_cpu_to_cores() {
  local cpu=$1
  if [[ "$cpu" == *m ]]; then
    # milli CPU
    echo "$(( ${cpu%m} / 1000 ))"
  else
    echo "$cpu"
  fi
}

total=0
count=0
for cpu_q in "${cores_arr[@]}"; do
  cores=$(convert_cpu_to_cores "$cpu_q")
  total=$((total + cores))
  count=$((count + 1))
done

avg=$(( total / count ))

# If --use-max, set workers to max cores found instead of average
if [ "$USE_MAX" = true ]; then
  max=0
  for cpu_q in "${cores_arr[@]}"; do
    cores=$(convert_cpu_to_cores "$cpu_q")
    if [ $cores -gt $max ]; then
      max=$cores
    fi
  done
  workers=$max
else
  workers=$avg
fi

if [ -z "$workers" ] || [ "$workers" -lt 1 ]; then
  workers=1
fi

# Patch the manifest: replace the workers: line under the node-cpu-stress-schedule block
if [ ! -f "$MANIFEST" ]; then
  echo "Manifest $MANIFEST not found"
  exit 1
fi

# Use awk to find the node-cpu-stress-schedule block and replace workers: N
awk -v w="$workers" '
  BEGIN{inside=0}
  /metadata:/ && /name: node-cpu-stress-schedule/ {inside=1}
  {
    if(inside==1 && /workers:/){ sub(/workers:[[:space:]]*[0-9]+/,"workers: " w)
      inside=0
    }
    print
  }' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo "Updated workers to $workers in $MANIFEST"
exit 0
