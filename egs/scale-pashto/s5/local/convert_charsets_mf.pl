#!/usr/bin/env perl
# Pashto normalization based on information from Michelle Fox
use warnings;
use strict;
use utf8;
use Unicode::Normalize;
use charnames ":full";
use open qw(:std :utf8);

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


while (<>) {
  NFC($_); #  Normalization Form C (canonical decomposition, then canonical composition)

  s/\N{ARABIC LETTER ALEF WITH WAVY HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g; 
  s/\N{ARABIC LETTER KAF}/\N{ARABIC LETTER KEHEH}/g;
  s/\N{ARABIC LETTER ALEF MAKSURA}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ARABIC LETTER YEH}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ARABIC LETTER GAF WITH RING}/\N{ARABIC LETTER KAF WITH RING}/g;
  s/\N{ARABIC LETTER GAF}/\N{ARABIC LETTER KAF WITH RING}/g;
  s/\N{ARABIC LETTER TEH MARBUTA}/\N{ARABIC LETTER HEH}/g;
  s/\N{ARABIC LETTER HEH WITH YEH ABOVE}/\N{ARABIC LETTER HEH}/g;
  s/\N{ARABIC LETTER RREH}/\N{ARABIC LETTER REH WITH RING}/g;
  s/\N{ARABIC LETTER YEH BARREE}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ARABIC LETTER TTEH}/\N{ARABIC LETTER TEH WITH RING}/g;

  s/\N{ARABIC HAMZA ABOVE}//g; # remove Hamza above
  s/\N{ARABIC FATHATAN}+/\N{ARABIC FATHATAN}/g; #Multiple fathatans->single

  # normalizations for Pashto
  s/\N{ARABIC LETTER HAMZA}(?=\s|$)//g;     #Remove word-final Hamza
  ##s/\N{ARABIC LETTER ALEF WITH MADDA ABOVE}/\N{ARABIC LETTER ALEF}/g;
  s/\N{ARABIC LETTER ALEF WITH HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g; 
  s/\N{ARABIC LETTER WAW WITH HAMZA ABOVE}/\N{ARABIC LETTER WAW}/g; 
  ##s/\N{ARABIC LETTER YEH WITH HAMZA ABOVE}/\N{ARABIC LETTER FARSI YEH}/g;
  # Remove Fathatan
  ##s/\N{ARABIC FATHATAN}//g; 
  # Remove Dammatan, Kasratan, Fatha, Damma, Kasra, Shadda, Sukun
  s/[\N{ARABIC DAMMATAN}-\N{ARABIC SUKUN}]//g;

  s/\N{ARABIC LETTER ALEF WITH WAVY HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g;
  s/\N{ARABIC LETTER YEH WITH TAIL}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ARABIC LETTER E}/\N{ARABIC LETTER FARSI YEH}/g;

  #Allah ligature decomposition
  s/\N{ARABIC LIGATURE ALLAH ISOLATED FORM}/\N{ARABIC LETTER ALEF}\N{ARABIC LETTER LAM}\N{ARABIC LETTER LAM}\N{ARABIC LETTER HEH}/g; 
  #Arabic ligature Lam-with-alef decomposition
  s/\N{ARABIC LIGATURE LAM WITH ALEF ISOLATED FORM}/\N{ARABIC LETTER LAM}\N{ARABIC LETTER ALEF}/g;

  #Remove Tatweel
  s/\N{ARABIC TATWEEL}//g;


  #Transcript cleaning, non-speech events mapping
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
  s:</?(SouthEast|SouthWest|NorthEast|NorthWest)></?(Female|Male)></?(Mobile|Landline)>::g;
 
  print;
}
