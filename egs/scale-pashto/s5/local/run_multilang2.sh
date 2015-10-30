#!/bin/bash
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.
system=nnet_ms_j_sp
use_gpu=true
train_stage=-99
stage=-1
num_jobs=50
# End configuration section
. ./utils/parse_options.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error
trap 'kill $(jobs -pr)' SIGINT SIGTERM EXIT

. ./cmd.sh
. ./path.sh


if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  parallel_opts="  --gpu 1"
  combine_num_threads=24
  combine_parallel_opts=" --gpu 0 --num-threads 24 "
  num_threads=1
  minibatch_size=512
  # the _a is in case I want to change the parameters.
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=24
  minibatch_size=128
  parallel_opts="--num-threads $num_threads"
  combine_parallel_opts="--num-threads 16"
fi

if [ $stage -le -1 ]; then
  for file in ./langs/A ./langs/B ./langs/T; do
    if [ ! -d $file  ]; then 
      echo "Directory/symlink $file does not exist"
      echo "The script will work only if you create appropriate"
      echo "corpus-specific system links into langs/"
      echo "Read the README.multilang"
      exit 1
    fi
  done

  for file in ./exp/ ./langs/A/exp/ ./langs/B/exp/ ./langs/T/exp/; do
    if [ ! -d $file/tri3_ali_sp  ]; then 
      echo "Directory $file/tri3_ali_sp does not exist"
      echo "That means you probably didn't run the script"
      echo "local/online/run_common.sh for the given corpora"
      exit 1
    fi
  done

  for file in ./ ./langs/A ./langs/B ./langs/T; do
    if [ ! -d $file/exp/nnet2_online/nnet_ms_j_sp/egs ]; then 
      echo "Directory $file/exp/nnet2_online/nnet_ms_j_sp/egs does not exist"
      echo "That means you probably didn't train the corpus specific network"
      if [ "$file" != "./" ] ; then
        echo "Please note that we do not really need the network itself -- we "
        echo "just need the egs, so feel free to cancel the training after"
        echo "the egs were generated"
      fi
      exit 1
    fi
  done

fi

if [ $stage -le 0 ]; then
  mkdir -p exp_multilang/$system/ 
  steps/nnet2/train_multilang2.sh --parallel-opts "$parallel_opts" \
    --num-threads $num_threads --minibatch-size $minibatch_size \
    --combine-parallel-opts "$combine_parallel_opts" \
    --combine-num-threads $combine_num_threads --unshare-layers "0:1:2"\
    --num-epochs 6 --mix-up "0 0 0 0" --num-jobs-nnet "10 8 8 8"\
    --cmd "$train_cmd"  --stage $train_stage \
    ./exp/tri3_ali_sp  ./exp/nnet2_online/nnet_ms_j_sp/egs\
    ./langs/A/exp/tri3_ali_sp ./langs/A/exp/nnet2_online/nnet_ms_j_sp/egs\
    ./langs/B/exp/tri3_ali_sp ./langs/B/exp/nnet2_online/nnet_ms_j_sp/egs\
    ./langs/T/exp/tri3_ali_sp ./langs/T/exp/nnet2_online/nnet_ms_j_sp/egs\
     exp/nnet2_online/$system/final.mdl  \
     exp_multilang/$system/
fi

if [ $stage -le 1 ] ; then
  utils/mkgraph.sh  data/langp_test exp_multilang/$system/0 \
    exp_multilang/$system/0/graphp
  utils/mkgraph.sh  ./langs/A/data/langp_test/ exp_multilang/$system/1 \
    exp_multilang/$system/1/graphp
  utils/mkgraph.sh  ./langs/B/data/langp_test/ exp_multilang/$system/2 \
    exp_multilang/$system/2/graphp
  utils/mkgraph.sh  ./langs/T/data/langp_test/ exp_multilang/$system/3 \
    exp_multilang/$system/3/graphp
fi

if [ $stage -le 2 ]; then
  mkdir -p exp_multilang/${system}_online/0/
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf\
    data/langp_test exp/nnet2_online/extractor \
    exp_multilang/$system/0/ exp_multilang/${system}_online/0/

  mkdir -p exp_multilang/${system}_online/1/
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf\
    ./langs/A/data/langp_test/  ./langs/A/exp/nnet2_online/extractor \
    exp_multilang/${system}/1/ exp_multilang/${system}_online/1/

  mkdir -p exp_multilang/${system}_online/2/
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf\
    ./langs/B/data/langp_test/  ./langs/B/exp/nnet2_online/extractor \
    exp_multilang/${system}/2/ exp_multilang/${system}_online/2/

  mkdir -p exp_multilang/${system}_online/3/
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf\
    ./langs/T/data/langp_test/  ./langs/T/exp/nnet2_online/extractor \
    exp_multilang/${system}/3/ exp_multilang/${system}_online/3/
fi

if [ $stage -le 3 ]; then
  for am in 0 1 2 3; do
    for decode_set in dev10h dev_appen dev_transtac ; do
      decode=exp_multilang/${system}_online/$am/decode_${decode_set}_utt_offline_prob
      mkdir -p $decode;
      steps/online/nnet2/decode.sh --config conf/decode.config\
        --cmd "$decode_cmd" --nj $num_jobs --per-utt true --online false \
        exp_multilang/${system}/$am/graphp \
        data/${decode_set}_hires  $decode | tee $decode/decode.log &
    done
    sleep 10s
  done
fi

wait



