#!/bin/bash
#

# To be run from one directory above this script.

## The input is some directory containing the switchboard-1 release 2
## corpus (LDC97S62).  Note: we don't make many assumptions about how
## you unpacked this.  We are just doing a "find" command to locate
## the .sph files.

# for example /mnt/matylda2/data/SWITCHBOARD_1R2

. path.sh

#check existing directories
if [ $# != 2 ]; then
   echo "Usage: callhome_data_prep.sh /path/to/SWBD /path/to/trans"
   exit 1; 
fi 

echo ARGS $1 $2

AUDIO_DIR=$1
TRANS_DIR=$2

# Audio data directory check
if [ ! -d $AUDIO_DIR ]; then
  echo "Error: run.sh requires a directory arguments"
  exit 1; 
fi  

# Audio data directory check
if [ ! -d $TRANS_DIR ]; then
  echo "Error: run.sh requires two directory arguments"
  exit 1; 
fi  

mkdir -p data/train_primary
mkdir -p data/dev10h
mkdir -p data/dev2h


ldctrain=$AUDIO_DIR/train
trtrans=$TRANS_DIR/train
echo "Preparing train corpora from $ldctrain"
perl local/corpora/chsp_fisher/make_corpus.pl data/train_primary \
    $ldctrain $trtrans || (echo "Error " &&  exit 1 ) 

ldcdev=$AUDIO_DIR/devtest
devtrans=$TRANS_DIR/devtest
echo "Preparing dev2h corpora from $ldcdev"
perl local/corpora/chsp_fisher/make_corpus.pl data/dev2h \
    $ldcdev $devtrans || (echo "Error " &&  exit 1 ) 


ldceval=$AUDIO_DIR/evltest
evaltrans=$TRANS_DIR/evltest
echo "Preparing dev10h corpora from $ldceval"
perl local/corpora/chsp_fisher/make_corpus.pl data/dev10h \
    $ldceval $evaltrans || (echo "Error " &&  exit 1 ) 
 
echo Callhome Spanish data preparation succeeded.

