#!/bin/bash
#
# Copyright 2014 Tanel Alumäe
# License: BSD 3-clause
#
# Example of how to train a duration model on tedlium data, using
# it's exp/nnet2_online/nnet_ms_sp as the baseline model. 
# You must train the baseline model and run the corresponding decoding
# experiments prior to running this script.
#
# Also, create a symlink: ln -s <kaldi-nnet-dur-model-dir>/dur-model
#
# Then run the script from the $KALDI_ROOT/egs/tedlium/s5 directory.
#
#

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)


nj=64           # Must be the same as when training the baseline model
decode_nj=8      # Must be the same as when decoding using the baseline 

stage=0 # resume training with --stage=N
pylearn_dir=~/tools/pylearn2
# Aggregating traing data for duration model needs more RAM than default in our SLURM cluster
aggregate_data_args="--mem 8g"

left_context=4
right_context=2

h0_dim=400
h1_dim=400

. utils/parse_options.sh || exit 1;

if [ $stage -le 0 ]; then
  # Align training data using a model in exp/nnet2_online/nnet_ms_sp_ali
  steps/nnet2/align.sh --nj $nj --cmd "$train_cmd" --use-gpu no  \
      --transform-dir "$transform_dir" --online-ivector-dir exp/nnet2_online/ivectors_train_hires/ \
      data/train_hires_sp data/lang exp/nnet2_online/nnet_ms_h_sp/ exp/nnet2_online/nnet_ms_h_sp_ali/ || exit 1
fi



if [ $stage -le 1 ]; then
  # Train a duration model based on alignments in exp/nnet2_online/nnet_ms_sp_ali
  ./dur-model/train_dur_model.sh --nj $nj --cmd "$cuda_cmd --gpu 0" --cuda-cmd "$cuda_cmd --mem 8g" --pylearn-dir $pylearn_dir --aggregate-data-args "$aggregate_data_args" \
    --stage 0 \
    --left-context $left_context --right-context $right_context \
    --language PASHTO \
    --h0-dim $h0_dim --h1-dim $h1_dim \
    data/train_hires_sp data/langp_test exp/nnet2_online/nnet_ms_h_sp_ali exp/dur_model_nnet_ms_h_sp || exit 1
fi



if [ $stage -le 2 ]; then
	# Decode dev/test data, try different duration model scales and phone insertion penalties.
	for decode_set in  dev10h dev_appen; do
  (
	  num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
	  # Rescore dev lattices using the duration model
	  ./dur-model/decode_dur_model.sh --cmd "$train_cmd" --cuda-cmd "$cuda_cmd --mem 8g" --nj $num_jobs \
		--language PASHTO --fillers "\<hes\>,\<noise\>,\<silence\>,\<v-noise\>" \
		--scales "0.2 0.3 0.4" --penalties "0.11 0.13 0.15 0.17 0.19 0.21" \
		--stage 0 \
		--left-context $left_context --right-context $right_context \
		data/langp_test \
		exp/nnet2_online/nnet_ms_h_sp/graph/ \
		data/${decode_set}_hires \
		exp/nnet2_online/nnet_ms_h_sp_online/decode_${decode_set}_utt_offline \
		exp/dur_model_nnet_ms_h_sp \
		exp/nnet2_online/nnet_ms_h_sp_online/decode_${decode_set}_utt_offline.dur-rescore || exit 1;
  ) &
	done
fi
wait
#%WER 10.9 | 1155 27512 | 90.8 6.9 2.3 1.8 11.0 78.6 | -0.351 | exp/nnet2_online/nnet_ms_sp_online/decode_test_utt_offline.rescore.dur-rescore/s0.2_p0.11/score_10_0.0/ctm.filt.filt.sys
