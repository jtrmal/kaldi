#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal)
# Apache 2.0.


help_message="$(basename $0): do keyword indexing and search.  data-dir is assumed to have
                 kws/ subdirectory that specifies the terms to search for.  Output is in
                 decode-dir/kws/
             Usage:
                 $(basename $0) <lang-dir> <data-dir> <decode-dir>"

# Begin configuration section.  
#acwt=0.0909091
min_lmwt=7
max_lmwt=17
duptime=0.6
cmd=run.pl
model=
skip_scoring=false
skip_optimization=false # true can speed it up if #keywords is small.
max_states=150000
indicesdir=
stage=0
word_ins_penalty=0
extraid=
silence_word=  # specify this if you did to in kws_setup.sh, it's more accurate.
ntrue_scale=1.1,1.5,2.0,2.2,2.5,3.0,3.5
max_silence_frames=50
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -u
set -e
set -o pipefail


if [[ "$#" -ne "3" ]] ; then
    echo -e "$0: FATAL: wrong number of script parameters!\n\n"
    printf "$help_message\n\n"
    exit 1;
fi

silence_opt=

langdir=$1
kwsdatadir=$2
decodedir=$3

datadir=$(dirname $kwsdatadir)
extraid=$(basename $kwsdatadir)


kwsoutdir=$decodedir/$extraid/
indicesdir=$decodedir/kws_indices

for d in "$datadir" "$kwsdatadir" "$langdir" "$decodedir"; do
  if [ ! -d "$d" ]; then
    echo "$0: FATAL: expected directory $d to exist"
    exit 1;
  fi
done
if [[ ! -f "$kwsdatadir/ecf.xml"  ]] ; then
    echo "$0: FATAL: the $kwsdatadir does not contain the ecf.xml file"
    exit 1;
fi

[ ! -f $kwsdatadir/duration ] && \
  echo "File $kwsdatadir/duration does not exist!" && exit 1
duration=`cat $kwsdatadir/duration`

#duration=`head -1 $kwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`

#duration=`head -1 $kwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    grep -o -E "[0-9]*[\.]*[0-9]*" |\
#    perl -e 'while(<>) {print $_/2;}'`

echo "Duration: $duration"

if [ ! -z "$model" ]; then
    model_flags="--model $model"
else
    model_flags=
fi
  

if [ $stage -le 0 ] ; then
  if [ ! -f $indicesdir/.done.index ] ; then
    [ ! -d $indicesdir ] && mkdir  $indicesdir
    for lmwt in `seq $min_lmwt $max_lmwt` ; do
        indices=${indicesdir}/$lmwt
        mkdir -p $indices
  
        acwt=`perl -e "print (1.0/$lmwt);"` 
        [ ! -z $silence_word ] && silence_opt="--silence-word $silence_word"
        steps/make_index.sh $silence_opt --cmd "$cmd" --acwt $acwt $model_flags\
          --skip-optimization $skip_optimization --max-states $max_states \
          --word-ins-penalty $word_ins_penalty --max-silence-frames $max_silence_frames\
          $kwsdatadir $langdir $decodedir $indices  || exit 1
    done
    touch $indicesdir/.done.index
  else
    echo "Assuming indexing has been aready done. If you really need to re-run "
    echo "the indexing again, delete the file $indicesdir/.done.index"
  fi
fi


if [ $stage -le 1 ]; then
  for lmwt in `seq $min_lmwt $max_lmwt` ; do
      kwsoutput=${kwsoutdir}/$lmwt
      indices=${indicesdir}/$lmwt
      mkdir -p $kwsoutdir
      steps/search_index.sh --cmd "$cmd" --indices-dir $indices --strict false\
        $kwsdatadir $kwsoutput  || exit 1
  done
fi

if [ $stage -le 2 ]; then
  echo "Writing unnormalized results"
  $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/log/write_unnormalized.LMWT.log \
    set -e ';' set -o pipefail ';'\
    cat ${kwsoutdir}/LMWT/result.* \| \
        utils/write_kwslist.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=false --duptime=$duptime --remove-dup=true\
          --map-utter=$kwsdatadir/utter_map \
          - ${kwsoutdir}/LMWT/kwslist.unnormalized.xml || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "Converting the normalized results to hitlist for optimization"
  for scale in ${ntrue_scale//,/ }; do
    $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/log/ntrue_scale.${scale}.LMWT.log \
      set -e ';' set -o pipefail ';' mkdir -p $kwsoutdir/LMWT/ntrue-scale\; \
      cat ${kwsoutdir}/LMWT/result.* \| \
        utils/write_kwslist.pl  --Ntrue-scale=$scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=true --duptime=$duptime --remove-dup=true\
          --map-utter=$kwsdatadir/utter_map --digits=3 - - \|\
        local/kwlist2hitlist.pl \| utils/sym2int.pl -f 2 $kwsdatadir/file_id \|\
        compute-atwv --sweep-step=0.005 $duration \
          ark,t:$kwsdatadir/hits ark,t:- \> $kwsoutdir/LMWT/ntrue-scale/${scale}
  done
  
  for lmwt in `seq $min_lmwt $max_lmwt` ; do
    best=`grep ATWV $kwsoutdir/$lmwt/ntrue-scale/* | sort -k2rn -t'=' | cut -d ':'  -f 1 | head -n 1`
    echo `basename $best` > $kwsoutdir/$lmwt/best_ntrue_scale
  done
fi

if [ $stage -le 4 ]; then
  echo "Writing normalized results (using the optimized ntrue-scale)"
  $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/log/write_normalized.LMWT.log \
    set -e ';' set -o pipefail ';'\
    cat ${kwsoutdir}/LMWT/result.* \| \
    utils/write_kwslist.pl  --Ntrue-scale=\$\(cat $kwsoutdir/LMWT/best_ntrue_scale\)\
        --flen=0.01 --duration=$duration --segments=$datadir/segments \
        --normalize=true --duptime=$duptime --remove-dup=true\
        --map-utter=$kwsdatadir/utter_map --digits=3 \
        - ${kwsoutdir}/LMWT/kwslist.xml || exit 1
fi

if [ $stage -le 5 ]; then
  if [[ (! -x local/kws_score.sh ) ]] ; then
    echo "Not scoring, because the file local/kws_score.sh is not present"
  elif [[ $skip_scoring == true ]] ; then
    echo "Not scoring, because --skip-scoring true was issued"
  else
    echo "Scoring KWS results"
    $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/log/scoring.LMWT.log \
       local/kws_score.sh $kwsdatadir ${kwsoutdir}/LMWT || exit 1;
  fi
fi

if [ $stage -le 6 ]; then
  grep "MTWV" ${kwsoutdir}/*/metrics.txt /dev/null | sort -k2nr -t '=' | head -n 1 | cut -f 1 -d ':' |xargs dirname > ${kwsoutdir}/best_system
  f=`cat $kwsoutdir/best_system`
  cp $f/metrics.txt $kwsoutdir/best_scores
  echo `dirname $f` $kwsoutdir/best_lmwt
  cp $f/best_ntrue_scale $kwsoutdir/best_ntrue_scale
fi

exit 0
