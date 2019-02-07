#!/bin/bash
# Copyright (c) 2019, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
# End configuration section
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error


audio=$1
transcripts=$2

traindir=data/train
devdir=data/dev

mkdir -p $traindir
mkdir -p $devdir
mkdir -p data/local

find $audio -name "*sph" -type f | \
  perl -ne ' {
    chomp;
    $wav=$_;
    s:.*/([^\/]+)\.sph:$1:;
    $wavid = sprintf("%020s", $_);
    # the channel affix (_1 or _0) must correspond with the channel in rdf
    print $wavid . "_0 sph2pipe -c 1 -f wav -p " . $wav . "|\n";
    print $wavid . "_1 sph2pipe -c 2 -f wav -p " . $wav . "|\n";
  }' | sort > data/local/wav.scp

find $transcripts -name "*tsv" -type f |\
  perl -CS -Mutf8 -ne ' {
    chomp;
    open(TSV, "<:encoding(utf-8)", $_) or die "Cannot open $_: $!";
    $counter = 0;
    while (<TSV>) {
      chomp;
      next if /^;;/;

      @F = split;
      pop(@F);pop(@F);pop(@F); # remove info about turns
      $F[0] =~ s:\.sph$::;
      $wav = $F[0];
      $F[0] = sprintf("%020s_%1s", $F[0], $F[1]);
      $spk = "$F[0]_$F[4]";
      $utt = sprintf("${spk}_%04d", $counter);
      $counter+=1;
      $text = join(" ", @F[7..$#F]);
      $sex = $F[5] =~ "female" ? "F" : "M";
      $start=$F[2];
      $stop=$F[3];
      next if $start == $stop;
      print "$wav\t$F[0]\t$start\t$stop\t$utt\t$spk\t$sex\t$text\n";
    }
  }' | sort -k5,5 -k2,5 | \
  perl -CS -ne '
    @F = split(/\t/, $_);
    $u = $F[7];
    next if $u =~ /<.{0,1}foreign/;
    $u =~ s:<laugh> </laugh>: <laugh> :g;
    $u =~ s:<background> </background>: <background> :g;
    $u =~ s:<breath/>: <breath> :g;
    $u =~ s:<lipsmack/>: <lipsmack> :g;
    $u =~ s:<cough/>: <cough> :g;
    $u =~ s:<lname/>: <lname> :g;
    $u =~ s:\(\([^\)]*\)\): <unk> :g;
    $u =~ s:\(+[^\)]*\)+: <unk> :g;



    $u =~ s/[.,?!:;\"]/ /g;
    $u =~ s/ - / /g;
    $u =~ s/  */ /g;
    $u =~  s/^ *//g;
    $u =~  s/ *$//g;

    next unless $u;
    next if $u =~ /65/;
    next if $u =~ /<\/laugh>/;
    next if $u =~ /<\/background>/;
    $F[7] = $u;
    print join("\t", @F);
  ' > data/local/transcripts

# `cut` does not do reordering :/
cut -f 4,5,2,3 data/local/transcripts | awk '{print $4, $1, $2, $3}' > $traindir/segments
cut -f 5,8 data/local/transcripts > $traindir/text
cut -f 5,6 data/local/transcripts > $traindir/utt2spk
utils/utt2spk_to_spk2utt.pl $traindir/utt2spk > $traindir/spk2utt
cat data/local/wav.scp | grep -f local/train_russian.lst -F -w > $traindir/wav.scp
utils/fix_data_dir.sh $traindir

# `cut` does not do reordering :/
cut -f 4,5,2,3 data/local/transcripts | awk '{print $4, $1, $2, $3}' > $devdir/segments
cut -f 5,8 data/local/transcripts > $devdir/text
cut -f 5,6 data/local/transcripts > $devdir/utt2spk
utils/utt2spk_to_spk2utt.pl $devdir/utt2spk > $devdir/spk2utt
cat data/local/wav.scp | grep -f local/dev_russian.lst -F -w > $devdir/wav.scp
utils/fix_data_dir.sh $devdir

