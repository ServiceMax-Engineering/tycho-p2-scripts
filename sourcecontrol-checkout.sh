#!/bin/bash -e
# ========================================================================
# Copyright (c) 2006-2010 Intalio Inc
# ------------------------------------------------------------------------
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# and Apache License v2.0 which accompanies this distribution.
# The Eclipse Public License is available at 
# http://www.eclipse.org/legal/epl-v10.html
# The Apache License v2.0 is available at
# http://www.opensource.org/licenses/apache2.0.php
# You may elect to redistribute this code under either of these licenses. 
# ========================================================================
# Author hmalphettes
#
# Simplisitic checkout script for git.
# Jenkins/Hudson does not support parameterized git repo's URL.
# Using this script is a simple way to workaround that.
# 
# If the environemnt variable GIT_CLONE_REPO_URL is not defined, then nothing happens.
#
# Execute a git checkout if .git is present and no branch is checked out.
#
#load the environment constants
# Absolute path to this script.

SCRIPT=$(readlink -f $0)
# Absolute path this script is in.
SCRIPTPATH=`dirname $SCRIPT`
[ -z "$RELEASE_ENV" ] && RELEASE_ENV=$SCRIPTPATH/default_env
[ -f "$RELEASE_ENV" ] && . $RELEASE_ENV

WORKSPACE_FOLDER=`pwd`

if [ -n "$GIT_CLONE_REPO_URL" ]; then
  if [ -d ".git" ]; then
    #let make sure the origin is the same than the current .git
    #if it is different, let's wipe-out the workspace.
    git_origin_url=`git remote -v | grep origin | head -1 | sed 's/^origin[[:space:]]//g' | sed 's/[[:space:]](fetch)$//'`
    if [ "$git_origin_url" != "$GIT_CLONE_REPO_URL" ]; then
      echo "Wiping out the workspace as the current git repo: $git_origin_url is not identical to the one defined GIT_CLONE_REPO_URL=$GIT_CLONE_REPO_URL"
      rm -rf * .??*
    fi
  fi

  if [ ! -d ".git" ]; then
    #Maybe the checkout was not done.
    #let's make sure that this folder is actually empty.
    if [ "$(ls -A $WORKSPACE_FOLDER)" ]; then
      echo "Can't clone a git repo into a directory that is not empty: $WORKSPACE_FOLDER"
      echo "Please delete the workspace first if that is not what is wanted."
      exit 120
    fi
    [ -n "$GIT_BRANCH" ] && git_branch_arg=" --branch $GIT_BRANCH"
    [ -n "$GIT_CLONE_DEPTH" ] && git_depth_arg=" --depth $GIT_CLONE_DEPTH"
    echo "git clone ${GIT_CLONE_REPO_URL}${git_branch_arg}${git_depth_arg} ${WORKSPACE_FOLDER}"
    git clone ${GIT_CLONE_REPO_URL}${git_branch_arg}${git_depth_arg} ${WORKSPACE_FOLDER}
  fi
fi

if [ -z "$NO_SOURCE_CONTROL_UPDATES" ]; then
  if [ -d ".git" ]; then
    if [ -z "$GIT_BRANCH" ]; then
      #trust the hudson job to have checked out the proper branch:
      GIT_BRANCH=`git branch | sed '/^\* /!d' | head -1 | sed 's/^\* //'`
      if [ -z "$GIT_BRANCH" ]; then
        echo "ERROR: Not able to read the current branch: no branch checked out and no GIT_BRANCH constant defined here "`pwd`
        echo "git branch"
        echo `git branch`
        exit 127
      fi
    fi
    git checkout $GIT_BRANCH
    git reset --hard
    git pull origin $GIT_BRANCH
  elif [ -d ".svn" ]; then
    svn up
  fi
fi

