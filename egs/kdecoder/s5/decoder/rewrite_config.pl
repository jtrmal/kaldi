#!/usr/bin/env perl

use File::Basename;

use FindBin;
use lib $FindBin::Bin;
my $bindir=$FindBin::Bin;


my ($config, $path, $outdir) = @ARGV;

$name = basename($config);

die "No conf directory found under $outdir" if  (! -d "$outdir/conf");
die "No conf directory found under $outdir" if  (! -d "$outdir/params");

print "# rewriting $config\n";

open F, "< $config";
open OUT, "> $outdir/conf/$name";

while (<F>) {
    chomp;
    if (/^#/){
	print OUT "$_\n";
	next;
    }
    ($flag, $val) = split "=", $_, 2;
  
    #print STDERR "val=$val\n";
    
    if ( ( $val =~ /.conf$/ || $val =~ /\// ) && ( -f $val ) ) {
	unless ($val =~ /^\//) {
	    $val = "$path/$val";
	}
    

	$name = basename($val);
	if ($val =~ /.conf$/ ) {
	    system("$bindir/rewrite_config.pl $val $path $outdir");
	    $val = "conf/$name";
	}
	else {
	    if ( -f "$outdir/params/$name" ) {
		die "Param file with name $name already exists...";
	    }
	    
	    system("cp $val $outdir/params/$name");
	    $val = "params/$name";
	}
    }
    print OUT "$flag=$val\n";
}

close F;
close OUT;

