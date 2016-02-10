#!/bin/bash

dataset_kind=supervised
extra=

. utils/parse_options.sh

if [ $# -ne 2 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi


dataset=$1
langdir=$2

. ./local.conf

eval my_stm_file=\$${dataset}_stm_file
eval my_ecf_file=\$${dataset}_ecf_file
eval my_kwlist_file=\$${dataset}_kwlist_file
eval my_rttm_file=\$${dataset}_rttm_file
eval my_nj=\$${dataset}_nj  #for shadow, this will be re-set when appropriate

my_subset_ecf=false


function check_variables_are_set {
  for variable in $mandatory_variables ; do
    eval my_variable=\$${variable}
    if [ -z $my_variable ] ; then
      echo "Mandatory variable ${variable/my/$dataset_type} is not set! " \
           "You should probably set the variable in the config file "
      exit 1
    else
      echo "$variable=$my_variable"
    fi
  done

  if [ ! -z ${optional_variables+x} ] ; then
    for variable in $optional_variables ; do
      eval my_variable=\$${variable}
      echo "$variable=$my_variable"
    done
  fi
}



if [ "${dataset_kind}" == "supervised" ] ; then
  mandatory_variables="my_ecf_file my_kwlist_file my_rttm_file" 
  optional_variables="my_subset_ecf"
else
  mandatory_variables="my_ecf_file my_kwlist_file" 
  optional_variables="my_subset_ecf"
fi

echo $mandatory_variables
check_variables_are_set

dataset_dir=data/$dataset
if [ -z $extra ]; then
kwsdir=${dataset_dir}/kws
else
kwsdir=${dataset_dir}/${extra}_kws
fi


if [ ! -f ${kwsdir}/.done ] ; then
  kws_flags=( --use-icu true )
  if [  "${dataset_kind}" == "supervised"  ] ; then
    kws_flags+=(--rttm-file $my_rttm_file )
  fi
  if $my_subset_ecf ; then
    kws_flags+=(--subset-ecf $my_data_list)
  fi
  if [ ! -z $extra ] ; then
	kws_flags+=(--extraid $extra)
  fi

  local/babel/kws_setup.sh --case_insensitive $case_insensitive \
    "${kws_flags[@]}" "${icu_opt[@]}" \
    $my_ecf_file $my_kwlist_file $langdir ${dataset_dir} || exit 1
  touch $kwsdir/.done 
fi


