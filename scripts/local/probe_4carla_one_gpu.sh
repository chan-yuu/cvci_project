#!/usr/bin/bash
# Probe: can 4 CARLA + expert collectors share one A100?
# Reuses an already-running instance on :2000 if RPC is up.
set -u

REPO="/vepfs-mlp2/xts001/400122/project/cvci_project"
PY="/vepfs-mlp2/xts001/400122/project/miniconda3/envs/cvci_project/bin/python"
OUT="$REPO/outputs/density_probe"
export DISPLAY="${DISPLAY:-:1}"
export PATH="$REPO/scripts/cli:$PATH"

PORTS=(2000 2100 2200 2300)
STREAMS=(2001 2101 2201 2301)
TM_PORTS=(8000 8100 8200 8300)

mkdir -p "$OUT"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

sample_gpu() {
  nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,power.draw --format=csv,noheader,nounits
}

count_carla() {
  pgrep -c -f 'CarlaUE4-Linux-Shipping' || true
}

wait_rpc() {
  local port="$1" timeout_s="${2:-90}"
  local i
  for i in $(seq 1 "$timeout_s"); do
    if "$PY" "$REPO/scripts/cli/test_carla_connection" "$port"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_missing_carlas() {
  local i port stream
  for i in 0 1 2 3; do
    port="${PORTS[$i]}"
    stream="${STREAMS[$i]}"
    if wait_rpc "$port" 2; then
      log "CARLA already serving on $port"
      continue
    fi
    log "Starting CARLA world=$port stream=$stream"
    setsid "$REPO/scripts/cli/start_carla" "$port" "$stream" \
      >"$OUT/carla_${port}.log" 2>&1 &
    echo $! >"$OUT/carla_${port}.pid"
    sleep 12
  done

  local ready=0
  for port in "${PORTS[@]}"; do
    if wait_rpc "$port" 90; then
      log "RPC OK on $port"
      ready=$((ready + 1))
    else
      log "RPC FAIL on $port — last 30 lines:"
      tail -n 30 "$OUT/carla_${port}.log" 2>/dev/null || true
    fi
  done
  echo "$ready"
}

run_wave() {
  local name="$1" route="$2" timeout_s="$3"
  local i port tm root eval_dir
  log "===== wave $name : 4-way same route ====="
  log "route=$route timeout=${timeout_s}s"
  echo "$(date -Iseconds) wave=$name gpu_before=$(sample_gpu) carlas=$(count_carla)" \
    | tee -a "$OUT/gpu_samples.csv" >&2

  for i in 0 1 2 3; do
    port="${PORTS[$i]}"
    tm="${TM_PORTS[$i]}"
    root="$OUT/data/${name}_w${i}"
    eval_dir="$OUT/eval/${name}_w${i}"
    mkdir -p "$root" "$eval_dir"
    (
      unset CARLA_ROOT
      export PY123D_DATA_ROOT="$root"
      export LEAD_OUTPUT_DIR_ROOT="$eval_dir"
      cd "$REPO"
      exec "$PY" -u -m lead --expert \
        --routes "$route" \
        --port "$port" \
        --traffic-manager-port "$tm" \
        --timeout "$timeout_s" \
        --output-dir "$eval_dir"
    ) >"$OUT/${name}_w${i}.log" 2>&1 &
    echo $! >"$OUT/${name}_w${i}.pid"
    log "worker $i pid=$(cat "$OUT/${name}_w${i}.pid") port=$port tm=$tm"
    # Evaluator ignores --traffic-manager-port and find_free_port() races
    # if four clients probe at once. Stagger so TM binds don't collide.
    sleep 3
  done

  local sampler_pid
  (
    while true; do
      echo "$(date -Iseconds) wave=$name gpu=$(sample_gpu) carlas=$(count_carla)" >>"$OUT/gpu_samples.csv"
      sleep 5
    done
  ) &
  sampler_pid=$!

  local failed=0
  for i in 0 1 2 3; do
    if wait "$(cat "$OUT/${name}_w${i}.pid")"; then
      log "worker $i $name OK"
    else
      log "worker $i $name FAILED exit=$?"
      failed=$((failed + 1))
      tail -n 40 "$OUT/${name}_w${i}.log" || true
    fi
  done
  kill "$sampler_pid" 2>/dev/null || true
  echo "$(date -Iseconds) wave=$name gpu_after=$(sample_gpu) failed=$failed" \
    | tee -a "$OUT/gpu_samples.csv" >&2
  echo "$failed"
}

# --- boot ---
log "GPU before extra CARLAs: $(sample_gpu)  existing=$(count_carla)"
READY="$(start_missing_carlas)"
log "CARLA RPC ready: $READY / 4   gpu=$(sample_gpu)  procs=$(count_carla)"
if [ "$READY" -lt 4 ]; then
  log "Could not bring up 4 CARLAs; aborting collection waves."
  exit 2
fi

nvidia-smi | tee "$OUT/nvidia_smi_4idle.txt"

# --- waves: short, medium Accident, heavy Town15 ---
FAIL_SHORT="$(run_wave short \
  "$REPO/src/lead/routes/data_routes/lead/noScenarios/short_route.xml" \
  300)"

FAIL_ACC="$(run_wave accident_town05 \
  "$REPO/src/lead/routes/data_routes/lead/Accident/route_001761.xml" \
  900)"

FAIL_T15="$(run_wave town15 \
  "$REPO/src/lead/routes/data_routes/lead/noScenarios/route_000643.xml" \
  1200)"

log "===== summary ====="
log "short failures: $FAIL_SHORT"
log "Town05 Accident failures: $FAIL_ACC"
log "Town15 failures: $FAIL_T15"
log "GPU final: $(sample_gpu)  carlas=$(count_carla)"
nvidia-smi | tee "$OUT/nvidia_smi_final.txt"

# Keep CARLAs up so nvtop can be inspected; do not auto-kill.
log "CARLA instances left running. Stop with: pkill -f CarlaUE4-Linux-Shipping"
