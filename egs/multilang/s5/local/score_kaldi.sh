#!/bin/bash
# Copyright 2012-2014  Johns Hopkins University (Author: Daniel Povey, Yenda Trmal)
# Apache 2.0

[ -f ./path.sh ] && . ./path.sh

# begin configuration section.
cmd=run.pl
stage=0
decode_mbr=false
reverse=false
stats=true
beam=6
word_ins_penalty=0.0,0.5,1.0
min_lmwt=9
max_lmwt=20
filter=
#end configuration section.

echo "$0 $@"  # Print the command line for logging
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 4 ]; then
  echo "Usage: local/score.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --decode_mbr (true/false)       # maximum bayes risk decoding (confusion network)."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  echo "    --reverse (true/false)          # score with time reversed features "
  exit 1;
fi

data=$1
lang_or_graph=$2
dir=$3
dest=$4

symtab=$lang_or_graph/words.txt

for f in $symtab $dir/lat.1.gz $data/text; do
  [ ! -f $f ] && echo "score.sh: no such file $f" && exit 1;
done


ref_filtering_cmd="cat"
[ -x local/wer_output_filter ] && ref_filtering_cmd="local/wer_output_filter"
[ -x local/wer_ref_filter ] && ref_filtering_cmd="local/wer_ref_filter"
[ ! -z "$filter" ] && [ -x $filter ] && ref_filtering_cmd="$filter"
hyp_filtering_cmd="cat"
[ -x local/wer_output_filter ] && hyp_filtering_cmd="local/wer_output_filter"
[ -x local/wer_hyp_filter ] && hyp_filtering_cmd="local/wer_hyp_filter"
[ ! -z "$filter" ] && [ -x $filter ] && hyp_filtering_cmd="$filter"


if $decode_mbr ; then
  echo "$0: scoring with MBR, word insertion penalty=$word_ins_penalty"
else
  echo "$0: scoring with word insertion penalty=$word_ins_penalty"
fi


mkdir -p $dir/$dest
cat $data/text | $ref_filtering_cmd > $dir/$dest/test_filt.txt || exit 1;

if [ $stage -le 0 ]; then

  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    mkdir -p $dir/$dest/penalty_$wip/log

    if $decode_mbr ; then
      $cmd LMWT=$min_lmwt:$max_lmwt $dir/$dest/penalty_$wip/log/best_path.LMWT.log \
        acwt=\`perl -e \"print 1.0/LMWT\"\`\; \
        lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
        lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
        lattice-prune --beam=$beam ark:- ark:- \| \
        lattice-mbr-decode  --word-symbol-table=$symtab \
        ark:- ark,t:- \| \
        utils/int2sym.pl -f 2- $symtab \| \
        $hyp_filtering_cmd '>' $dir/$dest/penalty_$wip/LMWT.txt || exit 1;

    else
      $cmd LMWT=$min_lmwt:$max_lmwt $dir/$dest/penalty_$wip/log/best_path.LMWT.log \
        lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
        lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
        lattice-best-path --word-symbol-table=$symtab ark:- ark,t:- \| \
        utils/int2sym.pl -f 2- $symtab \| \
        $hyp_filtering_cmd '>' $dir/$dest/penalty_$wip/LMWT.txt || exit 1;
    fi

    if $reverse; then # rarely-used option, ignore this.
      for lmwt in `seq $min_lmwt $max_lmwt`; do
        mv $dir/$dest/penalty_$wip/$lmwt.txt $dir/$dest/penalty_$wip/$lmwt.txt.orig
        awk '{ printf("%s ",$1); for(i=NF; i>1; i--){ printf("%s ",$i); } printf("\n"); }' \
          <$dir/$dest/penalty_$wip/$lmwt.txt.orig >$dir/$dest/penalty_$wip/$lmwt.txt
      done
    fi

    $cmd LMWT=$min_lmwt:$max_lmwt $dir/$dest/penalty_$wip/log/score.LMWT.log \
      cat $dir/$dest/penalty_$wip/LMWT.txt \| \
      compute-wer --text --mode=present \
      ark:$dir/$dest/test_filt.txt  ark,p:- ">&" $dir/wer_LMWT_$wip || exit 1;

  done
fi



if [ $stage -le 1 ]; then

  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    for lmwt in $(seq $min_lmwt $max_lmwt); do
      # adding /dev/null to the command list below forces grep to output the filename
      grep WER $dir/wer_${lmwt}_${wip} /dev/null
    done
  done | utils/best_wer.sh  >& $dir/$dest/best_wer || exit 1

  best_wer_file=$(awk '{print $NF}' $dir/$dest/best_wer)
  best_wip=$(echo $best_wer_file | awk -F_ '{print $NF}')
  best_lmwt=$(echo $best_wer_file | awk -F_ '{N=NF-1; print $N}')

  if [ -z "$best_lmwt" ]; then
    echo "$0: we could not get the details of the best WER from the file $dir/wer_*.  Probably something went wrong."
    exit 1;
  fi

  if $stats; then
    mkdir -p $dir/$dest/wer_details
    echo $best_lmwt > $dir/$dest/wer_details/lmwt # record best language model weight
    echo $best_wip > $dir/$dest/wer_details/wip # record best word insertion penalty

    $cmd $dir/$dest/log/stats1.log \
      cat $dir/$dest/penalty_$best_wip/$best_lmwt.txt \| \
      align-text --special-symbol="'***'" ark:$dir/$dest/test_filt.txt ark:- ark,t:- \|  \
      utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" \| tee $dir/$dest/wer_details/per_utt \|\
       utils/scoring/wer_per_spk_details.pl $data/utt2spk \> $dir/$dest/wer_details/per_spk || exit 1;

    $cmd $dir/$dest/log/stats2.log \
      cat $dir/$dest/wer_details/per_utt \| \
      utils/scoring/wer_ops_details.pl --special-symbol "'***'" \| \
      sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 \> $dir/$dest/wer_details/ops || exit 1;
  fi
fi

# If we got here, the scoring was successful.
# As a  small aid to prevent confusion, we remove all wer_{?,??} files;
# these originate from the previous version of the scoring files 
rm $dir/wer_{?,??} 2>/dev/null

exit 0;
