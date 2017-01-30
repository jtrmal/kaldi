// kwsbin/qbe-create-search-fst.cc

// Copyright (c) 2016, Johns Hopkins University (Yenda Trmal<jtrmal@gmail.com>)

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


#include <utility>

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "lat/kaldi-lattice.h"
#include "lat/lattice-functions.h"
#include "fstext/fstext-utils.h"

namespace kaldi {
namespace kws {

  void RemovePathsTooShort(fst::VectorFst<fst::StdArc> *fst, int states_limit) {
    std::vector<int> distance(fst->NumStates(), -1);
    std::vector<bool> visited(fst->NumStates(), false);

    distance[0] = 0;
    visited[0] = true;
    fst::StdArc::StateId start = fst->Start();
    if (start == fst::kNoStateId) {
      return;
    }

    for (fst::StateIterator<fst::StdFst> siter(*fst);
        !siter.Done(); siter.Next()) {
      fst::StdArc::StateId state_id = siter.Value();

      if (distance[state_id] <= states_limit) {
        fst->SetFinal(state_id, fst::StdArc::Weight::Zero());
      }

      for (fst::ArcIterator<fst::StdFst> aiter(*fst, state_id);
          !aiter.Done(); aiter.Next()) {
        const fst::StdArc &arc = aiter.Value();
        int dist = distance[state_id] + 1;
        distance[arc.nextstate] = distance[arc.nextstate] > 0 ? std::min(distance[arc.nextstate], dist) : dist;
      }
    }
  }

  void PostprocessLatticeUnion(fst::VectorFst<fst::StdArc> *combined_fsts,
      int beam, int nbest) {

    // First, lets determinize and minimize in the Log semiring...
    // The reason is that we want to bump up the probability
    // of the paths that appear often. StdArc would give us the max
    // instead of sum
    fst::VectorFst<fst::LogArc> combined_fsts_logarc;
    fst::Cast(*combined_fsts, &combined_fsts_logarc);

    fst::VectorFst<fst::LogArc> tmp_fst;
    fst::Determinize(combined_fsts_logarc, &tmp_fst);
    fst::Minimize(&tmp_fst);

    // Go back to StdArc (tropical semiring). Normalize the weights
    fst::Cast(tmp_fst, combined_fsts);
    fst::VectorFst<fst::StdArc> tmp2_fst;
    fst::Push<fst::StdArc, fst::REWEIGHT_TO_INITIAL>(*combined_fsts,
        &tmp2_fst, fst::kPushWeights);
    std::swap(tmp2_fst, *combined_fsts);

    if (beam > 0) {
      fst::VectorFst<fst::StdArc> tmp_pruned_fst;
      fst::Prune(*combined_fsts, &tmp_pruned_fst, beam);
      std::swap(tmp_pruned_fst, *combined_fsts);
    }

    if (nbest > 0) {
      fst::VectorFst<fst::StdArc> tmp_path_fst;
      fst::ShortestPath(*combined_fsts, &tmp_path_fst, nbest);
      std::swap(tmp_path_fst, *combined_fsts);
    }
    fst::RmEpsilon(combined_fsts);
  }

  void LatticeToFst(CompactLattice *clat, int path_length,
      vector<vector<double> > &scale,
      vector<int> &extra_syms,
      fst::VectorFst<fst::StdArc> *fst) {
    ScaleLattice(scale, clat);
    RemoveAlignmentsFromCompactLattice(clat);
    {
      Lattice lat;
      ConvertLattice(*clat, &lat);
      ConvertLattice(lat, fst);
    }
    fst::Project(fst, fst::PROJECT_OUTPUT);
    RemoveSomeInputSymbols(extra_syms, fst);
    fst::Project(fst, fst::PROJECT_INPUT);
    fst::RmEpsilon(fst);
    {
      fst::VectorFst<fst::StdArc> tmp_fst;
      fst::Determinize(*fst, &tmp_fst);
      fst::Minimize(&tmp_fst);
      std::swap(*fst, tmp_fst);
    }
    fst::TopSort(fst);
    if (path_length > 0) {
      RemovePathsTooShort(fst, path_length);
    }
  }

}  // namespace kws
}  // namespace kaldi

vector<int> ParseIntSequence(const std::string &str, const char sep=',') {
  vector<int> ret;
  size_t last = 0,
         next = 0;
  char *end = NULL;

  while ((next = str.find(sep, last)) != string::npos) {
    std::string number_str = str.substr(last, next-last);
    int number = strtol(number_str.data(), &end, 10);
    if (end == number_str.data()) {
      KALDI_ERR << "Invalid format of number: " << number_str;
    }
    KALDI_LOG << number;
    ret.push_back(number);
    last = next + 1;
  }
  std::string number_str = str.substr(last);
  int number = strtol(number_str.data(), &end, 10);
  if (end == number_str.data()) {
    KALDI_ERR << "Invalid format of number: " << number_str;
  }
  KALDI_LOG << number;
  ret.push_back(number);
  return ret;
}

int main(int argc, const char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::kws;

    const char *usage =
      "Combine the lattice slices into a fst that can be used for searching \n"
      "the kws index (see make_index, search_index binaries)\n"
      "\n"
      "Usage:\n"
      "  qbe-create-search-fst  <examples-rspecifier>   <fst-wspecifier>\n"
      "e.g.\n"
      "  qbe-create-search-fst  scp:examples.scp  ark:keywords.fsts\n"
      "\n"
      "Please note that you probably wanna use sorted scp in the place of\n"
      "the examples-rspecifier\n";

    bool determinize = false,
         minimize = false;

    float lm_scale = 0.01,
        ac_scale = 0.1;

    int nbest =  100;
    int path_length = 1;
    int beam = 0;
    std::string remove_symbols_str;

    ParseOptions po(usage);
    po.Register("determinize", &determinize,
        "Set true if the lattice slice should be determinized");
    po.Register("minimize", &minimize,
        "Set true if the lattice slice should be minimized");
    po.Register("lm-scale", &lm_scale,
        "Set true if the lattice slice should be determinized");
    po.Register("ac-scale", &ac_scale,
        "Set true if the lattice slice should be minimized");
    po.Register("beam", &beam,
        "Prune the fst so that only paths falling into specified beam"
        "will be retained. Set to zero to disable this feature");
    po.Register("nbest", &nbest,
        "Prune the fst so that only nbest paths will be retained."
        "Set to zero to disable this feature");
    po.Register("path-length", &path_length,
        "Remove all paths that are not AT LEAST path-length long."
        "Set to zero to disable this feature.");
    po.Register("remove-symbols", &remove_symbols_str,
        "Remove all paths that are not AT LEAST path-length long."
        "Set to zero to disable this feature.");

    po.Read(argc, argv);

    if (po.NumArgs() < 2 || po.NumArgs() > 2) {
      po.PrintUsage();
      exit(1);
    }

    int n_examples_done = 0,
        n_examples_failed = 0;
    int n_done = 0,
        n_fail = 0;

    vector<vector<double> >
      scale = fst::LatticeScale(lm_scale, ac_scale);

    std::vector<int>
      remove_symbols = ParseIntSequence(remove_symbols_str);

    std::string
      lats_rspecifier = po.GetOptArg(1),
      fsts_wscpecifier = po.GetOptArg(2);

    SequentialCompactLatticeReader lattice_reader(lats_rspecifier);
    TableWriter<fst::VectorFstHolder> fsts_writer(fsts_wscpecifier);

    std::string previous_key = "";
    int same_id_count = 0;
    fst::VectorFst<fst::StdArc> combined_fsts;
    for (; !lattice_reader.Done(); lattice_reader.Next()) {
      std::string key = lattice_reader.Key();
      CompactLattice clat = lattice_reader.Value();

      //Convert to FST
      fst::VectorFst<fst::StdArc> fst;
      LatticeToFst(&clat, path_length, scale, remove_symbols, &fst);
      fst::Connect(&fst);
      n_examples_done++;
      if (fst.NumStates() < 2) {
        n_examples_failed++;
        KALDI_WARN << " conversion failed for example " << key
                  << "(" << same_id_count << ")"
                  << " -- empty fst after Connect()";
      }

      if (key != previous_key) {
        if (previous_key != "") {
          //fst::VectorFs<fst::LogArc> res;
          KALDI_LOG << previous_key << ", "
                   << same_id_count << " examples" << std::endl;
          n_done++;

          PostprocessLatticeUnion(&combined_fsts, beam, nbest);
          fst::Connect(&combined_fsts);
          if (combined_fsts.NumStates() > 0) {
            fsts_writer.Write(previous_key, combined_fsts);
          } else {
            KALDI_WARN << "For keyword " << previous_key
                      << " no examples were extracted: "
                      << combined_fsts.NumStates();
            n_fail++;
          }
        }


        combined_fsts.DeleteStates();
        same_id_count = 0;
        previous_key = key;
      }

      fst::Union(&combined_fsts, fst);
      same_id_count++;
    }
    if (previous_key != "") {
      n_done++;
      PostprocessLatticeUnion(&combined_fsts, beam, nbest);
      fst::Connect(&combined_fsts);
      if (combined_fsts.NumStates() > 0) {
        fsts_writer.Write(previous_key, combined_fsts);
      } else {
        KALDI_WARN << "For keyword " << previous_key
                  << " no examples were extracted: "
                  << combined_fsts.NumStates();
        n_fail++;
      }
    }

    KALDI_LOG << "Done " << n_examples_done
              << " examples, failed for " << n_examples_failed;
    KALDI_LOG << "Done " << n_done << " keywords, failed for " << n_fail;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
  return 0;
}

