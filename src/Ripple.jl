module Ripple

export NxChannelHeader,NxHeader,NxPacket,NxFile
export NEVFile,NEVHeader,NEVExtendedHeader,NEVDigitalInput,NEVDigitalLabel,NEVPacket
export read_nfx,read_nsx,read_nev

using Dates

"""
    nullstring(x::Vector{UInt8})

    Trim an `unsigned char` string to its NULL termination.
"""
nullstring(x::Vector{UInt8}) = String(x[1:findfirst(==(0), x) - 1])

calc_gain(phys_min,phys_max,dig_min,dig_max) = (phys_max - phys_min) / (dig_max - dig_min)
calc_offset(gain,phys_max,dig_max) = phys_max - gain * dig_max
physical(x::T,gain::K,offset::L) where {T<:Real,K<:Real,L<:Real} = gain * x + offset

_nx_filtertype = [:none,:Butterworth,:Chebyshev]

struct NxChannelHeader
    id::Int
    label::String
    frontend_id::Int
    frontend_pin::Int
    digital_min::Int
    digital_max::Int
    analog_min::Int
    analog_max::Int
    units::String
    highpass_freq::Float64
    highpass_order::Int
    highpass_type::Symbol
    lowpass_freq::Float64
    lowpass_order::Int
    lowpass_type::Symbol
    gain::Float64
    offset::Float64
end

struct NxHeader
    version::Tuple{Int,Int}
    label::String
    comments::String
    timestamp::Int
    sampling_frequency::Float64
    utc_time::DateTime
    num_channels::Int
end

"""
    NxPacket(timestamp::Int,data::Matrix{Real})

Individual data packet (potentially multiple per file). The `timestamp` is the temporal offset
of this packet (using the processor `clock_frequency`) and `data is a 2D, "time" x "channel" `Matrix`.
"""
struct NxPacket{T<:Real}
    timestamp::Int
    data::Matrix{T}
end

"""
    NxFile(
        header::NxHeader,
        channel_headers::Vector{NxChannelHeader}
        data_packets::Vector{NxPacket}
    )

Object containing the Nx file header (for either NSx or NFX), a `Vector` of individual channel headers,
and a `Vector` of [`NxPacket`](@ref)'s found in the file.
"""
struct NxFile
    header::NxHeader
    channel_headers::Vector{NxChannelHeader}
    data_packets::Vector{NxPacket}
end

abstract type NEVExtendedHeader end

_nev_digitallabel_modes = Dict(0=>:serial,1=>:parallel)
struct NEVDigitalLabel <: NEVExtendedHeader
    label::String
    mode::Symbol
end

abstract type NEVPacket end

struct NEVDigitalInput <: NEVPacket
    timestamp::Int
    reason::NamedTuple
    values::NamedTuple
end

struct NEVHeader
    version::Tuple{Int,Int}
    flags::NamedTuple
    
    clock_frequency::Float64
    sample_frequency::Float64
    
    utc_time::DateTime
    
    application::String
    comment::String
    
    timestamp::Int
    
    extended_headers::Vector{NEVExtendedHeader}
end

struct NEVFile
    header::NEVHeader
    packets::Vector{NEVPacket}
end

"""
    function read_nfx(fname::String; applygain=true)

Read the NFx file `fname` and return a [`NxFile`](@ref).

If `applygain` is `true`, will automatically apply the calculated gain and offset to the data.
"""
function read_nfx(fname::String;applygain=true)
    match(r"\.nf[1-9]$",fname)==nothing && @warn("Attempting to load $fname as NFx, but suffix does not match!")

    open(fname) do f
        # A quick helper function to make reading all these Int's easy
        uints = Dict(8=>UInt8,16=>UInt16,32=>UInt32)
        readint(n::Int) = Int(read(f,uints[n]))

        magic = read(f,8)
        @assert magic==b"NEUCDFLT"
        ver_major = readint(8)
        ver_minor = readint(8)
        header_size = readint(32)
        label = nullstring(read(f,16))
        comments = nullstring(read(f,200))
        app = nullstring(read(f,52))
        length(app)>0 && (comments = "$comments; Application = $app")
        processor_timestamp = readint(32)
        sampling_period = readint(32)
        clock_frequency = readint(32)
        utc_time = begin
            year = readint(16)
            month = readint(16)
            dow = readint(16)
            day = readint(16)
            hour = readint(16)
            minute = readint(16)
            second = readint(16)
            ms = readint(16)
            DateTime(year,month,day,hour,minute,second,ms)
        end
        num_channels = readint(32)

        header = NxHeader(
            (ver_major,ver_minor),label,comments,
            processor_timestamp,clock_frequency / sampling_period,utc_time,num_channels
        )

        channel_headers = map(1:num_channels) do i
            channel_magic = read(f,2)
            @assert channel_magic == b"FC"

            id = readint(16)
            label = nullstring(read(f,16))
            frontend_id = readint(8)
            frontend_pin = readint(8)
            digital_min = read(f,Int16)
            digital_max = read(f,Int16)
            analog_min = read(f,Int16)
            analog_max = read(f,Int16)
            units = nullstring(read(f,16))
            highpass_freq = readint(32) # mHz
            highpass_order = readint(32)
            highpass_type = readint(16)
            # 0 = None, 1 = Butterworth, 2 = Chebyshev
            lowpass_freq = readint(32) # mHz
            lowpass_order = readint(32)
            lowpass_type = readint(16)

            gain = calc_gain(analog_min,analog_max,digital_min,digital_max)
            offset = calc_offset(gain,analog_max,digital_max)

            NxChannelHeader(
                id,label,frontend_id,frontend_pin,
                digital_min,digital_max,analog_min,analog_max,
                units,
                highpass_freq/1000,highpass_order,_nx_filtertype[highpass_type+1],
                lowpass_freq/1000,lowpass_order,_nx_filtertype[lowpass_type+1],
                gain,offset
            )
        end
        @assert position(f) == header_size

        packets = NxPacket[]
        while ! eof(f)
            @assert readint(8)==1

            timestamp = readint(32)
            num_points = readint(32)

            data = map(1:num_channels) do c
                map(1:num_points) do i
                    read(f,Float32)
                end
            end

            data = hcat(data...)

            if applygain
                for c=1:num_channels
                    data[:,c] .= physical.(data[:,c],channel_headers[c].gain,channel_headers[c].offset)
                end
            end

            push!(packets,NxPacket(timestamp,data))
        end

        return NxFile(header,channel_headers,packets)
    end
end


"""
    function read_nsx(fname::String)

Read the NSx file `fname` and return a [`NxFile`](@ref).

If `applygain` is `true`, will automatically apply the calculated gain and offset to the data.
"""
function read_nsx(fname::String;applygain=true)
    match(r"\.ns[1-9]$",fname)==nothing && @warn("Attempting to load $fname as NSx, but suffix does not match!")

    open(fname) do f
        magic = read(f,8)
        @assert magic in [b"BRSMPGRP",b"NEURALCD",b"NEURALSG"]
    
        timestamp_bytes = (magic==b"BRSMPGRP" ? 64 : 32)
        
        uints = Dict(8=>UInt8,16=>UInt16,32=>UInt32,64=>UInt64)
        readint(n::Int) = Int(read(f,uints[n]))
    
        ver_major = readint(8)
        ver_minor = readint(8)
        header_size = readint(32)
        label = nullstring(read(f,16))
        comments = nullstring(read(f,256))
    
        sampling_period = readint(32)
        clock_frequency = readint(32)
        utc_time = begin
            year = readint(16)
            month = readint(16)
            dow = readint(16)
            day = readint(16)
            hour = readint(16)
            minute = readint(16)
            second = readint(16)
            ms = readint(16)
            DateTime(year,month,day,hour,minute,second,ms)
        end 
        num_channels = readint(32)  
    
        header = NxHeader(
            (ver_major,ver_minor),label,comments,
            0,clock_frequency / sampling_period,utc_time,num_channels
        )

        channel_headers = map(1:num_channels) do i
            channel_magic = read(f,2)
            @assert channel_magic == b"CC"

            id = readint(16)
            label = nullstring(read(f,16))
            frontend_id = readint(8)
            frontend_pin = readint(8)
            digital_min = read(f,Int16)
            digital_max = read(f,Int16)
            analog_min = read(f,Int16)
            analog_max = read(f,Int16)
            units = nullstring(read(f,16))
            highpass_freq = readint(32) # mHz
            highpass_order = readint(32)
            highpass_type = readint(16)
            # 0 = None, 1 = Butterworth, 2 = Chebyshev
            lowpass_freq = readint(32) # mHz
            lowpass_order = readint(32)
            lowpass_type = readint(16)

            gain = calc_gain(analog_min,analog_max,digital_min,digital_max)
            offset = calc_offset(gain,analog_max,digital_max)

            NxChannelHeader(
                id,label,frontend_id,frontend_pin,
                digital_min,digital_max,analog_min,analog_max,
                units,
                highpass_freq/1000,highpass_order,_nx_filtertype[highpass_type+1],
                lowpass_freq/1000,lowpass_order,_nx_filtertype[lowpass_type+1],
                gain,offset
            )
        end
        @assert position(f) == header_size

        packets = NxPacket[]
        while ! eof(f)
            @assert readint(8)==1

            timestamp = readint(timestamp_bytes)
            num_points = readint(32)

            data = map(1:num_points) do i
                map(1:num_channels) do c
                    read(f,Int16)
                end
            end

            data = collect(hcat(data...)')

            if applygain
                # This reads as Int's, so make a new Float matrix
                newdata = Matrix{Float64}(undef,size(data))
                for c=1:num_channels
                    newdata[:,c] .= physical.(data[:,c],channel_headers[c].gain,channel_headers[c].offset)
                end
                data = newdata
            end

            push!(packets,NxPacket(timestamp,data))

            
        end

    return NxFile(header,channel_headers,packets)
    end
end

"""
    function read_nev(fname::String)

Read the NEV file `fname` and return a [`NEVFile`](@ref).

This method is still under contruction. Several of the extended headers and packet types were
not implemented yet.

This method is based on the NEV 2.2 file format as specified by Ripple from their [documentation](https://rippleneuro.s3-us-west-2.amazonaws.com/downloads/documentation/NEVspec2_2_v07.pdf)
"""
function read_nev(fname::String)
    match(r"\.nev$",fname)==nothing && @warn("Attempting to load $fname as NEV, but suffix does not match!")

    open(fname) do f
        magic = read(f,8)
        @assert magic == b"NEURALEV"
    
        uints = Dict(8=>UInt8,16=>UInt16,32=>UInt32,64=>UInt64)
        readint(n::Int) = Int(read(f,uints[n]))

        ver_major = readint(8)
        ver_minor = readint(8)
        flagsbits = readint(16)
        flags = (
            spikewaveforms16bit = (flagsbits & 0x01)!=0,
        )
        header_size = readint(32)
    
        packet_size = readint(32)
    
        clock_frequency = readint(32)
        sample_frequency = readint(32)

        utc_time = begin
            year = readint(16)
            month = readint(16)
            dow = readint(16)
            day = readint(16)
            hour = readint(16)
            minute = readint(16)
            second = readint(16)
            ms = readint(16)
            DateTime(year,month,day,hour,minute,second,ms)
        end 
    
        application = nullstring(read(f,32))
        comment = nullstring(read(f,200))
        
        # reserved
        skip(f,52)
        
        timestamp = readint(32)
    
        num_headers = readint(32)
    
        extended_headers = NEVExtendedHeader[]
        for i=1:num_headers
            magic = read(f,8)
    
            if magic==b"DIGLABEL"
                label = nullstring(read(f,16))
                mode = readint(8)
                push!(extended_headers,NEVDigitalLabel(label,_nev_digitallabel_modes[mode]))
                skip(f,7)
                continue
            end
        
            @warn("Have not implemented Extended Header named \"$(String(magic))\" yet!")
            skip(f,24)
        end
        
        header = NEVHeader(
            (ver_major,ver_minor),flags,
            clock_frequency,sample_frequency,utc_time,
            application,comment,timestamp,
            extended_headers)
    
        @assert position(f) == header_size
    
        packets = NEVPacket[]
    
        while ! eof(f)
            timestamp = readint(32)
            id=readint(16)

            if id==0
                bitreason = read(f,UInt8)
                reason = (
                    parallel = (bitreason & 0x01)!=0,
                    sma1 = (bitreason & 0x02)!=0,
                    sma2 = (bitreason & 0x04)!=0,
                    sma3 = (bitreason & 0x08)!=0,
                    sma4 = (bitreason & 0x10)!=0,
                    periodic = (bitreason & 0x40)!=0,
                    serial = (bitreason & 0x80)!=0
                )
                skip(f,1)
                values = (
                    parallel = readint(16),
                    sma1 = read(f,Int16),
                    sma2 = read(f,Int16),
                    sma3 = read(f,Int16),
                    sma4 = read(f,Int16),
                )
                push!(packets,NEVDigitalInput(timestamp,reason,values))
                skip(f,packet_size - 18)
                continue
            end
        
            @warn("Have not implemented Packet with ID $id yet!")
            skip(f,packet_size - 6)
        end
        
        NEVFile(header,packets)
    end
end

end