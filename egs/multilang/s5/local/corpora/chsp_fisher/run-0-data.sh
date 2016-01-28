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

if [[ ! -f data/train_primary/.done ]]; then 
    
    echo "Preparing Callhome training data from LDC96S35 "
    
    local/corpora/chsp_fisher/callhome_data_prep.sh $chsp_audio $chsp_trans
    
    awk '{ print $1 }' < data/train_primary/utt2spk | sed 's/_[0-9]*$//' | sort -u > data/train_primary/list
    
    touch data/train_primary/.done    
fi
    
if [ ! -d data/local/dict ]; then
    mkdir -p data/local/dict
fi

echo "Converting LDC spanish lexicon to babel format"
local/corpora/chsp_fisher/ldclex2babel.pl $lexicon_file \
     data/local/dict/primary_lexicon.txt 

local/filter_lexicon_kaldi.pl data/train_primary  \
    data/local/dict/primary_lexicon.txt \
    data/local/dict/filtered_primary_lexicon.txt

if [[ ! -z ${train_list_secondary} ]]; then 
    echo "Preparing fisher corpus"

    if [[ ! -f data/train_secondary/.done ]]; then
        mkdir -p data/train_secondary
	echo local/corpora/chsp_fisher/prepare_fisher_corpus.pl \
	    data/train_secondary $train_list_secondary \
            $fisher_audio $fisher_trans

        local/corpora/chsp_fisher/prepare_fisher_corpus.pl \
	    data/train_secondary $train_list_secondary \
            $fisher_audio $fisher_trans data/raw_audio

	touch data/train_secondary/.done
    fi

    # construct lexicon from switchboard, create g2p model if phonetisauruis is installed
    
    cp data/local/dict/filtered_primary_lexicon.txt \
        data/local/dict/filtered_secondary_lexicon.txt
        
    (align=`which phonetisaurus-align`) || echo cannot find phonetisaurus
    if [[ ! -z $align ]]; then
        echo "Running g2p"
        
        local/train_g2p.sh data/local/dict/primary_lexicon.txt \
            data/local/dict data/train_secondary/text > \
            data/local/dict/secondary_lexicon.txt

        local/filter_lexicon_kaldi.pl data/train_secondary \
            data/local/dict/secondary_lexicon.txt \
            data/local/dict/filtered_secondary_lexicon_add.txt

        cat data/local/dict/filtered_secondary_lexicon_add.txt >> \
            data/local/dict/filtered_secondary_lexicon.txt
	
    else
	echo "Using primary lexicon\n";
	local/filter_lexicon_kaldi.pl data/train_secondary \
            data/local/dict/primary_lexicon.txt \
            data/local/dict/filtered_secondary_lexicon.txt
    fi
    
    if [[ -z ${train_list_primary+x} ]]; then
        mv data/local/dict/filtered_primary_lexicon.txt data/local/dict/old_lexicon.txt
    fi

fi

# prepare decode corpora

if [[ ! -f data/fsp_eval/.done ]]; then
    mkdir -p data/fsp_eval
    local/corpora/chsp_fisher/prepare_fisher_corpus.pl \
	data/fsp_eval $fsp_eval_list \
        $fisher_audio $fisher_trans data/raw_audio

    touch data/fsp_eval/.done
fi


exit 0

