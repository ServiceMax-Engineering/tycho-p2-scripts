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
# This script should be called once mvn clean package (or integration-test)
# has been executed. and once the deb packages have been generated
# but before the repositories are "published" (aka moved) in their final location.
#
# This script collects the csv files that keep track of the deb packages
# published in association with some OSGi artifacts
# It finds the repositories of this build
# and write the concatenated csv file there
# if the repository has a filter file then it reads it to see what deb pacakge
# should be published in association with that repository.


# first read all the csv files so we have all info about the debs published
# in this build.
# we assume the current working directory is the root folder of the project.

headers=""
deb_files=[]
glob=File.join("**/target/*.deb-ius.csv")
csv_files=Dir.glob(glob)
puts "csv_files #{csv_files}"
csv_files.each do |path|
  File.open(path, 'r') do |properties_file|
    properties_file.read.each_line do |line|
      if (headers == "" && line =~ / /)
        #puts "Skip headers #{line}"
        headers=line.strip
      elsif line.strip == headers
        puts "skip a duplicated headers line"
      elsif line.strip != ""
        #puts "Reads #{line.strip}"
       # toks=line.strip.split(",")
        deb_files << line
      end
    end
  end
end

# now look for the projects where a repository is defined.
# TODO: optional file that filters in and out the deb packages actually related to a specific repository.
# useful if multiple repositories are created by the same build
built_repos=Dir.glob("**/target/*/artifacts.jar")
puts "built_repos #{built_repos}"
built_repos.each do |path|
  repo_folder=File.dirname(path)
  puts "Hello: #{repo_folder}"
  File.open(File.join(repo_folder,"repo.deb-ius.csv"), 'w') do |f1|
    f1.puts("Deb filename,Deb Package,Deb Version,OSGi IU id,OSGi IU version,Description")
    deb_files.each do |csv_line|
      f1.puts(csv_line)
    end
  end
  puts "Done with: #{repo_folder}"
end


puts "No problemo here."

