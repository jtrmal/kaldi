#!/bin/bash

SCRIPTNAME=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTNAME`

lmwt=10
prefix=
. $SCRIPTDIR/parse_options.sh


expdir=$1
graphdir=$2
model=$3
ivdir=$4
lpack=$5

if [ -z $TMP ]; then
    TMP=/tmp
fi

lpdir=$TMP/kaldi-lp-`uuidgen`

if [[ ! -d $lpdir ]]; then
   mkdir -p $lpdir
fi

if [[ ! -z $prefix ]]; then
    graphdir=$prefix/$graphdir
    model=$prefix/$model
    ivdir=$prefix/$ivdir
fi

echo "# Parsing config files..."

common=`grep -o conf/common.*LP' $expdir/local.conf`
echo "cat $expdir/$common > $lpdir/local.conf"
cat $expdir/$common > $lpdir/local.conf

echo "grep -v common $expdir/local.conf >> $lpdir/local.conf"
grep -v common $expdir/local.conf >> $lpdir/local.conf


echo "# Copying decoding graph HCLG.fst"
echo mkdir $lpdir/graph
mkdir $lpdir/graph

echo mkdir $lpdir/graph/phones
mkdir $lpdir/graph/phones

graphfiles=(HCLG.fst words.txt phones.txt disambig_tid.int)

phonefiles=(word_boundary.int word_boundary.txt align_lexicon.txt \
    align_lexicon.int disambig.int disambig.txt silence.csl)

for file in ${graphfiles[@]} ; do
  if [ ! -f $graphdir/$file ]; then
      echo "# Missing graph file $graphdir/$file"
      exit 1
  fi
  echo "cp $graphdir/$file $lpdir/graph"
  cp $graphdir/$file $lpdir/graph
done


for file in ${phonefiles[@]} ; do
  if [ ! -f $graphdir/phones/$file ]; then
      echo "# Missing graph file $graphdir/phones/$file"
      exit 1
  fi
  echo "cp $graphdir/phones/$file $lpdir/graph/phones"
  cp $graphdir/phones/$file $lpdir/graph/phones
done

modeldir=`dirname $model`

cp $modeldir/tree $lpdir
cp -L $model $lpdir/final.mdl
cp $modeldir/cmvn_opts $lpdir

echo "# Extracting ivector configs"

mkdir -p $lpdir/extractor
ivfiles=(final.ie final.mat final.dubm global_cmvn.stats \
    online_cmvn.conf splice_opts)

for file in ${ivfiles[@]} ; do
   if [ ! -f $ivdir/$file ]; then 
       echo "Missing ivector file $ivdir/$file"
       exit 1
   fi
   cp -L $ivdir/$file $lpdir/extractor
done

mkdir -p $lpdir/conf
mkdir -p $lpdir/params

conf=$modeldir/conf/online_nnet2_decoding.conf

if [[ ! -f $conf ]]; then
    conf=${modeldir}_online/conf/online_nnet2_decoding.conf

    if [[ ! -f $conf ]]; then
	echo "Missing online config $modeldir/conf/online_nnet2_decoding.conf"
	echo "                   or ${modeldir}_online/conf/online_nnet2_decoding.conf"
	exit 1
    fi
fi

echo "# fixing paths in $conf"
echo "$SCRIPTDIR/rewrite_config.pl $conf $expdir $lpdir"
$SCRIPTDIR/rewrite_config.pl $conf $expdir $lpdir

cp $expdir/conf/mfcc_hires.conf $lpdir/conf
cp $expdir/conf/plp.conf $lpdir/conf
cp $expdir/conf/pitch.conf $lpdir/conf

# if a dev set is decoded, we could extract best LMWT
lexicon=`grep ^lexicon_file local.conf| sed 's/lexicon_file=//'`
if [[ -f $lexicon ]]; then
  cp $lexicon $lpdir/lexicon.txt
else
  echo "Warning: Unable to find lexicon file $lexicon"
fi

echo optlmwt=$lmwt >> $lpdir/local.conf

touch $lpdir/conf/decode.config

fullpath=`readlink -f $lpack`

pushd $lpdir
zip -r $fullpath *
popd

rm -rf $lpdir

exit 0
