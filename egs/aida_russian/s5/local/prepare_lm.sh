#!/bin/bash
# Copyright (c) 2019, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
# End configuration section
. ./path.sh || die "path.sh expected";

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

unk=$1

local/train_lms_srilm.sh --oov_symbol "$unk" --train-text data/train/text data/ data/srilm

# for basic decoding, let's use only a trigram LM
[ -d data/lang_test/ ] && rm -rf data/lang_test
lm=$(cat data/srilm/perplexities.txt | grep 3gram | head -n1 | awk '{print $1}')
utils/format_lm.sh data/lang $lm data/local/dict/lexicon.txt data/lang_test

