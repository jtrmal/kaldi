#!/bin/bash

# Apache 2.0

# Collects the data.
# -> data/train/
# --> text, images.scp, utt2spk, spk2utt

# -> data/test/
# --> text, images.scp, utt2spk, spk2utt

# -> data/local/
# --> allowed_lengths.txt
# --> images/

# -> data/log/
# --> collect_data.log

set -e

. ./path.sh

corpus_location=$1

if [ -d data ]; then
    read -p "Data folder already exists. Overwrite it? [y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping."
        exit 1;
    fi
fi

rm -rf data
mkdir -p data/train
mkdir -p data/test
mkdir -p data/local
mkdir -p data/log

# Transform the raw data into the kaldi-compatible format
local/collect_data.py --raw_data_path $corpus_location \
                      --us_spks 12 \
                      --af_spks 370 \
                      --first_spknb_test 351 \
                      --feat_dim 40 \
                      --save_images false || exit 1

# Convert utt2spk into spk2utt for train and test
utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt
utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt
