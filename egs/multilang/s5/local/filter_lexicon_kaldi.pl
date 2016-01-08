#!/usr/bin/env perl

my ($train, $lex, $out) = @ARGV;

open TRANS, "<:utf8", "$train/text" or die "$!: $train/text";
while (<TRANS>) {
    chomp;
    ($segment, @words) = split;
    foreach $w (@words) {
        $intrans{$w}=1;
    }
}
close TRANS;

if ($lex ne "-") {
    open LEX, "<:utf8", $lex;
}
else {
    binmode STDIN, ":utf8";
    *LEX = *STDIN;
}

if ($out ne "-") {
    open OUT, ">:utf8", $out;
}
else {
    binmode STDOUT, ":utf8";
    *OUT = *STDOUT;
}

while (<LEX>) {
    chomp;
    ($word, @pron) = split;
    if ($intrans{$word}) {
        print OUT "$word\t$word\t@pron\n";
    }
}
close LEX;
close OUT;
