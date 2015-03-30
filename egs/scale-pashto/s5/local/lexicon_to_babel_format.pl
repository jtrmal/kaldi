#!/usr/bin/env perl

use warnings;
use strict;
use utf8;
use charnames ":full";
use Getopt::Long;
use Data::Dumper;

my $TAG="";
GetOptions ("tag=s" => \$TAG);

my %LEX = ();
my %ROM = ();

$TAG="_$TAG" if $TAG;

while (<>) {
  chomp;
  my @entries = split("\t");
  my $word = shift @entries;
  my $rom = shift @entries;
  foreach my $pron (@entries) {
    my @phones=split(' ', $pron);
    $pron= join(" ",map { "${_}${TAG}" } @phones);
    $LEX{$word}->{$pron}+=1;
    $ROM{$word}->{$rom}+=1;
  }
}

foreach my $word (sort keys %LEX) {
  my @roms = sort keys %{$ROM{$word}};
  my @prons = sort keys %{$LEX{$word}};
  my $rom=$roms[0];
  my $pron=join("\t", @prons);
  #print STDERR "Warning: $word has multiple romanizations " . join(" ",@roms ) . "\n" if @roms > 1;
  print "$word\t$rom\t$pron\n";
}
