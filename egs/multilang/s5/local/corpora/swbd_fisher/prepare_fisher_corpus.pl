#!/usr/bin/env perl

my ($corp, $list, $audio, $trans) = @ARGV;

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
open TRANS, "> $corp/text";
open SEG, "> $corp/segments";
open RECO, "> $corp/reco2file_and_channel";

#print "@ids\n";
@ids = sort(@ids);
foreach $id (@ids) {
#    print "$id\n";;
    $id =~ /fe_03_(\d\d\d)\d\d/;
    $subdir = $1;
    @af = glob("$audio/fe_03_p1_sph*/audio/$subdir/$id.sph");
    if (@af < 1 ) {
        #warn "Cannot find audio for id $id: $audio/fe_03_p1_sph*/audio/$subdir/$id.sph\n";
        next;
    }
    $text = "$trans/fe_03_p1_tran/data/trans/$subdir/$id.txt";
    unless ( -f $text ) {
        #warn "Cannot find transcript for $id\n";
        next;
    }
    
#    print STDERR "Got $af[0] $text\n";

    %chs = ();
    %sides = ();
    %segs = ();
    %seg = ();
    %trans = ();
    open TEXT, "<:utf8", $text;
    while (<TEXT>) {
        chomp;
        next if /^\s*$/;
        next if /^\#/;
        ($start, $stop, $ch, @words) = split;
        $ch =~ /^([AB])/;
        $ch = $1;
        
        $speaker = "${id}_$ch";
        $audioid = $speaker;

        if ($ch eq "A")  {
            $sides{$audioid}=1;
        }
        else {
            $sides{$audioid} = 2;
        }
        

        $segid = sprintf("${speaker}_%06d", int($start *100));
        push @{$segs{$audioid}}, $segid;
        $trans{$segid}="@words";
        $seg{$segid} = sprintf("$audioid %0.2f %0.2f", $start, $stop); 
        
    }
    close TEXT;

    foreach $audioid (sort(keys(%sides))) {
        $ch = $sides{$audioid};
        print WAV "$audioid $binary -f wav -p -c $ch $af[0] |\n";
        printf RECO "$audioid $id %s\n", ($ch==1) ? "A":"B";
        @utts = sort(@{$segs{$audioid}});
        print S2U "$audioid @utts\n";
        foreach $utt (@utts) {
            print U2S "$utt $audioid\n";
            print TRANS "$utt $trans{$utt}\n";
           print SEG "$utt $seg{$utt}\n";
        }
#        
    }
 #   print "Done @ids\n";
    
}
close U2S;
close S2U;
close WAV;
close RECO;
close SEG;
close TRANS;
