#!/bin/bash                                                                        
# Copyright (c) 2016, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
# End configuration section
set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

. ./cmd.sh
. ./path.sh

data=${1%/}
corpus=${2%/}
my_nj=$3

dataset=`basename $data`


echo $data
echo $corpus

mkdir -p $data
find -L $corpus  -name "*flac" > $data/filelist.list

for flac in `cat  $data/filelist.list ` ; do 
  fx=`basename $flac`; 
  fx=${fx%%.flac}; 
  #echo "$fx sox $flac -t wav -r 8000 -|"
  echo "$fx sox $flac -t wav -r 8000 -c 1 -  sinc 60-3300 -t 30|"
done > $data/wav.scp

wav-to-duration scp:$data/wav.scp  ark,t:- 2>$data/wav-to-duration.log| \
  perl -ane '
  $dur = $F[1] + 0.0;
  if ($dur > 20.0) {
    $i = 0;
    $k = 0;
    while ($i < $dur) {
      $seq = sprintf("%s-%02d", $F[0], $k);
      $end = $i + 10 + 5;
      if ($end > $dur) {
        $end = $dur;
      } elsif (($dur - $end) < 5) {
        $end = $dur;
      }
      $a = sprintf("%.3f", $i);
      $b = sprintf("%.3f", $end);
      print "$seq " . $F[0] . " $a $b\n";
      $k += 1;
      if ($end >= $dur) {
        $i = $end;
      }
      $i += 10;
    }
  } else {
    print $F[0] . "-00 " . $F[0] . " 0.0 " . $F[1] . "\n";
  }
  ' > $data/segments
#  awk '{print $1, $1, 0.0, $2}' > $data/segments 

for segment in `cat $data/segments | awk '{print $1}'`; do
  spk=${segment%_*}
  echo $segment $spk
done > $data/utt2spk

utils/fix_data_dir.sh $data


if [ ! -f ${data}_hires/.mfcc.done ]; then
  if [ ! -d ${data}_hires ]; then
    utils/copy_data_dir.sh $data ${data}_hires
  fi

  mfccdir=mfcc_hires
  steps/make_mfcc.sh --nj $my_nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" ${data}_hires exp/make_hires/$dataset $mfccdir;

  steps/compute_cmvn_stats.sh ${data}_hires exp/make_hires/${dataset} $mfccdir;

  utils/fix_data_dir.sh ${data}_hires;
  touch ${data}_hires/.mfcc.done
fi

