#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.
data_only=true

[ ! -f ./local.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;

[ -f local.conf ] && . ./local.conf

. ./utils/parse_options.sh

set -e           #Exit on non-zero return code from any command
#set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

#Preparing dev2h and train directories


if [ ! -d data/local/dict ]; then
    mkdir -p data/local/dict
fi

mkdir -p data/local
if [[ ! -f data/local/dict/lexicon.txt || data/local/dict/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data/local on" `date`
  echo ---------------------------------------------------------------------
  local/make_lexicon_subset.sh $train_data_dir/transcription $lexicon_file data/local/dict/primary_lexicon.txt
#  echo   local/prepare_lexicon.pl  --phonemap "\"$phoneme_mapping\"" \
#      '$lexiconFlags' data/local/filtered_lexicon.txt data/local
#  local/prepare_lexicon.pl  --phonemap "$phoneme_mapping" \
#      $lexiconFlags data/local/dict/primary_lexicon.txt data/local/dict || exit 1
fi


#echo "Converting Appen lexicon to babel format"
#local/corpora/chsp_fisher/ldclex2babel.pl $lexicon_file \
#     data/local/dict/primary_lexicon.txt 
#cp data/local/dict/filtered_lexicon.txt data/local/dict/primary_lexicon.txt



#exit 0

if [[ ! -z ${train_list_primary} ]]; then
    
    echo "Preparing Babel  training data from $train_data_dir ($train_list_primary)"
    if  [[ ! -f data/raw_train_primary/.done ]]; then
    
	local/make_corpus_subset.sh "$train_data_dir" "$train_list_primary" ./data/raw_train_primary
	touch data/raw_train_primary/.done 

    fi

    if [[ ! -f data/train_primary/wav.scp || data/train_primary/wav.scp -ot "$train_data_dir" ]]; then
	echo ---------------------------------------------------------------------
	echo "Preparing acoustic training lists in data/train_primary on" `date`
	echo ---------------------------------------------------------------------
	mkdir -p data/train_primary
	local/prepare_acoustic_training_data.pl \
	    --vocab data/local/dict/primary_lexicon.txt --fragmentMarkers \-\*\~ \
	    `pwd`/data/raw_train_primary data/train_primary > data/train_primary/skipped_utts.log
    fi


    local/filter_lexicon_kaldi.pl data/train_primary  \
	data/local/dict/primary_lexicon.txt \
	data/local/dict/filtered_primary_lexicon.txt

    
    awk '{ print $1 }' < data/train_primary/utt2spk | sed 's/_[0-9]*$//' | sort -u > data/train_primary/list
    
    touch data/train_primary/.done    
fi
    

if [[ ! -z ${train_list_secondary} ]]; then 
    echo "Preparing fisher corpus"

    if  [[ ! -f data/raw_train_secondary/.done ]]; then
    
	local/make_corpus_subset.sh "$train_data_dir" "$train_list_secondary" ./data/raw_train_secondary
	touch data/raw_train_secondary/.done 

    fi

    if [[ ! -f data/train_secondary/wav.scp || data/train_secondary/wav.scp -ot "$train_data_dir" ]]; then
	echo ---------------------------------------------------------------------
	echo "Preparing acoustic training lists in data/train_primary on" `date`
	echo ---------------------------------------------------------------------
	mkdir -p data/train_secondary
	local/prepare_acoustic_training_data.pl \
	    --vocab data/local/dict/primary_lexicon.txt --fragmentMarkers \-\*\~ \
	    `pwd`/data/raw_train_secondary data/train_secondary > data/train_secondary/skipped_utts.log
    fi

    
#    cp data/local/dict/filtered_primary_lexicon.txt \
#        data/local/dict/filtered_secondary_lexicon.txt
        
    echo "Using primary lexicon\n";
    local/filter_lexicon_kaldi.pl data/train_secondary \
        data/local/dict/primary_lexicon.txt \
        data/local/dict/filtered_secondary_lexicon.txt
    
#    if [[ -z ${train_list_primary+x} ]]; then
#        mv data/local/dict/filtered_primary_lexicon.txt data/local/dict/old_lexicon.txt
#    fi

fi

# prepare decode corpora

for d in primary secondary ; do
corpus="dev10h_$d"
if [[ ! -f data/$corpus/.done ]]; then
	local/make_corpus_subset.sh "$dev10h_data_dir" dev_${d}.list ./data/raw_$corpus
	mkdir -p data/$corpus
	local/prepare_acoustic_training_data.pl \
	    --vocab data/local/dict/primary_lexicon.txt --fragmentMarkers \-\*\~ \
	    `pwd`/data/raw_$corpus data/$corpus > data/$corpus/skipped_utts.log

    touch data/$corpus/.done
fi
done


exit 0

