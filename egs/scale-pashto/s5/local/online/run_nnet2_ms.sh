#!/bin/bash

# This is the "multi-splice" version of the online-nnet2 training script.
# It's currently the best recipe.
# You'll notice that we splice over successively larger windows as we go deeper
# into the network.

. ./cmd.sh
set -e 
stage=7
train_stage=-10
use_gpu=true
# Original splice indices 
#splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2" 
# These are taken from the SWBD recipe
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2"

dir=exp/nnet2_online/nnet_ms_a
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_b
nnet_params=( --num-epochs 9 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_c
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2" 
nnet_params=( --num-epochs 9 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_d
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_e
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2" 
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)

set -e
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  parallel_opts=" --config conf/queue_jhu.conf --gpu 1"
  combine_parallel_opts=" --config conf/queue_jhu.conf --gpu 0 --num-threads 8 "
  num_threads=1
  minibatch_size=512
  # the _a is in case I want to change the parameters.
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=8
  minibatch_size=128
  parallel_opts="--num-threads $num_threads" 
  combine_parallel_opts="--num-threads 8"
fi

# Run the common stages of training, including training the iVector extractor
local/online/run_nnet2_common.sh --stage $stage || exit 1;

if [ $stage -le 7 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/pastho-scale-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

  # The size of the system is kept rather small
  # this is because we want it to be small enough that we could plausibly run it
  # in real-time.
  steps/nnet2/train_multisplice_accel2.sh --stage $train_stage \
    --num-jobs-initial 3 --num-jobs-final 12 \
    --splice-indexes "$splice_indexes" --feat-type raw \
    --online-ivector-dir exp/nnet2_online/ivectors_train_hires \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --combine-parallel-opts "$combine_parallel_opts" \
    --io-opts "--max-jobs-run 12" \
    --initial-effective-lrate 0.0015 --final-effective-lrate 0.00015 \
    --add-layers-period 1 \
    --cmd "$decode_cmd" \
    "${nnet_params[@]}" \
    data/train_hires data/lang exp/tri3 $dir  || exit 1;
fi

if [ $stage -le 8 ]; then
  # dump iVectors for the testing data.
  for decode_set in dev10h dev_appen; do
      [ -f exp/nnet2_online/ivectors_${decode_set}_hires/.done ] && continue;
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $num_jobs \
        data/${decode_set}_hires exp/nnet2_online/extractor exp/nnet2_online/ivectors_${decode_set}_hires || exit 1;
  done
fi

if [ $stage -le 9 ]; then
  # this does offline decoding that should give about the same results as the
  # real online decoding (the one with --per-utt true)
  [ ! -f data/langp_test/L.fst ] && cp -r data/langp/tri5/ data/langp_test
  [ ! -f data/langp_test/G.fst ] && local/arpa2G.sh data/srilm/lm.gz data/langp_test data/langp_test
  utils/mkgraph.sh data/langp_test $dir $dir/graph
  for decode_set in dev10h dev_appen ; do
      [ -f  $dir/decode_${decode_set} ] && continue;
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet2/decode.sh --nj $num_jobs --cmd "$decode_cmd" --config conf/decode.config \
        --online-ivector-dir exp/nnet2_online/ivectors_${decode_set}_hires \
        $dir/graph data/${decode_set}_hires $dir/decode_${decode_set} &
  done
fi

if [ $stage -le 10 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf \
    data/lang exp/nnet2_online/extractor "$dir" ${dir}_online || exit 1;
fi

if [ $stage -le 11 ]; then
  # do the actual online decoding with iVectors, carrying info forward from 
  # previous utterances of the same speaker.
  for decode_set in dev10h dev_appen; do
    [ -f  ${dir}_online/decode_${decode_set} ] && continue;
    num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
    steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
      $dir/graph data/${decode_set}_hires ${dir}_online/decode_${decode_set} &
  done
fi
wait
if [ $stage -le 12 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information.
  for decode_set in dev10h dev_appen; do
      [ -f  ${dir}_online/decode_${decode_set}_utt ] && continue;
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
        --per-utt true $dir/graph data/${decode_set}_hires ${dir}_online/decode_${decode_set}_utt &
  done
fi

if [ $stage -le 13 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information, but looks to the end
  # of the utterance while computing the iVector (--online false)
  for decode_set in  dev10h dev_appen; do
      [ -f  ${dir}_online/decode_${decode_set}_utt_offline ] && continue;
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
        --per-utt true --online false $dir/graph data/${decode_set}_hires \
          ${dir}_online/decode_${decode_set}_utt_offline &
  done
fi
wait;
exit 0;
