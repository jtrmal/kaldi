#!/bin/bash
# Copyright (c) 2019, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin nfiguration section.
nj=16
dev_nj=6
stage=0
# End configuration section
. ./utils/parse_options.sh

# initialization PATH
. ./path.sh  || die "File path.sh expected";
. ./cmd.sh  || die "File cmd.sh expected to exist"
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

if [ $stage -le 8 ]; then
  echo "Starting SGMM training."
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
      data/train data/lang exp/tri3b exp/tri3b_ali

  steps/train_ubm.sh  --cmd "$train_cmd"  \
      600 data/train data/lang exp/tri3b_ali exp/ubm5b2

  steps/train_sgmm2.sh  --cmd "$train_cmd"  \
       5200 12000 data/train data/lang exp/tri3b_ali exp/ubm5b2/final.ubm exp/sgmm2_5b2
  echo "SGMM training done."

  (
  echo "Decoding the dev set using SGMM models"
  # Graph compilation
  utils/mkgraph.sh data/lang_test exp/sgmm2_5b2 exp/sgmm2_5b2/graph

  steps/decode_sgmm2.sh --nj $dev_nj --cmd "$decode_cmd" \
      --transform-dir exp/tri3b/decode_dev \
      exp/sgmm2_5b2/graph data/dev exp/sgmm2_5b2/decode_dev

  steps/lmrescore_const_arpa.sh  --cmd "$decode_cmd" \
      data/lang_test/ data/lang_test_fg/ data/dev \
      exp/sgmm2_5b2/decode_dev exp/sgmm2_5b2/decode_dev.rescored

  echo "SGMM decoding done."
  ) &
  # this is extremely computationally and memory-wise expensive, run with caution
  # or just don't run at all, there is no practical benefit
  #-(
  #-echo "Decoding the dev set using SGMM models and LargeLM"
  #-# Graph compilation
  #-utils/mkgraph.sh data/lang_test_fg/ exp/sgmm2_5b2 exp/sgmm2_5b2/graph.big

  #-steps/decode_sgmm2.sh --nj $dev_nj --cmd "$decode_cmd" \
  #-    --transform-dir exp/tri3b/decode_dev \
  #-    exp/sgmm2_5b2/graph.big data/dev exp/sgmm2_5b2/decode_dev.big
  #-echo "SGMM decoding done."
  #-) &
fi

wait;


