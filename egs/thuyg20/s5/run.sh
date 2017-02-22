#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh

H=`pwd`  #exp home
n=8      #parallel jobs

thuyg=$PWD/database
#corpus and trans directory
#you can obtain the database by uncommting the following lines
( mkdir -p $thuyg; 
  cd $thuyg
     echo "downloading THUYG20 at $PWD ..."
     [ ! -f data_thuyg20.tar.gz ] && wget http://www.openslr.org/resources/22/data_thuyg20.tar.gz
     [ ! -f resource.tar.gz ] && wget http://www.openslr.org/resources/22/resource.tar.gz 
     [ ! -d data_thuyg20  ] && tar xvf data_thuyg20.tar.gz
     [ ! -d resource  ] && tar xvf resource.tar.gz 
)

set -e -o pipefail
if false; then
  true
fi
#data preparation 
#generate text, wav.scp, utt2pk, spk2utt
local/thuyg-20_data_prep.sh $H $thuyg/data_thuyg20 || exit 1;

#produce MFCC features 
rm -rf data/mfcc && mkdir -p data/mfcc &&  cp -R data/{train,cv,test} data/mfcc || exit 1;
for x in train cv test; do
   #make  mfcc 
   steps/make_mfcc.sh --nj $n --cmd "$train_cmd" data/mfcc/$x exp/make_mfcc/$x mfcc/$x || exit 1;
   #compute cmvn
   steps/compute_cmvn_stats.sh data/mfcc/$x exp/mfcc_cmvn/$x mfcc/$x/_cmvn || exit 1;
done

#prepare language stuff
#build a large lexicon that invovles words in both the training and decoding. 
(
  echo "make word graph ..."
  cd $H; mkdir -p data/{dict,lang,graph} && \
  cp $thuyg/resource/dict/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} data/dict && \
  cat $thuyg/resource/dict/lexicon.txt | sort -u > data/dict/lexicon.txt || exit 1;
  utils/prepare_lang.sh --position_dependent_phones false data/dict "<unk>" data/local/lang data/lang || exit 1;
  cp $thuyg/data_thuyg20/lm_word/vword.3gram.th1e-7.gz data/graph || exit 1;
  utils/format_lm.sh data/lang data/graph/vword.3gram.th1e-7.gz $thuyg/data_thuyg20/lm_word/lexicon.txt data/graph/lang || exit 1;
)

#make big morpheme graph
#morpheme LM is too large to generate HCLG.fst beacause of limited memory. Fist, use the large LM to produce G.fst. Then, clip the large to make probability  more than e-5 and use the new LM to produce G.fst and HCLG.fst. Finally, combine HCLG.fst,G.fst from the new LM and G.fst from large LM to decode. 
(
  echo "make big morpheme graph ..."
  cd $H; mkdir -p data/{dict_morpheme,graph_morpheme,lang_morpheme} && \
  cp $thuyg/resource/dict/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} data/dict_morpheme  && \
  cat $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.lex | grep -v '<s>' | grep -v '</s>' | sort -u > data/dict_morpheme/lexicon.txt \
  && echo -e "SIL sil\n<unk> <unk>" >> data/dict_morpheme/lexicon.txt  || exit 1;
  utils/prepare_lang.sh --position_dependent_phones false data/dict_morpheme "<unk>" data/local/lang_morpheme data/lang_morpheme || exit 1;
  cp $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.arpa4-org.gz data/graph_morpheme || exit 1;
  utils/format_lm.sh data/lang_morpheme data/graph_morpheme/uyghur-pseudo-morpheme.arpa4-org.gz \
    $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.lex data/graph_morpheme/lang  || exit 1;
)

#make_small_morpheme_graph
(
  echo "make small morpheme graph ..."
  cd $H; mkdir -p data/{dict_morpheme_s,graph_morpheme_s,lang_morpheme_s} && \
  cp $thuyg/resource/dict/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} data/dict_morpheme_s  && \
  cat $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.lex | grep -v '<s>' | grep -v '</s>' | sort -u > data/dict_morpheme_s/lexicon.txt \
  && echo -e "SIL sil\n<unk> <unk>" >> data/dict_morpheme_s/lexicon.txt  || exit 1;
  utils/prepare_lang.sh --position_dependent_phones false data/dict_morpheme_s "<unk>" data/local/lang_morpheme_s data/lang_morpheme_s || exit 1;
  cp $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.arpa4.1e-5.gz data/graph_morpheme_s || exit 1;
  utils/format_lm.sh data/lang_morpheme_s data/graph_morpheme_s/uyghur-pseudo-morpheme.arpa4.1e-5.gz \
    $thuyg/data_thuyg20/lm_morpheme/uyghur-pseudo-morpheme.lex data/graph_morpheme_s/lang  || exit 1;
)

#monophone
steps/train_mono.sh --boost-silence 1.25 --nj $n --cmd "$train_cmd" data/mfcc/train data/lang exp/mono || exit 1; 

#test monophone model
local/thuyg-20_decode.sh --mono true --nj $n "steps/decode.sh" "steps/decode_biglm.sh" exp/mono data/mfcc &

#monophone_ali
steps/align_si.sh --boost-silence 1.25 --nj $n --cmd "$train_cmd" data/mfcc/train data/lang exp/mono exp/mono_ali || exit 1;

#triphone
steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 2000 10000 data/mfcc/train data/lang exp/mono_ali exp/tri1 || exit 1;

#test tri1 model
local/thuyg-20_decode.sh --nj $n "steps/decode.sh" "steps/decode_biglm.sh" exp/tri1 data/mfcc &

#triphone_ali
steps/align_si.sh --nj $n --cmd "$train_cmd" data/mfcc/train data/lang exp/tri1 exp/tri1_ali || exit 1;

#lda_mllt
steps/train_lda_mllt.sh --cmd "$train_cmd" --splice-opts "--left-context=3 --right-context=3" 2500 15000 data/mfcc/train data/lang exp/tri1_ali exp/tri2b || exit 1;

#test tri2b model
local/thuyg-20_decode.sh --nj $n "steps/decode.sh" "steps/decode_biglm.sh" exp/tri2b data/mfcc &

#lda_mllt_ali
steps/align_si.sh  --nj $n --cmd "$train_cmd" --use-graphs true data/mfcc/train data/lang exp/tri2b exp/tri2b_ali || exit 1;

#sat
steps/train_sat.sh --cmd "$train_cmd" 2500 15000 data/mfcc/train data/lang exp/tri2b_ali exp/tri3b || exit 1;

#test tri3b model
local/thuyg-20_decode.sh --nj $n "steps/decode_fmllr.sh" "steps/decode_biglm.sh" exp/tri3b data/mfcc &

#sat_ali
steps/align_fmllr.sh --nj $n --cmd "$train_cmd" data/mfcc/train data/lang exp/tri3b exp/tri3b_ali || exit 1;

#quick
steps/train_quick.sh --cmd "$train_cmd" 4200 40000 data/mfcc/train data/lang exp/tri3b_ali exp/tri4b || exit 1;

#test tri4b model
local/thuyg-20_decode.sh --nj $n "steps/decode_fmllr.sh" "steps/decode_biglm.sh" exp/tri4b data/mfcc &

#quick_ali
steps/align_fmllr.sh --nj $n --cmd "$train_cmd" data/mfcc/train data/lang exp/tri4b exp/tri4b_ali || exit 1;

#quick_ali_cv
steps/align_fmllr.sh --nj $n --cmd "$train_cmd" data/mfcc/cv data/lang exp/tri4b exp/tri4b_ali_cv || exit 1;

#train dnn model
local/nnet/run_dnn.sh --stage 0 --nj $n  exp/tri4b exp/tri4b_ali exp/tri4b_ali_cv || exit 1; 

#noise training dnn model
#python2.6 or above is required for noisy data generation.
#To speed up the process, pyximport for python is recommeded.
#In order to use the standard noisy test data, set "--stdtest true" and "--dwntest true"
local/nnet/run_dnn_noise_training.sh --stage 0  --stdtest false --dwntest false $thuyg exp/tri4b exp/tri4b_ali exp/tri4b_ali_cv ||  exit 1;
