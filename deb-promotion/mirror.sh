#!/bin/sh
#mirror
if [ -z "$site_url" ]; then
  echo "site_url must be defined."
  exit 2
fi
if [ -z "$P2_DIRECTOR_HOME" ]; then
  echo "P2_DIRECTOR_HOME must be defined."
  exit 2
fi

application="org.eclipse.equinox.p2.artifact.repository.extended.mirrorApplication"
applicationMetaData="org.eclipse.equinox.p2.metadata.repository.extended.mirrorApplication"
if [ -z "$destination" ]; then
  destination=`pwd`
fi

p2director_path=$P2_DIRECTOR_HOME
#/var/www-org/public/p2repo/p2director-extended-3.6.0.v20100909

eclipse_mirror_url=http://download.eclipse.org/
$p2director_path/start.sh -destination $destination \
 -application $application \
 -exclude *.source \
 -source $site_url \
 -consoleLog

$p2director_path/start.sh -destination $destination \
 -application $applicationMetaData \
 -exclude *.source \
 -source $site_url \
 -consoleLog

#http://www.eclipse.org/downloads/download.php?file=/eclipse/downloads/drops/R-3.6.1-201009090800/eclipse-SDK-3.6.1-linux-gtk.tar.gz&url=http://ftp.osuosl.org/pub/eclipse/eclipse/downloads/drops/R-3.6.1-201009090800/eclipse-SDK-3.6.1-linux-gtk.tar.gz&mirror_id=272
