#!/usr/bin/env perl

my ($lex, $out) = @ARGV;

open FILE, "< :encoding(Latin1)",  $lex or die "$!: $lex";
open OUTA, ">:utf8", "$out";

while (<FILE>) {
    chomp;
    ($wd, $parse, $pron, @rest) = split;
    @prons = split /\/+/, $pron;
    $wc = lc($wd);
    foreach $pron (@prons) {
	@phons = split "", $pron;
	print OUTA "$wd\t@phons\n";
    }


}
close FILE;
close OUTA;
