#!/bin/bash

###############################################################################
#                      Universal Acoustic Models
###############################################################################
#
# This script sets up data from the BABEL Languages to be used to train a
# universal acoustic models. By default, it leaves out 4 languages:
#
#  - 201_haitian: Many results numbers with which to compare for this language.
#  - 307_amharic: Left out to repeat LORELEI experiments.
#  - 107_vietnamese: Left out to test performance on a tonal language.
#  - 404_georgian: The final evaluation language from BABEL.
#
# which are used to test the trained universal acoustic models. The script
# consists of the following steps:
#   1. Prepare data directories
#   2. Standardize the lexicons
#   3. Training
###############################################################################
set -e
set -o pipefail
. ./path.sh
. ./lang.conf
. ./cmd.sh
. ./conf/common_vars.sh
###############################################################################
#                          PREPARE LANGUAGE DATA
###############################################################################
langs="101 102 103 104 105 106 202 203 204 205 206 207 301 302 303 304 305 306 401 402 403"
#langs="101 102 103"

# Just a subset of the training languages for now.
# Decoding an unseen language takes more work to standardize the dictionary,
# and to replace missing phonemes.
dev_langs="104 101 202 "
#test_langs="107 201 307 404"
test_langs="201 307 404"

# Just for documentation and debugging mostly, but these should probably be
# organized differently to reflect important parts of the training script
# or just removed entirely.
# ------------------------------------------------------------------------
# stage 0 -- Setup Language Directories
# stage 1 -- Prepare Data
# stage 2 -- Combine Data
# stage 3 -- training
# stage 4 -- cleanup data and segmentation
# stage 5 -- Chain TDNN training
# stage 6 -- Prepare Decode data directory
# stage 7 -- Prepare Universal Dictionaries, LM
# stage 8 -- Make Decoding Graph
# stage 9 -- Prepare Decode acoustic data
# stage 10 -- Decode Chain

stage=0

. ./utils/parse_options.sh

set -x

# For each language create the data and also create the lexicon
# Save the current directory
cwd=$(utils/make_absolute.sh $PWD)

if [ $stage -le 0 ]; then
  for lang in $langs; do
    config=`find conf/lang  -name "${lang}-*FLP*.conf" | head -1`
    ./local/prepare_directories.sh "$lang" "$config" data/
  done
  for lang in $test_langs; do
    config=`find conf/lang  -name "${lang}-*FLP*.conf" | head -1`
    ./local/prepare_directories.sh "$lang" "$config" data/
  done
fi

###############################################################################
# Combine all langauge specific training directories and generate a single
# lang directory by combining all langauge specific dictionaries
###############################################################################
if [ $stage -le 1 ]; then
  train_dirs=""
  dict_dirs=""
  for l in ${langs}; do
    train_dirs="data/${l}/data/train_${l} ${train_dirs}"
    dict_dirs="data/${l}/data/dict ${dict_dirs}"
  done

  ./utils/combine_data.sh data/train $train_dirs

  # This script was made to mimic the utils/combine_data.sh script, but instead
  # it merges the lexicons while reconciling the nonsilence_phones.txt,
  # silence_phones.txt, and extra_questions.txt by basically just calling
  # local/prepare_unicode_lexicon.py. As mentioned, it may be better to simply
  # modify an existing script to automatically create the dictionary dir from
  # a lexicon, rather than overuse the local/prepare_unicode_lexicon.py script.
  ./local/combine_lexicons.sh data/dict_universal $dict_dirs

  # Prepare lang directory
  ./utils/prepare_lang.sh --share-silence-phones true \
    data/dict_universal "$oovSymbol" data/dict_universal/tmp.lang data/lang_universal
fi


if [ $stage -le 2 ]; then
  set -x
  for lang in $langs; do
    ./utils/prepare_lang.sh --share-silence-phones true \
      --phone_symbol_table data/lang_universal/phones.txt \
      data/$lang/data/dict "$oovSymbol" data/$lang/data/dict_universal/tmp.lang data/$lang/data/lang_universal_test
    cp data/$lang/data/lang_test/G.fst data/$lang/data/lang_universal_test/
  done
  for lang in $test_langs; do
    ./utils/prepare_lang.sh --share-silence-phones true \
      --phone_symbol_table data/lang_universal/phones.txt \
      data/$lang/data/dict "$oovSymbol" data/$lang/data/dict_universal/tmp.lang data/$lang/data/lang_universal_test
    cp data/$lang/data/lang_test/G.fst data/$lang/data/lang_universal_test/
  done
fi

###############################################################################
#           Train the model through tri5 (like in babel recipe)
###############################################################################

# Currently, the full lang directory is used for alignments, but really each
# language specific directory should be used to get alignments for each
# language individually, and then combined to learn a shared tree over all
# languges. Language specific alignments will eliminate the problem of words
# shared across languages and consequently bad alignments. In practice, very
# few words are shared across languages, and when the are the pronunciations
# are often similar. The only real problem is for language specific hesitation
# markers <hes>.
#
# Training follows exactly the standard BABEL recipe. The number of Gaussians
# and leaves were previously tuned for a much larger dataset (10 langauges flp)
# which was about 700 hrs, instead of the 200 hrs here, but the same parameters
# are used here. These parameters could probably use some tweaking for this
# setup.


if [ $stage -le 3 ]; then
  if [ ! -f data/train_sub3/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Subsetting monophone training data in data/train_sub[123] on" `date`
    echo ---------------------------------------------------------------------
    numutt=`cat data/train/feats.scp | wc -l`;
    utils/subset_data_dir.sh data/train 5000 data/train_sub1
    if [ $numutt -gt 10000 ] ; then
      utils/subset_data_dir.sh data/train 10000 data/train_sub2
    else
      (cd data; ln -s train train_sub2 )
    fi
    if [ $numutt -gt 20000 ] ; then
      utils/subset_data_dir.sh data/train 20000 data/train_sub3
    else
      (cd data; ln -s train train_sub3 )
    fi

    touch data/train_sub3/.done
  fi


  if [ ! -f exp/mono/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting (small) monophone training in exp/mono on" `date`
    echo ---------------------------------------------------------------------
    steps/train_mono.sh \
      --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
      data/train_sub1 data/lang_universal exp/mono
    touch exp/mono/.done
  fi


  if [ ! -f exp/tri1/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting (small) triphone training in exp/tri1 on" `date`
    echo ---------------------------------------------------------------------
    steps/align_si.sh \
      --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
      data/train_sub2 data/lang_universal exp/mono exp/mono_ali_sub2

    steps/train_deltas.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" 3000 30000\
      data/train_sub2 data/lang_universal exp/mono_ali_sub2 exp/tri1

    touch exp/tri1/.done
  fi

  echo ---------------------------------------------------------------------
  echo "Starting (medium) triphone training in exp/tri2 on" `date`
  echo ---------------------------------------------------------------------
  if [ ! -f exp/tri2/.done ]; then
    steps/align_si.sh \
      --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
      data/train_sub3 data/lang_universal exp/tri1 exp/tri1_ali_sub3

    steps/train_deltas.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" 3000 60000\
      data/train_sub3 data/lang_universal exp/tri1_ali_sub3 exp/tri2

    local/reestimate_langp.sh --cmd "$train_cmd" --unk "$oovSymbol" \
      data/train_sub3 data/lang_universal data/dict_universal\
      exp/tri2 data/dict_universal/dictp/tri2 \
      data/dict_universal/langp/tri2 data/lang_universalp/tri2

    touch exp/tri2/.done
  fi

  echo ---------------------------------------------------------------------
  echo "Starting (full) triphone training in exp/tri3 on" `date`
  echo ---------------------------------------------------------------------
  if [ ! -f exp/tri3/.done ]; then
    steps/align_si.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data/train data/lang_universalp/tri2 exp/tri2 exp/tri2_ali

    steps/train_deltas.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" 18000 225000\
      data/train data/lang_universalp/tri2 exp/tri2_ali exp/tri3

    local/reestimate_langp.sh --cmd "$train_cmd" --unk "$oovSymbol" \
      data/train data/lang_universal data/dict_universal/ \
      exp/tri3 data/dict_universal/dictp/tri3 \
      data/dict_universal/langp/tri3 data/lang_universalp/tri3

    touch exp/tri3/.done
  fi


  echo ---------------------------------------------------------------------
  echo "Starting (lda_mllt) triphone training in exp/tri4 on" `date`
  echo ---------------------------------------------------------------------
  if [ ! -f exp/tri4/.done ]; then
    steps/align_si.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data/train data/lang_universalp/tri3 exp/tri3 exp/tri3_ali

    steps/train_lda_mllt.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" 18000 225000 \
      data/train data/lang_universalp/tri3 exp/tri3_ali exp/tri4

    local/reestimate_langp.sh --cmd "$train_cmd" --unk "$oovSymbol" \
      data/train data/lang_universal data/dict_universal \
      exp/tri4 data/dict_universal/dictp/tri4 \
      data/dict_universal/langp/tri4 data/lang_universalp/tri4

    touch exp/tri4/.done
  fi

  echo ---------------------------------------------------------------------
  echo "Starting (SAT) triphone training in exp/tri5 on" `date`
  echo ---------------------------------------------------------------------

  if [ ! -f exp/tri5/.done ]; then
    steps/align_si.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data/train data/lang_universalp/tri4 exp/tri4 exp/tri4_ali

    steps/train_sat.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" 18000 225000\
      data/train data/lang_universalp/tri4 exp/tri4_ali exp/tri5

    local/reestimate_langp.sh --cmd "$train_cmd" --unk "$oovSymbol" \
      data/train data/lang_universal data/dict_universal \
      exp/tri5 data/dict_universal/dictp/tri5 \
      data/dict_universal/langp/tri5 data/lang_universalp/tri5

    touch exp/tri5/.done
  fi

  if [ ! -f exp/tri5_ali/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/tri5_ali on" `date`
    echo ---------------------------------------------------------------------
    steps/align_fmllr.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data/train data/lang_universalp/tri5 exp/tri5 exp/tri5_ali

    local/reestimate_langp.sh --cmd "$train_cmd" --unk "$oovSymbol" \
      data/train data/lang_universal data/dict_universal \
      exp/tri5_ali data/dict_universal/dictp/tri5_ali \
      data/dict_universal/langp/tri5_ali data/lang_universalp/tri5_ali

    touch exp/tri5_ali/.done
  fi
fi


###############################################################################
#                          Data Cleanup
###############################################################################

# Issues:
#   1. There is an insufficient memory issue that arises in
#
#         steps/cleanup/make_biased_lm_graphs.sh
#
#      which I got around by using the -mem option in queue.pl and setting it
#      really high. This limits the number of jobs you can run and causes the
#      cleanup to be really slow. There is probably a better way around this.

if [ $stage -le 4 ]; then
  ./local/run_cleanup_segmentation.sh --langdir data/lang_universalp/tri5
fi

if [ $stage -le 5 ] ; then
if [ ! -f exp/tri6a/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri6a on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 100000 data/train_cleaned data/lang_universalp/tri5_ali exp/tri5_ali_cleaned/ exp/tri6a_cleaned
fi
if [ ! -f exp/tri6b/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri6b on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sat.sh --cmd "$train_cmd" \
    15000 225000 data/train_cleaned data/lang_universalp/tri5_ali exp/tri5_ali_cleaned/ exp/tri6b_cleaned
fi
if [ ! -f exp/tri6c/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri6c on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sat.sh --cmd "$train_cmd" \
    25000 330000 data/train_cleaned data/lang_universalp/tri5_ali exp/tri5_ali_cleaned/ exp/tri6c_cleaned
fi
fi

###############################################################################
#                                DNN Training
###############################################################################

if [ $stage -le 6 ]; then
  ./local/chain/run_tdnn.sh --langdir data/lang_universalp/tri5_ali --gmm tri6c_cleaned
fi

###############################################################################
#============================== END OF TRAINING ===============================
###############################################################################
if [ $stage -le 7 ] ; then
  echo "Universal Acoustic Model Training finished." && \
  echo "To decode, comment out these lines in run.sh (390-391)." && exit 0;
fi


###############################################################################
#                                  Decoding
###############################################################################

# Preparing Decoding Data
# For each decoding language setup the language directories
for lang in ${dev_langs}; do
  model=exp/chain_cleaned/tdnn_sp
  decode_nj=$(wc -l < data/$lang/data/dev10h.pem/spk2utt)

  # Make Decoding Graph
  if [ $stage -le 8 ]; then
    ./utils/mkgraph.sh --self-loop-scale 1.0 \
      data/$lang/data/lang_universal_test/ $model $model/graph_${lang}
  fi

  # Prepare Acoustic Data
  mkdir -p ${model}_online
  if [ $stage -le 9 ]; then
    steps/online/nnet3/prepare_online_decoding.sh \
      --mfcc-config conf/mfcc_hires.conf \
      --add-pitch true --online-pitch-config conf/online_pitch.conf \
      data/$lang/data/lang_universal_test exp/nnet3_cleaned/extractor  \
      $model  ${model}_online/$lang/
  fi

  # Decode
  if [ $stage -le 10 ]; then
    # Assign 100 / num_decode_langs nj per lang
    steps/online/nnet3/decode.sh --skip-scoring false \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $decode_nj --cmd "$decode_cmd" \
        $model/graph_${lang}\
        data/$lang/data/dev10h.pem \
        ${model}_online/$lang/decode_dev10h.pem

  fi
done

