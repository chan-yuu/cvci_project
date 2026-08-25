#!/usr/bin/bash
# Single-GPU: 1 CARLA vs 8 CARLAs on Town01 short and Town05 Accident.
set -u

REPO="/vepfs-mlp2/xts001/400122/project/cvci_project"
PY="/vepfs-mlp2/xts001/400122/project/miniconda3/envs/cvci_project/bin/python"
OUT="$REPO/outputs/density_probe"
export DISPLAY="${DISPLAY:-:1}"
export PATH="$REPO/scripts/cli:$PATH"

SHORT="$REPO/src/lead/routes/data_routes/lead/noScenarios/short_route.xml"
ACCIDENT="$REPO/src/lead/routes/data_routes/lead/Accident/route_001761.xml"

PORTS=(2000 2100 2200 2300 2400 2500 2600 2700)
STREAMS=(2001 2101 2201 2301 2401 2501 2601 2701)
TM_PORTS=(18000 18100 18200 18300 18400 18500 18600 18700)

mkdir -p "$OUT"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT/master.log" >&2; }

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

start_carla_n() {
  local n="$1" i port stream
  for i in $(seq 0 $((n - 1))); do
    port="${PORTS[$i]}"
    stream="${STREAMS[$i]}"
    if wait_rpc "$port" 2; then
      log "CARLA already up on $port"
      continue
    fi
    log "start CARLA world=$port stream=$stream"
    setsid "$REPO/scripts/cli/start_carla" "$port" "$stream" \
      >"$OUT/carla_${port}.log" 2>&1 &
    echo $! >"$OUT/carla_${port}.pid"
    sleep 10
  done
  local ready=0
  for i in $(seq 0 $((n - 1))); do
    port="${PORTS[$i]}"
    if wait_rpc "$port" 90; then
      log "RPC OK $port"
      ready=$((ready + 1))
    else
      log "RPC FAIL $port"
      tail -n 20 "$OUT/carla_${port}.log" | tee -a "$OUT/master.log" || true
    fi
  done
  echo "$ready"
}

run_one() {
  local name="$1" route="$2" timeout_s="$3" port="$4" tm="$5"
  local root="$OUT/data/$name" eval_dir="$OUT/eval/$name"
  mkdir -p "$root" "$eval_dir"
  log "RUN $name port=$port tm=$tm route=$(basename "$route")"
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
  ) >"$OUT/${name}.log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    log "OK $name"
  else
    log "FAIL $name rc=$rc"
    tail -n 30 "$OUT/${name}.log" | tee -a "$OUT/master.log" || true
  fi
  return "$rc"
}

run_nway() {
  local prefix="$1" route="$2" timeout_s="$3" n="$4"
  local i port tm
  log "===== ${n}-way $prefix ====="
  for i in $(seq 0 $((n - 1))); do
    port="${PORTS[$i]}"
    tm="${TM_PORTS[$i]}"
    run_one "${prefix}_w${i}" "$route" "$timeout_s" "$port" "$tm" &
    echo $! >"$OUT/${prefix}_w${i}.pid"
    sleep 2
  done
  local failed=0
  for i in $(seq 0 $((n - 1))); do
    if wait "$(cat "$OUT/${prefix}_w${i}.pid")"; then
      :
    else
      failed=$((failed + 1))
    fi
  done
  log "${n}-way $prefix done failed=$failed"
  echo "$failed"
}

log "GPU $(nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader)"

log "===== 1-way baseline (1 CARLA) ====="
READY="$(start_carla_n 1)"
log "CARLA ready $READY/1  gpu=$(nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader)"
if [ "$READY" -lt 1 ]; then
  log "cannot start first CARLA"
  exit 2
fi

run_one "short_1way" "$SHORT" 300 2000 18000 || true
run_one "accident_1way" "$ACCIDENT" 900 2000 18000 || true

log "===== scale to 8 CARLA ====="
READY8="$(start_carla_n 8)"
log "CARLA ready $READY8/8  gpu=$(nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader)"
nvidia-smi | tee "$OUT/nvidia_smi_8idle.txt"
if [ "$READY8" -lt 8 ]; then
  log "only $READY8 CARLAs; abort 8-way"
  exit 3
fi

run_nway "short_8way" "$SHORT" 300 8
run_nway "accident_8way" "$ACCIDENT" 1200 8

log "===== summary ====="
for f in short_1way accident_1way short_8way_w{0..7} accident_8way_w{0..7}; do
  if [ -f "$OUT/${f}.log" ]; then
    sys=$(grep -oE 'System Time[[:space:]]+│[[:space:]]+[0-9.]+s' "$OUT/${f}.log" | tail -n 1 || true)
    game=$(grep -oE 'Game Time[[:space:]]+│[[:space:]]+[0-9.]+s' "$OUT/${f}.log" | tail -n 1 || true)
    rc=$(grep -oE 'RouteCompletionTest.*[0-9]+ %' "$OUT/${f}.log" | tail -n 1 || true)
    log "STAT $f | $sys | $game | $rc"
  fi
done
nvidia-smi | tee "$OUT/nvidia_smi_final.txt"
log "CARLAs left running. master log: $OUT/master.log"
