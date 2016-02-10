#!/bin/bash                                                                        
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
# End configuration section
set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

echo "$0" "$@"
set -x
corpus="$1"
list="$2"
dest="$3"

AUDIO=${corpus}"/Pashto - Audio"
TRANSCRIPTS="${corpus}/Pashto - TX-TL"

[ -d $dest/audio ] && rm -rf $dest/audio
mkdir -p $dest/audio
find "${AUDIO[@]}" -name "*.wav" | \
  grep -v -i  'helmand' | \
  grep -F -f $list > $dest/wavs.list

if [ $(cat $list | wc -l) -ne $(cat $dest/wavs.list | wc -l) ] ; then
  echo "Error: list contains $(wc -l $list ) vs found $( wc -l $dest/wavs.list)"
  exit 1
fi

while read p; do
  ln -s "$p" $dest/audio/$(basename "$p")
done <$dest/wavs.list

mv $dest/wavs.list $dest/wavs.list.orig
find "$dest/audio" -name "*.wav" > $dest/wavs.list

[ -d $dest/transcription ] && rm -rf $dest/transcription
mkdir -p $dest/transcription
find "$TRANSCRIPTS" -name "*ALL_FINAL*zip" -print0 | \
  xargs -I {} -n 1 -0 unzip -q -j {} -d $dest/transcription 

find $dest/transcription -name "*.tdf" | grep -v -F -f $list | xargs rm

exit 0
#find $dest/transcription -name "*.tdf" | xargs cat |
#  perl local/tdf_convert.pl $list  $dest/wavs.list data/${dataset}_transtac

