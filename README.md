# Ripple

Utilities to interact with [Ripple](https://rippleneuromed.com) systems.

[![Build Status](https://github.com/bgross/Ripple.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/bgross/Ripple.jl/actions/workflows/CI.yml?query=branch%3Amain)

A work in progress.

## Usage:
### Loading files:
Currently the only function implemented is `read_nfx(fname)`, which will read NFx (i.e., *.nf3, *.nf6) produced by the Trellis program.

### Data Structures:
Data is loaded in a `NFxFile` object, which contains a `NFxHeader`, a `Vector` of `NFxChannelHeader`'s (one for each channel),
and a `Vector` of `NFxPacket`'s containing the actual data. Data is contained in a `Matrix` with each channel in a column, with time
progressing down the rows.
