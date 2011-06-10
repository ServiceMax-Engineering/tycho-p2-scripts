#!/bin/sh
./generate_composite_repo.rb --basefolder . \
   --absolutepathPrefix /example \
   --output ./example/all \
   --name all \
   --test false \
   --version 1.0.0.019 \
   --otherurls=otherurls.repos
