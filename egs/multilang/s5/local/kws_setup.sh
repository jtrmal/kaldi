#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal)
# Apache 2.0.

# Begin configuration section.  
cmd=run.pl
case_insensitive=true
subset_ecf=
rttm_file=
use_icu=true
icu_transform="Any-Lower"
kwlist_wordlist=false
langid=107
silence_word=  # Optional silence word to insert (once) between words of the transcript.
# End configuration section.

echo "$0 $@"  # Print the command line for logging

help_message="$0: Initialize and setup the KWS task directory
Usage:
       $0  <data-dir> <lang> <output>
allowed switches:
      --subset-ecf /path/to/filelist     # The script will subset the ecf file 
                                         # to contain only the files from the filelist
      --rttm-file /path/to/rttm          # the preferred way how to specify the rttm
                                         # the older way (as an in-line parameter is 
                                         # obsolete and will be removed in near future
      --case-insensitive <true|false>      # Shall we be case-sensitive or not?
                                         # Please not the case-sensitivness depends 
                                         # on the shell locale!
      --use-icu <true|false>           # Use the ICU uconv binary to normalize casing
      --icu-transform <string>           # When using ICU, use this transliteration
      --kwlist-wordlist                  # The file with the list of words is not an xml
              "

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -e 
set -u
set -o pipefail

if [ "$#" -ne "6" ] &&  [ "$#" -ne "5" ] ; then
    printf "FATAL: invalid number of arguments.\n\n"
    printf "$help_message\n"
    exit 1
fi

kwlist_file=$1
rttm_file=$2
datadir=$3
langdir=$4
alidir=$5
output=$6

mkdir -p $output

for dirname in "$langdir" "$datadir" ; do
    if [ ! -d $dirname ] ; then
        printf "FATAL: dirname \'$dirname\' does not refer to a valid directory\n"
        printf "$help_message\n"
        exit 1;
    fi
done

rm -rf $output/kwlist.xml
if [[ "$kwlist_file" == *.xml ]] ; then 
  cp $kwlist_file $output/kwlist.xml
else
  cat ${kwlist_file} | \
   awk 'BEGIN {
          print "<kwlist ecf_filename=\"kwlist.xml\" language=\"\" encoding=\"UTF-8\" compareNormalize=\"lowercase\" version=\"\">";
        };
        { printf("  <kw kwid=\"%s\">\n", $1);
          printf("    <kwtext>"); for (n=2;n<=NF;n++){ printf("%s", $n); if(n<NF){printf(" ");} }
          printf("</kwtext>\n");
          printf("  </kw>\n"); 
        }
        END {
          print "</kwlist>";
        }
        ' > $output/kwlist.xml || exit 1
fi

cat $datadir/segments | local/segments_to_ecf.pl > $output/ecf.xml
duration=`head -1 $output/ecf.xml |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`
echo "$duration" > $output/duration

if [ ! -z $rttm_file ] ; then
  test -f $output/rttm && rm -f $output/rttm
  cp "$rttm_file" $output/rttm 
fi

sil_opt=
[ ! -z $silence_word ] && sil_opt="--silence-word $silence_word"
local/kws_data_prep.sh --case-insensitive ${case_insensitive} \
  $sil_opt --use_icu ${use_icu} --icu-transform "${icu_transform}" \
  $langdir $datadir $output || exit 1

local/prepare_kws_hitlist.sh $output $langdir $alidir || exit 1
cp $alidir/$(basename $output)/hits $output/hits || exit 1
echo "Success"
