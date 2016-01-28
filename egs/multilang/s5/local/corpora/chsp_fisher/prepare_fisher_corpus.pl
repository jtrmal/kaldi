#!/usr/bin/env perl

sub clean {
    $str = shift @_;
    $str =~ s/[?!¿¡\*\+\"]//g;
    
  #  $str =~ s/\{[^\}]*\}//g; # ingore nonspeech
    $str =~ s/\[+[^\]]*\]+//g;  # ignore nonspeech

    $str =~ s/\(+[^\)]*\)+//g; # ignore nonspeech

    

    $str =~ s/\.\s*/ /g;  # periods are inconsistent so remove them.
    $str =~ s/\,\s*/ /g;  # end of sentence commas 

    $str =~ s/\/\// /g;  # pretty print parentheticals
    
    
    $str =~ s/#//g;   # not sure what LDC uses this for 

    $str =~ s/\%//g;   # filled pauses (uh,ah,em)

    $str =~ s/\&([A-Z])\s/$1 /g;  #abbreviations 
    $str =~ s/\&//g;   # remove entity markings


    $str =~ s/\<+(\S+)\s+//g; # these indicate out of language

    while ($str =~ s/\<+(\S+)\s+([^\>]+)\>+/$2/g) {
	; # these indicate out of language
    }
#    $str =~ s/\*+([^\*]+)\*+/\"$1\" \(sic\)/g;    

    $str =~ s/[;:]/ /g;
    
    $str =~ s/\(//g;
    $str =~ s/\)//g;

    $str =~ s/--/ /g;
    
    $str =~ s/\s+/ /g;  #normalize spaces
    
    $str =~ s/^ //;

    $str =~ s/\>//g;
    $str =~ s/\<//g;

    $str =~ s/\{\/?+[^\}]*\}+/<noise>/g;        # ignore nonspeech

   $str =~ s/__//g;
    $str =~ s/ -$//;
    $str =~ s/^- //;
    $str =~ s/ - //;

    return lc($str);
}


my ($corp, $list, $audio, $trans, $atmp) = @ARGV;

open LIST, "< $list";
while (<LIST>) {
    chomp;
    $id = $_;
    push @ids, $id;

}
close LIST;

$root = $ENV{'KALDI_ROOT'};

my $binary=`which sph2pipe` or die "Could not find the sph2pipe command"; chomp $binary;

open WAV, "> $corp/wav.scp";
open U2S, "> $corp/utt2spk";
open S2U, "> $corp/spk2utt";
open TRANS, ">:utf8", "$corp/text";
open SEG, "> $corp/segments";
open RECO, "> $corp/reco2file_and_channel";

%chs = ();
%sides = ();
%segs = ();
%seg = ();
%trans = ();

if (!defined($atmp)) {
    unless ( -d "$corp/raw_audio") {
	mkdir "$corp/raw_audio";
    }
    $atmp = "$corp/raw_audio";
}
else {
    
}

#print "@ids\n";
@ids = sort(@ids);
foreach $id (@ids) {
#    print "$id\n";;
    $subdir = $1;
    @af = glob("$audio/$id.sph*");
    if (@af < 1 ) {
        warn "Cannot find audio for id $id: $audio/$id.sph*\n";
        next;
    }
    $text = "$trans/$id.tdf";
    unless ( -f $text ) {
        #warn "Cannot find transcript for $id\n";
        next;
    }
    
#    print STDERR "Got $af[0] $text\n";

#    open TEXT, "< :encoding(Latin1)",  $text or die "$!: $text";
    open TEXT, "<:utf8", $text or die "$!: $text";
    $head = <TEXT>;
    while (<TEXT>) {
        chomp;
        next if /^\#/;
        next if /^;/;
        ($fid, $ch, $start, $stop, $spk, $gender, $native, $words, @rest) = split /\t/, $_;
        if ($ch == 0) {
	    $ch = 'A';
	}
	else { 
	    $ch = 'B'; 
	}
	
        $speaker = "${id}_$ch";
        $audioid = $speaker;

        if ($ch eq "A")  {
            $sides{$audioid}=1;
        }
        else {
            $sides{$audioid} = 2;
        }
        

        $segid = sprintf("${speaker}_%06d", int($start *100));
        #push @{$segs{$audioid}}, $segid;
	$w = clean($words);
	if (defined ($segs{$audioid}{$segid})) {
	    if (length($w) < length($trans{$segid})) {
		next;
	    }
	}

	if (int($start*100)/100 == int($stop*100)/100) {
	    next;
	}

	$segs{$audioid}{$segid}=1;
        $trans{$segid}=$w;
        $seg{$segid} = sprintf("$audioid %0.2f %0.2f", 
			       int($start*100)/100, int($stop*100)/100); 

        $afiles{$audioid}=$af[0];

    }
    close TEXT;
}

use File::Basename;

 
foreach $audioid (sort(keys(%sides))) {
    $ch = $sides{$audioid};
    $af = $afiles{$audioid};
    if ( $afiles{$audioid} =~ /.gz$/ ) {
	$name = basename($af);
	$name =~ s/.gz$//;
	if ( ! -f "$atmp/$name") {
	    print STDERR "Decompressing $af\n";
	    system("zcat $af > $atmp/$name");
	}
	$af = "$atmp/$name";
    }
    

    print WAV "$audioid $binary -f wav -p -c $ch $af |\n";
    printf RECO "$audioid $id %s\n", ($ch==1) ? "A":"B";
    @utts = sort(keys(%{$segs{$audioid}}));
    print S2U "$audioid @utts\n";
    foreach $utt (@utts) {
	print U2S "$utt $audioid\n";
	print TRANS "$utt $trans{$utt}\n";
	print SEG "$utt $seg{$utt}\n";
    }
#        
}
 #   print "Done @ids\n";
    

close U2S;
close S2U;
close WAV;
close RECO;
close SEG;
close TRANS;
