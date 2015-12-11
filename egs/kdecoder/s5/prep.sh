#!/bin/bash
# Copyright (c) 2015, Johns Hopkins University (Author: Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
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


if [ ! -f data/raw_train_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Creating  the BABEL-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_train_data
  local/make_corpus_subset.sh "$train_data_dir" "$train_data_list" ./data/raw_train_data
  touch data/raw_train_data/.done
fi

if [ ! -f data/train/.done ]; then
  mkdir -p data/train
  local/prepare_acoustic_training_data.pl \
    --fragmentMarkers \-\*\~ \
    data/raw_train_data data/train > data/train/skipped_utts.log || exit 1

  touch data/train/.done

fi


if [ ! -f data/raw_dev2h_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Creating  the BABEL-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_dev2h_data
  local/make_corpus_subset.sh "$dev2h_data_dir" "$dev2h_data_list" ./data/raw_dev2h_data
  touch data/raw_dev2h_data/.done
fi

if [ ! -f data/dev2h/.done ]; then
  mkdir -p data/dev2h
  local/prepare_acoustic_training_data.pl \
    --fragmentMarkers \-\*\~ \
    data/raw_dev2h_data data/dev2h > data/dev2h/skipped_utts.log || exit 1

  touch data/dev2h/.done

fi


if [ ! -z ${dev10h_data_list} ]; then

if [ ! -f data/raw_dev10h_data/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Creating  the BABEL-TRAIN set"
  echo ---------------------------------------------------------------------
  mkdir -p data/raw_dev10h_data
  local/make_corpus_subset.sh "$dev10h_data_dir" "$dev10h_data_list" ./data/raw_dev10h_data
  touch data/raw_dev10h_data/.done
fi

if [ ! -f data/dev10h/.done ]; then
  mkdir -p data/dev10h
  local/prepare_acoustic_training_data.pl \
    --fragmentMarkers \-\*\~ \
    data/raw_dev10h_data data/dev10h > data/dev10h/skipped_utts.log || exit 1

  touch data/dev10h/.done

fi
fi

