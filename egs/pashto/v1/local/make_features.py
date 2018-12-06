#!/usr/bin/env python3

# Author      2018  Martin Bulin (bulinmartin@gmail.com)
# Based on    ../../../cifar/v1/image/ocr/make_features.py
# Apache 2.0

""" This script converts images to Kaldi-format feature matrices. The input to
    this script is the path to a data directory, e.g. "data/train". This script
    reads the images listed in images.scp and writes them to standard output
    (by default) as Kaldi-formatted matrices (in text form).
"""

from argparse import ArgumentParser
from os.path import join as join_path, isfile
from scipy.misc import imread, imresize, imsave
from sys import stdout
import numpy as np

def parse_args():
    parser = ArgumentParser(description='Converts images into features of the standard format.')
    parser.add_argument('--images_orig_file', type=str,
                        help='path to images_orig.scp')
    parser.add_argument('--images_file', type=str,
                        help='path to images.scp')
    parser.add_argument('--allowed_lengths_file', type=str, default='data/local/allowed_lengths.txt',
                        help='path to allowed_lenghts.txt')
    parser.add_argument('--feat_dim', type=int, default=40,
                        help='height of the scaled images (feature dim)')
    parser.add_argument('--invert_colors', type=lambda x: (str(x).lower() == 'true'),
                        default=True,
                        help='invert colors of images (black text on white bg?)')
    parser.add_argument('--pad_pixels', type=int, default=4,
                        help='how many white pixels shall we pad the images?')
    parser.add_argument('--save_images', type=lambda x: (str(x).lower() == 'true'),
                        default=False,
                        help='save the scaled images into the eg\'s data dir?')
    parser.add_argument('--fliplr', type=lambda x: (str(x).lower()=='true'),
                        default=False,
                        help="flip the image left-right for right to left languages")
    parser.add_argument('--out_ark', type=str, default='',
                        help='output feature file; if not supplied, it goes to pipe')

    return parser.parse_args()

def scale_image(im):
    sy, sx = im.shape

    # Some images might be rotated
    if sy > sx:
        im = np.rot90(im, k=-1)
        sy, sx = im.shape

    scale_ratio = float(args.feat_dim)/sy
    return imresize(im, (int(args.feat_dim), int(scale_ratio*sx)))

def pad_image(im, base_pad_value, allowed_lengths_):
    im_len = im.shape[1]    # width
    allowed_len = 0
    for l in allowed_lengths_:
        if l > im_len+2*base_pad_value:
            allowed_len = l
            break

    if allowed_len == 0:
        return np.empty(0)     # image is too long

    padding = np.ones((args.feat_dim, (allowed_len-im_len)//2)) * 255
    return np.hstack((padding, im, padding))

def write_kaldi_matrix(file_handle, matrix, key, right_to_left=False):
    file_handle.write(key + " [ ")
    num_rows = len(matrix)
    if num_rows == 0:
        raise Exception('!! Matrix is empty')

    num_cols = len(matrix[0])
    # read bottom->up (from right to left) for r->l languages
    if right_to_left:
        rows = range(len(matrix)-1, -1, -1)
        stop_at = 0
    else:
        rows = range(len(matrix))
        stop_at = num_rows-1

    for row_index in rows:
        if num_cols != len(matrix[row_index]):
            raise Exception('!! All the rows of a matrix are expected to have the same length')
        file_handle.write(" ".join(map(lambda x: str(x), matrix[row_index])))
        if row_index != stop_at:
            file_handle.write("\n")

    file_handle.write(" ]\n")

if __name__ == '__main__':
    args = parse_args()
    if args.out_ark:
        out_fh = open(args.out_ark, 'wb')
    else:
        out_fh = stdout  # -> pipe

    if isfile(args.allowed_lengths_file):
        allowed_lengths = []
        with open(args.allowed_lengths_file, 'r') as f:
            for line in f:
                allowed_lengths.append(int(line.strip()))

    if args.save_images:
        new_paths = dict()
        with open(args.images_file, 'r') as f:
            for line in f:
                im_id, new_path = line.strip().split()
                new_paths[im_id] = new_path

    with open(args.images_orig_file) as f:
        for line in f:
            image_id, image_path = line.strip().split()
            im = imread(image_path, flatten=True)

            im = scale_image(im)

            if args.invert_colors:
                im = 255-im

            im = pad_image(im, args.pad_pixels, allowed_lengths)
            if im.size == 0:
                continue

            if args.save_images:
                imsave(new_paths[image_id], im)

            data = np.transpose(im, (1, 0))
            data = np.divide(data, 255.)
            write_kaldi_matrix(out_fh, matrix=data, key=image_id,
                               right_to_left=args.fliplr)
