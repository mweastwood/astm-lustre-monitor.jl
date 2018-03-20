#!/bin/bash
cd "$(dirname "$0")"
julia-0.6 -e 'include("Monitor.jl"); Monitor.main()'

