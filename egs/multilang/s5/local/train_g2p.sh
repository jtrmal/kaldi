#!/bin/bash

psdir=
order=7

. ./utils/parse_options.sh

#set -e           #Exit on non-zero return code from any command
#set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

inlex=$1
outdir=$2
trans=$3


if [[ -z $psdir ]]; then
    align=`which phonetisaurus-align`
    psdir=`dirname $align`/../..
fi

export LD_LIBRARY_PATH=$psdir/openfst/lib:$LD_LIBRARY_PATH

# must be WORDtabPRON
cut -f2- $inlex > $outdir/primary.lex
inlex=$outdir/primary.lex

echo $psdir/src/bin/phonetisaurus-align --input=$inlex --ofile=$outdir/train.corpus  1>&2
$psdir/src/bin/phonetisaurus-align --input=$inlex --ofile=$outdir/train.corpus || echo 'Ignore error code here' 1>&2

echo ngram-count -order $order -lm $outdir/arpa.lm -text $outdir/train.corpus 1>&2
ngram-count -order $order -lm $outdir/arpa.lm -text $outdir/train.corpus

echo $psdir/src/bin/phonetisaurus-arpa2wfst --lm=$outdir/arpa.lm --ofile=$outdir/g2p.fst 1>&2
$psdir/src/bin/phonetisaurus-arpa2wfst --lm=$outdir/arpa.lm --ofile=$outdir/g2p.fst || echo 'Ignore error here' 1>&2

# cat $trans | cut -f2- -d' ' |
#echo cat $trans \| cut -f2- -d' '  \| tr " " "\n" \| sort \| uniq \> $outdir/uniq.words
cat $trans | cut -f2- -d' '  | tr " " "\n" | sort | uniq > $outdir/uniq.words
awk '{print $1}' $inlex | sort | uniq > $outdir/lex.uniq.words

diff $outdir/lex.uniq.words $outdir/uniq.words | grep "^>" | awk '{print $2}' > $outdir/new.words 

echo $psdir/src/bin/phonetisaurus-g2pfst \
    --model=$outdir/g2p.fst --wordlist=$outdir/new.words 1>&2

$psdir/src/bin/phonetisaurus-g2pfst \
    --model=$outdir/g2p.fst --wordlist=$outdir/new.words | cut -f1,3 


exit 0






