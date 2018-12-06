#!/bin/bash

# Author     2018  Martin Bulin (bulinmartin@gmail.com)
# Apache 2.0


# -- Begin configuration section ----------------------------------------------
nj=32
nj_test=20
stage=-1
corpus_dir="/export/corpora4/ARL_OCR/win/OSI_Pashto_Project_572GB/\
database/WordImages"
# -- End configuration section ------------------------------------------------

. ./utils/parse_options.sh

. ./path.sh || die "File path.sh expected to exist"
. ./cmd.sh || die "File cmd.sh expected to exist"

set -e

if [ $stage -le -1 ]; then
    echo
    echo "== $0: $(date): STAGE -1: CORPUS EXTRACTION =="
    local/corpus_extraction/extract_words.sh $corpus_dir || exit 1;
fi

if [ $stage -le 0 ]; then
    echo
    echo "== $0: $(date): STAGE 0: COLLECTING DATA =="
    local/collect_data.sh $corpus_dir || exit 1;
fi

if [ $stage -le 1 ]; then
    echo
    echo "== $0: $(date): STAGE 1: MAKING FEATURES =="
    local/make_features.sh
fi

if [ $stage -le 2 ]; then
    echo
    echo "== $0: $(date): STAGE 2: CHECKING DATA DIRECTORIES =="
    local/image/fix_data_dir.sh data/train
    local/image/validate_data_dir.sh data/train

    local/image/fix_data_dir.sh data/test
    local/image/validate_data_dir.sh data/test

    echo
    echo "== $0: $(date): STAGE 2: CREATING A CORPUS FILE =="
    rm -rf data/local/corpus.txt
    cut -d' ' -f2- data/train/text data/test/text > data/local/corpus.txt

    echo
    echo "== $0: $(date): STAGE 2: CREATING A DICTIONARY =="
    mkdir -p data/local/dict
    local/make_dict.py
fi

if [ $stage -le 3 ]; then
    echo
    echo "== $0: $(date): STAGE 3: CREATING THE LANGUAGE MODEL =="
    local/create_lm.sh
fi

if [ $stage -le 4 ]; then
    echo
    echo "== $0: $(date): STAGE 4: TRAINING MONO =="
    steps/train_mono.sh --nj $nj --cmd $cmd --totgauss 1024 \
                        --num_iters 40 data/train data/lang \
                        exp/mono  || exit 1
fi

if [ $stage -le 5 ]; then
    echo
    echo "== $0: $(date): STAGE 5: MAKING A GRAPH FOR MONO =="
    utils/mkgraph.sh data/lang exp/mono exp/mono/graph

    echo
    echo "== $0: $(date): STAGE 5: DECODING MONO =="
    steps/decode.sh --nj $nj_test --cmd $cmd exp/mono/graph data/test\
                             exp/mono/decode_test
fi

if [ $stage -le 6 ]; then
    echo
    echo "== $0: $(date): STAGE 6: ALIGNING MONO =="
    steps/align_si.sh --nj $nj --cmd $cmd data/train data/lang \
                      exp/mono exp/mono_ali
fi

if [ $stage -le 7 ]; then
    echo
    echo "== $0: $(date): STAGE 7: TRAINING DELTAS (TRI) =="
    steps/train_deltas.sh --cmd $cmd 1024 16384 \
                          data/train data/lang exp/mono_ali exp/tri
fi

if [ $stage -le 8 ]; then
    echo
    echo "== $0: $(date): STAGE 8: MAKING A GRAPH FOR TRI =="
    utils/mkgraph.sh data/lang exp/tri exp/tri/graph

    echo
    echo "== $0: $(date): STAGE 8: DECODING TRI =="
    steps/decode.sh --nj $nj_test --cmd $cmd exp/tri/graph data/test\
                    exp/tri/decode_test
fi

if [ $stage -le 9 ]; then
    echo
    echo "== $0: $(date): STAGE 9: ALIGNING TRI =="
    steps/align_si.sh --nj $nj --cmd $cmd data/train data/lang \
                      exp/tri exp/tri_ali
fi

if [ $stage -le 10 ]; then
    echo
    echo "== $0: $(date): STAGE 10: TRAINING LDA+MLLT (TRI2) =="
    steps/train_lda_mllt.sh  --cmd $cmd \
                             --splice-opts "--left-context=3 --right-context=3" \
                             2048 65536 data/train data/lang  exp/tri_ali exp/tri2
fi

if [ $stage -le 11 ]; then
    echo
    echo "== $0: $(date): STAGE 11: MAKING A GRAPH FOR TRI2 =="
    utils/mkgraph.sh data/lang exp/tri2 exp/tri2/graph

    echo
    echo "== $0: $(date): STAGE 11: DECODING TRI2 =="
    steps/decode.sh --nj $nj_test --cmd $cmd exp/tri2/graph data/test\
                    exp/tri2/decode_test
fi

if [ $stage -le 12 ]; then
    echo
    echo "== $0: $(date): STAGE 12: ALIGNING TRI2 =="
    steps/align_si.sh --nj $nj --cmd $cmd data/train data/lang \
                      exp/tri2 exp/tri2_ali
fi

if [ $stage -le 13 ]; then
    echo
    echo "== $0: $(date): STAGE 13: TRAINING SAT+FMLLR (TRI3) =="
    steps/train_sat.sh --cmd $cmd 8192 131072 \
                       data/train data/lang exp/tri2_ali exp/tri3
fi

if [ $stage -le 14 ]; then
    echo
    echo "== $0: $(date): STAGE 14: MAKING A GRAPH FOR TRI3 =="
    utils/mkgraph.sh data/lang  exp/tri3 exp/tri3/graph

    echo
    echo "== $0: $(date): STAGE 14: DECODING TRI3 =="
    steps/decode_fmllr.sh --nj $nj_test --cmd $cmd \
                          exp/tri3/graph data/test exp/tri3/decode_test
fi

if [ $stage -le 15 ]; then
    echo
    echo "== $0: $(date): STAGE 15: ALIGNING TRI3 =="
    steps/align_fmllr.sh --nj $nj --cmd $cmd \
                         data/train data/lang exp/tri3 exp/tri3_ali
fi

if [ $stage -le 16 ]; then
    echo
    echo "RESULTS SO FAR:"
    find exp -name "best_wer" | xargs cat  | sort -k2,2g | tee RESULTS
    echo
    echo
    echo "== $0: $(date): STAGE 16: RUNNING NNET STAGES =="
    local/chain/run_cnn.sh --stage 0
fi

echo
echo "RESULTS:"
find exp -name "best_wer" | xargs cat  | sort -k2,2g | tee RESULTS
echo
