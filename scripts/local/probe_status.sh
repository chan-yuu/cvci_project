#!/usr/bin/bash
# Live density-probe status. Usage: watch -n 5 scripts/local/probe_status.sh
OUT="/vepfs-mlp2/xts001/400122/project/cvci_project/outputs/density_probe"
echo "===== $(date -Iseconds) ====="
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,power.draw --format=csv
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)  cores=$(nproc)  carlas=$(pgrep -c -f CarlaUE4-Linux-Shipping || echo 0)"
echo
echo "----- workers (latest Step) -----"
shopt -s nullglob
for f in "$OUT"/short_1way.log "$OUT"/accident_1way.log "$OUT"/*_w{0..7}.log "$OUT"/master.log; do
  [ -f "$f" ] || continue
  [[ "$(basename "$f")" == master.log ]] && continue
  base=$(basename "$f" .log)
  step=$(grep -oE 'Step: [0-9]+, Time per step: [0-9.]+ ms' "$f" | tail -n 1)
  done=$(grep -c 'RouteCompletionTest' "$f" 2>/dev/null || true)
  fail=$(grep -c 'bind error\|rpc::timeout\|exited with non-zero' "$f" 2>/dev/null || true)
  mark="run"
  [ "${done:-0}" -gt 0 ] && mark="done"
  [ "${fail:-0}" -gt 0 ] && [ "$mark" != "done" ] && mark="fail"
  printf '%-28s %-4s %s\n' "$base" "$mark" "${step:-(no step yet)}"
done
echo
echo "----- data on disk -----"
du -sh "$OUT"/data/* 2>/dev/null | sort -h | tail -n 20
echo
echo "total: $(du -sh "$OUT" | awk '{print $1}')"
echo "logs: $OUT/*.log"
echo "data: $OUT/data/"
