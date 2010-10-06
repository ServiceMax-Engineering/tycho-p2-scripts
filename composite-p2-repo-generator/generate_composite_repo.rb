#!/usr/bin/env ruby
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
# This script generates a p2 composite repository:
# http://wiki.eclipse.org/Equinox/p2/Composite_Repositories_(new)
#
# This script traverses the sub-directories recursively and looks for the
# folders that contain $NAME_OF_COMPOSITE_REPO.composite.mkrepo.properties
# when it finds one, it expects to find version numbers as the folders
# It looks by default for the latest version and adds the corresponding
# to the composite repository.

require "find"
require "erb"

class CompositeRepository
  def initialize(output, basefolder, name)
    @output = output
    @basefolder = basefolder
    @name = name

    @children_repo = [ ]
    @ArtifactOrMetadata="Artifact"
    @timestamp=Time.now.to_i
    
  end

  def add_childrepo( compositeMkrepoFile )
    @children_repo << compositeMkrepoFile
  end
 # Support templating of member data.
  def get_binding
    binding
  end
  
  def set_ArtifactOrMetaData(artifactOrMetadata)
    @ArtifactOrMetadata=artifactOrMetadata
  end
  
end

require "rubygems"
require "getopt/long"
opt = Getopt::Long.getopts(
  ["--basefolder", "-b", Getopt::REQUIRED],
  ["--output", "-o", Getopt::REQUIRED],
  ["--name", "-n", Getopt::OPTIONAL]
)

basefolder="."
if opt["basefolder"]
  basefolder=opt["basefolder"]
end
name="all"
if opt["name"]
  name=opt["name"]
end
if opt["output"]
  output=opt["output"]
else
  #look for the all folder and use this as the directory.
end

compositeRepository=CompositeRepository.new output, basefolder, name

Find.find(basefolder) do |path|
  if FileTest.directory?(path)
    if File.basename(path)[0] == ?. and File.basename(path) != '.'
      Find.prune
    elsif File.basename(path) == 'plugins' or File.basename(path) == 'features' or File.basename(path) == 'binaries' or File.basename(path) == name
      Find.prune
    else
      next
    end
  else
    if File.basename(path) == "#{name}.composite.mkrepo"
      compositeRepository.add_childrepo path
    end
  end
end

template=ERB.new File.new("composite.xml.rhtml").read, nil, "%"
res=template.result(compositeRepository.get_binding)
puts res
compositeRepository.set_ArtifactOrMetaData "Metadata"
res=template.result(compositeRepository.get_binding)
puts res