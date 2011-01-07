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
# This script reads csv files that first column is a filename. It copies that file to a folder.
# The filename can contain a glob expression (intalio-cloud-all-3.1.*.deb)
# When multiple files match this glob, the latest one according to its alphabetical order is selected.
# 
# This is used to promote deb packages from unstable to stable.

require "find"
require "pathname"
require "fileutils"

class DebPackageSelection
  
  # @param input_csv_files array of the paths to the csv files that first column is the path to the deb files
  # the name of the deb files can be glob in order to select a different version number than the latest one.
  # @param
  def initialize(input_csv_files,input_deb_repository,input_gpl_deb_repository,output_deb_repository,output_gpl_deb_repository,clean_output,dry_run)
    @output_deb_repository = File.expand_path(output_deb_repository)
    @input_deb_repository = File.expand_path(input_deb_repository)
    @output_gpl_deb_repository = File.expand_path(output_gpl_deb_repository)
    @input_gpl_deb_repository = File.expand_path(input_gpl_deb_repository)
    @input_csv_files = input_csv_files
    @clean_output = clean_output
    @dry_run=dry_run
    
    #the selected deb files indexed by the deb file name to avoid duplicates.
    @selected_deb_files = {}
    
    if !File.exists? @output_deb_repository
      raise "The folder 'input_deb_repository' #{@output_deb_repository} does not exist"
    end
    if !File.exists? @input_deb_repository
      raise "The folder 'output_deb_repository' #{@input_deb_repository} does not exist"
    end
    if !File.exists? @output_deb_repository
      raise "The folder 'input_gpl_deb_repository' #{@output_gpl_deb_repository} does not exist"
    end
    if !File.exists? @input_deb_repository
      raise "The folder 'output_gpl_deb_repository' #{@input_gpl_deb_repository} does not exist"
    end
    
    read_csv_files
    
    copy_selected_debs
    
    execute_apts
  end
  
  def read_csv_files()
    @input_csv_files.uniq.each do |csv_file|
      if !File.exists? csv_file
        raise "The csv file #{csv_file} does not exist"
      end
      csv_file=File.expand_path csv_file
      puts "---Reading #{csv_file}"
      base=@input_deb_repository
      headers=""
      File.open(csv_file, "r") do |infile|
        while (line = infile.gets)
          if line.strip.size != 0 && ((line =~ /^#/) == nil)
            #not an empty line and not a commented line.
            if (headers == "" && line =~ / /)
              #puts "Skip headers #{line}"
              headers=line.strip
            elsif line =~ /^BASE=(.*)/
              base=$1
              puts "current base #{base}"
              base = File.expand_path base
              if ! File.exists?(base)
                raise "The base directory #{base} does not exist"
              end
            elsif (line =~ /:\/\//) != nil
              select_deb_file(base,eval("\"#{line.strip}\""),@input_gpl_deb_repository,csv_file)
            else
              #break platform/xsharp.platform.repository/3.1.0.*
              #into platform/xsharp.platform.repository and the glob 3.1.0.*
              first_col=line.split(',')[0]
              line_a = first_col.split('/')
              version_glob = line_a.pop.strip
              path = line_a.join('/')
              if (path =~ /^\//) == nil
                path = File.join(base,path)
              end
#              puts "got #{path} and #{version_glob}"
              if ! File.exists?(path)
                raise "The directory #{path} does not exist"
              end
              selected=select_deb_file(path,version_glob,@input_gpl_deb_repository,csv_file)
              @selected_deb_files[File.basename(selected)]=selected
            end
          end
        end
      end
      
    end
  end
  
  # deb_file_name_selector The glob for the deb file to select.
  #when multiple files are possible the latest version is the one selected.
  def select_deb_file(path,deb_file_name_selector,alternative_path,csv_file)
    glob=File.join(path,deb_file_name_selector)
#    puts "Looking for the last version in #{glob}"
    versions = Dir.glob(glob)
    sortedversions= Array.new
    versions.uniq.sort.each do |path|
      if FileTest.file?(path) && !FileTest.symlink?(File.dirname(path))
        aversion=path
        sortedversions << aversion
      end
    end
    if sortedversions.empty?
      if alternative_path != nil
        return select_deb_file(alternative_path,deb_file_name_selector,nil,csv_file)
      else
        raise "Unable to find a file for #{glob} as listed in #{csv_file}"
      end
    end
#    puts "Got #{sortedversions.last}"
    return sortedversions.last
  end
  
  def copy_selected_debs()
    if @dry_run!="true" && @clean_output == "true"
      puts "Deleting all the files currently in the output directory #{@output_deb_repository}."
      Dir.foreach(@output_deb_repository) {|x| File.delete File.join(@output_deb_repository,x) unless File.directory? File.join(@output_deb_repository,x) }
      puts "Deleting all the files currently in the output directory #{@output_gpl_deb_repository}."
      Dir.foreach(@output_gpl_deb_repository) {|x| File.delete File.join(@output_gpl_deb_repository,x) unless File.directory? File.join(@output_gpl_deb_repository,x) }
    end
    
    @selected_deb_files.each do |filename,file|
      if @dry_run!="true"
        if (filename =~ /-gpl-/) == nil
          FileUtils.copy(file,@output_deb_repository)
        else
          FileUtils.copy(file,@output_gpl_deb_repository)
        end
      else
        puts "Dry-run: selected #{file}"
      end
    end
  end
  
  #looks for the apt.sh script in the 2 deb repositories
  def execute_apts()
    if @dry_run!="true"
      execute_apt @output_deb_repository
      execute_apt @output_gpl_deb_repository
    end
  end
  def execute_apt(deb_folder)
    curr_dir=Dir.pwd
    Dir.chdir(deb_folder)
    loop=0
    while loop < 6 do
      loop+=1
      if File.exists? "apt.sh"
        system "./apt.sh"
        return
      end
      Dir.chdir("..")
      #puts Dir.pwd
    end
    Dir.chdir(curr_dir)
  end
  
end


require "rubygems"
require "getopt/long"
opt = Getopt::Long.getopts(
  ["--input_csv_files", "-c", Getopt::REQUIRED],
  ["--input_deb_repository", "-i", Getopt::REQUIRED],
  ["--input_gpl_deb_repository", "", Getopt::OPTIONAL],
  ["--output_deb_repository", "-o", Getopt::REQUIRED],
  ["--output_gpl_deb_repository", "-", Getopt::OPTIONAL],
  ["--clean_output", "-l", Getopt::OPTIONAL],
  ["--dry_run", "-t", Getopt::OPTIONAL]
)

#the folder in which we start looking for the children repositories
input_csv_files = opt["input_csv_files"].split(",")
#
input_deb_repository = opt["input_deb_repository"]
input_gpl_deb_repository = opt["input_gpl_deb_repository"]
#The folder where the deb repository with the promoted debs is generated.
output_deb_repository = opt["output_deb_repository"]
output_gpl_deb_repository = opt["output_gpl_deb_repository"]
#false to not clean the previous debs that are in the repo.
clean_output=opt["clean_output"] || "true"
dry_run=opt["dry_run"] || "false"

debpackage_selection=DebPackageSelection.new input_csv_files,input_deb_repository,input_gpl_deb_repository,output_deb_repository,output_gpl_deb_repository,clean_output,dry_run
