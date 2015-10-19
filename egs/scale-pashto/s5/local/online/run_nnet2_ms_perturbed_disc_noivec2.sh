#!/bin/bash


# This script does discriminative training on top of the online, multi-splice
# system trained in run_nnet2_ms.sh.
# note: this relies on having a cluster that has plenty of CPUs as well as GPUs,
# since the lattice generation runs in about real-time, so takes of the order of
# 1000 hours of CPU time.
#
# Note: rather than using any features we have dumped on disk, this script
# regenerates them from the wav data three times-- when we do lattice
# generation, numerator alignment and discriminative training.  This made the
# script easier to write and more generic, because we don't have to know where
# the features and the iVectors are, but of course it's a little inefficient.
# The time taken is dominated by the lattice generation anyway, so this isn't
# a huge deal.


stage=0
train_stage=-10
use_gpu=true
srcdir=exp/nnet2_online/nnet_ms_j_sp
criterion=smbr
drop_frames=true  # only matters for MMI anyway.
boost=0.1
effective_lrate=0.000005
num_jobs_nnet=6
train_stage=-10 # can be used to start training in the middle.
decode_start_epoch=2 # can be used to avoid decoding all epochs, e.g. if we decided to run more.
num_epochs=4
num_nj_denlats=32
cleanup=false  # run with --cleanup true --stage 6 to clean up (remove large things like denlats,
               # alignments and degs).

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

set -e

if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  parallel_opts="--gpu 1 "
  num_threads=1
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=16
  parallel_opts="--num-threads $num_threads"
fi

if [ ! -f ${srcdir}/final.mdl ]; then
  echo "$0: expected ${srcdir}/final.mdl to exist; first run run_nnet2_ms.sh."
  exit 1;
fi


if [ $stage -le 1 ]; then
  nj=$num_nj_denlats  # this doesn't really affect anything strongly, except the num-jobs for one of
         # the phases of get_egs_discriminative2.sh below.
  num_threads_denlats=6
  subsplit=$nj
  steps/nnet2/make_denlats.sh --cmd "$decode_cmd --mem 1G --num-threads $num_threads_denlats " \
      --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
     data/train_hires_sp/ data/lang $srcdir ${srcdir}_denlats || exit 1;

  # the command below is a more generic, but slower, way to do it.
  #steps/online/nnet2/make_denlats.sh --cmd "$decode_cmd -l mem_free=1G,ram_free=1G -pe smp $num_threads_denlats" \
  #    --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
  #   data/train_hires data/lang ${srcdir}_online ${srcdir}_denlats || exit 1;

fi

if [ $stage -le 2 ]; then
  # hardcode no-GPU for alignment, although you could use GPU [you wouldn't
  # get excellent GPU utilization though.]
  nj=$num_nj_denlats
  use_gpu=no
  gpu_opts=

  steps/nnet2/align.sh  --cmd "$decode_cmd $gpu_opts" --use-gpu "$use_gpu" \
     --nj $nj data/train_hires_sp/ data/lang $srcdir ${srcdir}_ali || exit 1;

  # the command below is a more generic, but slower, way to do it.
  # steps/online/nnet2/align.sh --cmd "$decode_cmd $gpu_opts" --use-gpu "$use_gpu" \
  #    --nj $nj data/train_hires data/lang ${srcdir}_online ${srcdir}_ali || exit 1;
fi


if [ $stage -le 3 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${srcdir}_degs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{1,2,5,6}/$USER/kaldi-data/egs/scale-pashto-$(date +'%m_%d_%H_%M')/s5/${srcdir}_degs/storage ${srcdir}_degs/storage
  fi
  # have a higher maximum num-jobs if
  if [ -d ${srcdir}_degs/storage ]; then max_jobs=20; else max_jobs=5; fi

  if [[ $(hostname -f) == *.cm.cluster  ]] ; then
    max_jobs=15
  fi

  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd --max-jobs-run $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
     data/train_hires_sp/ data/lang ${srcdir}{_ali,_denlats,/final.mdl,_degs} || exit 1;

  # the command below is a more generic, but slower, way to do it.
  #steps/online/nnet2/get_egs_discriminative2.sh \
  #  --cmd "$decode_cmd -tc $max_jobs" \
  #  --criterion $criterion --drop-frames $drop_frames \
  #   data/train_hires data/lang ${srcdir}{_ali,_denlats,_online,_degs} || exit 1;
fi

outputdir=${srcdir}_${criterion}_${effective_lrate}
if [ "$criterion" == "mmi" ];  then
  outputdir=${srcdir}_${criterion}_${effective_lrate}_b${boost}
fi
if [ $stage -le 4 ]; then

  steps/nnet2/train_discriminative2.sh --cmd "$decode_cmd" \
    --parallel-opts "$parallel_opts" \
    --stage $train_stage --boost ${boost} \
    --effective-lrate $effective_lrate \
    --criterion $criterion --drop-frames $drop_frames \
    --num-epochs $num_epochs --adjust-priors true \
    --num-jobs-nnet 6 --num-threads $num_threads \
      ${srcdir}_degs $outputdir || exit 1;
fi

if [ $stage -le 5 ]; then
  dir=$outputdir
  for epoch in `seq 1 4` ; do
    for decode_set in decode_transtac dev10h dev_appen; do
        decode=$dir/decode_${decode_set}_prob_epoch$epoch
        [ ! -x data/${decode_set} ] && \
          echo "Skipping set data/$decode_set" && continue
        [ -f  $decode/.done  ] && continue;
        (
          num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
          [ $num_jobs -gt 50 ] && num_jobs=50;
          [ $num_jobs -le 0   ] && return 1;
          steps/nnet2/decode.sh --config conf/decode.config \
            --nj $num_jobs --cmd "$decode_cmd" --iter epoch$epoch\
            $srcdir/graphp data/${decode_set}_hires $decode
          touch $decode/.done
        ) &
    done
  done
  wait
  for decode_set in dev10h dev_appen; do
    cat $dir/decode*${decode_set}*/scoring_kaldi/best_wer | sort -k2n
  done
fi

if [ $stage -le 6 ] && $cleanup; then
  # if you run with "--cleanup true --stage 6" you can clean up.
  rm ${srcdir}_denlats/lat.*.gz || true
  rm ${srcdir}_ali/ali.*.gz || true
  steps/nnet2/remove_egs.sh ${srcdir}_degs || true
fi


exit 0;
