#!/usr/bin/bash
# Follow-up waves against already-running CARLAs on 2000/2100/2200/2300.
# Stagger client start so Traffic Manager find_free_port() does not collide.
set -u

REPO="/vepfs-mlp2/xts001/400122/project/cvci_project"
PY="/vepfs-mlp2/xts001/400122/project/miniconda3/envs/cvci_project/bin/python"
OUT="$REPO/outputs/density_probe"
export DISPLAY="${DISPLAY:-:1}"

PORTS=(2000 2100 2200 2300)
TM_PORTS=(18000 18100 18200 18300)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
sample_gpu() {
  nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader,nounits
}

run_wave() {
  local name="$1" route="$2" timeout_s="$3"
  local i port tm root eval_dir
  log "===== staggered wave $name ====="
  echo "$(date -Iseconds) wave=${name}_stagger gpu_before=$(sample_gpu)" | tee -a "$OUT/gpu_samples.csv" >&2

  for i in 0 1 2 3; do
    port="${PORTS[$i]}"
    tm="${TM_PORTS[$i]}"
    root="$OUT/data/${name}_stagger_w${i}"
    eval_dir="$OUT/eval/${name}_stagger_w${i}"
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
    ) >"$OUT/${name}_stagger_w${i}.log" 2>&1 &
    echo $! >"$OUT/${name}_stagger_w${i}.pid"
    log "worker $i pid=$(cat "$OUT/${name}_stagger_w${i}.pid") port=$port"
    sleep 4
  done

  local sampler_pid
  (
    while true; do
      echo "$(date -Iseconds) wave=${name}_stagger gpu=$(sample_gpu)" >>"$OUT/gpu_samples.csv"
      sleep 5
    done
  ) &
  sampler_pid=$!

  local failed=0
  for i in 0 1 2 3; do
    if wait "$(cat "$OUT/${name}_stagger_w${i}.pid")"; then
      log "worker $i $name OK"
    else
      log "worker $i $name FAILED exit=$?"
      failed=$((failed + 1))
      tail -n 25 "$OUT/${name}_stagger_w${i}.log" >&2 || true
    fi
  done
  kill "$sampler_pid" 2>/dev/null || true
  echo "$(date -Iseconds) wave=${name}_stagger gpu_after=$(sample_gpu) failed=$failed" \
    | tee -a "$OUT/gpu_samples.csv" >&2
  echo "$failed"
}

FAIL_SHORT="$(run_wave short_s \
  "$REPO/src/lead/routes/data_routes/lead/noScenarios/short_route.xml" \
  300)"

FAIL_T15="$(run_wave town15_s \
  "$REPO/src/lead/routes/data_routes/lead/noScenarios/route_000643.xml" \
  1200)"

log "staggered short failures: $FAIL_SHORT"
log "staggered Town15 failures: $FAIL_T15"
nvidia-smi | tee "$OUT/nvidia_smi_after_stagger.txt"
