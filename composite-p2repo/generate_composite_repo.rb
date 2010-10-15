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
# Sources published here: github.com/intalio/tycho-p2-scripts
#
# This script generates a p2 composite repository:
# http://wiki.eclipse.org/Equinox/p2/Composite_Repositories_(new)
#
# This script traverses the sub-directories recursively and looks for the
# folders that contain $NAME_OF_COMPOSITE_REPO.composite.mkrepo.properties
# when it finds one, it expects to find version numbers as the folders
# It looks by default for the latest version and adds the corresponding
# to the composite repository.
#
# Todo: ability to define the major versions numbers to build for each children repos
#

require "find"
require "erb"
require "pathname"
require "fileutils"

class CompositeRepository
  
  def initialize(output, version, basefolder, name, otherurls, test)
    @outputPath = Pathname.new(output).expand_path
    @basefolder = Pathname.new(basefolder).expand_path
    @name = name
    @version = version
    @test = test

    #contain the list of relative path to the linked versioned repos
    @children_repo = [ ]
    
    #contain the list of relative path to the linked versioned repos
    #according to the last released aggregate repository
    #we read it in the last released composite repo.
    #if nothing has changed then we don't need to make a new release.
    @currently_released_repo = []
    
    @ArtifactOrMetadata="Artifact"
    @timestamp=Time.now.to_i
    @date=Time.now.utc
    
    @versionned_output_dir=nil
    
    add_external_childrepos otherurls
    
    compute_versioned_output
  end

  def add_childrepo( compositeMkrepoFile )
    compositeRepoParentFolder=Pathname.new Pathname.new(File.dirname compositeMkrepoFile).expand_path
    #make it a path relative to the @versionned_output_dir
    relative=compositeRepoParentFolder.relative_path_from(Pathname.new(@versionned_output_dir))
    if relative.nil?
      raise "Could not compute the relative path of #{compositeMkrepoFile.to_s} from #{Pathname.new(@versionned_output_dir).to_s}"
    end
    last_version=compute_last_version compositeRepoParentFolder
    if last_version.nil?
      raise "Could not locate a version directory in #{compositeRepoParentFolder.to_s}"
    end
    relative=File.join(relative.to_s,last_version)
    @children_repo << relative
  end
  
  def add_external_childrepos(otherurls_file)
    if otherurls_file.nil?
      return
    end
    if ! File.exists?(otherurls_file)
      raise "The file #{otherurls_file} does not exist."
    end
    File.open(otherurls_file, "r") do |infile|
      while (line = infile.gets)
        if line.strip.size != 0 && ((line =~ /^#/) == nil)
          add_external_childrepo(eval("\"#{line.strip}\""))
        end
      end
    end
  end

  def add_external_childrepo(url)
    @children_repo << url
  end
  
  def get_versionned_output_dir()
    return @versionned_output_dir
  end
  def get_version()
    return @version
  end
  def is_changed()
    return @currently_released_repo.nil? || @currently_released_repo.empty? || @currently_released_repo != @children_repo.sort!
  end

  def get_binding
    binding
  end
  
  def set_ArtifactOrMetaData(artifactOrMetadata)
    @ArtifactOrMetadata=artifactOrMetadata
  end
  
  def compute_version()
    if @version
      return
    end
    #find the directories that contain a p2 repository
    #sort them by name and use the last one for the actual last version.
    #increment that version.
    current_latest=compute_last_version @outputPath
    if current_latest.nil?
     # raise "Expecting to find a version number in #{@outputPath}"
      @version="3.0.0.000"
    else
      @currently_released_repo=compute_children_repos File.join(@outputPath,current_latest)
      @version=increment_version current_latest
    end
    #puts @version
  end

  #returns the last version folder
  #parent_dir contains version folders such as 1.0.0.001, 1.0.0.002 etc
  def compute_last_version(parent_dir)
    puts "Looking for the last version in #{parent_dir}"
    versions = Dir.glob("#{parent_dir}/*/artifacts.*") | Dir.glob("#{parent_dir}/*/dummy") | Dir.glob("#{parent_dir}/*/compositeArtifacts.*")
    sortedversions= Array.new
    versions.uniq.sort.each do |path|
      if FileTest.file?(path) && !FileTest.symlink?(File.dirname(path)) && "latest" != File.basename(File.dirname(path))
        aversion= File.basename File.dirname(path)
        sortedversions << aversion
      end
    end
    return sortedversions.last
  end
  
  def compute_versioned_output()
    compute_version
    @versionned_output_dir = "#{@outputPath}/#{@version}"
    puts "Got #{@versionned_output_dir}"
    if @test != "true"
      if File.exist? @versionned_output_dir
        puts "warning: removing the existing directory #{@versionned_output_dir}"
        FileUtils.rm_rf @versionned_output_dir
      end
      puts @versionned_output_dir
      FileUtils.mkdir_p @versionned_output_dir
    end
  end
  
  # increment a version. if the version passed is 1.0.0.019, returns 1.0.0.020
  # keeps the padded zeros
  def increment_version(version)
    toks = version.split "."
    buildnb = toks.last
    incremented = buildnb.to_i+1
    inc_str_padded = "#{incremented.to_s.rjust(buildnb.size, "0")}"
    toks.pop
    toks.push inc_str_padded
    return toks.join "."
  end
  
  def compute_children_repos(compositeRepoFolder)
    children_repos = Array.new
    compositeArtifacts=File.join(compositeRepoFolder,"compositeArtifacts.xml")
    if !File.exist? compositeArtifacts
      puts "Warn #{compositeArtifacts} does not exists"
      return;
    end
    file = File.new(compositeArtifacts, "r")
      
    while (line = file.gets)
      #look for a line that contains <child location="../../be/3.0.0.178"/>
      #extract the location attribute.
      #put it in the array.
      m = /<child location="(.*)"\/>/.match line
      if m
        children_repos.push m[1]
        puts "found one in '#{m[1]}'"
      end
    end
    file.close
    children_repos.sort!
  end
  
end

require "rubygems"
require "getopt/long"
opt = Getopt::Long.getopts(
  ["--basefolder", "-b", Getopt::REQUIRED],
  ["--output", "-o", Getopt::REQUIRED],
  ["--name", "-n", Getopt::OPTIONAL],
  ["--test", "-t", Getopt::OPTIONAL],
  ["--version", "-v", Getopt::OPTIONAL],
  ["--otherurls", "-u", Getopt::OPTIONAL]
)

#the folder in which we start looking for the children repositories
basefolder = opt["basefolder"] || "."
#the name of the generated repository
name = opt["name"] || "all"
#forced version for the generated composite repository
version = opt["version"]
#The fodler where the composite repository is generated.
#such that $output/$theversion/compositeArtifacts.xml will exist.
if opt["output"]
  output=opt["output"]
else
  #look for the all folder and use this as the directory.
end

# a file where each line that does not start with a '#'
# is a url of another repository that is added to the child repos
otherurls=opt["otherurls"]

test=opt["test"] || "false"

compositeRepository=CompositeRepository.new output, version, basefolder, name, otherurls, test

#collect the child repos.
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
    if File.basename(path).downcase == "#{name.downcase}.composite.mkrepo"
      compositeRepository.add_childrepo path
    end
  end
end

if not compositeRepository.is_changed
  puts "WARNING: None of the children repositories have changed since the last release."
  #exit 1
end

current_dir=File.expand_path(File.dirname(__FILE__))
#Generate the Artifact Repository
template=ERB.new File.new(File.join(current_dir,"composite.xml.rhtml")).read, nil, "%"
artifactsRes=template.result(compositeRepository.get_binding)

#Generate the Metadata Repository
compositeRepository.set_ArtifactOrMetaData "Metadata"
metadataRes=template.result(compositeRepository.get_binding)

#Generate the HTML page.
html_template=ERB.new File.new(File.join(current_dir,"composite_index_html.rhtml")).read, nil, "%"
htmlRes=html_template.result(compositeRepository.get_binding)


if test == "true"
  puts "=== compositeArtifacts.xml:"
  puts artifactsRes
  puts "=== compositeContent.xml:"
  puts metadataRes
  puts "=== index.html:"
  puts htmlRes
elsif
  out_dir=compositeRepository.get_versionned_output_dir
  puts "Writing the composite repository in #{out_dir}"
  File.open(File.join(out_dir,"compositeArtifacts.xml"), 'w') {|f| f.puts(artifactsRes) }
  File.open(File.join(out_dir,"compositeContent.xml"), 'w') {|f| f.puts(metadataRes) }
  File.open(File.join(out_dir,"index.html"), 'w') {|f| f.puts(htmlRes) }
  current_symlink=File.join(output,"current")
  if File.symlink?(current_symlink) || File.exists?(current_symlink)
    File.delete current_symlink
  end
  File.symlink(out_dir,current_symlink)
end

# if the Buildfile exists in the working folder then update it with this version number.
#so that when buildrdeb-release.sh is called
# it will tag and commit with this version number.
if File.exists? "Buildfile"
  puts "Updating the Buildfile #{File.expand_path('Buildfile')}."
  File.open("Buildfile_n", "w") do |infile|
    File.open("Buildfile", "r") do |rfile|
      while (line = rfile.gets)
        if line =~ /^VERSION_NUMBER=/
          infile.puts "VERSION_NUMBER=\"#{compositeRepository.get_version}\""
        else
          infile.puts line
        end
      end
    end
  end
  if File.exists? "target"
    puts "Deleting the target repository before the deb package generation."
    FileUtils.rm_rf "target"
  end
  
  #let the buildrdeb.sh script do the renaming after it has updated from the git repo
  #File.delete "Buildfile"
  #File.rename("Buildfile_n","Buildfile")
end

