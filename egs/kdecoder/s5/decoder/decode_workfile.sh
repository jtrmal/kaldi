#!/bin/bash

set -e
set -o pipefail

if [ -z $KALDI_ROOT ]; then
 echo "Please define KALDI_ROOT where binaries are installed"
 exit 1;
fi

export PATH=$KALDI_ROOT/tools/sph2pipe_v2.5:$PATH

SCRIPTNAME=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTNAME`

type=decodetest
max_states=150000
nj=1
wip=0.5
mpe_epoch=1
lmwt=11
bzip=false
debug=false
use_htk=true
threaded=false
online=false
use_gpu=false
lattice_beam=6
clean=true
# end configuration

echo "Running: $0 $@"

. $SCRIPTDIR/parse_options.sh

lpack=$1
workfile=$2

if [ $# -ne 2 ]; then
  echo "Usage: $(basename $0) lpack workfile"
  exit 1
fi

if [ -z $TMP ]; then
    TMP=/tmp
fi

wdir=`dirname $workfile`
tmpdir=$TMP/kaldi-`uuidgen`

mkdir $tmpdir || \
  (echo "Unable to create working directory $tmpdir" && exit 1)

echo "Using tmpdir=$tmpdir"

if [[ ! -d $lpack ]]; then
    mkdir -p $tmpdir/lpack
    unzip $lpack -d $tmpdir/lpack &> /dev/null
    lpack=$tmpdir/lpack
fi

. $lpack/local.conf || exit 1

echo "Decoding: " 
echo "TMPDIR:   $tmpdir"
echo "WORKFILE: $workfile"
echo "LPACK:    $lpack"
echo "LMWT:     $optlmwt"

if [[ $optlmwt > 0 ]]; then
    lmwt=$optlmwt
fi

export PATH=$SCRIPTDIR:$SCRIPTDIR/../bin:$SCRIPTDIR/utils:$KALDI_ROOT/src/ivectorbin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/lmbin/:$KALDI_ROOT/src/nnet2bin/:$KALDI_ROOT/src/online2bin:$PATH

export LD_LIBRARY_PATH=$SCRIPTDIR/../lib:$LD_LIBRARY_PATH

echo Starting...

shadow_set_extra_opts=()

function make_plp {
    t=$1
    tdata=$2

    if [[ ! -d ${tdata}/plp ]]; then
	mkdir -p ${tdata}/plp
    fi
    
    if $use_pitch; then
	$SCRIPTDIR/feats/make_plp_pitch.sh --cmd "run.pl" --nj $nj \
	    --plp-config $lpack/conf/plp.conf \
	    --pitch-config $lpack/conf/pitch.conf \
	    ${tdata} $tmpdir/make_plp_pitch/${t} ${tdata}/plp
    else
	echo Only plp with pitch currently supported
	exit 1
    fi

    $SCRIPTDIR/utils/fix_data_dir.sh ${tdata}
    $SCRIPTDIR/feats/compute_cmvn_stats.sh ${tdata} \
	$tmpdir/make_plp/${t} ${tdata}/plp
    $SCRIPTDIR/utils/fix_data_dir.sh ${tdata}

}

datadir=$tmpdir/data/$type
dirid=$type

nj_max=`cat $workfile | wc -l`
if [[ "$nj_max" -lt "$nj" ]]; then
    echo "Maximum reasonable number of jobs is $nj_max -- you have $nj !"
    nj=$nj_max
fi

if $bzip; then
    bzip="--bzip"
else
    bzip=""
fi

mkdir -p $datadir
$SCRIPTDIR/utils/prepare_acoustic_decode_data.pl $bzip \
    --fragmentMarkers \-\*\~ $workfile $datadir \
    > $datadir/skipped_utts.log || exit 1

echo "Extracting plp pitch features"
make_plp ${dirid} ${datadir} || exit 1

$SCRIPTDIR/utils/split_data.sh $datadir $nj || exit 1

srcdir=$lpack


echo "Extracting hires mfccs"
mfccdir=$datadir/mfcc
$SCRIPTDIR/utils/copy_data_dir.sh $datadir ${datadir}_hires
$SCRIPTDIR/feats/make_mfcc.sh --nj $nj \
    --mfcc-config $lpack/conf/mfcc_hires.conf \
    --cmd run.pl ${datadir}_hires $tmpdir/make_hires/$type $mfccdir || exit 1
$SCRIPTDIR/feats/compute_cmvn_stats.sh ${datadir}_hires \
    $tmpdir/make_hires/$type $mfccdir || exit 1

#echo "Extracting ivectors for $type"
#$SCRIPTDIR/decoder/extract_ivectors_online.sh --cmd run.pl --nj $nj \
#    ${datadir}_hires $lpack/extractor $tmpdir/ivectors_${type}_hires || exit 1

# re-write configs?
sed "s|=conf|=$lpack/conf|" $lpack/conf/ivector_extractor.conf | sed "s|=params|=$lpack/params|" > $tmpdir/ivector_extractor.conf
sed "s|=conf|=$tmpdir|" $lpack/conf/online_nnet2_decoding.conf > $tmpdir/online.conf

cp $lpack/conf/mfcc.conf $tmpdir

$SCRIPTDIR/decode/online_decode.sh \
    --config $lpack/conf/decode.config \
    --decode-config $tmpdir/online.conf \
    --cmd run.pl --use-gpu $use_gpu --online $online --srcdir $srcdir \
    --nj $nj --threaded $threaded --iter final --per-utt true \
    --lattice-beam $lattice_beam --skip-scoring true \
    $srcdir ${datadir}_hires $tmpdir/decode_${type} || \
    (cat $tmpdir/decode_${type}/log/decode.1.log && exit 1)


echo extracting 1-best and converting to HTK lattice

decode=$tmpdir/decode_${type}

mkdir -p $decode/htk-out

$SCRIPTDIR/utils/run.pl JOB=1:$nj $tmpdir/decode_${type}/log/lat2cnet.JOB.log \
    $SCRIPTDIR/decode/lattice_to_htk.sh \
    $lpack/graph $lpack/final.mdl $decode/lat.JOB.gz \
    $decode/htk-out || exit 1

$SCRIPTDIR/decode/lattice_to_ctm.sh --cmd "run.pl" --word-ins-penalty $wip \
    --lmwt $lmwt --model $lpack/final.mdl \
    ${datadir} $srcdir/graph $decode || exit 1

tail $decode/log/decode.1.log

ctmfile=$decode/$type.ctm

for d in `cat $workfile | awk '{print $3}'` ; do
    mkdir -p $d
done

$SCRIPTDIR/decode/split_output.pl $workfile $datadir/segments \
    $ctmfile $decode/htk-out


if $clean; then
    rm -rf $tmpdir
fi

exit 0



