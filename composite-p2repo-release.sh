#!/bin/sh -e
# Calls the generation of the composite repo
# Get the built version number of the composite repo
# Update the version number of the Buildfile for the deb package
# Calls the buildr package and deployment script

SCRIPT=$(readlink -f $0)
# Absolute path this script is in.
SCRIPTPATH=`dirname $SCRIPT`
#load the env
[ -z "$RELEASE_ENV" ] && RELEASE_ENV=$SCRIPTPATH/default_env
[ -f "$RELEASE_ENV" ] && . $RELEASE_ENV

if [ -n "$SUB_DIRECTORY" ]; then
  cd "$SUB_DIRECTORY"
fi

generate_composite_repo_path=$SCRIPTPATH/composite-p2repo/generate_composite_repo.rb
cmd="$generate_composite_repo_path --name all --basefolder $HOME/p2repo/com/intalio/cloud/ --output $HOME/p2repo/com/intalio/cloud/all --otherurls=otherurls_for_composite_repo.txt"
echo "Executing $cmd"
$cmd

#make sure the Buildfile will be committed
commit_Buildfile=true

if [ -n "$SUB_DIRECTORY" ]; then
  cd ..
fi

buildrdeb_release_path=$SCRIPTPATH/buildrdeb-release.sh
echo "Executing $buildrdeb_release_path"
$buildrdeb_release_path
