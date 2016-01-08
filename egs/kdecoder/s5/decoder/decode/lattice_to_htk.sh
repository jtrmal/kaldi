#!/bin/bash
# Copyright Johns Hopkins University (Author: Daniel Povey) 2012.  Apache 2.0.

# begin configuration section.
cmd=run.pl
stage=0
decode_mbr=true
beam=5
word_ins_penalty=0.5
lmwt=11

#end configuration section.

#debugging stuff
echo $0 $@

. parse_options.sh || exit 1;

lang=$1
model=$2
lattice=$3
outdir=$4

lattice-align-words \
    $lang/phones/word_boundary.int $model \
    "ark:zcat $lattice |" ark:-  | \
    lattice-determinize ark:- ark,t:- | \
    int2sym.pl -f 3 $lang/words.txt |  \
    convert_slf.pl  - $outdir
    
exit 0