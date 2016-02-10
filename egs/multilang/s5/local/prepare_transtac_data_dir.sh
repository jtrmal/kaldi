#!/bin/bash                                                                        
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
oov="<unk>" 
# End configuration section

echo "$0" "$@"
. utils/parse_options.sh

set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

dir=$1
lang=$2
output=$3

list=$dir/wavs.list
find $dir/transcription -name "*.tdf" | xargs cat |
  perl local/tdf_convert.pl <(cat $list | xargs -I{} basename {} .wav)\
    $list $output

cat ${output}/transcripts| \
  grep -v 'overlap' | \
  local/convert_charsets.pl | \
  perl -CSDL -mutf8 -e '
    %LEX;
    %OOV;
    binmode STDIN, "utf8";
    binmode STDOUT, "utf8";
    open(VOCAB, "<:encoding(utf-8)", $ARGV[0]);
    while(<VOCAB>) {
      chomp;
      @F=split(" ");
      $LEX{$F[0]} = 1;
    }
    close(VOCAB);
    print STDERR "Read " . scalar (keys %LEX) . " vocab entries.\n";

    $unk = $ARGV[1];
    while( <STDIN> ) {
      chomp;
      @F = split(" ");
      for ( $i = 1; $i <$#F; $i++) {
        my $orig = $F[$i];

        if ($F[$i] =~ /<.*>/) {
          if (($F[$i] eq "<hes>") || ($F[$i] eq "<yes>")) {
            $F[$i] = "<v-noise>";
          } elsif ($F[$i] eq "<spk>") {
            $F[$i] = "<noise>";
          } elsif ($F[$i] =~ /<*_noise>/ ) {
            $F[$i] = "<noise>";
          }
        } else {
          $F[$i] =~ s/\^//g;
          $F[$i] =~ s/\+//g;
          $F[$i] =~ s/@//g;
          $F[$i] =~ s/--//g;
          $F[$i] =~ s/-//g;
        }
        next unless ($F[$i]);
        if ( !exists $LEX{$F[$i]} ) {
          $OOV{$orig} +=1;
          $F[$i] = $unk;
        }
      }
      print join(" ", @F) . "\n";
    }
    if ( defined $ARGV[2] ) {
      open(my $OOVS, "|-:encoding(utf8)", "sort -k2nr -k1,1 > $ARGV[2]");
      foreach $k (keys %OOV) {
        print $OOVS "$k\t $OOV{$k}\n";
      }
      close($OOVS);
    }
  ' $lang/words.txt $oov $output/oovCount > $output/text

