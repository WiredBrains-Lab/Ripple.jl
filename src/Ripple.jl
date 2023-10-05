module Ripple

export NxChannelHeader,NxHeader,NxPacket,NxFile
export read_nfx,read_nsx

using Dates

"""
    nullstring(x::Vector{UInt8})

    Trim an `unsigned char` string to its NULL termination.
"""
nullstring(x::Vector{UInt8}) = String(x[1:findfirst(==(0), x) - 1])

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

"""
    function read_nfx(fname::String)

Read the NFx file `fname` and return a [`NxFile`](@ref).
"""
function read_nfx(fname::String)
    match(r"\.nf[1-9]$",fname)==nothing && warn("Attempting to load $fname as NFx, but suffix does not match!")

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

            NxChannelHeader(
                id,label,frontend_id,frontend_pin,
                digital_min,digital_max,analog_min,analog_max,
                units,
                highpass_freq/1000,highpass_order,_nx_filtertype[highpass_type+1],
                lowpass_freq/1000,lowpass_order,_nx_filtertype[lowpass_type+1],
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

            push!(packets,NxPacket(timestamp,hcat(data...)))
        end

        return NxFile(header,channel_headers,packets)
    end
end


"""
    function read_nsx(fname::String)

Read the NSx file `fname` and return a [`NxFile`](@ref).
"""
function read_nsx(fname::String)
    match(r"\.ns[1-9]$",fname)==nothing && warn("Attempting to load $fname as NSx, but suffix does not match!")

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

            NxChannelHeader(
                id,label,frontend_id,frontend_pin,
                digital_min,digital_max,analog_min,analog_max,
                units,
                highpass_freq/1000,highpass_order,_nx_filtertype[highpass_type+1],
                lowpass_freq/1000,lowpass_order,_nx_filtertype[lowpass_type+1],
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

            push!(packets,NxPacket(timestamp,hcat(data...)))

            
        end

    return NxFile(header,channel_headers,packets)
    end
end

end