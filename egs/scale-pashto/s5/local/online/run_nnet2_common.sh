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

. cmd.sh


stage=0

set -e
. cmd.sh
. ./path.sh
. ./utils/parse_options.sh


if [ $stage -le 1 ]; then
  # Create high-resolution MFCC features (with 40 cepstra instead of 13).
  # this shows how you can split across multiple file-systems.  we'll split the
  # MFCC dir across multiple locations.  You might want to be careful here, if you
  # have multiple copies of Kaldi checked out and run the same recipe, not to let
  # them overwrite each other.
  mfccdir=mfcc
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $mfccdir/storage ]; then
    utils/create_split_dir.pl \
      /export/b0{1,2,3,4}/$USER/kaldi-data/egs/scale-pashto-$(date +'%m_%d_%H_%M')/s5/$mfccdir/storage $mfccdir/storage
  fi

  for datadir in train dev10h dev_appen dev_transtac; do
    if [ ! -x data/$datadir  ] ; then
      echo "Data directory data/${datadir} does not exist (ignoring)..." 
      continue;
    fi

    if [ ! -f data/${datadir}_hires/.done ] ; then
      utils/copy_data_dir.sh data/$datadir data/${datadir}_hires

      steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" --nj 70 data/${datadir}_hires \
        exp/make_hires/$datadir $mfccdir || exit 1;

      steps/compute_cmvn_stats.sh data/${datadir}_hires \
        exp/make_hires/$datadir $mfccdir || exit 1;

      touch data/${datadir}_hires/.done
    fi
  done
fi


if [ $stage -le 2 ]; then
  # Train a system just for its LDA+MLLT transform.  We use --num-iters 13
  # because after we get the transform (12th iter is the last), any further
  # training is pointless.
  steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 13 \
    --realign-iters "" --splice-opts "--left-context=3 --right-context=3" \
    5000 10000 data/train_hires data/langp/tri3/ \
    exp/tri3_ali exp/nnet2_online/tri4
fi


if [ $stage -le 3 ]; then
  mkdir -p exp/nnet2_online
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --num-frames 700000 \
    --nj 64 --num-threads 8  --parallel-opts " --num-threads 8" \
    data/train_hires 512 exp/nnet2_online/tri4 exp/nnet2_online/diag_ubm
fi

if [ $stage -le 4 ]; then
  # iVector extractors can in general be sensitive to the amount of data, but
  # this one has a fairly small dim (defaults to 100)
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" \
    --nj 10 --num-threads 2 --parallel-opts " --num-threads 8" \
    data/train_hires exp/nnet2_online/diag_ubm exp/nnet2_online/extractor
fi

if [ $stage -le 5 ]; then
  ivectordir=exp/nnet2_online/ivectors_train_hires
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $ivectordir/storage ]; then
    utils/create_split_dir.pl \
      /export/b0{1,2,3,4}/$USER/kaldi-data/egs/scale-pashto-$(date +'%m_%d_%H_%M')/s5/$ivectordir/storage $ivectordir/storage
  fi
  # We extract iVectors on all the train data, which will be what we train the
  # system on.  With --utts-per-spk-max 2, the script.  pairs the utterances
  # into twos, and treats each of these pairs as one speaker.  Note that these
  # are extracted 'online'.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 \
    data/train_hires data/train_hires_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
    data/train_hires_max2 exp/nnet2_online/extractor \
    exp/nnet2_online/ivectors_train_hires || exit 1;
fi



exit 0;
