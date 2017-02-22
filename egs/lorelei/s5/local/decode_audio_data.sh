#!/bin/bash                                                                        
# Copyright (c) 2016, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
# End configuration section
set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

system=$1
dataset_dir=$2
nj=$3

. ./path.sh
. ./cmd.sh

sysid=`basename $system`
dataset=`basename $dataset_dir`
my_nj=$nj

if [ ! -f ${dataset_dir}_hires/.mfcc.done ]; then
  if [ ! -d ${dataset_dir}_hires ]; then
    utils/copy_data_dir.sh data/$dataset data/${dataset}_hires
  fi

  diff $system/conf/mfcc_hires.conf conf/mfcc_hires.conf || exit 1

  mfccdir=mfcc_hires
  steps/make_mfcc.sh --nj $my_nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" ${dataset_dir}_hires exp/make_hires/$dataset $mfccdir;
  
  compute-cmvn-stats --spk2utt=ark:data/audio/track2cut  \
    scp:${dataset_dir}_hires/feats.scp ark,scp:mfcc_hires/cmvn.ark,${dataset_dir}_hires/cmvnx.scp

  perl -ane 'BEGIN{ 
                open(UTT, $ARGV[0]) or die "Cannot open $ARGV[0]"; 
                while(<UTT>) {
                  chomp;
                  ($cut, $chan) = split;
                  push @{$utt{$chan}}, $cut;
                }
              } 
              {
                while (<>) {
                  chomp;
                  ($chan, $path) = split;
                  foreach $cut (@{$utt{$chan}}) {
                    print "$cut $path\n";
                  }
                }
              }' ${dataset_dir}_hires/cut2track < ${dataset_dir}_hires/cmvnx.scp >${dataset_dir}_hires/cmvn.scp 


  utils/fix_data_dir.sh ${dataset_dir}_hires;
  touch ${dataset_dir}_hires/.mfcc.done
fi

if [ ! -f $sysid/ivectors_$dataset/.ivector.done ] ; then
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $my_nj \
    ${dataset_dir}_hires $system/exp/nnet3/extractor $sysid/ivectors_$dataset || exit 1;
  touch  $sysid/ivectors_$dataset/.ivector.done
fi

decode=$sysid/decode_${dataset}
rnn_opts=" --extra-left-context 40 --extra-right-context 40  --frames-per-chunk 20 "
decode_script=steps/nnet3/decode.sh
mkdir -p $decode
find $system/exp/nnet3/lstm_bidirectional_sp -maxdepth 1 -type f -not -name "*mdl" -not -name "*raw" -not -name ".done" -not -name "*cache" | xargs  -t -n 1 -I % cp % $sysid
cp $system/exp/nnet3/lstm_bidirectional_sp/final.mdl $sysid/

$decode_script --nj $my_nj --cmd "$decode_cmd" $rnn_opts \
      --min-active 1000 --beam 16.0 --lattice-beam 8.5 \
      --skip-scoring true  \
      --online-ivector-dir $sysid/ivectors_${dataset} \
      $system/exp/tri5/graph ${dataset_dir}_hires $decode | tee $decode/decode.log
      

