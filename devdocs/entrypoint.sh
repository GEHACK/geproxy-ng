#!/bin/bash

cd /devdocs
thor docs:download ${LANGUAGES}
thor assets:compile

rackup -o 0.0.0.0