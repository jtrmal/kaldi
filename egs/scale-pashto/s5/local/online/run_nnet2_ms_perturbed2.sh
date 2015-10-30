#!/bin/bash

# Copyright 2013  Johns Hopkins University (author: Daniel Povey)
#           2014  Tom Ko
#           2014  Vijay Peddinti
#           2015  Yenda Trmal
# Apache 2.0

# This scripts is a modified example of how to train a speed-perturbed
# system that is using ivectors (+I did some cleanup that could
# be backported back to the SWB scripts, eventually)
# It's based on the Vijay's SWB recipe

stage=6
train_stage=-10
use_gpu=true
corpus=none
config=nnet_ms_j_sp

. ./utils/parse_options.sh
name=$config

. ./cmd.sh
. ./path.sh

[ ! -f conf/nnet.conf ] && echo "File conf/nnet.conf does not exist" && exist 1
. ./conf/nnet.conf

set -e -o pipefail
if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  parallel_opts="  --gpu 1"
  combine_parallel_opts=" --gpu 0 --num-threads 8 "
  num_threads=1
  minibatch_size=512
  # the _a is in case I want to change the parameters.
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=12
  minibatch_size=128
  parallel_opts="--num-threads $num_threads"
  combine_parallel_opts="--num-threads 8"
fi

# Run the common stages of training, including training the iVector extractor
local/online/run_nnet2_common.sh --stage $stage || exit 1;

if [ $stage -le 6 ]; then
  # Although the nnet will be trained by high resolution data, we still
  # have to perturbe the normal data to get the alignment
  # _sp stands for speed-perturbed
  utils/perturb_data_dir_speed.sh 0.9 data/train data/local/train_sp_0.9
  utils/perturb_data_dir_speed.sh 1.0 data/train data/local/train_sp_1.0
  utils/perturb_data_dir_speed.sh 1.1 data/train data/local/train_sp_1.1
  utils/combine_data.sh --extra-files utt2uniq data/train_sp \
    data/local/train_sp_0.9 data/local/train_sp_1.0 data/local/train_sp_1.1
  rm -r data/local/train_sp_0.9 data/local/train_sp_1.0 data/local/train_sp_1.1

  mfccdir=param_perturbed
  for x in train_sp; do
    steps/make_plp_pitch.sh --cmd "$train_cmd" --nj 50 \
      data/$x exp/make_plp_pitch//$x $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/$x exp/make_plp//$x $mfccdir || exit 1;
    utils/fix_data_dir.sh data/train_sp
  done
fi

if [ $stage -le 7 ]; then
  #obtain the alignment of the perturbed data
  steps/align_fmllr.sh --nj 100 --cmd "$train_cmd" \
    data/train_sp data/langp/tri3/ exp/tri3 exp/tri3_ali_sp || exit 1
fi

if [ $stage -le 8 ]; then
  #Now perturb the high resolution daa
  utils/perturb_data_dir_speed.sh 0.9 data/train_hires \
    data/local/train_hires_sp_0.9
  utils/perturb_data_dir_speed.sh 1.0 data/train_hires \
    data/local/train_hires_sp_1.0
  utils/perturb_data_dir_speed.sh 1.1 data/train_hires \
    data/local/train_hires_sp_1.1

  utils/combine_data.sh --extra-files utt2uniq data/train_hires_sp \
      data/local/train_hires_sp_0.9 \
      data/local/train_hires_sp_1.0 \
      data/local/train_hires_sp_1.1

  rm -r data/local/train_hires_sp_0.9 \
      data/local/train_hires_sp_1.0 \
      data/local/train_hires_sp_1.1

  mfccdir=mfcc_perturbed
  for x in train_hires_sp; do
    steps/make_mfcc.sh --cmd "$train_cmd" --mfcc-config conf/mfcc_hires.conf \
      --nj 70 data/$x exp/make_hires/$x $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/$x exp/make_hires/$x $mfccdir || exit 1;
  done
  utils/fix_data_dir.sh data/train_hires_sp
fi

if [ $stage -le 9 ]; then
  # We extract iVectors on all the train data, which will be what we
  # train the system on.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 \
    data/train_hires_sp data/train_hires_sp_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
    data/train_hires_sp_max2 exp/nnet2_online/extractor \
    exp/nnet2_online/ivectors_train_hires_sp2 || exit 1;
fi

if [ $stage -le 10 ]; then
  steps/nnet2/train_multisplice_accel2.sh --stage $train_stage \
    --num-jobs-initial 3 --num-jobs-final 12 \
    --splice-indexes "$splice_indexes" --feat-type raw \
    --online-ivector-dir exp/nnet2_online/ivectors_train_hires_sp2 \
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
    data/train_hires_sp data/langp/tri3/ exp/tri3_ali_sp $dir  || exit 1;
fi

if [ $stage -le 11 ]; then
  # dump iVectors for the testing data.
  for decode_set in dev_transtac dev10h dev_appen; do
      [ ! -x data/${decode_set} ] && \
        echo "Skipping set data/$decode_set" && continue;

      [ -f exp/nnet2_online/ivectors_${decode_set}_hires/.done ] && continue;

      num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      [ $num_jobs -gt 200 ] && num_jobs=200;
      [ $num_jobs -le 0   ] && return 1;
      steps/online/nnet2/extract_ivectors_online.sh \
        --cmd "$train_cmd" --nj $num_jobs \
        data/${decode_set}_hires exp/nnet2_online/extractor \
        exp/nnet2_online/ivectors_${decode_set}_hires || exit 1;
  done
fi

if [ $stage -le 12 ]; then
  # this does offline decoding that should give about the same results as the
  # real online decoding (the one with --per-utt true)
  if [ ! -f data/lang_test/L.fst ] || [ ! -f data/lang_test/G.fst ] ; then
    echo "Decoding lang directory data/lang_test not created"
    exit 1
  fi

  utils/mkgraph.sh data/lang_test $dir $dir/graph
  for decode_set in decode_transtac dev10h dev_appen; do
      decode=$dir/decode_${decode_set}
      [ ! -x data/${decode_set} ] && \
        echo "Skipping set data/$decode_set" && continue
      [ -f  $decode/.done  ] && continue;
      (
        num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
        [ $num_jobs -gt 200 ] && num_jobs=200;
        [ $num_jobs -le 0   ] && return 1;
        steps/nnet2/decode.sh --config conf/decode.config \
          --nj $num_jobs --cmd "$decode_cmd" \
          $dir/graph data/${decode_set}_hires $decode
        touch $decode/.done
      ) &
  done
fi
wait

if [ $stage -le 13 ]; then
  # this does offline decoding that should give about the same results as the
  # real online decoding (the one with --per-utt true)
  [ ! -f data/langp_test/L.fst ] && cp -r data/langp/tri5/ data/langp_test
  [ ! -f data/langp_test/G.fst ] && cp -r data/lang_test/G.fst data/langp_test
  utils/mkgraph.sh data/langp_test $dir $dir/graphp
  for decode_set in decode_transtac dev10h dev_appen; do
      decode=$dir/decode_${decode_set}_prob
      [ ! -x data/${decode_set} ] && \
        echo "Skipping set data/$decode_set" && continue
      [ -f  $decode/.done  ] && continue;
      (
        num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
        [ $num_jobs -gt 200 ] && num_jobs=200;
        [ $num_jobs -le 0   ] && return 1;
        steps/nnet2/decode.sh --config conf/decode.config \
          --nj $num_jobs --cmd "$decode_cmd" \
          --online-ivector-dir exp/nnet2_online/ivectors_${decode_set}_hires \
          $dir/graphp data/${decode_set}_hires $decode
        touch $decode/.done
      ) &
  done
fi

if [ $stage -le 14 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh \
    --mfcc-config conf/mfcc_hires.conf \
    data/lang exp/nnet2_online/extractor "$dir" ${dir}_online || exit 1;
fi
wait;

if [ $stage -le 15 ]; then
  # do the actual online decoding with iVectors, carrying info forward from
  # previous utterances of the same speaker.
  for decode_set in dev_transtac dev10h dev_appen; do
    decode=${dir}_online/decode_${decode_set}_prob
    [ ! -x data/${decode_set} ] && \
      echo "Skipping set data/$decode_set" && continue
    [ -f  $decode/.done ] && continue;
    (
      num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      [ $num_jobs -gt 200 ] && num_jobs=200;
      [ $num_jobs -le 0   ] && return 1;
      steps/online/nnet2/decode.sh --config conf/decode.config \
        --cmd "$decode_cmd" --nj $num_jobs \
        $dir/graphp data/${decode_set}_hires $decode
      touch $decode/.done
    ) &
  done
fi
wait

if [ $stage -le 16 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information.
  for decode_set in dev_transtac dev10h dev_appen; do
    decode=${dir}_online/decode_${decode_set}_utt_prob
    [ ! -x data/${decode_set} ] && \
      echo "Skipping set data/$decode_set" && continue
    [ -f  $decode/.done ] && continue;
    (
      num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      [ $num_jobs -gt 200 ] && num_jobs=200;
      [ $num_jobs -le 0   ] && return 1;
      steps/online/nnet2/decode.sh --config conf/decode.config \
        --cmd "$decode_cmd" --nj $num_jobs --per-utt true \
        $dir/graphp data/${decode_set}_hires $decode
      touch $decode/.done
    )&
  done
fi

if [ $stage -le 17 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information, but looks to the end
  # of the utterance while computing the iVector (--online false)
  for decode_set in dev_transtac dev10h dev_appen; do
    decode=${dir}_online/decode_${decode_set}_utt_offline_prob
    [ ! -x data/${decode_set} ] && \
      echo "Skipping set data/$decode_set" && continue;
    [ -f  $decode/.done ] && continue;
    (
      num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      [ $num_jobs -gt 200 ] && num_jobs=200;
      [ $num_jobs -le 0   ] && return 1;
      mkdir -p $decode
      steps/online/nnet2/decode.sh --config conf/decode.config \
        --cmd "$decode_cmd" --nj $num_jobs --per-utt true --online false \
        $dir/graphp data/${decode_set}_hires  $decode > $decode/decode.log
      touch $decode/.done
    ) &
  done
fi

wait;
exit 0;
