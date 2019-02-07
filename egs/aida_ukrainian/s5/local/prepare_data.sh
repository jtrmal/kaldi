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

set -x
find $audio -type f -name "*.flac" |\
  perl -ne ' {
    chomp;
    $wav=$_;
    #$c = `soxi $wav | grep Channels`;
    #$c =~ s/Channels.*://;
    $c = 2;
    s:.*/([^\/]+)\.flac:$1:;
    $wavid = sprintf("%040s", $_);
    if ($c == 1) {
      print $wavid . "_0 sox " . $wav . " -t wav -c 1 -r 8000 -|\n";
    } else {
      print $wavid . "_0 sox " . $wav . " -t wav -c 1 -r 8000 - remix 1|\n";
      #print $wavid . "_1 sox " . $wav . " -t wav -c 1 -r 8000 - remix 2|\n";
    }
  }' | sort > data/local/wav.scp

find $transcripts -name "*tsv" -type f |\
  perl -CS -Mutf8 -ne ' {
    chomp;
    $counter = 0;
    open(TSV, "<:encoding(utf-8)", $_) or die "Cannot open $_: $!";
    s:.*/([^\/]+)\.tsv:$1:;
    $wav = $_;
    $wavid = sprintf("%040s_0", $wav);
    while (<TSV>) {
      chomp;

      @F = split;
      next unless scalar @F >= 5;
      $start=$F[0];
      $stop= $F[1];
      $spk = "${wavid}_$F[2]";
      $sex = ($F[3] =~ "female" ? "F" : "M");
      $utt = sprintf("${spk}_%04d", $counter);

      $counter+=1;
      $text = lc join(" ", @F[4..$#F]);
      next if $start == $stop;
      print "$wav\t$wavid\t$start\t$stop\t$utt\t$spk\t$sex\t$text\n";
    }
  }' | sort -k5,5 -k2,5 | uconv -f utf-8 -t utf-8 -x Any-NFKC |\
  perl -CS -mutf8 -nE '
    @F = split(/\t/, $_);
    $u = $F[7];
    next if $u =~ /<.{0,1}foreign/;
    next if $u =~ /\(foreign>/g;
    next if $u =~ /%foreign/g;
		next if $u =~ /<foreing>|<foriegn>|_foregn_/g;
		next if $u =~ /<>/g;

		next if $u =~ /%dw|&amp|\+/u;
		next if $u =~ /%\N{CYRILLIC SMALL LETTER A}\N{CYRILLIC SMALL LETTER TSE}/;

    next if $u =~ /[0-9]/;

		$u =~ s:% pw:%pw:g;
		$u =~ s:% fp:%fp:g;
		$u =~ s:% noise:%noise:g;
		$u =~ s:%pw%:%pw:g;
		$u =~ s:-%fp:%fp:g;

    $u =~ s:\$fp|%fp\#|%pf:%fp:g;
    $u =~ s:%fp([^ ]):%fp $1:g;
    $u =~ s:%pw([^ ]):%pw $1:g;
		$u =~ s:\^fp:%fp:g;
		$u =~ s:%wp:%pw:g;
		$u =~ s:%p :%pw :g;

    #$u =~ s/% /%/g;
    $u =~ s/«/ /g;
    #$u =~ s/([^ ])%/$1 %/g;

    $u =~ s:\(\([^\)]*\)\): <unk> :g;
    $u =~ s:\(+[^\)]*\)+: <unk> :g;


    $u =~ s:%[Nn]oise:<noise>:g;
    $u =~ s:%niose:<noise>:g;

    $u =~ s/[““””“”\/\N{HORIZONTAL ELLIPSIS}\N{LEFT DOUBLE QUOTATION MARK}\N{RIGHT DOUBLE QUOTATION MARK}]/ /g;
    $u =~ s/[\N{EN DASH}\N{EM DASH}]/-/g;
    $u =~ s/--/-/g;

    $u =~ s/[.,?!:;\"]/ /g;
	  $u =~ s: >::g;
	  $u =~ s:\\\\::g;
    $u =~ s/ - / /g;
    $u =~ s/  */ /g;
    $u =~  s/^ *//g;
    $u =~  s/ *$//g;
    $u =~ s/^- //g;
    $u =~ s/ -$//g;

    next unless $u;
		next if $u =~ /\)/g;
    $F[7] = $u;
    print join("\t", @F);
  ' > data/local/transcripts

exit
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

