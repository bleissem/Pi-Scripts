#!/bin/bash


PIDISTRO=xenial \
PIUSER=pi \
PIHOSTNAME=pi \
PIPACKAGES='ubuntu-mate-core '\
'ubuntu-mate-desktop '\
'language-pack-en language-pack-de '\
'language-pack-fr language-pack-es '\
'language-pack-pt' \
PISIZE=4000000000 PISWAP=500000000 \
PILANG=de_DE.UTF-8 \
PIXKBLAYOUT="de" \
bash pi-buntu-strap.sh
