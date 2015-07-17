#!/usr/bin/env perl
#===============================================================================
# Copyright (c) 2015, Johns Hopkins University (Author: Yenda Trmal <jtrmal@gmail.com>)
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.
#===============================================================================

use strict;
use warnings;
use utf8;
use Data::Dumper;

binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
binmode STDIN, ":utf8";

my $filelist = $ARGV[0];
my $wavlist = $ARGV[1];
my $dest = $ARGV[2];

my %FILES;
open(my $FILELIST, $filelist) or die "Couldn't open the filelist $filelist: $!\n"; 
while ( <$FILELIST> ) {
  chomp;
  $FILES{$_} = 1;
}
close($FILELIST);
print "Read " . scalar(keys %FILES) . " entries from filelist\n";
my %WAVMAP;
open(my $WAVLIST, $wavlist);
while(<$WAVLIST>) {
  chomp;
  my $filename = $_;
  my $base=`basename "$filename" .wav`;
  chomp $base;
  if ( $FILES{$base} ) {
    $WAVMAP{$base}=$filename;
  }
}
close($WAVLIST);
print "Read " . scalar(keys %WAVMAP) . " entries from wavlist\n";

if ( scalar(keys %WAVMAP) != scalar(keys %FILES) ) {
  die "Not all files from filelist found in wavlist (or vice versa)\n";
}

`mkdir -p $dest`;

my $sox=`which sox` || die "Could not find sox binary: $!\n"; chomp $sox;
open(my $WAV, "|-:encoding(utf8)", "sort -u > $dest/wav.scp") or die "Cannot open $dest/wav.scp: $!";
open(my $UTT2SPK, "|-:encoding(utf8)",  "sort -u > $dest/utt2spk") or die "Cannot open $dest/utt2spk: $!";
open(my $TEXT, "|-:encoding(utf8)", "sort -u > $dest/transcripts") or die "Cannot open $dest/transcripts: $!";
open(my $SEGMENTS, "|-:encoding(utf8)", "sort -u > $dest/segments") or die "Cannot open $dest/segments: $!";

while (<STDIN>) {
    my @F = split ("\t", $_);
    my ($filename, $chan, $start, $end, $speaker, 
        $speakerType, $speakerDialect,
        $transcript,  $section, $turn,  
        %segment, %sectionType, $suType,  %speakerRole) = @F;


    $transcript =~ s/%دانسان=غږ/<spk>/gu;
    $transcript =~ s/%نابشپوړ//gu;
    #$transcript =~ s/././gu;
    $transcript =~ s/؟/?/gu;
    $transcript =~ s/%په=وار=غږ/<noise>/gu;
    $transcript =~ s/%د=عږ=پیل/<begin_noise>/gu;
    $transcript =~ s/%د=غږ=پاې/<end_noise>/gu;
    $transcript =~ s/%د=ګډوډ=پیل/<begin_overlap>/gu;
    $transcript =~ s/%د=ګډوډ=پاې/<end_overlap>/gu;
    $transcript =~ s/%او/<hes>/gu;
    $transcript =~ s/%ام/<yes>/gu;
   
    $transcript =~ s/\(\( +/((/gu;
    $transcript =~ s/ +\)\)/))/gu;
    my $transcript2 = $transcript;
    $transcript2 =~ s/(?<=\(\()([^\s\)]+) /$1_/gu;
    while( $transcript2 ne $transcript) {
      $transcript = $transcript2;
      $transcript2 =~ s/(?<=\(\()([^\s\)]+) /$1_/gu;
    }
    $transcript =~ s/([^(])\(([^(])/$1 $2/g;
    $transcript =~ s/([^)])\)([^)])/$1 $2/g;
    $transcript =~ s/\(\^/^/g;

    if ($transcript =~ m/\p{Script=Arabic}/g) {
        my $UTT_START = sprintf("%08d", $start * 1000);
            
        my $SOXCHANNEL = $chan + 1;
        my $CHANNEL = ($chan % 2) == 0 ? "A" : "B";
        if ($filename =~ /sif/) {
            # The bilingual files info is more complicated;
            # The sif files have only tw channels, despite the fact
            # that the tdf files show three channels
            # interviewer: phys:0 tdf:0
            # interpreter: phys:1 tdf:2
            # respondent:  phys:0 tdf:1
            $CHANNEL = ($chan % 2) == 0 ? "B" : "A";
            $SOXCHANNEL = ($CHANNEL eq "A") ? 1 : 2;
        } 
        my $FILENAME = $filename;
        $FILENAME =~ s/\.wav//g;
        
        my $path = $WAVMAP{$FILENAME};
        next unless $path;
        my $WAV_ID="$FILENAME-$CHANNEL";
        my $UTT_ID="$WAV_ID-$UTT_START";
        my $SPK_ID="$UTT_ID-$speaker";
        print $WAV "$WAV_ID $sox $path -t wav -r 8000 -c 1 - remix $SOXCHANNEL|\n";
        print $SEGMENTS "$UTT_ID $WAV_ID $start $end\n";
        print $TEXT "$UTT_ID $transcript\n";
        print $UTT2SPK "$UTT_ID $SPK_ID\n";
        #print "$filename $speaker" . " $chan " . $transcript . "\n";
    } else {
        #print STDERR "$filename $speaker" . " $chan " . $transcript . "\n";

    }
}
