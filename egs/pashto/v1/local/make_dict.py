#!/usr/bin/env python3

# Author      2018  Martin Bulin (bulinmartin@gmail.com)
# Apache 2.0

"""
    Creates the dict files.

    data/local/dict/lexicon.txt
    data/local/dict/nonsilence_phones.txt
    data/local/dict/silence_phones.txt
    data/local/dict/optional_silence.txt
    data/local/dict/extra_questions.txt
"""

from argparse import ArgumentParser
from codecs import open as cod_open


def parse_args():
    parser = ArgumentParser(description='Creates data/local/dict files.')
    parser.add_argument('--corpus_file', type=str, default='data/local/corpus.txt',
                        help='path to the corpus file with all transcriptions')
    parser.add_argument('--dict_dir', type=str, default='data/local/dict',
                        help='dir place the dict files at')
    parser.add_argument('--oov_word', type=str, default='<UNK>',
                        help='unknown (out-of-vocabulary) word')
    parser.add_argument('--use_bpe', type=lambda x: (str(x).lower() == 'true'),
                        default=False, help='is BPE used?')
    return parser.parse_args()

if __name__ == '__main__':
    args = parse_args()

    all_words = list()
    with cod_open(args.corpus_file, 'r', encoding='utf-8') as f:
        for line in f.readlines():
            for word in line.strip().split():
                all_words.append(word)

    all_words_unique = list(set(all_words))

    # lexicon.txt
    f_lexicon = cod_open(args.dict_dir+'/lexicon.txt', 'w+', encoding='utf-8')
    for word in sorted(all_words_unique):
        if args.use_bpe:
            word_aer = ' '.join(['SIL' if ph == '|' else ph for ph in word])
        else:
            word_aer = ' '.join(word)

        f_lexicon.write(word+' '+word_aer+'\n')

    f_lexicon.write('!SIL SIL\n')
    f_lexicon.write(args.oov_word+' SPN\n')
    f_lexicon.close()

    # nonsilence_phones.txt, silence_phones.txt,
    # nonsilence_phones.txt and extra_questions.txt
    unique_chars = list(set([ch for word in all_words_unique for ch in word]))

    with cod_open(args.dict_dir+'/nonsilence_phones.txt', 'w', encoding='utf-8') as f:
        for ch in sorted(unique_chars):
            f.write(ch+'\n')

    with cod_open(args.dict_dir+'/silence_phones.txt', 'w', encoding='utf-8') as f:
        f.write('SIL\n')
        f.write('SPN\n')

    with cod_open(args.dict_dir+'/optional_silence.txt', 'w', encoding='utf-8') as f:
        f.write('SIL\n')

    open(args.dict_dir+'/extra_questions.txt', 'a').close()
