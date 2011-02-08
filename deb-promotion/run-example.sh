#!/bin/sh
./promote-debs.rb --input_csv_files ./example/cloud/all/1.0.0.019/repo.deb-ius.csv,./other_debs.csv \
   --input_deb_repository ./example/apt-repo-osgi/dists/3.0/unstable/binary \
   --output_deb_repository ./example/apt-repo-osgi/dists/3.0/stable/binary \
   --input_gpl_deb_repository ./example/apt-repo-osgi-gpl/dists/3.0/unstable/binary \
   --output_gpl_deb_repository ./example/apt-repo-osgi-gpl/dists/3.0/stable/binary \
   --p2-mirror-conf false \
   --clean_output true \
   --dry_run false
