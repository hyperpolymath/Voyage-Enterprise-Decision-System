using Test
using VEDSViz

@testset "VEDSViz" begin

    @testset "Data Types" begin
        seg = VEDSViz.Segment(
            "seg-1",
            31.2304, 121.4737,
            22.3193, 114.1694,
            :maritime,
            "COSCO",
            2500.0,
            48.0,
            850.0,
            1500
        )

        @test seg.id == "seg-1"
        @test seg.mode == :maritime
        @test seg.cost_usd == 2500.0
    end

    @testset "Sample Route Generation" begin
        route = VEDSViz.generate_sample_route()

        @test route.id == "route-001"
        @test length(route.segments) == 4
        @test route.total_cost > 0
        @test route.pareto_rank == 1
    end

    @testset "Haversine Distance" begin
        # Shanghai to Hong Kong
        dist = VEDSViz.haversine_distance(
            31.2304, 121.4737,
            22.3193, 114.1694
        )

        # Should be approximately 1200 km
        @test 1100 < dist < 1300
    end

    @testset "Color Schemes" begin
        @test haskey(VEDSViz.MODE_COLORS, :maritime)
        @test haskey(VEDSViz.MODE_COLORS, :rail)
        @test haskey(VEDSViz.MODE_COLORS, :road)
        @test haskey(VEDSViz.MODE_COLORS, :air)
    end

end
