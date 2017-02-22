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


diff $system/conf/mfcc_hires.conf conf/mfcc_hires.conf || exit 1


if [ ! -f $sysid/ivectors_$dataset/.ivector.done ] ; then
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $my_nj \
    ${dataset_dir}_hires $system/exp/nnet3/extractor $sysid/ivectors_$dataset || exit 1;
  touch  $sysid/ivectors_$dataset/.ivector.done
fi

decode=$sysid/decode_${dataset}.phn
rnn_opts=" --extra-left-context 40 --extra-right-context 40  --frames-per-chunk 20 "
decode_script=steps/nnet3/decode.sh
mkdir -p $decode
find $system/exp/nnet3/lstm_bidirectional_sp -maxdepth 1 -type f -not -name "*mdl" -not -name "*raw" -not -name ".done" -not -name "*cache" | xargs  -t -n 1 -I % cp % $sysid
cp $system/exp/nnet3/lstm_bidirectional_sp/final.mdl $sysid/

if [ ! -f $sysid/graph.phn/.done ]; then
  cp -R -L --copy-contents $system/data/langp_test.phn $sysid/langp_test.phn
  utils/mkgraph.sh $sysid/langp_test.phn $sysid $sysid/graph.phn
  touch $sysid/graph.phn/.done
fi

$decode_script --nj $my_nj --cmd "$decode_cmd" $rnn_opts \
      --min-active 1000 --beam 16.0 --lattice-beam 8.5 \
      --skip-scoring true  \
      --online-ivector-dir $sysid/ivectors_${dataset} \
      $sysid/graph.phn ${dataset_dir}_hires $decode | tee $decode/decode.log
      

