// kwsbin/qbe-extract-examples

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

namespace kaldi {
namespace kws {

// A structure used to store the forward and backward scores
// and state times of a lattice
struct LatticeInfo {
  // These values are stored in log.
  std::vector<double> alpha;
  std::vector<double> beta;
  std::vector<int32> state_times;

  void Check() const;
};

void LatticeInfo::Check() const {
  // Check if all the vectors are of size num_states
  KALDI_ASSERT(state_times.size() == alpha.size() &&
               state_times.size() == beta.size());

  // Check that the states are ordered in increasing order of state_times.
  // This must be true since the states are in breadth-first search order.
  KALDI_ASSERT(IsSorted(state_times));
}

// based on the code from Vimal
void ExtractLatticeRange(
    const Lattice &in_lat, const LatticeInfo &scores,
    int32 begin_frame, int32 end_frame, bool normalize,
    Lattice *out_lat)  {
  typedef Lattice::StateId StateId;

  const std::vector<int32> &state_times = scores.state_times;

  // Some checks to ensure the lattice and scores are prepared properly
  KALDI_ASSERT(state_times.size() == in_lat.NumStates());
  if (!in_lat.Properties(fst::kTopSorted, true))
    KALDI_ERR << "Input lattice must be topologically sorted.";

  std::vector<int32>::const_iterator
    begin_iter = std::lower_bound(state_times.begin(),
                                  state_times.end(), begin_frame),
      end_iter = std::lower_bound(begin_iter,
                                  state_times.end(), end_frame);

  KALDI_ASSERT(*begin_iter == begin_frame &&
               (begin_iter == state_times.begin() ||
                begin_iter[-1] < begin_frame));
  // even if end_frame == supervision_.num_frames, there should be a state with
  // that frame index.
  KALDI_ASSERT(end_iter[-1] < end_frame &&
               (end_iter < state_times.end() || *end_iter == end_frame));
  StateId begin_state = begin_iter - state_times.begin(),
          end_state = end_iter - state_times.begin();

  KALDI_ASSERT(end_state > begin_state);
  out_lat->DeleteStates();
  out_lat->ReserveStates(end_state - begin_state + 2);

  // Add special start state
  StateId start_state = out_lat->AddState();
  out_lat->SetStart(start_state);

  for (StateId i = begin_state; i < end_state; i++)
    out_lat->AddState();

  // Add the special final-state.
  StateId final_state = out_lat->AddState();
  out_lat->SetFinal(final_state, LatticeWeight::One());

  for (StateId state = begin_state; state < end_state; state++) {
    StateId output_state = state - begin_state + 1;
    if (state_times[state] == begin_frame) {
      // we'd like to make this an initial state, but OpenFst doesn't allow
      // multiple initial states.  Instead we add an epsilon transition to it
      // from our actual initial state.  The weight on this
      // transition is the forward probability of the said 'initial state'
      LatticeWeight weight = LatticeWeight::One();
      double score = (normalize ? scores.beta[0] : 0.0) - scores.alpha[state];
      weight.SetValue1(score);
      // Add negative of the forward log-probability to the graph cost score,
      // since the acoustic scores would be changed later.
      // Assuming that the lattice is scaled with appropriate acoustic
      // scale.
      // We additionally normalize using the total lattice score. Since the
      // same score is added as normalizer to all the paths in the lattice,
      // the relative probabilities of the paths in the lattice is not affected.
      // Note: Doing a forward-backward on this split must result in a total
      // score of 0 because of the normalization.

      out_lat->AddArc(start_state,
                      LatticeArc(0, 0, weight, output_state));
    } else {
      KALDI_ASSERT(scores.state_times[state] < end_frame);
    }
    for (fst::ArcIterator<Lattice> aiter(in_lat, state);
          !aiter.Done(); aiter.Next()) {
      const LatticeArc &arc = aiter.Value();
      StateId nextstate = arc.nextstate;
      if (nextstate >= end_state) {
        // A transition to any state outside the range becomes a transition to
        // our special final-state.
        // The weight is just the negative of the backward log-probability +
        // the arc cost. We again normalize with the total lattice score.
        LatticeWeight weight;
        // KALDI_ASSERT(scores.beta[state] < 0);
        weight.SetValue1(arc.weight.Value1() - scores.beta[nextstate]);
        weight.SetValue2(arc.weight.Value2());
        // Add negative of the backward log-probability to the LM score, since
        // the acoustic scores would be changed later.
        // Note: We don't normalize here because that is already done with the
        // initial cost.

        out_lat->AddArc(output_state,
            LatticeArc(arc.ilabel, arc.olabel, weight, final_state));
      } else {
        StateId output_nextstate = nextstate - begin_state + 1;
        out_lat->AddArc(output_state,
            LatticeArc(arc.ilabel, arc.olabel, arc.weight, output_nextstate));
      }
    }
  }

  fst::RmEpsilon(out_lat);
  // if (config_.collapse_transition_ids)
  //  CollapseTransitionIds(state_times, out_lat);

  fst::TopSort(out_lat);
  std::vector<int32> state_times_tmp;
  KALDI_ASSERT(LatticeStateTimes(*out_lat, &state_times_tmp) ==
                                            end_frame - begin_frame);
}

void PostprocessLattice(bool determinize, bool minimize, Lattice *lattice) {
  fst::RmEpsilon(lattice);
  if (determinize) {
    if (!minimize) {
      Lattice tmp_lat;
      fst::Determinize(*lattice, &tmp_lat);
      std::swap(*lattice, tmp_lat);
    } else {
      Lattice tmp_lat;
      fst::Reverse(*lattice, &tmp_lat);
      fst::Determinize(tmp_lat, lattice);
      fst::Reverse(*lattice, &tmp_lat);
      fst::Determinize(tmp_lat, lattice);
      fst::RmEpsilon(lattice);
    }
  }
}

void ComputeLatticeScores(const Lattice &lat, LatticeInfo *scores) {
  LatticeStateTimes(lat, &(scores->state_times));
  ComputeLatticeAlphasAndBetas(lat, false,
                               &(scores->alpha), &(scores->beta));
  scores->Check();
}

void PrepareLattice(Lattice *lat, LatticeInfo *scores) {
  LatticeStateTimes(*lat, &(scores->state_times));
  int32 num_states = lat->NumStates();
  std::vector<std::pair<int32, int32> > state_time_indexes(num_states);
  for (int32 s = 0; s < num_states; s++) {
    state_time_indexes[s] = std::make_pair(scores->state_times[s], s);
  }

  // Order the states based on the state times. This is stronger than just
  // topological sort. This is required by the lattice splitting code.
  std::sort(state_time_indexes.begin(), state_time_indexes.end());

  std::vector<int32> state_order(num_states);
  for (int32 s = 0; s < num_states; s++) {
    state_order[state_time_indexes[s].second] = s;
  }

  fst::StateSort(lat, state_order);
  ComputeLatticeScores(*lat, scores);
}

struct QbeLatticeExamplesInfo {
  unordered_map<std::string, std::vector<int> > lattice_to_example;
  std::vector<std::string> example_to_kwid;
  std::vector<std::pair<int, int> > example_to_time;
};

void QbeReadExampleMap(const std::string &filename_rspecifier,
                       int frames_per_sec,
                       kaldi::kws::QbeLatticeExamplesInfo *info) {
    Input ki(filename_rspecifier);
    std::string line;
    int num_lines = -1;
    int example_id = 0;

    while (std::getline(ki.Stream(), line)) {
      num_lines++;
      std::vector<std::string> split_line;
      // Split the line by space or tab and check the number of fields in each
      // line. There must be 4 fields-- example name , utterance id
      // start time, end time
      SplitStringToVector(line, " \t\r", true, &split_line);
      if ((split_line.size() < 4) || (split_line.size() > 5)) {
        KALDI_WARN << "Invalid line in the example map file: " << line;
        continue;
      }
      std::string example = split_line[0],
          utterance = split_line[1],
          start_str = split_line[2],
          end_str = split_line[3];

      // VConvert the start time and endtime to real from string. Segment is
      // ignored if start or end time cannot be converted to real.
      double start, end;
      if (!ConvertStringToReal(start_str, &start)) {
        KALDI_WARN << "Invalid line in segments file [bad start]: " << line;
        continue;
      }
      if (!ConvertStringToReal(end_str, &end)) {
        KALDI_WARN << "Invalid line in segments file [bad end]: " << line;
        continue;
      }
      // start time must not be negative;
      // start time must not be greater than end time
      if ((start < 0) || (end <= 0) || (start >= end)) {
        KALDI_WARN << "Invalid line in segments file "
                   << "[empty or invalid segment]: " << line;
        continue;
      }

      info->lattice_to_example[utterance].push_back(example_id);
      int start_frame = static_cast<int>(start);
      int end_frame = static_cast<int>(end) + 1;
      info->example_to_time.push_back(std::make_pair(start_frame, end_frame));
      info->example_to_kwid.push_back(example);
      example_id++;
    }
}

}  // namespace kws
}  // namespace kaldi


int main(int argc, const char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::kws;

    const char *usage =
      "Extract lattice chunks corresponding to the individual keywords\n"
      "instances and writes them as a lattices archive. The instance id\n"
      "will be used as a lattice name\n";

    bool determinize = false,
         minimize = false;
    ParseOptions po(usage);
    po.Register("determinize", &determinize,
        "Set true if the lattice slice should be determinized");
    po.Register("minimize", &minimize,
        "Set true if the lattice slice should be minimized");

    po.Read(argc, argv);

    if (po.NumArgs() < 3 || po.NumArgs() > 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string table_rspecifier = po.GetOptArg(1),
      lats_rspecifier = po.GetOptArg(2),
      examples_wscpecifier = po.GetOptArg(3);

    int n_examples_done = 0,
        n_examples_failed = 0;
    int n_done = 0,
        n_fail = 0;

    QbeLatticeExamplesInfo info;
    QbeReadExampleMap(table_rspecifier, 100, &info);
    SequentialLatticeReader lattice_reader(lats_rspecifier);
    LatticeWriter examples_writer(examples_wscpecifier);

    for (; !lattice_reader.Done(); lattice_reader.Next()) {
      std::string key = lattice_reader.Key();

      n_done++;
      if (info.lattice_to_example.find(key) == info.lattice_to_example.end())
        continue;
      KALDI_LOG << "Processing lattice " << key;


      Lattice lat = lattice_reader.Value();
      fst::TopSort(&lat);
      LatticeInfo lattice_info;
      PrepareLattice(&lat, &lattice_info);
      int num_states = lattice_info.state_times.size();
      int last_frame = lattice_info.state_times[num_states - 1];

      std::vector<int> examples = info.lattice_to_example[key];

      for (std::vector<int>::iterator it = examples.begin();
          it != examples.end(); ++it) {
        Lattice out;
        int start_frame = info.example_to_time[*it].first;
        int end_frame = info.example_to_time[*it].second;

        if (end_frame >= (last_frame)) {
          KALDI_LOG << "last frame: " << last_frame
                    << " end frame: " << end_frame;
          end_frame = last_frame;
        }

        ExtractLatticeRange(lat, lattice_info,
            start_frame, end_frame, false, &out);

        std::string example_name = info.example_to_kwid[*it];
        examples_writer.Write(example_name, out);

        PostprocessLattice(determinize, minimize, &out);

      }
    }

    KALDI_LOG << "Extracted " << n_examples_done
      << " lattice examples, failed for " << n_examples_failed;
    KALDI_LOG << "Done " << n_done << " lattices, failed for " << n_fail;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
  return 0;
}
