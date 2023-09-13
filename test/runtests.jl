using Ripple
using Test

using BSON,Dates

nfx_file = read_nfx(joinpath(@__DIR__,"test.nf3"))
bson_data = BSON.load(joinpath(@__DIR__,"test.bson"))[:data]

@testset "Ripple.jl" begin
    @test nfx_file.header.application==""
    @test nfx_file.header.comments=="1.14.4.41 Trellis[]"
    @test nfx_file.header.num_channels==1
    @test nfx_file.header.label=="2 ksamp/sec"
    @test nfx_file.header.sampling_frequency==2000.0
    @test nfx_file.header.timestamp==159923640
    @test nfx_file.header.utc_time==DateTime(2023,9,13,0,11,33,846)
    @test nfx_file.header.version==(2,2)
    @test length(nfx_file.channel_headers)==1
    @test nfx_file.channel_headers[1].analog_max==18487
    @test nfx_file.channel_headers[1].analog_min==5977
    @test nfx_file.channel_headers[1].digital_max==-14281
    @test nfx_file.channel_headers[1].digital_min==5977
    @test nfx_file.channel_headers[1].frontend_id==0
    @test nfx_file.channel_headers[1].frontend_pin==1
    @test nfx_file.channel_headers[1].highpass_freq==0.1
    @test nfx_file.channel_headers[1].highpass_order==2
    @test nfx_file.channel_headers[1].highpass_type==:Butterworth
    @test nfx_file.channel_headers[1].id==1
    @test nfx_file.channel_headers[1].label=="hi-res 1"
    @test nfx_file.channel_headers[1].lowpass_freq==500.0
    @test nfx_file.channel_headers[1].lowpass_order==4
    @test nfx_file.channel_headers[1].lowpass_type==:Butterworth
    @test nfx_file.channel_headers[1].units=="uV"
    @test length(nfx_file.data_packets)==1
    @test nfx_file.data_packets[1].timestamp==0
    @test nfx_file.data_packets[1].data==bson_data
end
