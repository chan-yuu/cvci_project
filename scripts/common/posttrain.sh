#!/bin/bash
cd "$(dirname "$(realpath "${BASH_SOURCE:-$0}")")/../.."

export LEAD_OUTPUT_DIR_ROOT=$(dotenv LEAD_OUTPUT_DIR_ROOT)

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export NUMBA_NUM_THREADS=1 NUMBA_THREADING_LAYER=workqueue
export NCCL_P2P_DISABLE=1
export NCCL_P2P_LEVEL=NVL
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export LEAD_RUNTIME_TYPE_CHECKING=false

_initial_weights_file="$(ls -t "$LEAD_OUTPUT_DIR_ROOT"/local_training/pretrain/model_*.pth 2>/dev/null | head -n1 || true)"
if [[ -z "$_initial_weights_file" ]]; then
	echo "no model_*.pth under $LEAD_OUTPUT_DIR_ROOT/local_training/pretrain" >&2
	exit 1
fi

python3 src/lead/training/train.py \
	training.experiment.output_dir=$LEAD_OUTPUT_DIR_ROOT/local_training/posttrain \
	training.experiment.initial_weights_file=$_initial_weights_file \
	policy.transfuser.use_planning_decoder=true \
	training.data.read_from_cache_store=true \
	training.optimization.torch_compile_mode=max-autotune
