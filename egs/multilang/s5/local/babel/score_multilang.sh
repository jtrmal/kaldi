#!/bin/bash

data_primary=dev10h_primary
data_secondary=dev10h_secondary
min_lmwt=7
max_lmwt=17
ntrue_scale=1.0
duptime=0.6
cmd=run.pl


. utils/parse_options.sh

if [ $# -ne 2 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

. ./local.conf


expdir=$1
expdirB=$2

decodeA=$expdir/decode_${data_primary}_utt_offline_prob
decodeB=$expdirB/decode_${data_secondary}_utt_offline_prob


if [ ! -f $decodeA/exA_kws_$min_lmwt/kwslist.xml.orig ]; then
echo 	run.pl LMWT=$min_lmwt:$max_lmwt /dev/null \
		cp $decodeA/exA_kws_LMWT/kwslist.xml $decodeA/exA_kws_LMWT/kwslist.xml.orig
fi


echo "Writing normalized results"
kwsoutdir=$decodeA/exA_kws

cat data/$data_primary/segments data/$data_secondary/segments > $kwsoutdir/segments
cat data/$data_primary/exA_kws/utter_map data/$data_secondary/exB_kws/utter_map > $kwsoutdir/utter_map

duration=`head -1 data/$data_primary/exA_kws/ecf.xml |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`


$cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/write_normalized.LMWT.log \
    set -e ';' set -o pipefail ';'\
    cat $decodeA/exA_kws_LMWT/result.* $decodeB/exB_kws_LMWT/result.* \| \
      utils/write_kwslist.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
        --segments=$kwsoutdir/segments --normalize=true --duptime=$duptime --remove-dup=true\
        --map-utter=$kwsoutdir/utter_map --digits=3 \
        - $decodeA/exA_kws_LMWT/kwslist.xml || exit 1


$cmd LMWT=$min_lmwt:$max_lmwt $decodeA/exA_kws/log/score.LMWT.log \
	local/babel/kws_score.sh --extraid exA data/$data_primary $decodeA/exA_kws_LMWT


