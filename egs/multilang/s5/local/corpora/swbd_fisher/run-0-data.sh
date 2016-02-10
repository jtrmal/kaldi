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

#  SWITCHBOARD PREP
if [ ! -d local.swbd ]; then
  echo Please symlink in the switchboard recipe local directory as local.swbd
  exit 1
fi

if [[ ! -f data/train_primary/.done ]]; then 

    if [ -d ../exp_A/data/local/train/swbd_ms98_transcriptions ]; then
        ln -s `pwd`/../exp_A/data/local/train/swbd_ms98_transcriptions \
            data/local/train/swbd_ms98_transcriptions 
    fi

    if [ ! -d data/local/train/swb_ms98_transcriptions ]; then
        local.swbd/swbd1_data_download.sh /export/corpora3/LDC/LDC97S62
        # now we have data/local/train/swb_ms98_transcriptions
    fi
    
    echo "Preparing lexicon..."
    if [ ! -f data/local/dict_nosp/lexicon5.txt ]; then
        sed 's/local/local.swbd/' local.swbd/swbd1_prepare_dict.sh  | \
            sed 's/data\/local.swbd/data\/local/' > data/local/train/swbd.sh
        
        bash data/local/train/swbd.sh
    fi
    
    echo "Preparing Switchboard training data from LDC97S62 "
    
    if  [ ! -f data/train_primary/wav.scp ]; then
        sed 's/local/local.swbd/' local.swbd/swbd1_data_prep.sh  | \
            sed 's/data\/local.swbd/data\/local/' > data/local/train/swbd2.sh
        
        bash data/local/train/swbd2.sh /export/corpora3/LDC/LDC97S62
        
        
    # change segment id's to be only utterance start...
        
        awk '{ print $1 }' < data/train/utt2spk | sed 's/_[0-9]*$//' | sort -u > data/train/list
        mv data/train data/train_primary
        
        
    fi
    
    train_data_list=data/train/list
    
    
    
    if [ ! -d data/local/dict ]; then
        mkdir data/local/dict
    fi
    
    echo "Preparing kaldi lexicon $train_secondary_list" 
    
    local/filter_lexicon_kaldi.pl data/train_primary \
        data/local/dict_nosp/lexicon.txt data/local/dict/filtered_primary_lexicon.txt

    touch data/train_primary/.done

fi

if [[ ! -z ${train_list_secondary+x} ]]; then 
    echo "Preparing fisher corpus"

    if [[ ! -d data/train_secondary ]]; then
        mkdir -p data/train_secondary
        local/prepare_fisher_corpus.pl data/train_secondary $train_list_secondary \
            $train_speech $train_transcripts
    fi

    # construct lexicon from switchboard, create g2p model if phonetisauruis is installed

    cp data/local/dict/filtered_primary_lexicon.txt \
        data/local/dict/filtered_secondary_lexicon.txt
    
    
    
    align=`which phonetisaurus-align`
    if [[ ! -z $align ]]; then
        echo "Running g2p"
        
        local/train_g2p.sh data/local/dict/filtered_primary_lexicon.txt \
            data/local/dict data/train_secondary/text > \
            data/local/dict/secondary_lexicon.txt

        local/filter_lexicon_kaldi.pl data/train_secondary \
            data/local/dict/secondary_lexicon.txt \
            data/local/dict/filtered_secondary_lexicon_add.txt

        cat data/local/dict/filtered_secondary_lexicon_add.txt >> \
            data/local/dict/filtered_secondary_lexicon.txt

    fi
    
    if [[ -z ${train_list+x} ]]; then
        mv data/local/dict/filtered_primary_lexicon.txt data/local/dict/old_lexicon.txt
    fi

fi


exit 0

