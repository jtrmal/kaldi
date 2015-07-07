#!/bin/bash

# Copyright 2013  Johns Hopkins University (author: Daniel Povey)
#           2014  Tom Ko
#           2014  Vijay Peddinti
# Apache 2.0

# This example script demonstrates how speed perturbation of the data helps the nnet training in the SWB setup.

stage=6
train_stage=-10
use_gpu=true
# Original splice indices 
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
# These are taken from the SWBD recipe
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2"
dir=exp/nnet2_online/nnet_ms_a
nnet_params=( --num-epochs 3 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350 --mix-up 12000)
dir=exp/nnet2_online/nnet_ms_d_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_e_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3500 --pnorm-output-dim 350)
dir=exp/nnet2_online/nnet_ms_f_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 4500 --pnorm-output-dim 450)
dir=exp/nnet2_online/nnet_ms_g_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 3000 --pnorm-output-dim 300)
dir=exp/nnet2_online/nnet_ms_h_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 2500 --pnorm-output-dim 250)
#dir=exp/nnet2_online/nnet_ms_i_sp
#splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
#nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 2000 --pnorm-output-dim 200)
dir=exp/nnet2_online/nnet_ms_j_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 1500 --pnorm-output-dim 150)
dir=exp/nnet2_online/nnet_ms_k_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 1000 --pnorm-output-dim 100)
dir=exp/nnet2_online/nnet_ms_h_09_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 2502 --pnorm-output-dim 278)
dir=exp/nnet2_online/nnet_ms_h_07_sp
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2"
nnet_params=( --num-epochs 6 --num-hidden-layers 6 --pnorm-input-dim 2499 --pnorm-output-dim 357)

. ./cmd.sh
. ./path.sh 
. ./utils/parse_options.sh

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
  #Although the nnet will be trained by high resolution data, we still have to perturbe the normal data to get the alignment
  # _sp stands for speed-perturbed
  utils/perturb_data_dir_speed.sh 0.9 data/train data/local/train_sp_0.9
  utils/perturb_data_dir_speed.sh 1.0 data/train data/local/train_sp_1.0
  utils/perturb_data_dir_speed.sh 1.1 data/train data/local/train_sp_1.1
  utils/combine_data.sh --extra-files utt2uniq data/train_sp data/local/train_sp_0.9 data/local/train_sp_1.0 data/local/train_sp_1.1
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
    data/train_sp data/lang exp/tri3 exp/tri3_ali_sp || exit 1
fi

if [ $stage -le 8 ]; then
  #Now perturb the high resolution daa
  utils/perturb_data_dir_speed.sh 0.9 data/train_hires data/local/train_hires_sp_0.9
  utils/perturb_data_dir_speed.sh 1.0 data/train_hires data/local/train_hires_sp_1.0
  utils/perturb_data_dir_speed.sh 1.1 data/train_hires data/local/train_hires_sp_1.1
  utils/combine_data.sh --extra-files utt2uniq data/train_hires_sp data/local/train_hires_sp_0.9 data/local/train_hires_sp_1.0 data/local/train_hires_sp_1.1
  rm -r data/local/train_hires_sp_0.9 data/local/train_hires_sp_1.0 data/local/train_hires_sp_1.1

  mfccdir=mfcc_perturbed
  for x in train_hires_sp; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 70 --mfcc-config conf/mfcc_hires.conf \
      data/$x exp/make_hires/$x $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/$x exp/make_hires/$x $mfccdir || exit 1;
  done
  utils/fix_data_dir.sh data/train_hires_sp
fi

if [ $stage -le 9 ]; then
  # We extract iVectors on all the train data, which will be what we
  # train the system on.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 data/train_hires_sp data/train_hires_sp_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
    data/train_hires_sp_max2 exp/nnet2_online/extractor exp/nnet2_online/ivectors_train_hires_sp2 || exit 1;
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
    data/train_hires_sp data/lang exp/tri3_ali_sp $dir  || exit 1;
fi

if [ $stage -le 11 ]; then
  # dump iVectors for the testing data.
  for decode_set in dev10h dev_appen; do
      [ -f exp/nnet2_online/ivectors_${decode_set}_hires/.done ] && continue;
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $num_jobs \
        data/${decode_set}_hires exp/nnet2_online/extractor exp/nnet2_online/ivectors_${decode_set}_hires || exit 1;
  done
fi

if [ $stage -le 12 ]; then
  # this does offline decoding that should give about the same results as the
  # real online decoding (the one with --per-utt true)
  [ ! -f data/langp_test/L.fst ] && cp -r data/langp/tri5/ data/langp_test
  [ ! -f data/langp_test/G.fst ] && local/arpa2G.sh data/srilm/lm.gz data/langp_test data/langp_test
  utils/mkgraph.sh data/langp_test $dir $dir/graph
  for decode_set in dev10h dev_appen; do
      [ -f  $dir/decode_${decode_set}/.done  ] && continue;
      (
        num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
        steps/nnet2/decode.sh --nj $num_jobs --cmd "$decode_cmd" --config conf/decode.config \
          --online-ivector-dir exp/nnet2_online/ivectors_${decode_set}_hires \
          $dir/graph data/${decode_set}_hires $dir/decode_${decode_set}
        touch $dir/decode_${decode_set}/.done  
      ) &
  done
fi

if [ $stage -le 13 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf \
    data/lang exp/nnet2_online/extractor "$dir" ${dir}_online || exit 1;
fi
wait;

if [ $stage -le 14 ]; then
  # do the actual online decoding with iVectors, carrying info forward from 
  # previous utterances of the same speaker.
  for decode_set in dev10h dev_appen; do
    [ -f  ${dir}_online/decode_${decode_set}/.done ] && continue;
    (
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
        $dir/graph data/${decode_set}_hires ${dir}_online/decode_${decode_set}
      touch ${dir}_online/decode_${decode_set}/.done 
    ) &
  done
fi
wait

if [ $stage -le 15 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information.
  for decode_set in dev10h dev_appen; do
      [ -f  ${dir}_online/decode_${decode_set}_utt/.done ] && continue;
      (
        num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
        steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
          --per-utt true $dir/graph data/${decode_set}_hires ${dir}_online/decode_${decode_set}_utt 
        touch ${dir}_online/decode_${decode_set}_utt/.done 
      )&
  done
fi

if [ $stage -le 16 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information, but looks to the end
  # of the utterance while computing the iVector (--online false)
  for decode_set in  dev10h dev_appen; do
      [ -f  ${dir}_online/decode_${decode_set}_utt_offline/.done ] && continue;
      (
        num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
        steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $num_jobs \
          --per-utt true --online false $dir/graph data/${decode_set}_hires \
            ${dir}_online/decode_${decode_set}_utt_offline 
        touch ${dir}_online/decode_${decode_set}_utt_offline/.done 
      ) &
  done
fi
wait;
exit 0;
