#!/bin/sh
#export site_url=$HOME/p2repo/com/intalio/cloud/all/3.1.1.408
export site_url=http://release.intalio.com/p2repo/com/intalio/cloud/core/master/current
export destination=$HOME/tmp_p2_try
mkdir -p $HOME/tmp_p2_try
#export P2_DIRECTOR_HOME=$HOME/tools/p2director-20101010
./mirror.sh
