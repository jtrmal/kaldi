#!/bin/bash                                                                        
# Copyright (c) 2015, Johns Hopkins University ( Yenda Trmal <jtrmal@gmail.com> )
# License: Apache 2.0

# Begin configuration section.  
# End configuration section
set -e -o pipefail 
set -o nounset                              # Treat unset variables as an error

lexicon=$1
destination=$2

cat "$lexicon" | local/convert_charsets.pl | \
 perl -CSDL -ne '{
                @F=split(/\t/,) ; push @{$LEX{$F[0]}}, $F[3];
              }
              END{foreach $w(sort keys %LEX){
                print "$w\t".join("\t", @{$LEX{$w}})."\n"}
              }' | sed 's/ _ / . /g' |sort - > $destination

