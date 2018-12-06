#### Pashto OCR

This is a Kaldi recipe for the Pashto OCR data - a handwritten text in Arabic (or "Pashto" -  one of the two official languages of Afghanistan). At the moment limited to single isolated words.

##### Database size
The database consists of 1862 different words and two sets of authors (speakers in Kaldi-ASR):
1. US: 12 authors, 13K samples
2. AF: 370 authors, 420K samples


##### Default experimental setting
* training set: 350 AF authors (398K samples)
* evaluation set: 20 AF authors (22K samples)

##### Baseline results

| Model   | %WER |                                                 |
| --------|:----:|:------------------------------------------------|
| mono    |115.93| [ 26244 / 22637, 9057 ins, 103 del, 17084 sub ] |
| tri     | 65.19| [ 14758 / 22637, 3875 ins, 108 del, 10775 sub ] |
| tri2    | 32.61| [ 7383 / 22637, 1037 ins, 61 del, 6285 sub ]    |
| tri3    | 40.31| [ 9124 / 22637, 1556 ins, 88 del, 7480 sub ]    |
| tri2 nn |  6.32| [ 1431 / 22637, 3 ins, 13 del, 1415 sub ]       |
| tri3 nn |  6.52| [ 1476 / 22637, 3 ins, 12 del, 1461 sub ]       |
| e2e nn  |  4.56| [ 1033 / 22637, 1 ins, 10 del, 1022 sub ] |

* _mono_ : a simple monophone alignment
* _tri_ : _mono_ -> deltas
* _tri2_ : _tri_ -> LDA+MLLT
* _tri3_ : _tri2_ -> SAT+FMLLR
* _tri2 nn_ : _tri2_ -> 7CNN+3TDNN
* _tri3 nn_ : _tri3_ -> 7CNN+3TDNN
* _e2e nn_ : 7CNN+3TDNN with flat start (end2end system)
