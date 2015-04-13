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

$TAG=" _$TAG . " if $TAG;

while (<>) {
  chomp;
  my @entries = split("\t");
  my $word = shift @entries;
  my $rom = shift @entries;
  foreach my $pron (@entries) {
    my @phones=split(' ', $pron);
    my @new_phones=();
    my $stress_marker="";
    if ($TAG) {
      foreach my $phone (@phones) {
        if ($phone eq '.') {
          # Do nothing
          $stress_marker = "";
          ;
        } elsif ($phone eq '"') {
          $stress_marker="\"";
          #push @new_phones,  "$phone " ;
        } else {
          if ($stress_marker) {
            push @new_phones,  "$stress_marker $phone${TAG}" ;
          } else {
            push @new_phones,  "$phone${TAG}" ;
          }
        }
      }
    } else {
      @new_phones = @phones;
    }
    $pron= join(" ", @new_phones);
    $pron =~ s/\s*\.\s*$//g;
    $LEX{$word}->{$pron}+=1;
    $ROM{$word}->{$rom}+=1;
    undef @new_phones;
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
