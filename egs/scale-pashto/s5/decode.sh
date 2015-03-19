#!/bin/bash 
set -e
set -o pipefail

data_only=false
. conf/common_vars.sh || exit 1;
. ./local.conf || exit 1;


echo "$0 $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

#This seems to be the only functioning way how to ensure the comple
#set of scripts will exit when sourcing several of them together
#Otherwise, the CTRL-C just terminates the deepest sourced script ?
# Let shell functions inherit ERR trap.  Same as `set -E'.
set -o errtrace 
trap "echo Exited!; exit;" SIGINT SIGTERM


#Just a minor safety precaution to prevent using incorrect settings
#The dataset_* variables should be used.
set -e
set -o pipefail
set -u

function make_plp {
  target=$1
  logdir=$2
  output=$3
  if $use_pitch; then
    steps/make_plp_pitch.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  else
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  fi
  utils/fix_data_dir.sh $target
  steps/compute_cmvn_stats.sh $target $logdir $output
  utils/fix_data_dir.sh $target
}

dataset_type=dev10h
dataset_dir=data/$dataset_type
#The $dataset_type value will be the dataset name without any extrension
eval my_stm_file=\$${dataset_type}_stm_file
eval my_nj=\$${dataset_type}_nj  #for shadow, this will be re-set when appropriate
eval my_data_dir=( "\${${dataset_type}_data_dir[@]}" )
eval my_data_list=( "\${${dataset_type}_data_list[@]}" )
if [ -z $my_data_dir ] || [ -z $my_data_list ] ; then
  echo "Error: The dir you specified ($dataset_type) does not have existing config";
  exit 1
fi
l1=${#my_data_dir[*]}

for i in `seq 0 $(($l1 - 1))`; do
  resource_string+=" ${my_data_dir[$i]} "
  resource_string+=" ${my_data_list[$i]} "
done

if [ ! -f data/raw_${dataset_type}_data/.done ] ; then
  local/make_corpus_subset.sh $resource_string ./data/raw_${dataset_type}_data
  touch data/raw_${dataset_type}_data/.done
fi

my_data_dir=`readlink -f ./data/raw_${dataset_type}_data`
[ -f $my_data_dir/filelist.list ] && my_data_list=$my_data_dir/filelist.list
nj_max=`cat $my_data_list | wc -l` || nj_max=`ls $my_data_dir/audio | wc -l`

if [ "$nj_max" -lt "$my_nj" ] ; then
  echo "Number of jobs ($my_nj) is too big!"
  echo "The maximum reasonable number of jobs is $nj_max"
  my_nj=$nj_max
fi

if [ ! -f $dataset_dir/.done ] ; then
  echo ---------------------------------------------------------------------
  echo "Preparing ${dataset_type} data lists in ${dataset_dir} on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p ${dataset_dir}
  local/prepare_acoustic_training_data.pl --fragmentMarkers \-\*\~  \
    $my_data_dir ${dataset_dir} > ${dataset_dir}/skipped_utts.log || exit 1
  
  echo ---------------------------------------------------------------------
  echo "Preparing ${dataset_type} stm files in ${dataset_dir} on" `date`
  echo ---------------------------------------------------------------------
  if [ ! -z $my_stm_file ] ; then
    local/augment_original_stm.pl $my_stm_file ${dataset_dir}
  else
    local/prepare_stm.pl --fragmentMarkers \-\*\~ ${dataset_dir}
  fi
  
  if [ ! -f ${dataset_dir}/.plp.done ]; then
    echo ---------------------------------------------------------------------
    echo "Preparing ${dataset_type} parametrization files in ${dataset_dir} on" `date`
    echo ---------------------------------------------------------------------
    make_plp ${dataset_dir} exp/make_plp/${dataset_type} plp
    touch ${dataset_dir}/.plp.done
  fi

  touch $dataset_dir/.done 
fi


if $data_only ; then
  echo "Exiting, as data-only was requested..."
  exit 0;
fi

####################################################################
##
## FMLLR decoding 
##
####################################################################
decode=exp/tri5/decode_${dataset_type}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri5 exp/tri5/graph |tee exp/tri5/mkgraph.log

  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --beam 10 --lattice-beam 4\
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri5/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
fi



####################################################################
## SGMM2 decoding 
## We Include the SGMM_MMI inside this, as we might only have the DNN systems
## trained and not PLP system. The DNN systems build only on the top of tri5 stage
####################################################################
if [ -f exp/sgmm5/.done ]; then
  decode=exp/sgmm5/decode_fmllr_${dataset_type}
  if [ ! -f $decode/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Spawning $decode on" `date`
    echo ---------------------------------------------------------------------
    utils/mkgraph.sh \
      data/lang exp/sgmm5 exp/sgmm5/graph |tee exp/sgmm5/mkgraph.log

    mkdir -p $decode
    steps/decode_sgmm2.sh --use-fmllr true --nj $my_nj \
      --cmd "$decode_cmd" --transform-dir exp/tri5/decode_${dataset_type} "${decode_extra_opts[@]}"\
      exp/sgmm5/graph ${dataset_dir} $decode |tee $decode/decode.log
    touch $decode/.done

  fi

  ####################################################################
  ##
  ## SGMM_MMI rescoring
  ##
  ####################################################################

  for iter in 1 2 3 4; do
      # Decode SGMM+MMI (via rescoring).
    decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_type}_it$iter
    if [ ! -f $decode/.done ]; then

      mkdir -p $decode
      steps/decode_sgmm2_rescore.sh   \
        --cmd "$decode_cmd" --iter $iter --transform-dir exp/tri5/decode_${dataset_type} \
        data/lang ${dataset_dir} exp/sgmm5/decode_fmllr_${dataset_type} $decode | tee ${decode}/decode.log

      touch $decode/.done
    fi
  done

fi

echo "Everything looking good...." 
exit 0
