# This script only needs to be ran once per Julia installation, to install dependencies

using Pkg
Pkg.activate(".")
Pkg.instantiate()