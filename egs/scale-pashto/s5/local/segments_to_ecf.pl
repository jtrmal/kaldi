#!/usr/bin/env perl
#===============================================================================
# Copyright 2015  (Author: Yenda Trmal <jtrmal@gmail.com>)
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
use Getopt::Long;
use Data::Dumper;

my %FILES;
while (my $line = <>) {
    my @F = split(" ", $line);
    (my $utt, my $file, my $start, my $end) = @F;
    if (defined $FILES{$file} ) {
        if ($FILES{$file}->[0] > $start) {
            $FILES{$file}->[0] = $start;
        }
        if ($FILES{$file}->[1] < $end) {
            $FILES{$file}->[1] = $end;
        }

    } else {
        $FILES{$file}->[0] = $start;
        $FILES{$file}->[1] = $end;
    }

}

my $total_duration=0;
foreach my $file(keys %FILES) {
    $total_duration +=  ($FILES{$file}->[1] - $FILES{$file}->[0]);
}

print "<ecf source_signal_duration=\"$total_duration\" language=\"\" version=\"\">\n";
foreach my $file(keys %FILES) {
    my $tbeg =   $FILES{$file}->[0];
    my $dur =  $FILES{$file}->[1] - $FILES{$file}->[0];
    print "  <excerpt audio_filename=\"$file\" channel=\"1\" tbeg=\"$tbeg\" dur=\"$dur\" source_type=\"splitcts\"/>\n";
}

print "</ecf>\n";
