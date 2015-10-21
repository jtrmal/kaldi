#!/bin/bash
# Copyright (c) 2015, Johns Hopkins University (Author: Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.
tri5_only=false
sgmm5_only=false
data_only=false

# Begin configuration section.
boost_sil=1.5
# End configuration section

. ./path.sh
. ./cmd.sh

if [ ! -f ./local.conf ]; then
  echo "You must create (or symlink from conf/) data sources configuration"
  echo "Symlink it to your experiment's root directory as local.conf"
  echo "See conf/lang-clsp-ab.conf for an example"
  exit 1
fi
. ./local.conf
. ./utils/parse_options.sh

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will
                 #return non-zero return code
set -u           #Fail on an undefined variable

romanized=false

if [ ! -f data/raw_babel_train_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Creating  the BABEL-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_babel_train_data
  if [ ! -z ${train_data_dir+x}  ]; then
    local/make_corpus_subset.sh --romanized $romanized "$train_data_dir" "$train_data_list" ./data/raw_babel_train_data
  fi
  touch data/raw_babel_train_data/.done
fi
babel_train=`readlink -f ./data/raw_babel_train_data`

if [ ! -f data/raw_appen_train_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Creating the APPEN-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_appen_train_data
  if [ ! -z ${train_data_appen_dir+x}  ]; then
    local/make_appen_corpus_subset.sh --romanized $romanized  "$train_data_appen_dir" "$train_data_appen_list" ./data/raw_appen_train_data
  fi
  touch data/raw_appen_train_data/.done
fi
appen_train=`readlink -f ./data/raw_appen_train_data`

if [ ! -f data/raw_transtac_train_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the TRANSTAC-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_transtac_train_data
  if [ ! -z ${train_data_transtac_dir+x}  ]; then
    local/subset_transtac_data.sh "$train_data_transtac_dir" \
      conf/lists/transtac_pashto.train data/raw_transtac_train_data
  fi
  touch data/raw_transtac_train_data/.done
fi
transtac_train=`readlink -f ./data/raw_transtac_train_data`


mkdir -p data/local/dict
if [[ ! -f data/local/dict/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data/local on" `date`
  echo ---------------------------------------------------------------------

  romanized=true
  if [ ! -z ${train_data_transtac_dir+x} ] ; then
    echo "Using only the TransTac Lexicon..."
    romanized=false
    local/convert_transtac_lexicon.sh \
      "$lexicon_transtac_file" data/local/dict/filtered_lexicon.txt
  elif [ ! -z ${train_data_appen_dir+x}  ] && [ ! -z ${train_data_dir+x} ]  ; then
    echo "Merging the lexicons..."
    local/make_lexicon_subset.sh $babel_train/transcription \
      <(local/convert_charsets.pl $lexicon_file) \
      data/local/dict/filtered_babel_lexicon.txt
    cut -f 1,2,3 $lexicon_appen_file | local/convert_charsets.pl | \
      local/lexicon_to_babel_format.pl --tag 1 > data/local/dict/filtered_appen_lexicon.txt
    
    cat data/local/dict/filtered_*_lexicon.txt | \
      local/lexicon_to_babel_format.pl > data/local/dict/filtered_lexicon.txt

  elif  [ ! -z ${train_data_appen_dir+x}  ] ; then
    echo "Using only the Appen Lexicon..."
    cut -f 1,2,3 $lexicon_appen_file | local/convert_charsets.pl | \
      local/lexicon_to_babel_format.pl --tag 1 > data/local/dict/filtered_appen_lexicon.txt
    
    cat data/local/dict/filtered_*_lexicon.txt | \
      local/lexicon_to_babel_format.pl > data/local/dict/filtered_lexicon.txt

  else
    echo "Using only the Babel Lexicon..."
    local/make_lexicon_subset.sh $babel_train/transcription \
      <(local/convert_charsets.pl $lexicon_file) \
      data/local/dict/filtered_babel_lexicon.txt
    
    cat data/local/dict/filtered_*_lexicon.txt | \
      local/lexicon_to_babel_format.pl > data/local/dict/filtered_lexicon.txt

  fi

  if $romanized ; then
    lexiconFlags=" --romanized $lexiconFlags "
  fi

  local/prepare_lexicon.pl \
    $lexiconFlags data/local/dict/filtered_lexicon.txt data/local/dict/
fi

mkdir -p data/lang
if [[ ! -f data/lang/L.fst || data/lang/L.fst -ot data/local/dict/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating L.fst etc in data/lang on" `date`
  echo ---------------------------------------------------------------------
  utils/prepare_lang.sh \
    --share-silence-phones true \
    data/local/dict $oovSymbol data/local/lang data/lang
fi

if [[ ! -f data/train_babel/wav.scp || data/train_babel/wav.scp -ot "$babel_train" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train_babel
  if  [ ! -z ${train_data_dir+x}  ] ; then
    local/prepare_acoustic_training_data.pl \
      --vocab data/local/dict/lexicon.txt --fragmentMarkers \-\*\~ \
      $babel_train data/train_babel > data/train_babel/skipped_utts.log
    utils/fix_data_dir.sh data/train_babel
  fi
fi

if [[ ! -f data/train_appen/wav.scp || data/train_appen/wav.scp -ot "$appen_train" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train_appen
  if  [ ! -z ${train_data_appen_dir+x}  ] ; then
    local/prepare_acoustic_training_data.pl \
      --vocab data/local/dict/lexicon.txt --fragmentMarkers \-\*\~ \
      $appen_train data/train_appen > data/train_appen/skipped_utts.log
    utils/fix_data_dir.sh data/train_appen
  fi
fi

if [[ ! -f data/train_transtac/wav.scp || data/train_transtac/wav.scp -ot "$transtac_train" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train_transtac on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train_transtac
  if  [ ! -z ${train_data_transtac_dir+x}  ] ; then
    local/prepare_transtac_data_dir.sh \
      $transtac_train data/lang data/train_transtac

    utils/fix_data_dir.sh data/train_transtac
  fi
fi

if [ ! -f data/train/.done ] ; then
  if [ ! -z ${train_data_appen_dir+x}  ] && [ ! -z ${train_data_dir+x} ]  ; then
    combine_data.sh data/train data/train_appen data/train_babel
  elif  [ ! -z ${train_data_transtac_dir+x} ]; then
    utils/copy_data_dir.sh data/train_transtac data/train
  elif  [ ! -z ${train_data_appen_dir+x}  ] ; then
    utils/copy_data_dir.sh data/train_appen data/train
  else
    utils/copy_data_dir.sh data/train_babel data/train
  fi

  touch data/train/.done
fi

nj_max=`cat data/train/spk2utt | wc -l`
if [[ "$nj_max" -lt "$train_nj" ]] ; then
    echo "The maximum reasonable number of jobs is $nj_max (you have $train_nj)! (The training and decoding process has file-granularity)"
    exit 1;
    train_nj=$nj_max
fi

if [ ! -f data/lang_test/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  local/train_lms_srilm.sh  --oov-symbol "<unk>" \
    --train-text data/train/text \
    --words-file data/lang/words.txt data/ data/srilm

  rm -rf data/lang_test/
  cp -R data/lang/ data/lang_test
  local/arpa2G.sh data/srilm/lm.gz data/lang_test data/lang_test
  touch data/lang_test/.done
fi

if [ ! -f data/train/.plp.done ]; then
  steps/make_plp_pitch.sh --cmd "$train_cmd" --nj $train_nj \
      data/train exp/make_plp_pitch/train plp

  utils/fix_data_dir.sh data/train
  steps/compute_cmvn_stats.sh data/train exp/make_plp/train plp
  utils/fix_data_dir.sh data/train
  touch data/train/.plp.done
fi

mkdir -p exp

if [ ! -f data/train_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/train_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/train/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/train  5000 data/train_sub1
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

if $data_only; then
  echo "--data-only is true" && exit 0
fi

if [ ! -f exp/mono/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/mono on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data/train_sub1 data/lang exp/mono
  touch exp/mono/.done
fi

if [ ! -f exp/tri1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/tri1 on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data/train_sub2 data/lang exp/mono exp/mono_ali_sub2
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data/train_sub2 data/lang exp/mono_ali_sub2 exp/tri1

  touch exp/tri1/.done
fi


echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/tri2 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri2/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data/train_sub3 data/lang exp/tri1 exp/tri1_ali_sub3
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data/train_sub3 data/lang exp/tri1_ali_sub3 exp/tri2

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train_sub3 data/lang data/local/dict \
    exp/tri2 data/local/dictp/tri2 data/local/langp/tri2 data/langp/tri2

  touch exp/tri2/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/tri3 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri3/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri2 exp/tri2 exp/tri2_ali

  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data/train data/langp/tri2 exp/tri2_ali exp/tri3

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri3 data/local/dictp/tri3 data/local/langp/tri3 data/langp/tri3

  touch exp/tri3/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri3 exp/tri3 exp/tri3_ali

  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data/train data/langp/tri3 exp/tri3_ali exp/tri4

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri4 data/local/dictp/tri4 data/local/langp/tri4 data/langp/tri4

  touch exp/tri4/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5 on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri4 exp/tri4 exp/tri4_ali

  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/train data/langp/tri4 exp/tri4_ali exp/tri5

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri5 data/local/dictp/tri5 data/local/langp/tri5 data/langp/tri5

  touch exp/tri5/.done
fi


if [ ! -f exp/tri5_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri5 exp/tri5 exp/tri5_ali

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri5_ali data/local/dictp/tri5_ali data/local/langp/tri5_ali data/langp/tri5_ali

  touch exp/tri5_ali/.done
fi

if $tri5_only ; then
  echo "Exiting after stage TRI5, as requested. "
  echo "Everything went fine. Done"
  exit 0;
fi

if [ -x ./decode.sh ] ; then
  ## Spawn decoding....
  echo ---------------------------------------------------------------------
  echo "Starting decoding on" `date`
  echo ---------------------------------------------------------------------
  ./decode.sh
fi

# this part of the recipe is only for the KWS
# if [ ! -f exp/tri5_ali/.done ]; then
#   echo ---------------------------------------------------------------------
#   echo "Starting exp/tri5_ali on" `date`
#   echo ---------------------------------------------------------------------
#
#   local/ali_to_rttm.sh  --cmd "$decode_cmd" \
#     data/train data/langp/tri5 data/local/langp/tri5/ exp/tri5_ali/
#
#   steps/align_fmllr.sh \
#     --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
#     data/dev10h data/langp/tri5 exp/tri5 exp/tri5_ali/dev10h
#
#   local/ali_to_rttm.sh  --cmd "$decode_cmd" \
#     data/dev10h data/langp/tri5 data/local/langp/tri5/ exp/tri5_ali/dev10h
#
#   steps/align_fmllr.sh \
#     --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
#     data/dev_appen data/langp/tri5 exp/tri5 exp/tri5_ali/dev_appen
#
#   local/ali_to_rttm.sh  --cmd "$decode_cmd" \
#     data/dev_appen data/langp/tri5 data/local/langp/tri5/ exp/tri5_ali/dev_appen
#
#   touch exp/tri5_ali/.done
# fi

echo "All done OK"
exit 0

