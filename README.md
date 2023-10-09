# Ripple

Utilities to interact with [Ripple](https://rippleneuromed.com) systems.

[![Build Status](https://github.com/WiredBrains-Lab/Ripple.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/WiredBrains-Lab/Ripple.jl/actions/workflows/CI.yml?query=branch%3Amain)

A work in progress. Not all functions are currently implemented, but I believe what is there is currently functional. Please let me know if you find errors.

## Usage:
### Loading files:
Currently functions for reading NFx (i.e., *.nf3, *.nf6), NSx, and NEV files are implemented. I'm currently using the specs provided by Ripple to build these functions, and so they may not be fully compatible with other versions of these formats from Blackrock systems.

:warning: the NEV implementation is fairly limited right now. I'm not doing spike recordings, so I only implemented the digital events.

### Data Structures:
Regardless of whether the original file is NSx or NFx, the data are loaded into a `NxFile` object, which contains a `NxHeader`, a `Vector` of `NxChannelHeader`'s (one for each channel), and a `Vector` of `NxPacket`'s containing the actual data. Data is contained in a `Matrix` 
with each channel in a column, with time progressing down the rows.
