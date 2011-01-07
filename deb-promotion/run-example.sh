#!/bin/sh
site_url=$HOME/p2repo/com/intalio/cloud/all/3.1.1.345
destination=$HOME/tmp_p2_try
mkdir -p $HOME/tmp_p2_try
P2_DIRECTOR_HOME=$HOME/tools/p2director-20101010
export site_url
export destination
./mirror.sh
