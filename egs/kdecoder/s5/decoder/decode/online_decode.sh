#!/bin/bash

# Copyright 2015 Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# Begin configuration section.
nj=1
cmd=run.pl
max_active=7000
threaded=false
modify_ivector_config=false
beam=15.0
lattice_beam=6.0
acwt=0.1
per_utt=true
online=false
do_endpointing=false
do_speex_compressing=false
scoring_opts=
skip_scoring=false
use_gpu=false
srcdir=
decode_config=
silence_weight=1.0
max_state_duration=40
iter=final
# End configuration section.

echo "$0 $@" # print the command line for logging

. parse_options.sh
# path needs to be properly set externally

if [ $# != 3 ]; then
    
    echo "Usage: "
    exit 1
fi

#graphdir=$1
lpdir=$1
data=$2
dir=$3
sdata=$data/split$nj

graphdir=$lpdir/graph

mkdir -p $dir/log
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $data $nj || exit 1

echo $nj > $dir/num_jobs

if [[ -z $decode_config ]]; then
  decode_config=$lpdir/conf/online_nnet2_decoding.conf
fi

for f in $decode_config $lpdir/final.mdl \
    $graphdir/HCLG.fst $graphdir/words.txt $data/wav.scp ; do
    if [ ! -f $f ]; then
	echo "$0: no such file $f"
	exit 1
    fi
done

if ! $per_utt; then
    spk2utt_rspecifier="ark:$sdata/JOB/spk2utt"
else
    mkdir -p $dir/per_utt
    for j in $(seq $nj); do
	awk '{print $1, $1}' < $sdata/$j/utt2spk > $dir/per_utt/utt2spk.$j || exit 1
    done
    spk2utt_rspecifier="ark:$dir/per_utt/utt2spk.JOB"
fi

if [ -f $data/segments ]; then
    wav_rspecifier="ark,s,cs:extract-segments scp,p:$sdata/JOB/wav.scp $sdata/JOB/segments ark:- |"
else
    wav_rspecifier="ark,s,cs:wav-copy scp,p:$sdata/JOB/wav.scp ark:- |"
fi

if $do_speex_compressing; then
    wav_rspecifier="$wav_rspecifier compress-uncompress-speex ark:- ark:- |"
fi

if $do_endpointing; then
    wav_rspecifier="$wav_rspecifier extend-wav-with-silence ark:- ark:- |"
fi

if [ "$silence_weight" != "1.0" ]; then
    silphones=$(cat $graphdir/phones/silence.csl) || exit 1
    silence_weighting_opts="--ivector-silence-weighting.max-state-duration=$max_state_duration --ivector-silence-weighting.silence_phones=$silphons --ivector-silence-weighting.silence-weight=$silence_weight"
else
    silence_weighting_opts=
fi

if $threaded; then
    decoder=online2-wav-nnet2-latgen-threaded
    parallel_opts="--num-threads 2"
    opts="--modify-ivector-config=$modify_ivector_config --verbose=0 --simulate-realtime-decoding=false"
else
    decoder=online2-wav-nnet2-latgen-faster
    parallel_opts=
    opts="--online=$online"
fi

$cmd $parallel_opts JOB=1:$nj $dir/log/decode.JOB.log \
    $decoder $opts $silence_weighting_opts --do-endpointing=$do_endpointing \
    --config=$decode_config \
    --max-active=$max_active --beam=$beam --lattice-beam=$lattice_beam \
    --acoustic-scale=$acwt --word-symbol-table=$graphdir/words.txt \
    $srcdir/final.mdl $graphdir/HCLG.fst $spk2utt_rspecifier "$wav_rspecifier" \
    "ark:|gzip -c > $dir/lat.JOB.gz" | exit 1;

exit 0

    



