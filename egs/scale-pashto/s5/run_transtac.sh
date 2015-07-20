#!/bin/bash                                                                        
# Copyright (c) 2015, Johns Hopkins University (Author: Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.  
boost_sil=1.5
# End configuration section
. ./path.sh
. ./cmd.sh
[ -f local.conf ] && . ./local.conf

. ./utils/parse_options.sh



set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
set -u           #Fail on an undefined variable

AUDIO="${train_data_transtac_dir}"/'Pashto - Audio'
TRANSCRIPTS="${train_data_transtac_dir}"/'Pashto - TX-TL'
LEXICON="$lexicon_transtac_file"
OTHER_SYSTEM="../exp_07_A_and_B_rules_from_david/"
wavlist=transtac/wav.list

if true; then
[ -d $(dirname $wavlist)/audio ] && rm  `dirname $wavlist`/audio/*
mkdir -p `dirname $wavlist`/audio
find "$AUDIO" -name "*.wav" | grep -v -i  'helmand' > $wavlist
while read p; do
    ln -s "$p" `dirname $wavlist`/audio/
done <$wavlist
find `dirname $wavlist`/audio -name "*.wav" > $wavlist


for dataset in train dev dev2; do
   find "$TRANSCRIPTS" -name "*ALL_FINAL*zip" -print0 | xargs -n 1 -0 unzip -p | \
    perl local/tdf_convert.pl conf/lists/transtac_pashto.$dataset  \
                              $wavlist data/${dataset}_transtac
done


mkdir -p data/local/dict
cat "$LEXICON" | local/convert_charsets.pl | \
 perl -CSDL -ne '{
                @F=split(/\t/,) ; push @{$LEX{$F[0]}}, $F[3];
              } 
              END{foreach $w(sort keys %LEX){
                print "$w\t".join("\t", @{$LEX{$w}})."\n"} 
              }' | sed 's/ _ / . /g' |sort - > data/local/dict/filtered_lexicon.txt

local/prepare_lexicon.pl \
  data/local/dict/filtered_lexicon.txt data/local/dict/

if [ ! -z $OTHER_SYSTEM ] && [ -f $OTHER_SYSTEM/data/lang/phones.txt ] ; then 
utils/prepare_lang.sh \
  --share-silence-phones true --phone-symbol-table $OTHER_SYSTEM/data/lang/phones.txt \
  data/local/dict $oovSymbol data/local/lang data/lang
else
utils/prepare_lang.sh \
  --share-silence-phones true \
  data/local/dict $oovSymbol data/local/lang data/lang
fi


for dataset in train_transtac dev_transtac dev2_transtac ; do
  cat data/${dataset}/transcripts| \
  grep -v 'overlap' | \
  local/convert_charsets.pl | \
  perl -CSDL -mutf8 -e '
    %LEX;
    %OOV;
    binmode STDIN, "utf8";
    binmode STDOUT, "utf8";
    open(VOCAB, "<:encoding(utf-8)", $ARGV[0]);
    while(<VOCAB>) {
      chomp;
      @F=split(" ");
      $LEX{$F[0]} = 1;
    }
    close(VOCAB);
    print STDERR "Read " . scalar (keys %LEX) . " vocab entries.\n";
    
    $unk = $ARGV[1];
    while( <STDIN> ) {
      chomp;
      @F = split(" ");
      for ( $i = 1; $i <$#F; $i++) {
        my $orig = $F[$i];
        
        if ($F[$i] =~ /<.*>/) {
          if (($F[$i] eq "<hes>") || ($F[$i] eq "<yes>")) {
            $F[$i] = "<v-noise>";
          } elsif ($F[$i] eq "<spk>") {
            $F[$i] = "<noise>";
          } elsif ($F[$i] =~ /<*_noise>/ ) {
            $F[$i] = "<noise>";
          }
        } else { 
          $F[$i] =~ s/\^//g;
          $F[$i] =~ s/\+//g;
          $F[$i] =~ s/@//g;
          $F[$i] =~ s/--//g;
          $F[$i] =~ s/-//g;
        }
        next unless ($F[$i]);
        if ( !exists $LEX{$F[$i]} ) {
          $OOV{$orig} +=1;
          $F[$i] = $unk;
        }
      }
      print join(" ", @F) . "\n";
    }
    if ( defined $ARGV[2] ) {
      open(my $OOVS, "|-:encoding(utf8)", "sort -k2nr -k1,1 > $ARGV[2]");
      foreach $k (keys %OOV) {
        print $OOVS "$k\t $OOV{$k}\n"; 
      }
      close($OOVS);
    }
  ' data/lang/words.txt "<unk>" data/${dataset}/oovCount > data/${dataset}/text
done


(cd data; ln -s train_transtac train)
local/train_lms_srilm.sh  --oov-symbol "<unk>" \
  --train-text data/train//text \
  --words-file data/lang/words.txt data/ data/srilm 

rm -rf data/lang_test/
cp -R data/lang/ data/lang_test
local/arpa2G.sh data/srilm/lm.gz data/lang_test data/lang_test

for dataset in train_transtac dev_transtac dev2_transtac ; do
  if [ ! -f data/${dataset}/.plp.done ]; then
    utils/fix_data_dir.sh data/${dataset}
    steps/make_plp_pitch.sh --cmd "$train_cmd" --nj 32 \
        data/${dataset} exp/make_plp_pitch/${dataset} plp

    utils/fix_data_dir.sh data/${dataset}
    steps/compute_cmvn_stats.sh data/${dataset} exp/make_plp/${dataset} plp
    utils/fix_data_dir.sh data/${dataset}
    touch data/${dataset}/.plp.done
  fi
done

numutt=`cat data/train/feats.scp | wc -l`;
utils/subset_data_dir.sh data/train  5000 data/train_sub1
if [ $numutt -gt 10000 ] ; then
  utils/subset_data_dir.sh data/train 10000 data/train_sub2
else
  (cd data; ln -s train train_sub2 )
fi
if [ $numutt -gt 20000 ] ; then
  utils/subset_data_dir.sh data/train 20000 data/train_sub3
else
  (cd data; ln -s train train_sub3 )
fi

fi

if [ ! -f exp/mono/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/mono on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data/train_sub1 data/lang exp/mono
  touch exp/mono/.done
fi

if [ ! -f exp/tri1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/tri1 on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data/train_sub2 data/lang exp/mono exp/mono_ali_sub2
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data/train_sub2 data/lang exp/mono_ali_sub2 exp/tri1
  
  touch exp/tri1/.done
fi


echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/tri2 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri2/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data/train_sub3 data/lang exp/tri1 exp/tri1_ali_sub3
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data/train_sub3 data/lang exp/tri1_ali_sub3 exp/tri2
  
  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train_sub3 data/lang data/local/dict \
    exp/tri2 data/local/dictp/tri2 data/local/langp/tri2 data/langp/tri2

  touch exp/tri2/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/tri3 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri3/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri2 exp/tri2 exp/tri2_ali

  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data/train data/langp/tri2 exp/tri2_ali exp/tri3
  
  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri3 data/local/dictp/tri3 data/local/langp/tri3 data/langp/tri3

  touch exp/tri3/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri3 exp/tri3 exp/tri3_ali

  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data/train data/langp/tri3 exp/tri3_ali exp/tri4

  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri4 data/local/dictp/tri4 data/local/langp/tri4 data/langp/tri4

  touch exp/tri4/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5 on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri4 exp/tri4 exp/tri4_ali

  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/train data/langp/tri4 exp/tri4_ali exp/tri5
  
  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri5 data/local/dictp/tri5 data/local/langp/tri5 data/langp/tri5
  
  touch exp/tri5/.done
fi


if [ ! -f exp/tri5_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/langp/tri5 exp/tri5 exp/tri5_ali
  
  local/reestimate_langp.sh --cmd "$train_cmd" --unk "<unk>" \
    data/train data/lang data/local/dict \
    exp/tri5_ali data/local/dictp/tri5_ali data/local/langp/tri5_ali data/langp/tri5_ali
fi

exit  0
if [ -x ./decode.sh ] ; then
  ## Spawn decoding....
  echo ---------------------------------------------------------------------
  echo "Starting decoding on" `date`
  echo ---------------------------------------------------------------------
  ./decode.sh
fi






