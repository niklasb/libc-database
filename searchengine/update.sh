#!/bin/bash
cd "$(dirname "$0")"
cd ..
./get
cd searchengine
workon libcsearch
python -m index ../db
