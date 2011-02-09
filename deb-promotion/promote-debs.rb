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
  def initialize(input_csv_files,input_deb_repository,input_gpl_deb_repository,output_deb_repository,output_gpl_deb_repository,clean_output,dry_run,p2_mirror_conf,p2_mirror_filters,composite_repo_version)
    @output_deb_repository = File.expand_path(output_deb_repository)
    @input_deb_repository = File.expand_path(input_deb_repository)
    @output_gpl_deb_repository = File.expand_path(output_gpl_deb_repository)
    @input_gpl_deb_repository = File.expand_path(input_gpl_deb_repository)
    @input_csv_files = input_csv_files
    @clean_output = clean_output
    @dry_run=dry_run
    @p2_mirror_conf=p2_mirror_conf
    @p2_mirror_filters=p2_mirror_filters
    @composite_repo_version=composite_repo_version
    
    #the selected deb files indexed by the deb file name to avoid duplicates.
    @selected_deb_files = {}
    #the deb file names indexed by the osgi artifact id when there is such thing.
    #when we read the excluding filters for the p2-mirror
    #we can find which corresponding deb should also be excluded.
    @selected_deb_filebasenames_indexed_by_osgi_id = {}
    @deb_excludes=[]
    @p2_mirror_excludes=[]
    
  end
  
  def execute()
    clean_previous_repo
    execute_p2_mirror
    generate_cloud_all_deb
    read_p2_mirror_filters
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
            elsif line =~ /^-exclude*=(.*)/
              #an exclusion simple pattern
              patterns=$1.split(" ")
              patterns.collect! {|x| Regexp.new(p2_simple_pattern_to_regexp(x)) }
              @deb_excludes=@deb_excludes+patterns
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
              #sample csv line:
              #intalio-bpm-pipes-registry-1.0.0.071.deb,intalio-bpm-pipes-registry,1.0.0.071,bpm.pipes.registry.f.feature.group,1.0.0.071,"Intalio|Cloud Pipes Bpm registry"
              #for the non osgi list, there might be a path.
              #break platform/xsharp.platform.repository/3.1.0.*
              #into platform/xsharp.platform.repository and the glob 3.1.0.*
              columns=line.split(',')
              first_col=columns[0]
              osgi_id=columns[3] unless columns.size <= 4
              line_a = first_col.split('/')
              version_glob = line_a.pop.strip
              path = line_a.join('/')
              #make sure that when the p2repo are concatenated
              #we don't mirror the intalio-cloud-all deb: we generate our own one here
              if line =~ /^intalio-cloud-all-/ && @p2_mirror_conf != nil
                puts "skip cloud-all"
              else
                if (path =~ /^\//) == nil
                  path = File.join(base,path)
                end
#                puts "got #{path} and #{version_glob}"
                if ! File.exists?(path)
                  raise "The directory #{path} does not exist"
                end
                selected=select_deb_file(path,version_glob,@input_gpl_deb_repository,csv_file)
                #let's see if in fact this artifact is excluded.
                included=true
                #look at the ezxclude filters for debs
                @deb_excludes.each do |exclude|
                  if exclude =~ File.basename(selected)
                    included = false
                    puts "Excluded: Matched #{File.basename(selected)} with #{exclude.to_s}"
                  end
                end
                #CL-178 !Hack! don't filter the gpl ext js otherwise we won't see it in the generated gpl repo.
                #all this will be so much better once we generate a single repository at a time.
                if included && osgi_id != nil && osgi_id != "xsharpplugin.client.ext" && osgi_id != "xsharpplugin.client.ext.f.feature.group"
                  @selected_deb_filebasenames_indexed_by_osgi_id[osgi_id]=File.basename(selected)
                  #let's make sure that this osgi artifact is not filtered out by the p2mirror
                  puts "looking at #{osgi_id}"
                  @p2_mirror_excludes.each do |exclude|
                    #puts "matching on #{exclude.to_s}"
                    #execute each one of the regexp. if any of them match then filter this out.
                    if exclude =~ osgi_id
                      included = false
                      #puts "Matched #{osgi_id} with #{exclude.to_s}"
                    end
                  end
                end
                if included
                  @selected_deb_files[File.basename(selected)]=selected
                end
              end
            end
          end
        end
      end
      
    end
  end
  
  #Transforms a p2 simple pattern into a regexp
  def p2_simple_pattern_to_regexp(simplePattern)
    #escape it
    esc = Regexp.escape simplePattern
    #replace '\?' by '.?' and '\*' by '.*'
    esc.gsub!("\\\?",".?")
    esc.gsub!("\\\*",".*")
    #puts "#{simplePattern} -> #{esc}"
    return esc
  end
  
  #the p2mirror filters some osgi artifacts.
  #we need to read which ones so we can find out which deb packages
  #should also be filtered out.
  def read_p2_mirror_filters()
#    if @p2_mirror_conf == nil
#      return
#    end
    #for now select the properties files assuming that they start with
    #p2_ mirror.. need to do better one day.
    #in fact this is messy because we are geenrating multiple deb repos and p2repos at once
    #we need to generate a single one at once instead.
    #p2filters=Dir.glob("p2_mirror.properties")
    @p2_mirror_filters.sort.each do |path|
      #read line by line. if a line starts with -exclude then look closely.
      File.open(path, "r") do |infile|
        while (line = infile.gets)
          if line =~ /^-exclude*=(.*)/
            #extract the value
            patterns=$1.split(" ")
            patterns.collect! {|x| Regexp.new(p2_simple_pattern_to_regexp(x)) }
            @p2_mirror_excludes=@p2_mirror_excludes+patterns
          end
        end
      end
    end
    #transform each simple pattern into a regexp we can use later
    puts "p2_mirror_excludes #{@p2_mirror_excludes}"
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
      if alternative_path != nil && (deb_file_name_selector =~ /-gpl-/) != nil
        return select_deb_file(alternative_path,deb_file_name_selector,nil,csv_file)
      else
        raise "Unable to find a file for #{glob} as listed in #{csv_file}"
      end
    end
#   puts "Got #{sortedversions.last} for glob: #{glob}"
    return sortedversions.last
  end
  
  def clean_previous_repo
    if !File.exists? @input_deb_repository
      raise "The folder 'input_deb_repository' #{@input_deb_repository} does not exist"
    end
    if !File.exists? @input_gpl_deb_repository
      raise "The folder 'input_gpl_deb_repository' #{@input_gpl_deb_repository} does not exist"
    end
    if @dry_run!="true" && @clean_output == "true"
      puts "Deleting all the files currently in the output directory #{@output_deb_repository}."
      #Dir.foreach(@output_deb_repository) {|x| File.delete File.join(@output_deb_repository,x) unless File.directory? File.join(@output_deb_repository,x) }
      FileUtils.rm_rf @output_deb_repository
      puts "Deleting all the files currently in the output directory #{@output_gpl_deb_repository}."
      FileUtils.rm_rf @output_gpl_deb_repository
      #Dir.foreach(@output_gpl_deb_repository) {|x| File.delete File.join(@output_gpl_deb_repository,x) unless File.directory? File.join(@output_gpl_deb_repository,x) }
    end
    if !File.exists? @output_deb_repository
      FileUtils.mkdir_p "#{@output_deb_repository}"
    end
    if !File.exists? @output_gpl_deb_repository
      FileUtils.mkdir_p "#{@output_gpl_deb_repository}/"
    end
  end
  
  def copy_selected_debs()
    
    @selected_deb_files.each do |filename,file|
      if @dry_run!="true"
        if (filename =~ /-gpl-/) == nil
          #this code will fail if the destination folder does not exist.
          FileUtils.copy(file,File.join(@output_deb_repository,File.basename(file)))
        else
          FileUtils.copy(file,File.join(@output_gpl_deb_repository,File.basename(file)))
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
  
  #TODO: option to aggregate the cloud-all repository first
  #During the aggregate use a tmp folder
  #Archive the previous repository just in case (timestamp or fixed number of archives?)
  #Find a way to customize the cloud-all deb?
  def execute_p2_mirror()
    #First the non-GPL repository
    if @p2_mirror_conf == nil
      puts "No p2 mirror taking place."
      return
    elsif @p2_mirror_conf == "default"
      #use the default settings for the mirror configuration
      p2_repo_destination="#{@output_deb_repository}/../p2repo"
      p2_repo_gpl_destination="#{@output_gpl_deb_repository}/../p2repo"
      source=""
      @input_csv_files.uniq.each do |csv_file|
        #Make sure that in fact we are in a p2 repository folder:
        #it could be a csv file unrelated to a p2 repo.
        parentOfcsv=File.dirname(csv_file)
        if File.exists?(File.join(parentOfcsv,"plugins")) || File.exists?(File.join(parentOfcsv,"compositeArtifacts.xml")) || File.exists?(File.join(parentOfcsv,"compositeArtifacts.jar"))
          source="#{source} -source file:#{File.expand_path(File.dirname(csv_file))}"
        end
      end
      props=""
      props_index=0
      @p2_mirror_filters.each do |path|
        if !File.exists? path
          raise "Could not find #{File.expand_path(path)}"
        end
        props="#{props} -props#{props_index} #{path}"
        props_index=props_index+1
      end
      props_gpl="-props ./p2_mirror_gpl.properties"
      if !File.exists? "./p2_mirror_gpl.properties"
        raise "Could not find #{File.expand_path(props_gpl)}"
      end
    elsif File.exists @p2_mirror_conf
      #TODO: read the configuration file.
      p2_repo_destination="#{@output_deb_repository}/p2repo"
    else
      raise "The p2 mirror configuration file #{@p2_mirror_conf} does not exist."
    end
    #non GPL
    execute_p2_mirror_both_apps(source,p2_repo_destination,props)
    #now GPL
    execute_p2_mirror_both_apps(source,p2_repo_gpl_destination,props_gpl)
  end

  def execute_p2_mirror_both_apps(source,destination,props)
    FileUtils.rm_rf destination
    
    exit_code=execute_p2_mirror_one_app("org.eclipse.equinox.p2.artifact.repository.extended.mirrorApplication",source,destination,props)
    if exit_code!=0
      puts "Unable to mirror the application. Please consult the logs."
      exit 3
    end
    execute_p2_mirror_one_app("org.eclipse.equinox.p2.metadata.repository.extended.mirrorApplication",source,destination,props)
  end
  
  #returns the exit status of the p2 mirror app
  def execute_p2_mirror_one_app(application,source,destination,props)
    FileUtils.mkdir_p destination
cmd="$P2_DIRECTOR_HOME/start.sh -destination #{destination} \
 -application #{application} \
 #{source} \
 #{props} \
 -consoleLog"
    if @dry_run!="true"
      puts "Executing #{cmd} 2>&1"
      system "#{cmd} 2>&1"
      puts "It returned #{$?.to_i}"
      return $?.to_i
    else
      puts "Dry-run: #{cmd}"
    end
  end
  
  #Generate a cloud-all deb pacakge that contains the pointer to the mirrored p2 repos.
  def generate_cloud_all_deb()
    if (@dry_run!="true" && @p2_mirror_conf != nil && File.exists?("mirrored"))
      #Setup the version number and all
      curr_dir=Dir.pwd
      Dir.chdir("mirrored")
      
      #Same code than in the composite-p2repo
      puts "Updating the Buildfile #{File.expand_path('Buildfile_versioned')}."
      File.open("Buildfile_versioned", "w") do |infile|
        File.open("Buildfile", "r") do |rfile|
          while (line = rfile.gets)
            if line =~ /^VERSION_NUMBER=/
              infile.puts "VERSION_NUMBER=\"#{@composite_repo_version}\""
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
      #Invoke buildr
      `buildr --buildfile Buildfile_versioned package`
      #copy the deb generated into the target debian repositories
      #it won't hurt to put it both in the gpl and non gpl repositories
      #copy the deb generated into the target debian repositories
      #it won't hurt to put it both in the gpl and non gpl repositories
      #look for all the deb files inside the target directory and copy them:
      debs = Dir.glob(File.join("target","*.deb"))
      debs.each do |path|
        if FileTest.file?(path)
          puts "Copying #{path} to #{@output_deb_repository} and #{@output_gpl_deb_repository}"
          FileUtils.cp(path,@output_deb_repository)
          FileUtils.cp(path,@output_gpl_deb_repository)
        end
      end
      #clean-up behind ourselves
      FileUtils.rm "Buildfile_versioned" 
      Dir.chdir(curr_dir)
    end
  end
  
end


require "rubygems"
require "getopt/long"
opt = Getopt::Long.getopts(
  ["--composite_repo_version", "-v", Getopt::REQUIRED],
  ["--input_csv_files", "-c", Getopt::REQUIRED],
  ["--input_deb_repository", "-i", Getopt::REQUIRED],
  ["--input_gpl_deb_repository", "", Getopt::OPTIONAL],
  ["--output_deb_repository", "-o", Getopt::REQUIRED],
  ["--output_gpl_deb_repository", "-g", Getopt::OPTIONAL],
  ["--clean_output", "-l", Getopt::OPTIONAL],
  ["--p2_mirror_conf", "-p", Getopt::OPTIONAL],
  ["--p2_mirror_filters", "-f", Getopt::OPTIONAL],
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
#optional points to the configuration file for the p2-mirror to aggregate the cloud-all repo.
p2_mirror_conf=opt["p2_mirror_conf"]
if p2_mirror_conf == "false"
  p2_mirror_conf=nil
end
dry_run=opt["dry_run"] || "false"
composite_repo_version=opt["composite_repo_version"]
p2_mirror_filters=opt["p2_mirror_filters"].split(",")

debpackage_selection=DebPackageSelection.new(input_csv_files,input_deb_repository,
                                             input_gpl_deb_repository,output_deb_repository,
                                             output_gpl_deb_repository,clean_output,
                                             dry_run,p2_mirror_conf,p2_mirror_filters,composite_repo_version)
debpackage_selection.execute()

