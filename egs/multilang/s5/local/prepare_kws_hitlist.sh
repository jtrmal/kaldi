#!/bin/bash                                                                        
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
cmd="run.pl"
nj=64
duptime=0.0
stage=0
# End configuration section
echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

if [ $# != 3 ] ; then
   echo "Usage: steps/kws_prepare_ref.sh <data-dir> <lang-dir> <ali-dir> "
   exit 1
fi

alidir=$3
langdir=$2
kwsdatadir=$1

extraid=$( basename $kwsdatadir )
datadir=$( dirname $kwsdatadir )
dataid=$( basename $datadir )
output=$alidir/$extraid
keywords=$kwsdatadir/keywords.fsts


mkdir -p $output
if [ $stage -le 0 ] ; then
  $cmd JOB=1:$nj $output/log/search.JOB.log \
    linear-to-nbest  'ark:gunzip -c '$alidir'/ali.JOB.gz|' \
                     'ark:utils/sym2int.pl -f 2- --map-oov "<unk>" '$langdir'/words.txt '$datadir'/text |' \
                     '' \
                     '' \
                     ark:-  \| \
      lattice-align-words --test $langdir/phones/word_boundary.int  $alidir/final.mdl ark:- ark:- \| \
      lattice-to-kws-index --allow-partial=true ark:$kwsdatadir/utter_id  ark:- ark:- \|\
      kws-index-union --skip-optimization=false --strict=false ark:- ark:- \|\
      kws-search --strict=true ark:-  ark:$keywords "ark,t:|int2sym.pl -f 2 $kwsdatadir/utter_id > $output/hits.JOB"
fi

[ ! -f $kwsdatadir/duration ] && echo "File $kwsdatadir/duration does not exist" && exit 1
duration=$(cat $kwsdatadir/duration)

if [ $stage -le 1 ]; then
  echo "Writing normalized results"
    cat $output/hits.* |\
      utils/write_kwslist.pl  --Ntrue-scale=1.0 --flen=0.01 --duration=$duration \
        --segments=$datadir/segments --normalize=true --duptime=$duptime --remove-dup=false\
        --map-utter=$kwsdatadir/utter_map --digits=3 - - |\
      local/kwlist2hitlist.pl |\
      utils/sym2int.pl -f 2 $kwsdatadir/file_id > $output/hits || exit 1
fi

