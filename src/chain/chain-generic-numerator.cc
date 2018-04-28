// chain/chain-generic-numerator.cc

// Copyright      2017   Hossein Hadian

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


#include "chain/chain-generic-numerator.h"
#include "chain/chain-kernels-ansi.h"

#include <iterator>

namespace kaldi {
namespace chain {

// GenericNumeratorComputation is responsible for the forward-backward of the
// end-to-end 'supervision' (numerator) FST. It is used in chain-training.cc
// (similar to NumeratorComputation) to compute the numerator derivatives
// for end-to-end training 'supervision's.

GenericNumeratorComputation::GenericNumeratorComputation(
    const Supervision &supervision,
    const CuMatrixBase<BaseFloat> &nnet_output):
    supervision_(supervision),
    nnet_output_x_(nnet_output),
    tot_prob_(supervision.num_sequences, kUndefined),
    ok_(true) {
  KALDI_ASSERT(supervision.num_sequences *
               supervision.frames_per_sequence == nnet_output.NumRows() &&
               supervision.label_dim == nnet_output.NumCols());

  using std::vector;
  int32 B = supervision_.num_sequences;
  KALDI_ASSERT(supervision_.e2e_fsts.size() == B);

  alpha_.resize(B);
  beta_.resize(B);
  probs_.resize(B);
  nnet_output_deriv_.resize(B);

  // Find the maximum number of HMM states and then
  // initialize final probs, alpha, and beta.
  int max_num_hmm_states = 0;
  for (int32 i = 0; i < B; i++) {
    KALDI_ASSERT(supervision_.e2e_fsts[i].Properties(fst::kIEpsilons, true)
                 == 0);
    if (supervision_.e2e_fsts[i].NumStates() > max_num_hmm_states)
      max_num_hmm_states = supervision_.e2e_fsts[i].NumStates();
  }
  final_probs_.Resize(B, max_num_hmm_states);

  // Initialize incoming transitions for easy access
  in_transitions_.resize(B); // indexed by seq, state
  out_transitions_.resize(B); // indexed by seq, state
  for (int32 seq = 0; seq < B; seq++) {
    in_transitions_[seq] = vector<vector<DenominatorGraphTransition> >(
        supervision_.e2e_fsts[seq].NumStates());
    out_transitions_[seq] = vector<vector<DenominatorGraphTransition> >(
        supervision_.e2e_fsts[seq].NumStates());
  }

  offsets_.Resize(B);
  for (int32 seq = 0; seq < B; seq++) {
    std::vector<MatrixIndexT> index_to_pdf;
    std::unordered_map<int, MatrixIndexT> pdf_to_index;
    for (int32 s = 0; s < supervision_.e2e_fsts[seq].NumStates(); s++) {
      final_probs_(seq, s)= -supervision_.e2e_fsts[seq].Final(s).Value();
      BaseFloat offset = 0.0;
      if (s == 0) {
        for (fst::ArcIterator<fst::StdVectorFst> aiter(
                 supervision_.e2e_fsts[seq], s);
             !aiter.Done();
             aiter.Next())
          if (aiter.Value().weight.Value() > offset)
            offset = aiter.Value().weight.Value();
        offsets_(seq) = offset;
      }

      for (fst::ArcIterator<fst::StdVectorFst> aiter(
             supervision_.e2e_fsts[seq], s);
           !aiter.Done();
           aiter.Next()) {
        const fst::StdArc &arc = aiter.Value();
        DenominatorGraphTransition transition;
        transition.transition_prob = -(arc.weight.Value() - offset);
        int pdf_id = arc.ilabel - 1;
        if (pdf_to_index.find(pdf_id) == pdf_to_index.end()) {
          index_to_pdf.push_back(pdf_id);
          pdf_to_index[pdf_id] = index_to_pdf.size() - 1;
        }

        transition.pdf_id = pdf_to_index[pdf_id];
        transition.hmm_state = s;
        in_transitions_[seq][arc.nextstate].push_back(transition);
        transition.hmm_state = arc.nextstate;
        out_transitions_[seq][s].push_back(transition);
      }
    }
    index_to_pdf_.push_back(index_to_pdf);
    KALDI_ASSERT(index_to_pdf_.size() == (seq + 1));
  }
}


void GenericNumeratorComputation::AlphaFirstFrame(int seq) {
  const int32 num_frames = supervision_.frames_per_sequence,
      num_states = supervision_.e2e_fsts[seq].NumStates();
  // Set alpha_0(0) for all sequences to 1.0 and leave the rest to be 0.0.
  alpha_[seq].Resize(num_frames + 1,  num_states + 1, kSetZero);
  alpha_[seq].Set(-std::numeric_limits<BaseFloat>::infinity());
  alpha_[seq](0, 0) = 0.0;
  alpha_[seq](0, num_states) = 0.0;
  //SubMatrix<double> alpha_hmm_state0(alpha_, 0, 1, 0, num_states + 1) ;
  //alpha_hmm_state0.Set(0.0);
}


void GenericNumeratorComputation::CopySpecificPdfsProbs(int sequence_id,
                                                        int num_sequences,
                                                        int frames_per_sequence,
                                                        int num_pdfs,
                                                        const std::vector<MatrixIndexT> &indices,
                                                        Matrix<BaseFloat> *out) {
  //BaseFloat *starting_ptr = const_cast<BaseFloat *>(nnet_output_.Data()) + sequence_id * nnet_output_.Stride();

  const BaseFloat *starting_ptr = nnet_output_x_.RowData(sequence_id);
  //const BaseFloat *starting_ptr = nnet_output_x_.Data() +
  //                                sequence_id * nnet_output_x_.Stride();
  int view_stride = num_sequences * nnet_output_x_.Stride();
  const CuSubMatrix<BaseFloat> sequence_view(starting_ptr,
                                             frames_per_sequence,
                                             num_pdfs,
                                             view_stride );

  std::vector<MatrixIndexT> indices_expanded(num_pdfs, -1);
  copy(indices.begin(), indices.end(), indices_expanded.begin());

  CuArray<MatrixIndexT> indices_gpu(indices_expanded);
  CuMatrix<BaseFloat> single_sequence(frames_per_sequence,
                                      sequence_view.NumCols());

  single_sequence.CopyCols(sequence_view, indices_gpu);
  CuSubMatrix<BaseFloat> sequence_pdfs_gpu(single_sequence,
                             0, single_sequence.NumRows(),
                             0, indices.size());

  //sequence_pdfs_gpu.ApplyExp();
  out->Resize(sequence_pdfs_gpu.NumCols(),
             sequence_pdfs_gpu.NumRows());
  out->CopyFromMat(sequence_pdfs_gpu, kTrans);
}

// The alpha computation for some 0 < t <= num_time_steps_.
BaseFloat GenericNumeratorComputation::AlphaGeneralFrame(int32 seq) {
  // Define some variables to make things nicer
  const int32
    num_sequences = supervision_.num_sequences,
    num_frames = supervision_.frames_per_sequence,
    num_pdfs = nnet_output_x_.NumCols();

  KALDI_ASSERT(seq >= 0 && seq < num_sequences);
  CopySpecificPdfsProbs(seq, num_sequences, num_frames, num_pdfs,
      index_to_pdf_[seq], &(probs_[seq]));

  SubMatrix<BaseFloat> alpha(alpha_[seq],
                          0, alpha_[seq].NumRows(),
                          0, alpha_[seq].NumCols());

  // variables for log_likelihood computation
  double log_scale_product = 0,
         log_prob_product = 0;

  for (int t = 1; t <= num_frames; ++t) {
    SubMatrix<BaseFloat> prev_alpha_t(alpha, t - 1, 1, 0, alpha_[seq].NumCols() - 1);
    SubMatrix<BaseFloat> this_alpha_t(alpha, t, 1, 0, alpha_[seq].NumCols() - 1);

    // for h == 0 the incoming transitions will be always an empty set
    for (int32 h = 0; h < supervision_.e2e_fsts[seq].NumStates(); h++) {
      for (auto tr = in_transitions_[seq][h].begin();
          tr != in_transitions_[seq][h].end(); tr++) {
        BaseFloat transition_prob = tr->transition_prob;
        //double exp_transition_prob = exp(transition_prob);
        int32 pdf_id = tr->pdf_id,
              prev_hmm_state = tr->hmm_state;
        BaseFloat prob = probs_[seq](pdf_id, t-1);
        //double exp_prob = exp(prob);
        //double this_alpha_val = alpha(t, h);
        //double exp_this_alpha_val = exp(this_alpha_val);
        //double prev_alpha_val = alpha(t-1, prev_hmm_state);
        //double exp_prev_alpha_val = exp(prev_alpha_val);
        alpha(t, h) = LogAdd(alpha(t, h),
            alpha(t-1, prev_hmm_state) + transition_prob + prob);
        //double this_alpha_val2 = alpha(t, h);
        //double exp_this_alpha_val2 = exp(this_alpha_val2);
        //int this_pdf_id = index_to_pdf_[seq][pdf_id];
        //double fake = 5;
      }
    }
    double norm = alpha(t-1, alpha.NumCols() - 1);
    //KALDI_LOG << norm;
    //KALDI_LOG << this_alpha_t << std::endl;
    this_alpha_t.Add(-norm);
    double sum = this_alpha_t.LogSumExp();
    alpha(t, alpha.NumCols() - 1) = sum;
    log_scale_product += sum;
    //KALDI_LOG << this_alpha_t << std::endl;

    // for debug
    //alpha.CopyFromMat(alpha_);
    //alpha.ApplyExp();
    //KALDI_LOG << alpha << std::endl;
  }
  SubMatrix<BaseFloat> last_alpha(alpha, alpha.NumRows() - 1, 1,
                                       0, alpha.NumCols() - 1);
  SubVector<BaseFloat> final_probs(final_probs_.RowData(seq),
                                alpha.NumCols() - 1);

  // adjust last_alpha
  double sum = alpha(alpha.NumRows() - 1, alpha.NumCols() - 1);
  log_scale_product -= sum;
  last_alpha.AddVecToRows(1.0, final_probs);
  sum = last_alpha.LogSumExp();
  alpha(alpha.NumRows() - 1, alpha.NumCols() - 1) = sum;
  tot_prob_(seq) = sum;

  // second part of criterion
  log_prob_product = sum - offsets_(seq);

  return log_prob_product + log_scale_product;
}

BaseFloat GenericNumeratorComputation::Forward() {
  BaseFloat total_loglike = 0;
  const int32 num_sequences = supervision_.num_sequences;
  for (int seq = 0; seq < num_sequences; ++seq) {
    AlphaFirstFrame(seq);
    total_loglike += AlphaGeneralFrame(seq);
  }
  KALDI_LOG <<  "total_loglike: " << total_loglike;
  return total_loglike;
}


bool GenericNumeratorComputation::Backward(
    CuMatrixBase<BaseFloat> *nnet_output_deriv) {

  const int32 num_sequences = supervision_.num_sequences;

  for (int seq = 0; seq < num_sequences; ++seq) {
    BetaLastFrame(seq);
    BetaGeneralFrame(seq);
    CopyLogProbIndirect(seq, nnet_output_deriv_[seq],
                        index_to_pdf_[seq], nnet_output_deriv);
  }
  return ok_;
}

void GenericNumeratorComputation::BetaLastFrame(int seq) {
  // Sets up the beta quantity on the last frame (frame ==
  // frames_per_sequence_).  Note that the betas we use here contain a
  // 1/(tot-prob) factor in order to simplify the backprop.
  const int32 num_frames = supervision_.frames_per_sequence,
      num_states = supervision_.e2e_fsts[seq].NumStates();

  beta_[seq].Resize(2, num_states);
  beta_[seq].Set(-std::numeric_limits<BaseFloat>::infinity());

  int num_pdfs = probs_[seq].NumRows();
  nnet_output_deriv_[seq].Resize(num_frames, num_pdfs, kSetZero);
  nnet_output_deriv_[seq].Set(-std::numeric_limits<BaseFloat>::infinity());

  SubVector<BaseFloat> beta_mat(beta_[seq].RowData(num_frames % 2), num_states);
  SubVector<BaseFloat> final_probs(final_probs_.RowData(seq), num_states);

  BaseFloat inv_tot_prob = -tot_prob_(seq);
  beta_mat.Set(inv_tot_prob);
  //KALDI_LOG << beta_mat;
  beta_mat.AddVec(1.0, final_probs);
  //KALDI_LOG << beta_mat;
}

void GenericNumeratorComputation::BetaGeneralFrame(int32 seq) {
  const int32
      num_sequences = supervision_.num_sequences,
      num_frames = supervision_.frames_per_sequence,
      num_states = supervision_.e2e_fsts[seq].NumStates();
  KALDI_ASSERT(seq >= 0 && seq < num_sequences);

  SubMatrix<BaseFloat> alpha(alpha_[seq],
                          0, alpha_[seq].NumRows(),
                          0, alpha_[seq].NumCols());

  SubMatrix<BaseFloat> log_prob_deriv(nnet_output_deriv_[seq],
                          0, nnet_output_deriv_[seq].NumRows(),
                          0, nnet_output_deriv_[seq].NumCols());
  log_prob_deriv.Set(-std::numeric_limits<BaseFloat>::infinity());

  //KALDI_LOG << alpha_[seq] << std::endl;

  //KALDI_LOG << beta_[seq] << std::endl;
  for (int t = num_frames - 1; t >= 0; --t) {
    SubVector<BaseFloat> this_beta(beta_[seq].RowData(t % 2), num_states);
    const SubVector<BaseFloat> next_beta(beta_[seq].RowData((t + 1) % 2), num_states);

    BaseFloat inv_arbitrary_scale = alpha(t, num_states);
    //KALDI_LOG << inv_arbitrary_scale << std::endl;
    //std::unordered_map<int, double> derivs;

    for (int32 h = 0; h < supervision_.e2e_fsts[seq].NumStates(); h++) {
      BaseFloat tot_variable_factor = -std::numeric_limits<BaseFloat>::infinity();
      for (auto tr = out_transitions_[seq][h].begin();
               tr != out_transitions_[seq][h].end(); tr++) {
        BaseFloat transition_prob = tr->transition_prob;
        int32 pdf_id = tr->pdf_id,
            next_hmm_state = tr->hmm_state;
        BaseFloat variable_factor = transition_prob +
            next_beta(next_hmm_state) +
            probs_[seq](pdf_id, t) - inv_arbitrary_scale;
        tot_variable_factor = LogAdd(tot_variable_factor,
                                     variable_factor);

        BaseFloat occupation_prob = variable_factor + alpha(t, h);
        log_prob_deriv(t, pdf_id) = LogAdd(log_prob_deriv(t, pdf_id),
                                           occupation_prob);
        //if ((seq == 0) && (std::isfinite(log_prob_deriv(t, pdf_id)))) {
        //  derivs[pdf_id] = log_prob_deriv(t, pdf_id);
        //}
      }
      this_beta(h) = tot_variable_factor;
    }
    //if (seq == 0) {
    //  KALDI_LOG << "Derivs in t = " << t << std::endl;
    //  std::stringstream s;
    //  for (auto x : derivs) {
    //    s << (index_to_pdf_[seq][x.first]) << " : " << (x.second) << ", ";
    //  }
    //  KALDI_LOG << s.str();
    //}
    //KALDI_LOG << beta_[seq] << std::endl;
  }
}


void GenericNumeratorComputation::CopyLogProbIndirect(int sequence_id,
                                 Matrix<BaseFloat> &logprobs,
                                 std::vector<MatrixIndexT> &indices,
                                 CuMatrixBase<BaseFloat> *output) {

  int num_sequences = supervision_.num_sequences;
  int frames_per_sequence = supervision_.frames_per_sequence;
  int num_pdfs = nnet_output_x_.NumCols();

  BaseFloat *starting_ptr = output->RowData(sequence_id);
  int view_stride = output->Stride() * num_sequences;

  KALDI_ASSERT(output->NumCols() == nnet_output_x_.NumCols());
  KALDI_ASSERT(frames_per_sequence * supervision_.num_sequences == output->NumRows());

  CuMatrix<BaseFloat> specific_pdfs(nnet_output_deriv_[sequence_id]);
  specific_pdfs.ApplyExp();

  std::vector<MatrixIndexT> indices_expanded(num_pdfs, -1);
  for (int i = 0; i < indices.size(); ++i) {
    int pdf_index = indices[i];
    KALDI_ASSERT(pdf_index < num_pdfs);
    KALDI_ASSERT(i < specific_pdfs.NumCols());
    indices_expanded[pdf_index] = i;
  }

  CuArray<MatrixIndexT> cu_indices(indices_expanded);
  //CuSubMatrix<BaseFloat> out(*output, sequence_id * frames_per_sequence,
  //                           frames_per_sequence, 0, num_pdfs);
  CuSubMatrix<BaseFloat> out(starting_ptr, frames_per_sequence,
                             num_pdfs, view_stride);
  CuMatrix<BaseFloat> tmp(frames_per_sequence, num_pdfs);
  KALDI_ASSERT(specific_pdfs.NumRows() == out.NumRows());

  // CopyCols also relies on the fact that we do not work in log domain anymore
  // because CopyCols zeroes all columns for which it has -1 in the cu_indices
  tmp.CopyCols(specific_pdfs, cu_indices);
  out.AddMat(supervision_.weight, tmp, kNoTrans);
  //Matrix<BaseFloat> mem(out);
  //KALDI_LOG << mem
  //KALDI_LOG << mem(0,0);
  //KALDI_ASSERT(false);
}

// /home/jtrmal/.local/bin//gdb  --args nnet3-chain-train --use-gpu=yes --apply-deriv-weights=False --l2-regularize=5e-05 --leaky-hmm-coefficient=0.1 --xent-regularize=0.0 --print-interval=10 --momentum=0.0 --max-param-change=2.0 --backstitch-training-scale=0.0 --backstitch-training-interval=1 --l2-regularize-factor=0.5 --srand=2 'nnet3-am-copy --raw=true --learning-rate=0.00173192864672 --scale=1.0 2.mdl - |' den.fst ark,bg:egs 3.2.x.raw
//
void GenericNumeratorComputation::BetaGeneralFrameDebug(int32 t) {
  // int32 alpha_beta_size = final_probs_.NumRows() * supervision_.num_sequences;
  // SubVector<double> this_alpha(alpha_.RowData(t), alpha_beta_size),
  //     this_beta(beta_.RowData(t % 2), alpha_beta_size);
  // int32 t_wrapped = t % static_cast<int32>(kMaxDerivTimeSteps),
  //       num_pdfs = exp_nnet_output_transposed_.NumRows();
  // SubMatrix<BaseFloat> this_log_prob_deriv(
  //     nnet_output_deriv_transposed_, 0, num_pdfs,
  //     t_wrapped * supervision_.num_sequences, supervision_.num_sequences);
  // double alpha_beta_product = VecVec(this_alpha,
  //                                    this_beta),
  //     this_log_prob_deriv_sum = this_log_prob_deriv.Sum();
  // if (!ApproxEqual(alpha_beta_product, supervision_.num_sequences)) {
  //   KALDI_WARN << "On time " << t << ", alpha-beta product "
  //              << alpha_beta_product << " != " << supervision_.num_sequences
  //              << " alpha-sum = " << this_alpha.Sum()
  //              << ", beta-sum = " << this_beta.Sum();
  //   if (fabs(alpha_beta_product - supervision_.num_sequences) > 2.0
  //       || alpha_beta_product - alpha_beta_product != 0) {
  //     KALDI_WARN << "Excessive error detected, will abandon this minibatch";
  //     ok_ = false;
  //   }
  // }
  // // Use higher tolerance, since we are using randomized pruning for the
  // // log-prob derivatives.
  // if (!ApproxEqual(this_log_prob_deriv_sum,
  //                  supervision_.num_sequences, 0.01)) {
  //   KALDI_WARN << "On time " << t << ", log-prob-deriv sum "
  //              << this_log_prob_deriv_sum << " != "
  //              << supervision_.num_sequences;
  //   if (fabs(this_log_prob_deriv_sum - supervision_.num_sequences) > 2.0 ||
  //       this_log_prob_deriv_sum - this_log_prob_deriv_sum != 0) {
  //     KALDI_WARN << "Excessive error detected, will abandon this minibatch";
  //     ok_ = false;
  //   }
  // }
}

}  // namespace chain
}  // namespace kaldi
