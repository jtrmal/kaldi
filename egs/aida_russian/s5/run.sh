#!/bin/bash
# Copyright (c) 2019, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
stage=0

# End configuration section
. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

AUDIO=/export/corpora/LDC/LDC2018E75/speech/
TRANSCRIPTS=/export/corpora/LDC/LDC2018E75/trans/

if [ $stage -le 0 ]; then
	local/prepare_data.sh $AUDIO $TRANSCRIPTS
	local/prepare_dict.sh data/train/text data/local/dict
  utils/prepare_lang.sh data/local/dict '<unk>' data/local/lang data/lang
  local/prepare_lm.sh '<unk>'
fi

if [ $stage -le 1 ] ; then
	steps/make_mfcc.sh --nj 16 --cmd "$cmd" data/train exp/make_mfcc/train mfcc
  utils/fix_data_dir.sh data/train
  steps/compute_cmvn_stats.sh data/train exp/make_mfcc/train_cmvn mfcc
  utils/fix_data_dir.sh data/train

	steps/make_mfcc.sh --nj 16 --cmd "$cmd" data/dev exp/make_mfcc/dev mfcc
  utils/fix_data_dir.sh data/dev
  steps/compute_cmvn_stats.sh data/dev exp/make_mfcc/dev_cmvn mfcc
  utils/fix_data_dir.sh data/dev
fi

if [ $stage -le 2 ] ; then
	utils/subset_data_dir.sh data/train 1000 data/train_sub1
fi

if [ $stage -le 3 ] ; then
  echo "Starting triphone training."
  steps/train_mono.sh --nj 8 --cmd "$cmd" data/train data/lang exp/mono
  echo "Monophone training done."
fi

nj=16
dev_nj=16
if [ $stage -le 4 ]; then
  ### Triphone
  echo "Starting triphone training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      data/train data/lang exp/mono exp/mono_ali
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$cmd"  \
      3200 30000 data/train data/lang exp/mono_ali exp/tri1
  echo "Triphone training done."

  (
  echo "Decoding the dev set using triphone models."
  #utils/mkgraph.sh data/lang_test  exp/tri1 exp/tri1/graph
  steps/decode.sh --nj $dev_nj --cmd "$cmd"  \
      exp/tri1/graph  data/dev exp/tri1/decode_dev
  echo "Triphone decoding done."
  ) &
fi

if [ $stage -le 5 ]; then
  ## Triphones + delta delta
  # Training
  echo "Starting (larger) triphone training."
  steps/align_si.sh --nj $nj --cmd "$cmd" --use-graphs true \
       data/train data/lang exp/tri1 exp/tri1_ali
  steps/train_deltas.sh --cmd "$cmd"  \
      4200 40000 data/train data/lang exp/tri1_ali exp/tri2a
  echo "Triphone (large) training done."

  (
  echo "Decoding the dev set using triphone(large) models."
  utils/mkgraph.sh data/lang_test exp/tri2a exp/tri2a/graph
  steps/decode.sh --nj $dev_nj --cmd "$cmd" \
      exp/tri2a/graph data/dev exp/tri2a/decode_dev
  ) &
fi

if [ $stage -le 6 ]; then
  ### Triphone + LDA and MLLT
  # Training
  echo "Starting LDA+MLLT training."
  steps/align_si.sh --nj $nj --cmd "$cmd"  \
      data/train data/lang exp/tri2a exp/tri2a_ali

  steps/train_lda_mllt.sh --cmd "$cmd"  \
    --splice-opts "--left-context=3 --right-context=3" \
    4200 40000 data/train data/lang exp/tri2a_ali exp/tri2b
  echo "LDA+MLLT training done."

  (
  echo "Decoding the dev set using LDA+MLLT models."
  utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph
  steps/decode.sh --nj $dev_nj --cmd "$cmd" \
      exp/tri2b/graph data/dev exp/tri2b/decode_dev
  ) &
fi


if [ $stage -le 7 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang exp/tri2b exp/tri2b_ali
  steps/train_sat.sh --cmd "$cmd" 4200 40000 \
      data/train data/lang exp/tri2b_ali exp/tri3b
  echo "SAT+FMLLR training done."

  (
  echo "Decoding the dev set using SAT+FMLLR models."
  utils/mkgraph.sh data/lang_test  exp/tri3b exp/tri3b/graph
  steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" \
      exp/tri3b/graph  data/dev exp/tri3b/decode_dev

  echo "SAT+FMLLR decoding done."
  ) &
fi

wait
