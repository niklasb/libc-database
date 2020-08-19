#!/bin/bash
cd "$(dirname "$0")"
cd ..
./get
cd searchengine
source $HOME/.local/bin/virtualenvwrapper.sh
workon libcsearch
python -m index ../db
