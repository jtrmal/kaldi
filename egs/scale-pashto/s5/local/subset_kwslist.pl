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
use XML::Simple;
use Data::Dumper;

binmode STDOUT, ":utf8";

my %seen;
while (my $keyword = <STDIN>) {
  chomp $keyword;
  $seen{$keyword} = 1;
}


my $data = XMLin($ARGV[0], ForceArray => 1);

#print Dumper($data->{kw});
my @filtered_kws = ();

foreach my $kwentry (@{$data->{kw}}) {
  if (defined $seen{$kwentry->{kwid}}) {
    push @filtered_kws, $kwentry;
  }
}
$data->{kw} = \@filtered_kws;
my $xml = XMLout($data, RootName=> "kwlist", KeyAttr=>'');
print $xml; 
exit 0
