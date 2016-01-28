// online2bin/online2-wav-nnet2-latgen-faster.cc

// Copyright 2014  Johns Hopkins University (author: Daniel Povey)

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include "feat/wave-reader.h"
#include "online2/online-nnet2-decoding.h"
#include "online2/onlinebin-util.h"
#include "online2/online-timing.h"
#include "online2/online-endpoint.h"
#include "fstext/fstext-lib.h"
#include "lat/lattice-functions.h"
#include "thread/kaldi-thread.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    
    typedef kaldi::int32 int32;
    typedef kaldi::int64 int64;
    
    const char *usage =
        "Reads in wav file(s) and simulates online decoding with neural nets\n"
        "(nnet2 setup), with optional iVector-based speaker adaptation and\n"
        "optional endpointing.  Note: some configuration values and inputs are\n"
        "set via config files whose filenames are passed as options\n"
        "\n"
        "Usage: online2-wav-nnet2-latgen-faster [options] <nnet2-in> <fst-in> "
        "<spk2utt-rspecifier> <wav-rspecifier> <lattice-wspecifier>\n"
        "The spk2utt-rspecifier can just be <utterance-id> <utterance-id> if\n"
        "you want to decode utterance by utterance.\n"
        "See egs/rm/s5/local/run_online_decoding_nnet2.sh for example\n"
        "See also online2-wav-nnet2-latgen-threaded\n";
    
    ParseOptions po(usage);
    
    std::string word_syms_rxfilename;
    
    OnlineEndpointConfig endpoint_config;

    // feature_config includes configuration for the iVector adaptation,
    // as well as the basic features.
    OnlineNnet2FeaturePipelineConfig feature_config;  
    OnlineNnet2DecodingConfig nnet2_decoding_config;

    BaseFloat chunk_length_secs = 0.05;
    bool do_endpointing = false;
    bool online = true;
    
    po.Register("word-symbol-table", &word_syms_rxfilename,
                "Symbol table for words [for debug output]");

    feature_config.Register(&po);
    nnet2_decoding_config.Register(&po);
    endpoint_config.Register(&po);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 1) {
      po.PrintUsage();
      return 1;
    }
    
    std::string nnet2_rxfilename = po.GetArg(1);
    
    OnlineNnet2FeaturePipelineInfo feature_info(feature_config);

    if (!online) {
      feature_info.ivector_extractor_info.use_most_recent_ivector = true;
      feature_info.ivector_extractor_info.greedy_ivector_extractor = true;
      chunk_length_secs = -1.0;
    }
    
    TransitionModel trans_model;
    nnet2::AmNnet nnet;
    {
      bool binary;
      Input ki(nnet2_rxfilename, &binary);
      trans_model.Read(ki.Stream(), binary);
      nnet.Read(ki.Stream(), binary);
    }

    nnet2::Nnet &net  = nnet.GetNnet();

    cout << "NNET:  NumPdfs = " << nnet.NumPdfs() << "\n";
    cout << "NNET:  NumComponents = " << net.NumComponents() << "\n";

	int c;
	for (c=0; c < net.NumComponents(); c++) {
		cout << "NNET(" << c << "): " << net.GetComponent(c).Info() << "\n";
	}

    fst::SymbolTable *word_syms = NULL;
    if (word_syms_rxfilename != "")
      if (!(word_syms = fst::SymbolTable::ReadText(word_syms_rxfilename)))
        KALDI_ERR << "Could not read symbol table from file "
                  << word_syms_rxfilename;
    
    int32 num_done = 0, num_err = 0;
    double tot_like = 0.0;
    int64 num_frames = 0;
    
    
    KALDI_LOG << "Decoded " << num_done << " utterances, "
              << num_err << " with errors.";
    KALDI_LOG << "Overall likelihood per frame was " << (tot_like / num_frames)
              << " per frame over " << num_frames << " frames.";

    delete word_syms; // will delete if non-NULL.
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception& e) {
    std::cerr << e.what();
    return -1;
  }
} // main()
