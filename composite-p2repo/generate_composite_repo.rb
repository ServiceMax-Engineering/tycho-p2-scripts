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
require "set"

class CompositeRepository
  
  def initialize(output, version, basefolder, absolutepathPrefix, name, otherurls, test)
    @outputPath = Pathname.new(output).expand_path
    @basefolder = Pathname.new(basefolder).expand_path
    @absolutepathPrefix = absolutepathPrefix
    @name = name
    @version = version
    @test = test

    #contain the list of relative path to the linked versioned repos
    @children_repo_relative = [ ]
    #contain the list of absolute paths to the linked versioned repos. in fact relative to the base folder.
    @children_repo_absolute = [ ]
    
    #contains the parent folders of each repo already in the composite repo so we don't duplicate
    @already_indexed_parents = Set.new
    
    #all the csv lines to keep track of the deb packages and their associated p2-ius.
    #indexed by the deb file name to avoid duplicates
    @deb_osgi_csv_line = {}
    
    #contain the list of relative path to the linked versioned repos
    #according to the last released aggregate repository
    #we read it in the last released composite repo.
    #if nothing has changed then we don't need to make a new release.
    @currently_released_repo = []
    
    @ArtifactOrMetadata="Artifact"
    @timestamp=Time.now.to_i
    @date=Time.now.utc
    @hasdebs=nil
    @versionned_output_dir=nil
    compute_versioned_output
    
    add_external_childrepos otherurls
    
    write_composite_deb_ius_csv
  end
  
  def add_childrepo( compositeMkrepoFile, version_glob="*" )
    if File.directory? compositeMkrepoFile
      compositeRepoParentFolder=Pathname.new compositeMkrepoFile.path
    else
      compositeRepoParentFolder=Pathname.new Pathname.new(File.dirname compositeMkrepoFile).expand_path
    end
    if @already_indexed_parents.include? compositeRepoParentFolder
      raise "The repo #{compositeRepoParentFolder} is already added to the composite repository"
    end
    
    #make it a path relative to the @versionned_output_dir
    relative=compositeRepoParentFolder.relative_path_from(Pathname.new(@versionned_output_dir))
    if relative.nil?
      raise "Could not compute the relative path of #{compositeRepoParentFolder.to_s} from #{Pathname.new(@versionned_output_dir).to_s}"
    end
    last_version=compute_last_version(compositeRepoParentFolder,version_glob)
    if last_version.nil?
      raise "Could not locate a version directory in #{compositeRepoParentFolder.to_s}/#{version_glob}"
    end
    relative=File.join(relative.to_s,last_version)
    absolute="#{@absolutepathPrefix}/#{compositeRepoParentFolder.relative_path_from(Pathname.new(@basefolder))}/#{last_version}"
    @children_repo_relative << relative
    @children_repo_absolute << absolute
    @already_indexed_parents << compositeRepoParentFolder
    collect_deb_associated_packages(File.join(compositeRepoParentFolder.to_s,last_version))
    copy_deb_associated_files(File.join(compositeRepoParentFolder.to_s,last_version))
  end
    
  def add_external_childrepos(otherurls_file)
    if otherurls_file.nil?
      return
    end
    puts otherurls_file
    if ! File.exists?(otherurls_file)
      raise "The file #{otherurls_file} does not exist."
    end
    File.open(otherurls_file, "r") do |infile|
      while (line = infile.gets)
        if line.strip.size != 0 && ((line =~ /^#/) == nil)
          #not an empty line and not a commented line.
          if line =~ /^GROUP_ID=(.*)/
            puts "skip #{line}"
            #continue
          elsif line =~ /^VERSION_NUMBER=(.*)/
            puts "skip #{line}"
            #continue
          elsif line =~ /^BASE=(.*)/
            base=$1
            puts "current base #{base}"
            base = File.expand_path base
            if ! File.exists?(base)
              raise "The base directory #{base} does not exist"
            end
          elsif (line =~ /:\/\//) != nil
            add_external_childrepo(eval("\"#{line.strip}\""))
          else
            #break platform/xsharp.platform.repository/3.1.0.*
            #into platform/xsharp.platform.repository and the glob 3.1.0.*
            line_a = line.split('/')
            version_glob = line_a.pop.strip
            path = line_a.join('/')
            if (path =~ /^\//) == nil
              path = File.join(base,path)
            end
            puts "got #{path} and #{version_glob}"
            if ! File.exists?(path)
              raise "The directory #{path} does not exist"
            end
            add_childrepo(File.new(path),version_glob)
          end
        end
      end
    end
  end

  def add_external_childrepo(url)
    @children_repo_absolute << url
    @children_repo_relative << url
  end
  
  def get_versionned_output_dir()
    return @versionned_output_dir
  end
  def get_version()
    return @version
  end
  def is_changed()
    return @currently_released_repo.nil? || @currently_released_repo.empty? || @currently_released_repo != @children_repo_absolute.sort!
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
      @version="1.0.0.000"
    else
      @currently_released_repo=compute_children_repos File.join(@outputPath,current_latest)
      @version=increment_version current_latest
    end
    #puts @version
  end

  #returns the last version folder
  #parent_dir contains version folders such as 1.0.0.001, 1.0.0.002 etc
  def compute_last_version(parent_dir, version_glob="*")
    puts "version->#{@version}"
    if 'latest'==@version
      path=File.join(parent_dir,"latest")
      if !File.directory?(path)
        puts "Looking at #{path}"
        path=File.join(parent_dir,"current")
      end
      if File.directory?(path)
        puts "Found #{path}"
        return File.basename(File.dirname(path))
      end
    end
    glob=File.join(parent_dir,version_glob)
    puts "Looking for the last version in #{glob}"
    versions = Dir.glob(File.join(glob,"artifacts.*")) | Dir.glob(File.join(glob,"dummy")) | Dir.glob(File.join(glob,"compositeArtifacts.*"))
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
    puts "Output path #{@outputPath}"
    if (@outputPath =~ /target\/repository$/) != nil
      @versionned_output_dir = @outputPath
    else
      @versionned_output_dir = "#{@outputPath}/#{@version}"
    end
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
  
  #returns the debian filenames related to the IUs published in the p2-repo as debian packages
  #the repository must contain *.deb-ius.csv files generated by the deb gen script.
  #it contains a csv file that first column is the name of a the deb file generated.
  def collect_deb_associated_packages(repo_folder)
    headers=""
    glob=File.join(repo_folder,"*.deb-ius.csv")
    csv_files=Dir.glob(glob)
    csv_files.each do |path|
      File.open(path, 'r') do |properties_file|
        properties_file.read.each_line do |line|
          if (headers == "" && line =~ / /)
           # puts "Skip headers #{line}"
            headers=line.strip
          elsif line.strip == headers
            puts "skip a duplicated headers line"
          elsif line.strip != ""
            line = line.strip
            toks=line.split(",")
            #use the deb filename as a key to avoid duplicate entries.
            @deb_osgi_csv_line[toks[0]] = line.strip
          end
        end
      end
    end
  end
  
  #look for the debs folder inside the repo_folder.
  #copy the content deb files into the composite folder's 'debs' folder.
  def copy_deb_associated_files(repo_folder)
    glob=File.join(repo_folder, "debs", "*.deb")
    deb_files = Dir.glob(glob)
    puts "Looking for #{glob} gave #{deb_files}"
    if deb_files and !deb_files.empty?
      @hasdebs=true
      dest_folder = File.join(@versionned_output_dir, 'debs')
      FileUtils.mkdir_p dest_folder
      FileUtils.cp(deb_files, dest_folder)
    end
  end

  
  def write_composite_deb_ius_csv()
    File.open(File.join(@versionned_output_dir,"repo.deb-ius.csv"), 'w') do |f1|
      #headers
      f1.puts("Deb filename,Deb Package,Deb Version,OSGi IU id,OSGi IU version,Description")
      #cloud-all also generates a deb package
      f1.puts("#{@name}-#{@version}.deb,#{@name},#{@version},NA,NA,\"#{@name}\"")
      @deb_osgi_csv_line.values.sort.each do |csv_line|
        f1.puts(csv_line)
      end
    end
  end
  
end

require "rubygems"
require "getopt/long"
opt = Getopt::Long.getopts(
  ["--basefolder", "-b", Getopt::REQUIRED],
  ["--absolutepathPrefix", "-a", Getopt::OPTIONAL],
  ["--output", "-o", Getopt::REQUIRED],
  ["--name", "-n", Getopt::OPTIONAL],
  ["--test", "-t", Getopt::OPTIONAL],
  ["--version", "-v", Getopt::OPTIONAL],
  ["--otherurls", "-u", Getopt::OPTIONAL],
  ["--symlinkname", "-s", Getopt::OPTIONAL]
)

#the folder in which we start looking for the children repositories
basefolder = opt["basefolder"] || "."
#the name of the generated repository
name = opt["name"] || "all"
#forced version for the generated composite repository
version = opt["version"]
absolutepathPrefix = opt["absolutepathPrefix"] || ""
#The fodler where the composite repository is generated.
#such that $output/$theversion/compositeArtifacts.xml will exist.
if opt["output"]
  output=opt["output"]
else
  #look for the all folder and use this as the directory.
end
if opt["symlinkname"]
  symlink_name=opt["symlinkname"]
else
  symlink_name="current"
end

# a file where each line that does not start with a '#'
# is a url of another repository that is added to the child repos
otherurls=opt["otherurls"]

test=opt["test"] || "false"

compositeRepository=CompositeRepository.new output, version, basefolder, absolutepathPrefix, name, otherurls, test

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
  if (output =~ /target\/repository$/) == nil
    current_symlink=File.join(output,symlink_name)
    if File.symlink?(current_symlink) || File.exists?(current_symlink)
      File.delete current_symlink
    end
    Dir.chdir "#{out_dir}/.."
    File.symlink(out_dir,symlink_name)
    Dir.chdir "#{current_dir}"
  end
end

