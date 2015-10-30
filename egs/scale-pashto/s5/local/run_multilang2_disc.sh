#!/bin/bash
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.
system=nnet_ms_j_sp
use_gpu=true
train_stage=-99
stage=-99
num_jobs=50
num_nj_denlats=50
drop_frames=true
effective_lrate=0.0000005
criterion=smbr
boost=0.1
num_epochs=6
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

ali_system=exp_multilang/${system}_disc2_multi_ali
den_system=exp_multilang/${system}_disc2_multi_denlats
degs_system=exp_multilang/${system}_disc2_multi_degs
disc_system=exp_multilang/${system}_disc2_multi_${criterion}_${effective_lrate}
srcdir=exp_multilang/$system
#srcdir=exp/nnet2_online/$system

if [ ! -f ${srcdir}/0/final.mdl ]; then
  echo "$0: expected ${srcdir}/0/final.mdl to exist; first run run_nnet2_ms.sh."
  exit 1;
fi

rm -f $den_system/*/.error
if [ $stage -le 1 ]; then
  nj=$num_nj_denlats   num_threads_denlats=6
  subsplit=$nj
  (
  steps/nnet2/make_denlats.sh \
    --cmd "$decode_cmd --mem 1G --num-threads $num_threads_denlats " \
    --online-ivector-dir exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
    data/train_hires_sp data/langp_test/ $srcdir/0 $den_system/0 || touch $den_system/0/.error
  )&

  (
  steps/nnet2/make_denlats.sh \
    --cmd "$decode_cmd --mem 1G --num-threads $num_threads_denlats " \
    --online-ivector-dir langs/A/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
    langs/A/data/train_hires_sp langs/A/data/langp_test $srcdir/1 $den_system/1 || touch $den_system/1/.error
  )&

  (
  steps/nnet2/make_denlats.sh \
    --cmd "$decode_cmd --mem 1G --num-threads $num_threads_denlats " \
    --online-ivector-dir langs/B/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
    langs/B/data/train_hires_sp langs/B/data/langp_test $srcdir/2 $den_system/2 || touch $den_system/2/.error
  )&

  (
  steps/nnet2/make_denlats.sh \
    --cmd "$decode_cmd --mem 1G --num-threads $num_threads_denlats " \
    --online-ivector-dir langs/T/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
    langs/T/data/train_hires_sp langs/T/data/langp_test $srcdir/3 $den_system/3  || touch $den_system/3/.error
  )&
fi
wait

if [ -f $den_system/0/.error ] || [ -f $den_system/1/.error ] || [ -f $den_system/2/.error ] || [ -f $den_system/3/.error ] ; then
  exit 1
fi

rm -f $ali_system/*/.error
if [ $stage -le 2 ]; then
  # hardcode no-GPU for alignment, although you could use GPU [you wouldn't
  # get excellent GPU utilization though.]
  nj=$num_nj_denlats
  use_gpu=yes
  gpu_opts=

  (
  steps/nnet2/align.sh  --cmd "$cuda_cmd $gpu_opts" --use-gpu "$use_gpu" \
    --online-ivector-dir exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj data/train_hires_sp/ data/langp_test/ $srcdir/0 $ali_system/0 || touch $ali_system/0/.error
  )&

  (
  steps/nnet2/align.sh  --cmd "$cuda_cmd $gpu_opts" --use-gpu "$use_gpu" \
    --online-ivector-dir langs/A/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj langs/A/data/train_hires_sp/ langs/A/data/langp_test $srcdir/1 $ali_system/1  || touch $ali_system/1/.error
  )&

  (
  steps/nnet2/align.sh  --cmd "$cuda_cmd $gpu_opts" --use-gpu "$use_gpu" \
    --online-ivector-dir langs/B/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj langs/B/data/train_hires_sp/ langs/B/data/langp_test $srcdir/2 $ali_system/2  || touch $ali_system/2/.error
  )&

  (
  steps/nnet2/align.sh  --cmd "$cuda_cmd $gpu_opts" --use-gpu "$use_gpu" \
    --online-ivector-dir langs/T/exp/nnet2_online/ivectors_train_hires_sp2/ \
    --nj $nj langs/T/data/train_hires_sp/ langs/T/data/langp_test $srcdir/3 $ali_system/3  || touch $ali_system/3/.error
  )&
fi
wait

if [ -f $ali_system/0/.error ] || [ -f $ali_system/1/.error ] || [ -f $ali_system/2/.error ] || [ -f $ali_system/3/.error ] ; then
  exit 1
fi

rm -f $degs_system/*/.error
if [ $stage -le 3 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${srcdir}_degs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{1,2,5,6}/$USER/kaldi-data/egs/scale-pashto-$(date +'%m_%d_%H_%M')/s5/${srcdir}_degs/storage ${srcdir}_degs/storage
  fi
  # have a higher maximum num-jobs if
  if [ -d ${srcdir}_degs/storage ]; then max_jobs=20; else max_jobs=5; fi

  if [[ $(hostname -f) == *.cm.cluster  ]] ; then
    max_jobs=$num_jobs
  fi

  (
  [ -f $degs_system/0/.done ] && exit ;
  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd --max-jobs-run $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
    --online-ivector-dir exp/nnet2_online/ivectors_train_hires_sp2/ \
     data/train_hires_sp/ data/langp_test/ \
     $ali_system/0 $den_system/0 $ali_system/0/final.mdl $degs_system/0 || touch $degs_system/0/.error

  [ ! -f $degs_system/0/.error ] && touch $degs_system/0/.done
  ) &

  [ ! -f $degs_system/0/.done ] &&  sleep 60m

  (
  [ -f $degs_system/1/.done ] && exit ;
  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd --max-jobs-run $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
    --online-ivector-dir langs/A/exp/nnet2_online/ivectors_train_hires_sp2/ \
    langs/A/data/train_hires_sp/ langs/A/data/langp_test \
    $ali_system/1 $den_system/1 $ali_system/1/final.mdl $degs_system/1 || touch $degs_system/1/.error

  [ ! -f $degs_system/1/.error ] && touch $degs_system/1/.done
  ) &

  [ ! -f $degs_system/1/.done ] &&  sleep 60m

  (
  [ -f $degs_system/2/.done ] && exit ;
  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd --max-jobs-run $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
    --online-ivector-dir langs/B/exp/nnet2_online/ivectors_train_hires_sp2/ \
    langs/B/data/train_hires_sp/ langs/B/data/langp_test \
    $ali_system/2 $den_system/2 $ali_system/2/final.mdl $degs_system/2 || touch $degs_system/2/.error

  [ ! -f $degs_system/2/.error ] && touch $degs_system/2/.done
  ) &

  [ ! -f $degs_system/2/.done ] &&  sleep 60m

  (
  [ -f $degs_system/3/.done ] && exit ;
  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd --max-jobs-run $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
    --online-ivector-dir langs/T/exp/nnet2_online/ivectors_train_hires_sp2/ \
    langs/T/data/train_hires_sp/ langs/T/data/langp_test \
    $ali_system/3 $den_system/3 $ali_system/3/final.mdl $degs_system/3 || touch $degs_system/3/.error

  [ ! -f $degs_system/3/.error ] && touch $degs_system/3/.done
  ) &

fi
wait

if [ -f $degs_system/0/.error ] || [ -f $degs_system/1/.error ] || [ -f $degs_system/2/.error ] || [ -f $degs_system/3/.error ] ; then
  exit 1
fi

if [ $stage -le 4 ]; then
  steps/nnet2/train_discriminative_multilang2.sh --num-jobs-nnet "8 4 4 4"\
    --cmd "$train_cmd" --parallel-opts "--gpu 1 " --drop-frames true \
    --criterion smbr --num-threads 1  --boost $boost --unshare-layers "0:1:2"\
    --effective-lrate "$effective_lrate" --num-epochs $num_epochs \
    --cleanup false --adjust-priors true --stage $train_stage \
    $degs_system/0 $degs_system/1 $degs_system/2 $degs_system/3 \
    $disc_system

fi

if [ $stage -le 5 ] ; then
  test -d ${disc_system}/0/graphp && rm -rf ${disc_system}/0/graphp
  test -d ${disc_system}/1/graphp && rm -rf ${disc_system}/1/graphp
  test -d ${disc_system}/2/graphp && rm -rf ${disc_system}/2/graphp
  test -d ${disc_system}/3/graphp && rm -rf ${disc_system}/3/graphp
  cp -r $srcdir/0/graphp ${disc_system}/0
  cp -r $srcdir/1/graphp ${disc_system}/1
  cp -r $srcdir/2/graphp ${disc_system}/2
  cp -r $srcdir/3/graphp ${disc_system}/3
fi

if [ $stage -le 6 ]; then
  root=`pwd`
  (cd $disc_system/0/; ln -s $root/exp_multilang/${system}_online/0/conf .)
  (cd $disc_system/1/; ln -s $root/exp_multilang/${system}_online/1/conf .)
  (cd $disc_system/2/; ln -s $root/exp_multilang/${system}_online/2/conf .)
  (cd $disc_system/3/; ln -s $root/exp_multilang/${system}_online/3/conf .)
fi

if [ $stage -le 7 ]; then
  for iter in $(seq 1 $num_epochs); do
    for am in 0 1 2 3; do
      for decode_set in dev10h dev_appen dev_transtac ; do
        decode=${disc_system}/$am/decode_${decode_set}_utt_offline_prob_epoch${iter}
        mkdir -p $decode;
        test -f $decode/scoring_kaldi/best_wer || \
        steps/online/nnet2/decode.sh --config conf/decode.config \
          --iter epoch${iter} --cmd "$decode_cmd" --nj $num_jobs \
          --per-utt true --online false \
          $disc_system/$am/graphp data/${decode_set}_hires  $decode | tee $decode/decode.log &
      done
      sleep 20s
    done
    sleep 10s
  done
fi

wait


if [ $stage -le 8 ]; then
  for iter in $(seq 1 $num_epochs); do
    for am in 0 1 2 3; do
      for decode_set in dev10h dev_appen dev_transtac ; do
        decode=${disc_system}/$am/decode_${decode_set}_utt_offline_prob_epoch${iter}.adj
        mkdir -p $decode;
        test -f $decode/scoring_kaldi/best_wer || \
        steps/online/nnet2/decode.sh --config conf/decode.config \
          --iter epoch${iter}.adj --cmd "$decode_cmd" --nj $num_jobs \
          --per-utt true --online false \
          $disc_system/$am/graphp data/${decode_set}_hires  $decode | tee $decode/decode.log &
      done
      sleep 20s
    done
    sleep 10s
  done
fi

wait

echo "Done OK."

