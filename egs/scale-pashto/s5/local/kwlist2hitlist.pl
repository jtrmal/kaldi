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
use encoding 'utf8';

use XML::Parser;
use Data::Dumper;

my $KW;
my $frames_per_sec = 100;

sub  detected_kwlist {
  my $expat = shift @_;
  my $tag = shift @_;
  my %params = @_;
  $KW = $params{kwid};
}

sub  _detected_kwlist {
  print Dumper(\@_);
}

sub  kw  {
  my $expat = shift @_;
  my $tag = shift @_;
  my %params = @_;

  my $s = sprintf("%s %d %d %f", $params{file}, 
                                 $params{tbeg} * $frames_per_sec,
                                 ($params{tbeg}+$params{dur}) * $frames_per_sec,
                                 $params{score});
  print "$KW $s\n";
}

sub  _kw {
  print Dumper(\@_);
}

sub handle_char {
    #print Dumper(\@_);
}

my $p = new XML::Parser(Style => 'Subs', 
                        Handlers=>{  Char  => \&handle_char });
$p->parse(\*STDIN, ErrorContext => 3);

