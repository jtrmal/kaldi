#!/usr/bin/env perl

my ($decodeA, $decodeB) = @ARGV;

if (! -f "$decodeA/kwslist.xml.original") {
	system("cp $decodeA/kwslist.xml $decodeA/kwslist.xml.original");
}


open OUT, "> $decodeA/kwslist.xml";
open A, "< $decodeA/kwslist.xml.original";
while (<A>) {
	chomp;
	if (/<kwslist/) {
		print OUT "$_\n";
	}
	elsif (/<detected
