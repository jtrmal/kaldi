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
use charnames ":full";
use open qw(:std :utf8);

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


while (<>) {
    s/\N{ARABIC LETTER ALEF MAKSURA ISOLATED FORM}/\N{ARABIC LETTER FARSI YEH}/g;
    s/\N{ZERO WIDTH NON-JOINER}/ /g;

    s/\N{ARABIC LETTER KAF}/\N{ARABIC LETTER KEHEH}/g;
    s/\N{ARABIC LETTER GAF}/\N{ARABIC LETTER KAF WITH RING}/g;
    s/\N{ARABIC LETTER GAF WITH RING}/\N{ARABIC LETTER KAF WITH RING}/g;
    s/\N{ARABIC LETTER FARSI YEH}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER YEH WITH TAIL}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER YEH WITH HAMZA ABOVE}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER E}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER ALEF MAKSURA}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER YEH BARREE}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER YEH BARREE WITH HAMZA ABOVE}/\N{ARABIC LETTER YEH}/g;
    s/\N{ARABIC LETTER ALEF WITH HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g;
    s/\N{ARABIC LETTER ALEF WITH HAMZA BELOW}/\N{ARABIC LETTER ALEF}/g;
    s/\N{ARABIC LETTER ALEF WITH WAVY HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g;
    s/\N{ARABIC LETTER WAW WITH HAMZA ABOVE}/\N{ARABIC LETTER WAW}/g;
    s/\N{ARABIC LETTER HAMZA}//g;
    s/\N{ARABIC SUKUN}//g;
    s/\N{ARABIC DAMMATAN}//g;
    s/\N{ARABIC KASRATAN}//g;
    s/\N{ARABIC DAMMA}//g;
    s/\N{ARABIC SMALL KASRA}//g;
    s/\N{ARABIC SMALL FATHA}//g;
    s/\N{ARABIC LETTER HEH WITH YEH ABOVE}/\N{ARABIC LETTER HEH}/g;
    s/\N{ARABIC LETTER TEH MARBUTA}/\N{ARABIC LETTER HEH}/g;
    s/\N{ARABIC LETTER RREH}/\N{ARABIC LETTER REH WITH RING}/g;
    s/\N{ARABIC LETTER TTEH}/\N{ARABIC LETTER TEH WITH RING}/g;

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

  s/\./ /gi;
  s/\?/ /gi;
  s/,/ /gi;
  s/<[-_A-Za-z\/][-_A-Za-z\/]*>/ /g;
  print uc($_);
}
