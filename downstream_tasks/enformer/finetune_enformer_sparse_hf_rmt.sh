#!/usr/bin/env bash
set -e
# change dir to the repository root
cd ../..

CUBLAS_WORKSPACE_CONFIG=:4096:2
CUDA_LAUNCH_BLOCKING=1

TASK=enformer

# BASE_MODEL=bert_base_512_lastln_t2t_1000G_bs256_lr_1e-04_linear_fp16
# BASE_MODEL=bert_base_512_t2t_1000G_multi_from_1M_bs256_lr_1e-04_fp16
# BASE_MODEL=bert_base_512_t2t_1000G_bs256_lr_1e-04_fp16
BASE_MODEL=hf_bigbird_base_4096_t2t_1000G_bs256_FusedAdam_linear_lr_1e-04_wd_0.0_2x8_enformer/run_2
# BASE_CKPTS=(model_500000 model_1000000 model_2000000)
BASE_CKPTS=(model_best)
TOKENIZER=./data/tokenizers/t2t_1000h_multi_32k/
# CONFIG=./data/configs/L12-H768-A12-V32k-preln-lastln.json
CONFIG=./data/configs/hf_bigbird_L12-H768-A12-V32k-L4096.json

# SCHEDULER=constant_with_warmup
SCHEDULER=cosine
ITERS=200000
PATIENCE=40
LR=1e-04
OPT=AdamW
WD=0.0

TBS=128
BS=1

INPUT_SEQ_LEN=16356
BINS_PER_SAMPLE=608
# RMT
INPUT_SIZE=4096  # segment length
MAX_N_SEGMENTS=4
MAX_BINS_PER_SEGMENT=152
MEMORY_SIZE=5
BPTT=-1

AUGS=1
MIX_LENGTH=0.5

HOME_PATH=/home/jovyan
DATA_PATH=${HOME_PATH}/data
PRETRAINED_PATH=${HOME_PATH}/t5-experiments/runs

for N in 1
do
for (( i=0; i<${#BASE_CKPTS[@]}; i++ ))
do
for LR in 5e-05
do
for SCHEDULER in cosine #constant_with_warmup
do
BASE_CKPT=${BASE_CKPTS[i]}
rmt_params=rmt_seglen_${INPUT_SIZE}_len${INPUT_SEQ_LEN}_maxnsegm_${MAX_N_SEGMENTS}_bins${BINS_PER_SAMPLE}_binspersegm_${MAX_BINS_PER_SEGMENT}_msz_${MEMORY_SIZE}_bptt${BPTT}_mix_${MIX_LENGTH}_augs_${AUGS}
MODEL_PATH=./runs/${TASK}/${BASE_MODEL}/${BASE_CKPT}/${rmt_params}_lr${LR}_${OPT}_${SCHEDULER}_wd${WD}_p${PATIENCE}_bs${TBS}_it${ITERS}/run_${N}
#--backbone_checkpoint ${PRETRAINED_PATH}/${BASE_MODEL}/${BASE_CKPT}.pth \
echo $MODEL_PATH
horovodrun --gloo -np $NP python -m downstream_tasks.enformer.run_enformer_finetuning_rmt \
        --data_path ${DATA_PATH}/downstream_tasks/enformer/human/h5/human_train.h5 \
        --valid_data_path ${DATA_PATH}/downstream_tasks/enformer/human/h5/human_valid.h5 \
        --test_data_path ${DATA_PATH}/downstream_tasks/enformer/human/h5/human_test.h5 \
        --model_path ${MODEL_PATH} \
        --tokenizer $TOKENIZER --model_cfg $CONFIG \
        --backbone_cls downstream_tasks.enformer.enformer_model:BigBirdForEnformer \
        --init_checkpoint ${HOME_PATH}/dnalm/runs/enformer/hf_bigbird_base_4096_t2t_1000G_bs256_FusedAdam_linear_lr_1e-04_wd_0.0_2x8_enformer/run_2/model_best/rmt_seglen_4096_len8178_maxnsegm_2_bins304_binspersegm_152_msz_5_bptt-1_mix_0.5_augs_1_lr5e-05_AdamW_cosine_wd0.0_p40_bs128_it200000/run_1/model_best.pth \
        --model_cls src.gena_lm.modeling_rmt:RMTEncoderForEnformer \
        --input_seq_len $INPUT_SEQ_LEN --bins_per_sample $BINS_PER_SAMPLE --data_n_workers 2 \
        --input_size $INPUT_SIZE \
        --num_mem_tokens $MEMORY_SIZE \
        --max_n_segments $MAX_N_SEGMENTS \
        --max_bins_per_segment $MAX_BINS_PER_SEGMENT \
        --mixed_length_ratio $MIX_LENGTH \
        --use_augs $AUGS \
        --backbone_trainable \
        --bptt_depth -1 \
        --n_valid_samples 2000 \
        --iters $ITERS \
        --batch_size $BS --gradient_accumulation_steps $(($TBS/($BS*$NP))) \
        --lr $LR --lr_scheduler $SCHEDULER --num_warmup_steps 5000 \
        --optimizer ${OPT} --weight_decay $WD \
        --reset_lr --reset_optimizer --reset_iteration \
        --log_interval 250 --valid_interval 500 --early_stopping_patience $PATIENCE \
        --optimize_metric pearson_corr_enformer_statefull --optimize_mode max --save_best \
        --seed $(($N+100*$MAX_N_SEGMENTS+42))
#find $MODEL_PATH | grep .pth | xargs -l rm -rf
done
done
done
done
echo "done"
