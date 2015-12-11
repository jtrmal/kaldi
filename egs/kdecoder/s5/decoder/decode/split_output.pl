#!/usr/bin/env perl

use File::Basename;

my ($workfile, $segments, $ctmfile, $htkdir) = @ARGV;

open WF, "< $workfile";
while (<WF>) {
    chomp;
    ($audio, $marks, $output) = split;
    $fileID = basename($output);
    $outputFor{$fileID}=$output;
    if ( ! -d $output ){
	system ("mkdir -p $output");
    }

    system ("zcat $htkdir/$fileID* | gzip -c > $output/$fileID.htk.lat.gz");
    
}
close WF;

open CTM, "<:utf8", $ctmfile;
$lastfile = "";
$utt = "";
while (<CTM>) {
    chomp;
    if (/# utterance (.*$)/) {
	if ($utt ne "") {
	    print TRANS "$utt @words\n";
	}
	$utt = $1;
	$file = $utt;
	$file =~ s/_\d+$//;
 	@words = ();
	    
    }
    else {
	($file, @rest) = split;
    }
    if ($file ne $lastfile ) {
	close TRANS;
	close F;
	$output = $outputFor{$file};
	open F, ">:utf8", "$output/$file.ctm";
	open TRANS, ">:utf8", "$output/$file.txt";
    }
    print F "$_\n";
    $lastfile = $file;
    @f = split;
    $conf = pop @f;
    $word = pop @f;
    push @words, $word;
}

print F;
if ($utt ne "") {
    print TRANS "$utt @words\n";
}
close TRANS;

