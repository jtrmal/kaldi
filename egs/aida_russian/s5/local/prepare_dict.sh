#!/bin/bash
# Copyright (c) 2019, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
# End configuration section
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error


input=$1
output=$2

mkdir -p $output

(
	echo '<sil>'
	cut -f 2 $input |  sed 's/ /\n/g; /^[ \t]*$/d' |  sort -u
) | awk  '{print $0, NR}' > $output/words.txt

echo '<unk>' > $output/oov.txt

awk '{print $1}' $output/words.txt  | \
	local/grapheme_lexicon.py  >  $output/lexicon.txt

sed 's/^[^ \t][^ \t]* //;' $output/lexicon.txt | sed -e 's/ /\n/g' | sort -u | sed '/^[ \t]*$/d'  > $output/phones.txt

grep '<' $output/phones.txt > $output/silence_phones.txt
grep -v '<' $output/phones.txt > $output/nonsilence_phones.txt
echo '<sil>' > $output/optional_silence.txt

utils/validate_dict_dir.pl $output
