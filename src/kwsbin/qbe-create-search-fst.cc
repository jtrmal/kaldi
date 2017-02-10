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

  // this function computes the number of non-eps transitions
  // assumes for each state there is only one outgoing arc
  int ComputePathLength(fst::VectorFst<fst::StdArc> &fst, int state) {
    int len = 0;
    //std::cout << state << " " << fst.Final(state) << " " << fst::StdArc::Weight::Zero() << std::endl;
    while ( fst.Final(state) == fst::StdArc::Weight::Zero() ) {
      int num_arcs = fst.NumArcs(state);
      KALDI_ASSERT(num_arcs == 1);
      fst::ArcIterator<fst::VectorFst<fst::StdArc> > aiter(fst, state);
      //std::cout << state << " " << aiter.Value().ilabel << std::endl;
      len += (aiter.Value().ilabel == 0) ? 0 : 1;
      KALDI_ASSERT(aiter.Value().ilabel == aiter.Value().olabel);
      state = aiter.Value().nextstate;
      //std::cout << state << " " << fst.Final(state) << " " << fst::StdArc::Weight::Zero() << std::endl;
    }
    return len;
  }

  // removes the paths from the fst that are too short (defined by states_limit)
  // it does that by generating first paths_max best paths and then manually
  // for each path of those either keeps it or trash it depending on its length
  // after that, the fst is determinized again.
  void RemovePathsTooShortApprox(fst::VectorFst<fst::StdArc> *fst, int states_limit, int paths_max) {
    fst::VectorFst<fst::StdArc> ofst, ofst_without_weights;

    //std::cout << "Input: " << std::endl;
    //fst::WriteFstKaldi(std::cout, false, *fst);
    //std::cout << " " << std::endl;

    fst::StdArc::StateId start = fst->Start();
    //fst->SetFinal(start, fst::StdArc::Weight::Zero());

    fst::ShortestPath(*fst, &ofst, paths_max);
    fst::TopSort(&ofst);
    fst::StdArc::StateId dummy = ofst.AddState();
    std::vector<fst::StdArc::Weight> distances;

    for (fst::MutableArcIterator<fst::VectorFst<fst::StdArc> > aiter(&ofst, start);
        !aiter.Done(); aiter.Next() ){

      fst::StdArc arc = aiter.Value();
      float my_length = ComputePathLength(ofst, arc.nextstate);
      //std::cout << "len=" << my_length << ", limit=" << states_limit << std::endl;
      if (my_length < states_limit) {
        arc.nextstate = dummy;
        aiter.SetValue(arc);
      }
    }
    fst::Connect(&ofst);
    fst::RmEpsilon(&ofst);
    fst::Determinize(ofst, fst);
    //fst::Minimize(fst);

    //std::cout << "Input: " << std::endl;
    //fst::WriteFstKaldi(std::cout, false, *fst);
    //std::cout << " " << std::endl;
  }

  void RemovePathsTooShort2(fst::VectorFst<fst::StdArc> *fst, int states_limit) {
    std::vector<int> distance(fst->NumStates(), -1);
    std::vector<bool> visited(fst->NumStates(), false);

    distance[0] = 0;
    visited[0] = true;
    fst::StdArc::StateId start = fst->Start();
    if (start == fst::kNoStateId) {
      return;
    }

    fst->SetFinal(start, fst::StdArc::Weight::Zero());

    for (fst::StateIterator<fst::StdFst> siter(*fst);
        !siter.Done(); siter.Next()) {
      fst::StdArc::StateId state_id = siter.Value();

      if (distance[state_id] < states_limit) {
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
    //fst::Minimize(&tmp_fst);

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
      std::vector<std::vector<double> > &scale,
      std::vector<int> &extra_syms,
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
    RemovePathsTooShortApprox(fst, path_length, 10000);
    bool acyclic = fst::TopSort(fst);
    KALDI_ASSERT(acyclic == true);
  }

}  // namespace kws
}  // namespace kaldi

std::vector<int> ParseIntSequence(const std::string &str, const char sep=',') {
  std::vector<int> ret;
  size_t last = 0,
         next = 0;
  char *end = NULL;

  while ((next = str.find(sep, last)) != string::npos) {
    std::string number_str = str.substr(last, next-last);
    int number = strtol(number_str.data(), &end, 10);
    if (end == number_str.data()) {
      KALDI_ERR << "Invalid format of number: \"" << number_str << "\"";
    }
    ret.push_back(number);
    last = next + 1;
  }
  std::string number_str = str.substr(last);
  if (number_str != "") {
    int number = strtol(number_str.data(), &end, 10);
    if (end == number_str.data()) {
      KALDI_ERR << "Invalid format of number: \"" << number_str << "\"";
    }
    ret.push_back(number);
  }
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
        "Set the weight of the language model score.");
    po.Register("ac-scale", &ac_scale,
        "Set the weight of the acoustic score.");
    po.Register("beam", &beam,
        "Prune the fst so that only paths falling into specified beam"
        "will be retained. Set to zero to disable this feature.");
    po.Register("nbest", &nbest,
        "Prune the fst so that only nbest paths will be retained."
        "Set to zero to disable this feature.");
    po.Register("path-length", &path_length,
        "Remove all paths that are not AT LEAST path-length long."
        "Set to zero to disable this feature.");
    po.Register("remove-symbols", &remove_symbols_str,
        "Comma-separated list of symbols that should be removed."
        "Default: empty string, i.e. no symbols will be removed");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    int n_examples_done = 0,
        n_examples_failed = 0;
    int n_done = 0,
        n_fail = 0;

    std::vector<std::vector<double> >
      scale = fst::LatticeScale(lm_scale, ac_scale);

    std::vector<int>
      remove_symbols = ParseIntSequence(remove_symbols_str);

    std::string
      lats_rspecifier = po.GetArg(1),
      fsts_wscpecifier = po.GetArg(2);

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
          bool acyclic = fst::TopSort(&combined_fsts);
          if (combined_fsts.NumStates() > 0) {
            fsts_writer.Write(previous_key, combined_fsts);
          } else {
            KALDI_WARN << "For keyword " << previous_key
                      << " no examples were extracted: "
                      << combined_fsts.NumStates();
            n_fail++;
          }
          KALDI_ASSERT(acyclic == true);
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
      bool acyclic = fst::TopSort(&combined_fsts);
      if (combined_fsts.NumStates() > 0) {
        fsts_writer.Write(previous_key, combined_fsts);
      } else {
        KALDI_WARN << "For keyword " << previous_key
                  << " no examples were extracted: "
                  << combined_fsts.NumStates();
        n_fail++;
      }
      KALDI_ASSERT(acyclic == true);
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

