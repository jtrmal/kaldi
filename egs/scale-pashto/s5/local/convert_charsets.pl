#!/usr/bin/env perl
use warnings;
use strict;
use utf8;
use charnames ":full";
use open qw(:std :utf8);

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


while (<>) {
  s/\N{ARABIC LETTER ALEF MAKSURA ISOLATED FORM}/\N{ARABIC LETTER FARSI YEH}/g;
  s/\N{ZERO WIDTH NON-JOINER}/ /g;

  s/\N{ARABIC LETTER KAF}/\N{ARABIC LETTER KEHEH}/g;
  s/\N{ARABIC LETTER GAF}/\N{ARABIC LETTER KAF WITH RING}/g;
  s/\N{ARABIC LETTER GAF WITH RING}/\N{ARABIC LETTER KAF WITH RING}/g;
  s/\N{ARABIC LETTER FARSI YEH}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER YEH WITH TAIL}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER YEH WITH HAMZA ABOVE}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER E}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER ALEF MAKSURA}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER YEH BARREE}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER YEH BARREE WITH HAMZA ABOVE}/\N{ARABIC LETTER YEH}/g;
  s/\N{ARABIC LETTER ALEF WITH HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g;
  s/\N{ARABIC LETTER ALEF WITH HAMZA BELOW}/\N{ARABIC LETTER ALEF}/g;
  s/\N{ARABIC LETTER ALEF WITH WAVY HAMZA ABOVE}/\N{ARABIC LETTER ALEF}/g;
  s/\N{ARABIC LETTER WAW WITH HAMZA ABOVE}/\N{ARABIC LETTER WAW}/g;
  s/\N{ARABIC LETTER HAMZA}//g;
  s/\N{ARABIC SUKUN}//g;
  s/\N{ARABIC FATHA}//g;
  s/\N{ARABIC DAMMA}//g;
  s/\N{ARABIC KASRA}//g;
  s/\N{ARABIC DAMMATAN}//g;
  s/\N{ARABIC KASRATAN}//g;
  s/\N{ARABIC SMALL KASRA}//g;
  s/\N{ARABIC SMALL FATHA}//g;
  s/\N{ARABIC LETTER HEH WITH YEH ABOVE}/\N{ARABIC LETTER HEH}/g;
  s/\N{ARABIC LETTER TEH MARBUTA}/\N{ARABIC LETTER HEH}/g;
  s/\N{ARABIC LETTER RREH}/\N{ARABIC LETTER REH WITH RING}/g;
  s/\N{ARABIC LETTER TTEH}/\N{ARABIC LETTER TEH WITH RING}/g;


  ###Fix orthography -- sorry, in native script only
s/\bچي\b/چه/g;
s/\bکي\b/کښي/g;
s/\bکنه\b/که.نه/g;
s/\bهاغه\b/هغه/g;
s/\bانشالله\b/انشاالله/g;
s/\bصيب\b/صاحب/g;
s/\bسلامعليکم\b/السلام.علیکم/g;
s/\bاسلامعليکم\b/السلام.علیکم/g;
s/\bوعليکمسلام\b/عليکم.السلام/g;
s/\bوعليکم\b/عليکم/g;
s/\bهيچ\b/هيڅ/g;
s/\bهيچا\b/هيڅ.چا/g;
s/\bهيڅوک\b/هيڅ.څوک/g;
s/\bزياد\b/زيات/g;
s/\bزياده\b/زياته/g;
s/\bتاته\b/تا.ته/g;
s/\bګوزاره\b/ګذاره/g;
s/\bالحمدالله\b/الحمدلله/g;
s/\bاستاذ\b/استاد/g;
s/\bاستاذان\b/استادان/g;
s/\bاستاذه\b/استاده/g;
s/\bاستاذانو\b/استادانو/g;
s/\bپکي\b/په.کښي/g;
s/\bپکښي\b/په.کښي/g;
s/\bنيشته\b/نشته/g;
s/\bکراري\b/قراري/g;
s/\bهسي\b/هغسی/g;
s/\bانشالله\b/انشاالله/g;
s/\bپخپله\b/په.خپله/g;
s/\bپخپل\b/په.خپل/g;
s/\bخلک\b/خلق/g;
s/\bخلکو\b/خلقو/g;
s/\bکمپوټر\b/کمپيوټر/g;
s/\bکمپوټران\b/کمپيوټران/g;
s/\bفټبال\b/فوټبال/g;
s/\bفټبالر\b/فوټبالر/g;
s/\bفټبالو\b/فوټبالو/g;
s/\bقيصه\b/قصه/g;
s/\bجواب\b/ځواب/g;
s/\bخيرخيريت\b/خير.او.خيريت/g;
s/\bخيروخيريت\b/خير.او.خيريت/g;
s/\bکندهار\b/قندهار/g;
s/\bسحر\b/سحار/g;
s/\bسهار\b/سحار/g;
s/\bکوشش\b/کوښښ/g;
s/\bبورد\b/بورډ/g;
s/\bخرچ\b/خرڅ/g;
s/\bخرچونه\b/خرڅونه/g;
s/\bخرچو\b/خرڅو/g;
s/\bخرچه\b/خرڅه/g;
s/\bخرچي\b/خرڅي/g;
s/\bخرچونه\b/خرڅونه/g;
s/\bهماغه\b/هم.هغه/g;
s/\bدولس\b/دوولس/g;
s/\bدولسم\b/دوولسم/g;
s/\bدولسو\b/دوولسو/g;
s/\bدولسمه\b/دوولسمه/g;
s/\bجيني\b/ځيني/g;
s/\bتنخا\b/تنوخواه/g;
s/\bراروان\b/را.روان/g;
s/\bمسيله\b/مسله/g;
s/\bنسوار\b/نصوار/g;
s/\bماسخوتن\b/ماسختن/g;
s/\bکومک\b/کمک/g;
s/\bماسپخين\b/ماسپښين/g;
s/\bماسپخيني\b/ماسپښيني/g;
s/\bماسپخينه\b/ماسپښينه/g;
s/\bپينځلس\b/پنځلس/g;
s/\bپينځه\b/پنځه/g;
s/\bهمدغه\b/هم.دغه/g;
s/\bسرک\b/سړک/g;
s/\bسرکونه\b/سړکونه/g;
s/\bسرکونو\b/سړکونو/g;
s/\bسرکو\b/سړکو/g;
s/\bاسپتال\b/هسپتال/g;
s/\bمځکو\b/ځمکو/g;
s/\bمځکه\b/ځمکه/g;
s/\bمځکي\b/ځمکي/g;
  





  s/#ah/<hes>/g;
  s/#ay/<hes>/g;
  s/#breath/<breath>/g;
  s/#click/<click>/g;
  s/#cough/<cough>/g;
  s/#dtmf/<dtmf>/g;
  s/#foreign/<foreign>/g;
  s/#laugh/<laugh>/g;
  s/#lipsmack/<lipsmack>/g;
  s/#noise/<noise>/g;
  s/#overlap/<overlap>/g;
  s/#ring/<ring>/g;
  s/#silence/<silence>/g;
  s/#um/<hes>/g;
  s/<male2female>/<male-to-female>/g;
  s/<female2male>/<female-to-male>/g;
  s:</?(SouthEast|SouthWest|NorthEast|NorthWest)></?(Female|Male)></?(Mobile|Landline)>::g;
 
  print;
}
