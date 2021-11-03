module PropertyDestructuringTest

using PropertyDestructuring
using Test

struct Point2D{T}
    x::T
    y::T
end

struct Point3D{T}
    x::T
    y::T
    z::T
end

@testset "PropertyDestructuring.jl" begin

    @testset "Assignment" begin
        pt1 = Point2D(1, 2)
        @destructure (; x, y) = pt1
        @test x == 1
        @test y == 2

        pt2 = Point2D(3.14, 9.99)
        @destructure (; x, y) = pt2
        @test x == 3.14
        @test y == 9.99

        pt3 = Point3D(1.2, 3.4, 5.6)
        @destructure (; x, y) = pt3
        @test x == 1.2
        @test y == 3.4

        @destructure (; x, y) = (x=:x, y="歪")
        @test x === :x
        @test y == "歪"
    end

    @testset "Complex Assignment" begin
        pt1 = Point2D(1, 2)
        @destructure (_DUMMY, (; x, y)) = (:DUMMY, pt1)
        @test x == 1
        @test y == 2

        pt2 = Point2D(3.14, 9.99)
        @destructure ((; x, y), _DUMMY) = (pt2, :DUMMY)
        @test x == 3.14
        @test y == 9.99

        pt3 = Point3D(1.2, 3.4, 5.6)
        @destructure ((; x, y), ((; z, w), _DUMMY)) = (pt3, ((z=:z, w="W"), :DUMMY))
        @test x == 1.2
        @test y == 3.4
        @test z === :z
        @test w == "W"
    end

    @testset "Function Argument (1)" begin
        @destructure function _test1((; x, y))
            (x, y)
        end

        pt1 = Point2D(1, 2)
        x, y = _test1(pt1)
        @test x == 1
        @test y == 2

        pt2 = Point2D(3.14, 9.99)
        x, y = _test1(pt2)
        @test x == 3.14
        @test y == 9.99

        pt3 = Point3D(1.2, 3.4, 5.6)
        x, y = _test1(pt3)
        @test x == 1.2
        @test y == 3.4

        x, y = _test1((x=:x, y="歪"))
        @test x === :x
        @test y == "歪"
    end

    @testset "Function Argument (2)" begin
        @destructure _test2((; x, y)) = (x, y)

        pt1 = Point2D(1, 2)
        x, y = _test2(pt1)
        @test x == 1
        @test y == 2

        pt2 = Point2D(3.14, 9.99)
        x, y = _test2(pt2)
        @test x == 3.14
        @test y == 9.99

        pt3 = Point3D(1.2, 3.4, 5.6)
        x, y = _test2(pt3)
        @test x == 1.2
        @test y == 3.4

        x, y = _test2((x=:x, y="歪"))
        @test x === :x
        @test y == "歪"
    end

    @testset "`in` clause of `for`" begin
        pts = [
            Point2D(1, 2),
            Point2D(3.14, 9.99),
            Point3D(1.2, 3.4, 5.6),
            (x=:x, y="歪"),
        ]

        index = 1
        @destructure for (; x, y) in pts
            @test x == pts[index].x
            @test y == pts[index].y
            index += 1
        end

        @destructure for (pt, (; x, y)) in zip(pts, pts)
            @test x == pt.x
            @test y == pt.y
        end

        index = 1
        @destructure for (; x, y) in pts, _DUMMY in 1
            @test x == pts[index].x
            @test y == pts[index].y
            index += 1
        end

        @destructure for (pt, (; x, y)) in zip(pts, pts), _DUMMY in 1
            @test x == pt.x
            @test y == pt.y
        end
    end
end

end  # module