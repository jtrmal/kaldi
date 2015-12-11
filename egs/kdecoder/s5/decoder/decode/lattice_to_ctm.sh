#!/bin/bash
# Copyright Johns Hopkins University (Author: Daniel Povey) 2012.  Apache 2.0.

# begin configuration section.
cmd=run.pl
stage=0
decode_mbr=true
beam=5
word_ins_penalty=0.5
lmwt=11
model=

#end configuration section.

#debugging stuff
echo $0 $@

. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <dataDir> <langDir|graphDir> <decodeDir>" && exit;
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1)                 # (createCTM | filterCTM )."
  exit 1;
fi

data=$1
lang=$2 # Note: may be graph directory not lang directory, but has the necessary stuff copied.
dir=$3

if [ -z "$model" ] ; then
    echo must specify model location.
    exit 1
fi


for f in $lang/words.txt $lang/phones/word_boundary.int \
     $model $data/segments $data/reco2file_and_channel $dir/lat.1.gz; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

name=`basename $data`; # e.g. eval2000

mkdir -p $dir/scoring/log

lattice-scale --inv-acoustic-scale=$lmwt "ark:zcat $dir/lat.*.gz|" ark:- | \
    lattice-add-penalty --word-ins-penalty=$word_ins_penalty ark:- ark:- | \
    lattice-prune --beam=$beam ark:- ark:- | \
    lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- | \
    lattice-to-ctm-conf --decode-mbr=$decode_mbr ark:- - | \
    int2sym.pl -f 5 $lang/words.txt | tee $dir/$name.utt.ctm | \
    convert_ctm.pl $data/segments $data/reco2file_and_channel > \
    $dir/$name.ctm || exit 1;


  # Remove some stuff we don't want to score, from the ctm.
x=$dir/$name.ctm
cp $x $x.bkup1;
cat $x.bkup1 | grep -v -E '\[NOISE|LAUGHTER|VOCALIZED-NOISE\]' | \
    grep -v -E '<UNK>|%HESITATION|\(\(\)\)' | \
    grep -v -E '<eps>' | \
    grep -v -E '<noise>' | \
    grep -v -E '<silence>' | \
    grep -v -E '<hes>' | \
    grep -v -E '<unk>' | \
    grep -v -E '<v-noise>' > $x;

echo "Lattice2CTM finished on " `date`
exit 0
