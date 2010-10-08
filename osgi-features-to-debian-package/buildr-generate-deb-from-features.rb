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
# Author hmalphettes, atoulme
# Sources published here: github.com/intalio/tycho-p2-scripts
#
# This apache-buildr script generates a small debian packages 
# with the id of a built eclipse feature.
#
# This script traverses the sub-directories recursively and looks for folders that contain a ".control"
# file. It uses the name of the .control to generate a debian package providing a package of the same name
# and containing a single file "#{control-filename}.ius" that is placed in /var/www/cloud/conf/osgi
#

require "buildrdeb"
require "rexml/document"
include REXML

FOLDER_CONF_OSGI="/var/www/cloud/conf/osgi"

def eval_file_task(file, contents = nil)
  buffer = _("target/#{File.basename(file)}") 
  rm buffer if File.exists? buffer
  file(buffer) do |f|
    File.open(f.to_s, "w") do |writer|
      writer.write eval("\"#{contents.nil? ? File.read(file) : contents}\"")
    end
  end
end

def eval_file(file, contents = nil, label = nil)
  buffer = _("target/#{File.basename(file)}") 
  rm buffer if File.exists? buffer
  File.open(buffer, "w") do |writer|
    writer.write eval("\"#{contents.nil? ? File.read(file) : contents}\"")
  end
  return buffer
end

def controle_file_empty?(control_file)
  File.open(control_file, "r") do |infile|
    while (line = infile.gets)
        if line.strip.size != 0 && ((line =~ /^#/) == nil)
            puts line
            return false
        end
    end
  end
  return true
end

# load properties file into a hash
def load_properties(properties_filename)
  properties = {}
  File.open(properties_filename, 'r') do |properties_file|
    properties_file.read.each_line do |line|
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
  end
  properties
end

def read_built_feature_version(control_file)
  feature_project_folder = File.dirname(control_file)
  target_folder = File.join(feature_project_folder, "target")
  featfile=File.join(target_folder, "feature.xml")
  if File.exist? featfile
    xmlfile = File.new File.join(target_folder, "feature.xml")
    xmlfeat = Document.new(xmlfile)
    return xmlfeat.root.attributes["version"]
  else
    #look for the product filename
    #at the moment we support a single product file.
    Dir.glob(File.join(feature_project_folder, "*.product")).each do|product_file|
      xmlfile = File.new product_file
      xmlprod = Document.new(xmlfile)
      return xmlprod.root.attributes["version"]
    end
  end
end

# Reads the built target/feature.xml file
# Generates an iu file with a useful comment
# Copy the control file in the target folder and evaluate it.
def build_deb(control_file,deb)
  feature_project_folder = File.dirname(control_file)
  target_folder = File.join(feature_project_folder, "target")
  featfile=File.join(target_folder, "feature.xml")
  id="unknown"
  if File.exist? featfile
    xmlfile = File.new featfile
    xmlfeat = Document.new(xmlfile)
    version=xmlfeat.root.attributes["version"]
    id=xmlfeat.root.attributes["id"]+".feature.group"
    label=xmlfeat.root.attributes["label"]
    if label =~ /^%/
      feature_properties=load_properties File.join(feature_project_folder, "feature.properties")
      label.slice!(0)
      label=feature_properties[label]
    end
  else
    puts "No feature.xml looking for products"
    #look for the product filename
    #at the moment we support a single product file.
    Dir.glob(File.join(feature_project_folder, "*.product")).each do|product_file|
    puts "prod #{product_file}"
      xmlfile = File.new product_file
      xmlprod = Document.new(xmlfile)
      version=xmlprod.root.attributes["version"]
      id=xmlprod.root.attributes["uid"]
      label=xmlprod.root.attributes["name"]
    end
    
  end

  puts "version=#{version}"
  puts "id=#{id}"
  puts "label=#{label}"

  control_content=nil
  if controle_file_empty?(control_file)
    control_content= <<-CONTROL
Package: #{File.basename(control_file).chomp(".control")}
Version: #{version}
Section: Intalio-Cloud
Priority: optional
Architecture: all
Depends: intalio-cloud-platform
Installed-Size: 5024
Maintainer: Intalio <info@intalio.com>
Description: #{label}
CONTROL
  end
  
  built_control=eval_file(control_file, control_content, label)

  iu_file=File.join(feature_project_folder,File.basename(control_file).chomp(".control")+".ius")
  ius_content = <<-IUS
# Installable Units for #{id} #{version}
# Build-Time: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}
# Note: the version is controlled by the cloud-all repository; not by the debian package
#{id}
IUS
  built_ius=eval_file(iu_file, ius_content, label)
 
  deb.version=version
  deb.control=built_control.to_s
  deb.include(built_ius, :path => FOLDER_CONF_OSGI)

end

def collect_control_files()
   controls=Array.new
   Dir.glob(File.join("**", "*.control")).each do|f|
     if File.basename(File.dirname(f))!="target"
       controls << f
     end
   end
   return controls
end

desc "Generic Deb Packages of OSGi features"
define "generic.osgi.feature.to.deb" do
  
  project.group = "generic.osgi.feature.to.deb"
  project.version = "1.0"
  
collect_control_files.each do |control|
  project_name=File.basename(control).chomp('.control')
  project_version=read_built_feature_version(control)
  buildr_project = <<-CONTROL
  project.version = "#{project_version}"
  desc "Intalio|Cloud deb package for #{control.to_s}"
  define "#{project_name}", :base_dir => "#{File.dirname(control)}" do
    package(:deb, :id=>"#{project_name}").tap do |deb|
      build_deb("#{control}",deb)
    end
  end
CONTROL
  puts "Building #{buildr_project}"
  eval buildr_project
end
  
end