sub msystem {
    print "@_\n";
    system @_;
}

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


my ($corp, $audio, $src) = @ARGV;
use File::Basename;

$root = $ENV{'KALDI_ROOT'};

my $binary=`which sph2pipe` or die "Could not find the sph2pipe command"; chomp $binary;

open WAV, "> $corp/wav.scp";
open U2S, "> $corp/utt2spk";
open S2U, "> $corp/spk2utt";
open TRANS, ">:utf8",  "$corp/text";
open SEG, "> $corp/segments";
open RECO, "> $corp/reco2file_and_channel";

%chs = ();
%sides = ();
%segs = ();
%seg = ();
%trans = ();




@tr = glob("$src/*.txt");

foreach $file (@tr) {
    $name = basename($file);
    $name =~ s/.txt$//;

    open TEXT, "< :encoding(Latin1)",  $file or die "$!: $file";
#    open OUTA, ">:utf8", "$dest/${name}_A.txt" or die;
#    open OUTB, ">:utf8", "$dest/${name}_A.txt" or die;
    $lasta = 0;
    $lastb = 0;

#   print "$file\n";

    $id = basename($file);
    $id =~ s/.txt//;

    $af = "$audio/$id.sph";
    if ( ! -f $af ) {
	warn "Cannot find audio for $id\n";
	next;
    }


    while (<TEXT>) {
	chomp;

	($start, $stop, $ch, $rest) = split /\s+/, $_, 4;

	$rest = clean($rest);
	@words = split /\s+/,  $rest;

        #($start, $stop, $ch, @words) = split;
        $ch =~ /^([AB])/;
        $ch = $1;
        
        $speaker = "${id}_$ch";
        $audioid = $speaker;
	$audioFor{$audioid}=$af;

        if ($ch eq "A")  {
            $sides{$audioid}=1;
        }
        else {
            $sides{$audioid} = 2;
        }
        

        $segid = sprintf("${speaker}_%06d", int($start *100));
	if (defined ($segs{$audioid}{$segid})) {
	    if (length("@words") < length($trans{$segid})) {
		next;
	    }
	}
	$segs{$audioid}{$segid}=1;
        $trans{$segid}="@words";
        $seg{$segid} = sprintf("$audioid %0.2f %0.2f", $start, $stop); 
        


#	if  ($spk =~ /^A/) {
#	    if ($lasta != $start) {
#		if ($lasta > 0 && $lasta < $start) {
#		    print OUTA "<no-speech>\n";
#		}
#		if ($start > $lasta) {
#		    printf OUTA "[%0.3f]\n", $start;
#		    
#		}
#		if ($end < $lasta) {
#		    next;
#		}
#	    }
#	    print OUTA "$rest\n";
#	    printf OUTA "[%0.3f]\n", $end;
#	    $lasta = $end;
#	}
#	if  ($spk =~ /^B/) {
#	    if ($lastb != $start) {
#		if ($lastb > 0 && $lastb < $start) {
#		    print OUTB "<no-speech>\n";
#		}
#		if ($start > $lastb) {
#		    printf OUTB "[%0.3f]\n", $start;
#		}
#		if ($end < $lastb) {
#		    next;
#		}
#	    }
#	    print OUTB "$rest\n";
#	    printf OUTB "[%0.3f]\n", $end;
#	    $lastb = $end;
#	}

#    }
    }
    close TEXT;

}

foreach $audioid (sort(keys(%sides))) {
    $ch = $sides{$audioid};
	$af = $audioFor{$audioid};
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

close U2S;
close S2U;
close WAV;
close RECO;
close SEG;
close TRANS;




