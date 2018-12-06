#!/bin/bash
# Copyright (c) 2018, Johns Hopkins University (Yenda Trmal <jtrmal@gmail.com>)
# Based on ../../mini_librispeech/local/run_kws.sh
# Adjusted for Pashto OCR    2018 (Martin Bulin <bulinmartin@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
flen=0.01
stage=0
cmd=run.pl
nj_align=4
data=data/test
lang=data/lang
ref_model=exp/sat                         # model used for hitlist creation
system=exp/cnn_e2e/decode_test/           # choose your KWS system here
keywords=local/kws/example/keywords.txt   # put your keywords in here
output=data/test/kws/
min_lmwt=8
max_lmwt=10
# End configuration section

. ./utils/parse_options.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

if [ $stage -le 0 ]; then
  echo
  echo "== $0: $(date): STAGE 0: CHECKING PREREQUISITIES =="

  for d in $data $ref_model $system; do
    if [ ! -d $d ]; then
      echo "ERR: Expected directory $d to exist." && exit 1;
    fi
  done

  mkdir -p $output
fi

if [ $stage -le 1 ] ; then
  echo
  echo "== $0: $(date): STAGE 1: GENERATING AUXILIARY FILES =="
  echo "== utt.map, images.map, trials, frame_length, keywords.int =="

  ## For simplicity, we do not generate the following files
  ## categories

  utils/data/get_utt2dur.sh $data

  duration=$(cat ${data}/utt2dur | awk '{sum += $2} END{print sum}' )

  echo $duration > ${output}/trials
  echo $flen > ${output}/frame_length

  echo "Number of trials: $(cat ${output}/trials)"
  echo "Frame lengths: $(cat ${output}/frame_length)"

  echo "Generating map files"
  cat ${data}/utt2dur | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > ${output}/utt.map
  cat ${data}/images.scp | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > ${output}/images.map

  cp ${lang}/words.txt ${output}/words.txt
  cp $keywords ${output}/keywords.txt
  cat ${output}/keywords.txt | \
    local/kws/keywords_to_indices.pl --map-oov 0  ${output}/words.txt | \
    sort -u > ${output}/keywords.int
fi

if [ $stage -le 2 ] ; then
  echo
  echo "== $0: $(date): STAGE 2: GENERATING THE HITLIST (REFERENCE) =="

  ## in many cases, when the reference hits are given, the following two steps \
  ## are not needed, here we create the alignments of the data directory
  ## this is only so that we can obtain the hitlist
  ## you need to adjust the aligning script if not using sat (fmllr)

  if [ ! -d "${ref_model}_ali_$(basename $data)" ]; then
    steps/align_fmllr.sh --nj $nj_align --cmd "$cmd" \
        $data $lang $ref_model "${ref_model}_ali_$(basename $data)"
  fi

  local/kws/create_hitlist.sh $data $lang data/local/lang_work \
    "${ref_model}_ali_$(basename $data)" $output
fi

if [ $stage -le 3 ] ; then
  echo
  echo "== $0: $(date): STAGE 3: GENERATING THE KEYWORDS FSTS =="

  ## compile the keywords (it's done via tmp work dirs, so that
  ## you can use the keywords filtering and then just run fsts-union
  local/kws/compile_keywords.sh $output $lang ${output}/tmp.2
  cp ${output}/tmp.2/keywords.fsts ${output}/keywords.fsts
  # for example
  #    fsts-union scp:<(sort data/$dir/kwset_${set}/tmp*/keywords.scp) \
  #      ark,t:"|gzip -c >data/$dir/kwset_${set}/keywords.fsts.gz"
  ##
fi

if [ $stage -le 4 ]; then
  echo
  echo "== $0: $(date): STAGE 4: MAKING THE INDEX (INDICES $min_lmwt to $max_lmwt) =="

  ## this is not exactly necessary for a single system and single keyword set
  ## but if you have multiple keyword sets, then it avoids having to recompute
  ## the indices unnecesarily every time (see --indices-dir and --skip-indexing
  ## parameters to the search script bellow).
  for lmwt in $(seq $min_lmwt $max_lmwt) ; do
    steps/make_index.sh --cmd "$cmd" --lmwt $lmwt --acwt 1.0 \
      --frame-subsampling-factor 4 \
      $output $lang $system ${system}/kws_indices_${lmwt}
  done
fi

if [ $stage -le 5 ]; then
  echo
  echo "== $0: $(date): STAGE 5: SEARCHING, NORMALIZING, SCORING =="

  local/kws/search.sh --cmd "$cmd" --min-lmwt $min_lmwt --max-lmwt $max_lmwt \
    --indices-dir ${system}/kws_indices --skip-indexing true \
    $lang $data $system
fi

if [ $stage -le 6 ]; then
  echo
  echo "== $0: $(date): STAGE 6: RESULTS =="
    
  echo
  echo "== $0: $(date): Keywords: =="
  cat local/kws/example/keywords.txt

  echo
  echo "== $0: $(date): KWS Result: =="
  find $system -name "score.txt" -path "*details*" | \
    xargs -I % sh -c "printf %': '; head -n 1 %;" | \
      sort -rn -k5 | head -n 1

  #find $system -name "score.txt" -path "*details*" | \
  #  xargs -I % sh -c "printf %': '; awk 'FNR == 1' %;" | \
  #    sort -rn -k5 | head -n 1 > ${system}/RESULTS.kws
  #
  #find $system -name "score.txt" -path "*details*" | \
  #  xargs -I % sh -c "printf %': '; awk 'FNR == 2' %;" | \
  #    sort -rn -k5 | head -n 1 >> ${system}/RESULTS.kws
  #
  #find $system -name "score.txt" -path "*details*" | \
  #  xargs -I % sh -c "printf %': '; awk 'FNR == 3' %;" | \
  #    sort -rn -k5 | head -n 1 >> ${system}/RESULTS.kws
  #
  #find $system -name "score.txt" -path "*details*" | \
  #  xargs -I % sh -c "printf %': '; awk 'FNR == 5' %;" | \
  #    sort -rn -k5 | head -n 1 >> ${system}/RESULTS.kws
fi

echo
echo "== $0: $(date): DONE. =="
