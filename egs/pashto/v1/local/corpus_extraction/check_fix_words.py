#!/usr/bin/env python3

# Author      2018  Martin Bulin (bulinmartin@gmail.com)
# Apache 2.0

# Check if every transcription have an image
# Check for duplicate transcription lines in one file
# Fix all found defects.

from argparse import ArgumentParser
from glob import glob
from codecs import open as cod_open
from os.path import join as join_path, exists
from sys import stdout

def parse_args():
    parser = ArgumentParser(description='Extracts isolated words from database.')
    parser.add_argument('--corpus_dir', type=str, 
                        help='Where to extract the corpus')
    parser.add_argument('--set_id', type=str, choices=['us', 'af'],
                        help='ID of a set to extract [us|af]')
    parser.add_argument('--fix', type=lambda x: (str(x).lower() == 'true'),
                        default=False,
                        help='Fix the defects? Or just check and report?')

    return parser.parse_args()

if __name__ == '__main__':
    args = parse_args()
    sid = args.set_id
    set_folder = {'us': 'US_Final', 'af': 'Afghanistan'}
    
    # if the number of OK samples is lower => exit(1)
    set_limit = {'us': 10000, 'af': 400000}

    trs_dir = join_path(args.corpus_dir, set_folder[sid], 'extractedWords', 'transcriptions')
    words_dir = join_path(args.corpus_dir, set_folder[sid], 'extractedWords', 'words')

    print('Checking the '+set_folder[sid]+' set.')
    stats = {'ok': 0, 'no_image': 0, 'duplicate_trs': 0}
    for file_i, txt_file_path in enumerate(sorted(glob(join_path(trs_dir, '*.txt')))):
        filename = txt_file_path.split('/')[-1]
        word_nb = filename.strip('.txt')

        with cod_open(txt_file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        checked_lines = list()
        for line in lines:
            im_name = line[line.find('(')+1:line.find(')')]+'.bmp'
            if exists(join_path(words_dir, word_nb, im_name)):
                if line not in checked_lines:
                    checked_lines.append(line)
                    stats['ok'] += 1
                else:
                    print('W: DUP in '+filename+': '+line)
                    stats['duplicate_trs'] += 1
            else:
                print('W: MISSING IMAGE: '+im_name)
                stats['no_image'] += 1

        if args.fix:
            with cod_open(txt_file_path, 'w', encoding='utf-8') as f:
                for line in checked_lines:
                    f.write(line)
            
        if (file_i+1) % 20 == 0:
            print('Checked '+str(file_i+1)+' files.')
            stdout.flush()

    print('Check stats:\n\t'+str(stats['ok'])+' OK samples')
    print('\t'+str(stats['no_image'])+' transcriptions with no corresponding image')
    print('\t'+str(stats['duplicate_trs'])+' transcription duplicates')

    if stats['ok'] < set_limit[sid]:
        print('E: Too few OK. Something is wrong. You should consider corpus re-extracting.')
        exit(1)

    if args.fix:
        print('\nAll defects fixed.')

    print('\nSet '+set_folder[sid]+' is checked and ready to be used.\n')
