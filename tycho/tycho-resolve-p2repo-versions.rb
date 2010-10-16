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
# This script parses a pom.xml in which p2 repositories are defined.
# It resolves the value of each URL for the p2 repositories
# Then tries to download the #{p2_repo-url}/version_built.properties
# If it exists, it reads this file for the actual version of the repositories
# and it outputs all the information about repsoitories use during the built
# in the file pom.repositories_report.xml
#
# This enables us to mark the exact version of each repository used during a build
# even if during developement those urls are actually always pointing to the latest release.
#

require "rubygems"
require "getopt/long"
require "net/http"
require "rexml/document"
include REXML

opt = Getopt::Long.getopts(
  ["--pom", "-p", Getopt::REQUIRED],
  ["--output", "-o", Getopt::OPTIONAL]
)

#pom path to the pom.xml file to parse
pom=opt["pom"]
if ! File.exists? pom
  raise "The #{pom} file does not exist"
end
output=opt["output"]
if ! output
  output=File.dirname pom
end
if ! File.exists? output
  raise "The #{output} file does not exist"
end

# load properties string into a hash
def load_properties(properties_str)
  properties = {}
#  File.open(properties_filename, 'r') do |properties_file|
    properties_str.each do |line|
      line.strip!
      if (line[0] != ?# and line[0] != ?=)
        i = line.index('=')
        if (i)
          properties[line[0..i - 1].strip] = line[i + 1..-1].strip
        else
          properties[line] = ''
        end
      end
    end      
#  end
  properties
end



class P2Repository
  def initialize(id, url)
    @id = id
    @url = url
    @read_version = "unknown"
    @read_built  = "unknown"
    @read_artifact = "unknown"
    puts "New repo #{id} -> #{url}"
    resolve_version
  end
  
  def resolve_version()
    url_built_version="#{@url}/built_version.properties"
    uri = URI.parse(url_built_version)
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.get(uri.path) }
    if response.code == "200"
      built_props= load_properties(response.body)
      @read_version=built_props['version']
      @read_built=built_props['built']
      @read_artifact=built_props['artifact']
    else
   #   puts "#{url_built_version} -> #{response.code}"
    end
  end
  
  def print_report()
    return <<-REPORT
    <repository>
        <id>#{@id}</id>
        <layout>p2</layout>
        <url>#{@url}</url>
        <built_version>
           <artifact>#{@read_artifact}</artifact>
           <version>#{@read_version}</version>
           <built>#{@read_built}</built>
        </built_version>
    </repository>
REPORT
  end
  
end

REPOSITORIES = {}
PROPERTIES={}

#parse the pom.xml
pom_xml=Document.new(File.new pom)

#put the properties into a hash.
XPath.each(pom_xml,"//properties") { |properties_elem|
  properties_elem.elements.each { |prop| 
     PROPERTIES[prop.name] = prop.text
  }
}
# return true if the string was mutated false otherwise
def resolve_property_single_pass(value)
  m = /\$\{(.*)\}/.match value
  if m != nil
    prop_ref=m[1]
    prop_value=PROPERTIES[prop_ref]
    if prop_value
      atleast_one_more_replacement=true
      #new_value = value.gsub /\$\{.*\}/, 'prop_value\1 '
      value.gsub!(/\$\{.*\}/) do|w|
        w = prop_value
      end
      return true
    end
  end
  return false
end

# 'flatten' the properties: parse the {otherproperty} and substitute them recursively
atleast_one_more_replacement=true
loop_counter=0
while atleast_one_more_replacement && loop_counter < 25
  atleast_one_more_replacement = false
  PROPERTIES.each_pair do |prop,value|
    if resolve_property_single_pass value
      atleast_one_more_replacement = true
    end
  end
  loop_counter+=1
end

#now iterate over each p2 repository:
XPath.each(pom_xml,"//repositories/repository[layout/text()='p2']") { |repository_elem|
  id = repository_elem.get_elements("id").first.text
  url = repository_elem.get_elements("url").first.text
  resolve_property_single_pass url
  REPOSITORIES[id] = P2Repository.new(id, url)
}

#now output the pom.repositories_report.xml file
File.open(File.join(output,"pom.repositories_report.xml"), 'w') { |f|
  f.puts "<repositories>"
  REPOSITORIES.each_pair do |k,v|
    f.puts v.print_report
  end
  f.puts "</repositories>"
}

