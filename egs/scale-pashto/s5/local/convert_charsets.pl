#!/usr/bin/env perl
use warnings;
use strict;
use utf8;
use charnames ":full";
use open qw(:std :utf8);

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


while (<>) {
  s/\N{ARABIC SUKUN}//g;
  s/\N{ARABIC FATHA}//g;
  s/\N{ARABIC DAMMA}//g;
  s/\N{ARABIC KASRA}//g;
  s/\N{ARABIC FATHATAN}//g;
  s/\N{ARABIC KASRATAN}//g;
  s/\N{ARABIC LETTER KEHEH}/\N{ARABIC LETTER KAF}/g;
  s/\N{ARABIC LETTER KAF WITH RING}/\N{ARABIC LETTER GAF}/g;
  s/\N{ARABIC LETTER ALEF MAKSURA ISOLATED FORM}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ZERO WIDTH NON-JOINER}//g;

  s/#ah/<hes>/g;
  s/#ay/<hes>/g;
  s/#breath/<breath>/g;
  s/#click/<click>/g;
  s/#cough/<cough>/g;
  s/#dtmf/<dtmf>/g;
  s/#foreign/<foreign>/g;
  s/#laugh/<laugh>/g;
  s/#lipsmack/<lipsmack>/g;
  s/#noise/<noise>/g;
  s/#overlap/<overlap>/g;
  s/#ring/<ring>/g;
  s/#silence/<silence>/g;
  s/#um/<hes>/g;
  s/<male2female>/<male-to-female>/g;
  s/<female2male>/<female-to-male>/g;
 
  print;
}
