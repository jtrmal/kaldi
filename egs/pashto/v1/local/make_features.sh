#!/bin/bash

# Apache 2.0


# Extracts features for the "train" and "test" data subsets.
# -> data/train/
# --> feats.scp, cmvn.scp

# -> data/train/data/
# --> images.ark, cmvn_train.scp, cmvn_train.ark

# -> data/test/
# --> feats.scp, cmvn.scp

# -> data/test/data/
# --> images.ark, cmvn_test.scp, cmvn_test.ark

set -e

. ./path.sh

rm -rf data/{train,test}/data
mkdir -p data/{train,test}/data

# Convert the images into kaldi matrices
for set_name in train test; do
    local/make_features.py --images_orig_file data/${set_name}/images_orig.scp \
                           --images_file data/${set_name}/images.scp \
                           --feat_dim 40 \
                           --save_images false \
                           --fliplr true | \
    copy-feats --compress=true --compression-method=7 \
               ark:- ark,scp:data/${set_name}/data/images.ark,data/${set_name}/feats.scp || exit 1

    steps/compute_cmvn_stats.sh data/${set_name} || exit 1;
done
