
A recipe designed to decode with modules using the scale-pashto
nnet recipies developed during the Scale 2015 workshop
(see http://hltcoe.jhu.edu/research/scale-workshops/ ) as a part of
the speech-to-text translation (STTT) system.

This recipe introduces the notion of a model pack, in which the
acoustic model, decoding graph (HCLG.fst), i-vector extractor,
and supporting configuration files are combined together in a 
single self-contained archive.  This recipe is intended to be 
run on machines or systems without the experiment structure or
full Kaldi distribution from which the models were trained.

s5 -- the current recipe
