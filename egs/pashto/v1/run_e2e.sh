#!/bin/bash

# Author     2018  Martin Bulin (bulinmartin@gmail.com)
# Based on   ../../yomdle_tamil/v1/run_end2end.sh
# Apache 2.0


# -- Begin configuration section ----------------------------------------------
nj=32
nj_test=20
stage=-1
corpus_dir="/export/corpora4/ARL_OCR/win/OSI_Pashto_Project_572GB/\
database/WordImages"

feature_dim=40
tdnn_dim=450
cnn_dir=exp/cnn_e2e
cnn_treedir=exp/work/cnn_e2e_tree
cnn_latdir=exp/work/cnn_e2e_lat
cnn_lang_train=data/lang_cnn_e2e_train
cnn_numchunk_per_minibatch=150=32,16/300=16,8/600=8,4/1200=4,2
#cnn_numchunk_per_minibatch=150=16,8/300=8,4/600=4,2/1200=2,1  # try if training fails
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
    echo "== $0: $(date): STAGE 4: PREPARING FLAT START =="
    if ! cuda-compiled; then
        cat <<EOF && exit 1
        !!E: This script is intended to be used with GPUs but you have not compiled
        Kaldi with CUDA. If you want to use GPUs (and have them), go to src/, and
        configure and make on a machine where "nvcc" is installed.
EOF
    fi

    [ ! -f data/train/feats.scp ] && \
    echo "$0: !!E: Expected file data/train/feats.scp to exist." && exit 1

    # hack: script steps/nnet3/chain/e2e/get_egs_e2e.sh
    # expects allowed_lenghts.txt to be in the train directory
    cp data/local/allowed_lengths.txt data/train/allowed_lengths.txt

    echo "-- $0: $(date): Removing old directories in use"
    rm -rf $cnn_dir $cnn_treedir $cnn_latdir

    echo "== $0: $(date): Creating a training lang =="
    if [ -d $cnn_lang_train ] && [ ${cnn_lang_train}/L.fst -nt data/lang/L.fst ]; then
        echo "-- $0: $(date): LM $cnn_lang_train (chain-type topology) already exists.\
            not overwriting it; continuing..."
    else
        echo "-- $0: $(date): Creating LM $cnn_lang_train (chain-type topology)..."
        cp -r data/lang $cnn_lang_train
        silphonelist=$(cat ${cnn_lang_train}/phones/silence.csl) || exit 1;
        nonsilphonelist=$(cat ${cnn_lang_train}/phones/nonsilence.csl) || exit 1;
        steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist > ${cnn_lang_train}/topo
    fi

    echo "-- $0: $(date): Initializing NN end2end system"
    steps/nnet3/chain/e2e/prepare_e2e.sh --nj $nj --cmd $cmd \
                                         --shared-phones true \
                                         --type mono \
                                         data/train $cnn_lang_train $cnn_treedir

    $cmd $cnn_treedir/log/make_phone_lm.log \
    cat data/train/text \| \
    steps/nnet3/chain/e2e/text_to_phones.py data/lang \| \
    utils/sym2int.pl -f 2- data/lang/phones.txt \| \
    chain-est-phone-lm --num-extra-lm-states=500 ark:- $cnn_treedir/phone_lm.fst
fi

if [ $stage -le 5 ]; then
    echo
    echo "== $0: $(date): STAGE 5: NN TOPOLOGY DESIGN =="

    num_targets=$(tree-info ${cnn_treedir}/tree | grep num-pdfs | awk '{print $2}')
    cnn_opts="l2-regularize=0.075"
    tdnn_opts="l2-regularize=0.075"
    output_opts="l2-regularize=0.1"
    common1="${cnn_opts} required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=36"
    common2="${cnn_opts} required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=70"
    common3="${cnn_opts} required-time-offsets= height-offsets=-1,0,1 num-filters-out=70"

    mkdir -p ${cnn_dir}/configs

    echo "-- $0: $(date): Designing topology for e2e system..."
    cat <<EOF > ${cnn_dir}/configs/network.xconfig
    input dim=$feature_dim name=input
    conv-relu-batchnorm-layer name=cnn1 height-in=$feature_dim height-out=$feature_dim time-offsets=-3,-2,-1,0,1,2,3 $common1
    conv-relu-batchnorm-layer name=cnn2 height-in=$feature_dim height-out=$((feature_dim/2)) time-offsets=-2,-1,0,1,2 $common1 height-subsample-out=2
    conv-relu-batchnorm-layer name=cnn3 height-in=$((feature_dim/2)) height-out=$((feature_dim/2)) time-offsets=-4,-2,0,2,4 $common2
    conv-relu-batchnorm-layer name=cnn4 height-in=$((feature_dim/2)) height-out=$((feature_dim/2)) time-offsets=-4,-2,0,2,4 $common2
    conv-relu-batchnorm-layer name=cnn5 height-in=$((feature_dim/2)) height-out=$((feature_dim/4)) time-offsets=-4,-2,0,2,4 $common2 height-subsample-out=2
    conv-relu-batchnorm-layer name=cnn6 height-in=$((feature_dim/4)) height-out=$((feature_dim/4)) time-offsets=-4,0,4 $common3
    conv-relu-batchnorm-layer name=cnn7 height-in=$((feature_dim/4)) height-out=$((feature_dim/4)) time-offsets=-4,0,4 $common3
    relu-batchnorm-layer name=tdnn1 input=Append(-4,0,4) dim=$tdnn_dim $tdnn_opts
    relu-batchnorm-layer name=tdnn2 input=Append(-4,0,4) dim=$tdnn_dim $tdnn_opts
    relu-batchnorm-layer name=tdnn3 input=Append(-4,0,4) dim=$tdnn_dim $tdnn_opts
    ## adding the layers for chain branch
    relu-batchnorm-layer name=prefinal-chain dim=$tdnn_dim target-rms=0.5 $output_opts
    output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5 $output_opts
EOF

    steps/nnet3/xconfig_to_configs.py \
        --xconfig-file ${cnn_dir}/configs/network.xconfig \
        --config-dir ${cnn_dir}/configs
fi

if [ $stage -le 6 ]; then
    echo
    echo "== $0: $(date): NN TRAINING =="

    steps/nnet3/chain/e2e/train_e2e.py \
        --stage -10 \
        --cmd $cmd \
        --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
        --chain.leaky-hmm-coefficient 0.1 \
        --chain.apply-deriv-weights true \
        --egs.stage -10 \
        --egs.opts "--num_egs_diagnostic 100 --num_utts_subset 400" \
        --chain.frame-subsampling-factor 4 \
        --chain.alignment-subsampling-factor 4 \
        --trainer.add-option="--optimization.memory-compression-level=2" \
        --trainer.num-chunk-per-minibatch $cnn_numchunk_per_minibatch \
        --trainer.frames-per-iter 1500000 \
        --trainer.num-epochs 4 \
        --trainer.optimization.momentum 0 \
        --trainer.optimization.num-jobs-initial 3 \
        --trainer.optimization.num-jobs-final 8 \
        --trainer.optimization.initial-effective-lrate 0.001 \
        --trainer.optimization.final-effective-lrate 0.0001 \
        --trainer.optimization.shrink-value 1.0 \
        --trainer.max-param-change 2.0 \
        --cleanup.remove-egs true \
        --feat-dir data/train \
        --tree-dir $cnn_treedir \
        --dir $cnn_dir  || exit 1;

    echo
    echo "== $0: $(date): DONE NN TRAINING. =="
fi

if [ $stage -le 7 ]; then
    echo
    echo "== $0: $(date): DECODING NN =="
    utils/mkgraph.sh --self-loop-scale 1.0 \
      data/lang ${cnn_dir} ${cnn_dir}/graph || exit 1;

    rm -rf ${cnn_dir}/decode_test
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --extra-left-context 0 \
      --extra-right-context 0 \
      --extra-left-context-initial 0 \
      --extra-right-context-final 0 \
      --frames-per-chunk 340 \
      --nj $nj_test --cmd $cmd \
      ${cnn_dir}/graph \
      data/test ${cnn_dir}/decode_test || exit 1;

    echo
    echo "DONE. Date: $(date). Results:"
    echo "--------------------------------"
    echo -n "# Model              "
    printf "% 10s" " ${cnn_dir}"
    echo
    echo -n "# WER TEST            "
    wer=$(cat ${cnn_dir}/decode_test/scoring_kaldi/best_wer | awk '{print $2}')
    printf "% 10s" $wer
    echo
fi
