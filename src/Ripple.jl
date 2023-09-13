module Ripple

export NFxChannelHeader,NFxHeader,NFxPacket,NFxFile
export read_nfx

using Dates

"""
    nullstring(x::Vector{UInt8})

    Trim an `unsigned char` string to its NULL termination.
"""
nullstring(x::Vector{UInt8}) = String(x[1:findfirst(==(0), x) - 1])

_nfx_filtertype = [:none,:Butterworth,:Chebyshev]

struct NFxChannelHeader
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

struct NFxHeader
    version::Tuple{Int,Int}
    label::String
    comments::String
    application::String
    timestamp::Int
    sampling_frequency::Float64
    utc_time::DateTime
    num_channels::Int
end

"""
    NFxPacket(timestamp::Int,data::Matrix{Float32})

Individual data packet (potentially multiple per file). The `timestamp` is the temporal offset
of this packet (using the processor `clock_frequency`) and `data is a 2D, "time" x "channel" `Matrix`.
"""
struct NFxPacket
    timestamp::Int
    data::Matrix{Float32}
end

"""
    NFxFile(
        header::NFxHeader,
        channel_headers::Vector{NFxChannelHeader}
        data_packets::Vector{NFxPacket}
    )

Object containing the NFx file header, a `Vector` of individual channel headers,
and a `Vector` of [`NFxPacket`](@ref)'s found in the file.
"""
struct NFxFile
    header::NFxHeader
    channel_headers::Vector{NFxChannelHeader}
    data_packets::Vector{NFxPacket}
end

"""
    function read_nfx(fname::String)

Read the NFx file `fname` and return a [`NFxFile`](@ref).
"""
function read_nfx(fname::String)
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

        header = NFxHeader(
            (ver_major,ver_minor),label,comments,app,
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

            NFxChannelHeader(
                id,label,frontend_id,frontend_pin,
                digital_min,digital_max,analog_min,analog_max,
                units,
                highpass_freq/1000,highpass_order,_nfx_filtertype[highpass_type+1],
                lowpass_freq/1000,lowpass_order,_nfx_filtertype[lowpass_type+1],
            )
        end
        @assert position(f) == header_size

        packets = NFxPacket[]
        while ! eof(f)
            @assert readint(8)==1

            timestamp = readint(32)
            num_points = readint(32)

            data = map(1:num_channels) do c
                map(1:num_points) do i
                    read(f,Float32)
                end
            end

            push!(packets,NFxPacket(timestamp,hcat(data...)))
        end

        return NFxFile(header,channel_headers,packets)
    end
end

end
