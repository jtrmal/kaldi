#!/usr/bin/env python3

# Author      2018  Martin Bulin (bulinmartin@gmail.com)
# Apache 2.0

# Take the pashto original (large .bmp) images and the (.xml) annotations
# and extract the isolated words (starting on page 11)
# Sorted by words (not by speakers), as it originally was

from argparse import ArgumentParser
import xml.etree.ElementTree
from glob import glob
from os import makedirs
from os.path import join as join_path, exists
from codecs import open as cod_open
from scipy.misc import imread, imsave
from sys import stdout

def parse_args():
    parser = ArgumentParser(description='Extracts isolated words from database.')
    parser.add_argument('--database_dir', type=str, 
                        help='where the original database is located')
    parser.add_argument('--corpus_dir', type=str, 
                        help='where to extract the corpus')
    parser.add_argument('--set_id', type=str, choices=['us', 'af'],
                        help='ID of a set to extract [us|af]')

    return parser.parse_args()

if __name__ == '__main__':

    args = parse_args()
    sid = args.set_id
    set_folder = {'us': 'US_Final', 'af': 'Afghanistan'}
    doc_nb_pos = {'us': 2, 'af': 1}     # slightly different formatting us/af

    trs_dir = join_path(args.corpus_dir, set_folder[sid], 'extractedWords', 'transcriptions')
    words_dir = join_path(args.corpus_dir, set_folder[sid], 'extractedWords', 'words')
    try:
        makedirs(trs_dir)
        makedirs(words_dir)
    except FileExistsError:
        print('E: Corpus dir exists but is not complete. Remove it safely and try again.')
        exit(1)
    
    source_data_dir = join_path(args.database_dir, set_folder[sid])
    words_list_file = join_path(args.database_dir, 'words.lst')

    sorted_words = dict()
    with cod_open(words_list_file, 'r', encoding='utf-8') as f:
        for l_m1, line in enumerate(f):
            word = line.rstrip()

            # one word might appear more times (several positions)
            if word not in sorted_words.keys():
                sorted_words[word] = [l_m1+1]
            else:
                sorted_words[word].append(l_m1+1)

    print('Got the list of words.\nExtracting from '+source_data_dir)

    for spk_dir_path in sorted(glob(join_path(source_data_dir, '*'))):
        dirname = spk_dir_path.split('/')[-1]
        spk_id = dirname.split('_')[0]

        print('Processing speaker', spk_id)
        stdout.flush()
        
        for xml_file_path in sorted(glob(join_path(spk_dir_path, '*.xml'))):
            filename = xml_file_path.split('/')[-1]
            if sid == 'us' and 'final' not in filename:
                continue

            try:
                doc_nb = filename.split('_')[doc_nb_pos[sid]][:3]
            except IndexError:
                print('W: Skipping bad xml file: '+filename)
                continue

            try:
                if int(doc_nb) < 11:
                    continue        # separated words starts on page 11
            except ValueError:
                print('W: Skipping bad xml file: '+filename)
                continue

            tree_root = xml.etree.ElementTree.parse(xml_file_path).getroot()
            ns = tree_root.tag.split('}')[0]+'}'     # namespace stamp

            doc = tree_root.find(ns+'DL_DOCUMENT')
            page_src = doc.attrib['src']
            try:
                im_page = imread(join_path(spk_dir_path, page_src), flatten=True)
            except FileNotFoundError:
                try:
                    if sid == 'us':
                        page_src = 'final_'+page_src    # us5: bug in the xml
                    else:
                        page_src = page_src.replace('.jpg', '.bmp') # bugs in some af xml files

                    im_page = imread(join_path(spk_dir_path, page_src), flatten=True)
                except FileNotFoundError:
                    print('W: File '+page_src+' not found. Skipping.')
                    continue

            for page in doc.findall(ns+'DL_PAGE'):
                zones = page.findall(ns+'DL_ZONE')
                for zone in zones:
                    try:
                        trs = zone.attrib['contents']
                        r = int(zone.attrib['row'])
                        w = int(zone.attrib['width'])
                        c = int(zone.attrib['col'])
                        h = int(zone.attrib['height'])
                    except KeyError:
                        print('W: Skipping zone (missing info).')
                        continue

                    if trs in sorted_words.keys():
                        for word_nb in sorted_words[trs]:
                            trs_filename = str(word_nb)+'.txt'
                            trs_file_path = join_path(trs_dir, trs_filename)
                            
                            if sid == 'us':
                                stamp = 'final_'+spk_id+'_'+doc_nb+'-'+str(word_nb)
                            else:
                                stamp = spk_id+'_'+doc_nb+'-'+str(word_nb)

                            with cod_open(trs_file_path, 'a', encoding='utf-8') as f:
                                f.write('<s> '+trs+' </s> ('+stamp+')\n')

                            word_dir_path = join_path(words_dir, str(word_nb))
                            if not exists(word_dir_path):
                                makedirs(join_path(word_dir_path))

                            im_filename = stamp+'.bmp'
                            im_file_path = join_path(word_dir_path, im_filename)
                            
                            # crop and invert to white-on-black as originally was
                            im_word = 255-im_page[r:r+h, c:c+w]  
                            imsave(im_file_path, im_word)
                    else:
                        print('W: Word '+trs+' is not in the word list.')
