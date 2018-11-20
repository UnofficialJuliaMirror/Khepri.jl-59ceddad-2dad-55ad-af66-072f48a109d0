export unity,
       unity_material_family

macro unity_str(str)
    rpc("Unity", str)
end

# We need some additional Encoders
encode_GameObject = encode_int
decode_GameObject = decode_int_or_error
encode_GameObject_array = encode_int_array
decode_GameObject_array = decode_int_array

encode_Material = encode_int
decode_Material = decode_int_or_error

# Must convert from local to world coordinates
encode_Vector3(c::IO, v::Union{XYZ, VXYZ}) = begin
  v = in_world(v)
#  encode_float3(c, v.x, v.y, v.z)
  encode_float3(c, v.x, v.z, v.y)
end
decode_Vector3(c::IO) =
  let x = decode_float(c)
      z = decode_float(c)
      y = decode_float(c)
    xyz(x, y, z, world_cs)
  end
encode_Vector3_array(c::IO, v::Vector) = begin
  encode_int(c, length(v))
  for e in v encode_Vector3(c, e) end
end
decode_Vector3_array(c::IO) = begin
  len = decode_int_or_error(c)
  r = Vector{XYZ}(undef, len)
  for i in 1:len
    r[i] = decode_Vector3(c)
  end
  r
end

encode_Vector3_array_array(c::IO, v::Vector) = begin
  encode_int(c, length(v))
  for e in v encode_Vector3_array(c, e) end
end
decode_Vector3_array_array(c::IO) = begin
  len = decode_int_or_error(c)
  r = Vector{Vector{XYZ}}(undef, len)
  for i in 1:len
    r[i] = decode_Vector3_array(c)
  end
  r
end


#=
encode_Quaternion(c::IO, pv::Union{XYZ, VXYZ}) =
  let tr = pv.cs.transform
    for i in 1:3
      for j in 1:3
        encode_float(c, tr[i,j])
      end
    end
  end
=#

abstract type UnityKey end
const UnityId = Int
const UnityIds = Vector{UnityId}
const UnityRef = GenericRef{UnityKey, UnityId}
const UnityRefs = Vector{UnityRef}
const UnityEmptyRef = EmptyRef{UnityKey, UnityId}
const UnityUniversalRef = UniversalRef{UnityKey, UnityId}
const UnityNativeRef = NativeRef{UnityKey, UnityId}
const UnityUnionRef = UnionRef{UnityKey, UnityId}
const UnitySubtractionRef = SubtractionRef{UnityKey, UnityId}
const Unity = SocketBackend{UnityKey, UnityId}

void_ref(b::Unity) = UnityNativeRef(-1)

create_Unity_connection() =
    begin
        #check_plugin()
        create_backend_connection("Unity", 11002)
    end

const unity = Unity(LazyParameter(TCPSocket, create_Unity_connection))

backend_name(b::Unity) = "Unity"

realize(b::Unity, s::EmptyShape) =
  UnityEmptyRef()
realize(b::Unity, s::UniversalShape) =
  UnityUniversalRef()

#=
realize(b::Unity, s::Point) =
  UnityPoint(connection(b), s.position)
realize(b::Unity, s::Line) =
  UnityPolyLine(connection(b), s.vertices)
realize(b::Unity, s::Spline) =
  if (s.v0 == false) && (s.v1 == false)
    #UnitySpline(connection(b), s.points)
    UnityInterpSpline(connection(b),
                     s.points,
                     s.points[2]-s.points[1],
                     s.points[end]-s.points[end-1])
  elseif (s.v0 != false) && (s.v1 != false)
    UnityInterpSpline(connection(b), s.points, s.v0, s.v1)
  else
    UnityInterpSpline(connection(b),
                     s.points,
                     s.v0 == false ? s.points[2]-s.points[1] : s.v0,
                     s.v1 == false ? s.points[end-1]-s.points[end] : s.v1)
  end
realize(b::Unity, s::ClosedSpline) =
  UnityInterpClosedSpline(connection(b), s.points)
realize(b::Unity, s::Circle) =
  UnityCircle(connection(b), s.center, vz(1, s.center.cs), s.radius)
realize(b::Unity, s::Arc) =
  if s.radius == 0
    UnityPoint(connection(b), s.center)
  elseif s.amplitude == 0
    UnityPoint(connection(b), s.center + vpol(s.radius, s.start_angle, s.center.cs))
  elseif abs(s.amplitude) >= 2*pi
    UnityCircle(connection(b), s.center, vz(1, s.center.cs), s.radius)
  else
    end_angle = s.start_angle + s.amplitude
    if end_angle > s.start_angle
      UnityArc(connection(b), s.center, vz(1, s.center.cs), s.radius, s.start_angle, end_angle)
    else
      UnityArc(connection(b), s.center, vz(1, s.center.cs), s.radius, end_angle, s.start_angle)
    end
  end

realize(b::Unity, s::Ellipse) =
  if s.radius_x > s.radius_y
    UnityEllipse(connection(b), s.center, vz(1, s.center.cs), vxyz(s.radius_x, 0, 0, s.center.cs), s.radius_y/s.radius_x)
  else
    UnityEllipse(connection(b), s.center, vz(1, s.center.cs), vxyz(0, s.radius_y, 0, s.center.cs), s.radius_x/s.radius_y)
  end
realize(b::Unity, s::EllipticArc) =
  error("Finish this")

realize(b::Unity, s::Polygon) =
  UnityClosedPolyLine(connection(b), s.vertices)
realize(b::Unity, s::RegularPolygon) =
  UnityClosedPolyLine(connection(b), regular_polygon_vertices(s.edges, s.center, s.radius, s.angle, s.inscribed))
realize(b::Unity, s::Rectangle) =
  UnityClosedPolyLine(
    connection(b),
    [s.corner,
     add_x(s.corner, s.dx),
     add_xy(s.corner, s.dx, s.dy),
     add_y(s.corner, s.dy)])
realize(b::Unity, s::SurfaceCircle) =
  UnitySurfaceCircle(connection(b), s.center, vz(1, s.center.cs), s.radius)
realize(b::Unity, s::SurfaceArc) =
    #UnitySurfaceArc(connection(b), s.center, vz(1, s.center.cs), s.radius, s.start_angle, s.start_angle + s.amplitude)
    if s.radius == 0
        UnityPoint(connection(b), s.center)
    elseif s.amplitude == 0
        UnityPoint(connection(b), s.center + vpol(s.radius, s.start_angle, s.center.cs))
    elseif abs(s.amplitude) >= 2*pi
        UnitySurfaceCircle(connection(b), s.center, vz(1, s.center.cs), s.radius)
    else
        end_angle = s.start_angle + s.amplitude
        if end_angle > s.start_angle
            UnitySurfaceFromCurves(connection(b),
                [UnityArc(connection(b), s.center, vz(1, s.center.cs), s.radius, s.start_angle, end_angle),
                 UnityPolyLine(connection(b), [add_pol(s.center, s.radius, end_angle),
                                              add_pol(s.center, s.radius, s.start_angle)])])
        else
            UnitySurfaceFromCurves(connection(b),
                [UnityArc(connection(b), s.center, vz(1, s.center.cs), s.radius, end_angle, s.start_angle),
                 UnityPolyLine(connection(b), [add_pol(s.center, s.radius, s.start_angle),
                                              add_pol(s.center, s.radius, end_angle)])])
        end
    end

#realize(b::Unity, s::SurfaceElliptic_Arc) = UnityCircle(connection(b),
#realize(b::Unity, s::SurfaceEllipse) = UnityCircle(connection(b),
=#

unity"public GameObject SurfacePolygon(Vector3[] ps)"

realize(b::Unity, s::SurfacePolygon) =
  UnitySurfacePolygon(connection(b), reverse(s.vertices))
#=
realize(b::Unity, s::SurfaceRegularPolygon) =
  UnitySurfaceClosedPolyLine(connection(b), regular_polygon_vertices(s.edges, s.center, s.radius, s.angle, s.inscribed))
realize(b::Unity, s::SurfaceRectangle) =
  UnitySurfaceClosedPolyLine(
    connection(b),
    [s.corner,
     add_x(s.corner, s.dx),
     add_xy(s.corner, s.dx, s.dy),
     add_y(s.corner, s.dy)])
realize(b::Unity, s::Surface) =
  let #ids = map(r->UnityNurbSurfaceFrom(connection(b),r), UnitySurfaceFromCurves(connection(b), collect_ref(s.frontier)))
      ids = UnitySurfaceFromCurves(connection(b), collect_ref(s.frontier))
    foreach(mark_deleted, s.frontier)
    ids
  end
backend_surface_boundary(b::Unity, s::Shape2D) =
    map(shape_from_ref, UnityCurvesFromSurface(connection(b), ref(s).value))

# Iterating over curves and surfaces

Unity"public double[] CurveDomain(Entity ent)"
Unity"public double CurveLength(Entity ent)"
Unity"public Frame3d CurveFrameAt(Entity ent, double t)"
Unity"public Frame3d CurveFrameAtLength(Entity ent, double l)"

backend_map_division(b::Unity, f::Function, s::Shape1D, n::Int) =
    let conn = connection(b)
        r = ref(s).value
        (t1, t2) = UnityCurveDomain(conn, r)
        map_division(t1, t2, n) do t
            f(UnityCurveFrameAt(conn, r, t))
        end
    end


Unity"public Vector3d RegionNormal(Entity ent)"
Unity"public Point3d RegionCentroid(Entity ent)"
Unity"public double[] SurfaceDomain(Entity ent)"
Unity"public Frame3d SurfaceFrameAt(Entity ent, double u, double v)"

backend_surface_domain(b::Unity, s::Shape2D) =
    tuple(UnitySurfaceDomain(connection(b), ref(s).value)...)

backend_map_division(b::Unity, f::Function, s::Shape2D, nu::Int, nv::Int) =
    let conn = connection(b)
        r = ref(s).value
        (u1, u2, v1, v2) = UnitySurfaceDomain(conn, r)
        map_division(u1, u2, nu) do u
            map_division(v1, v2, nv) do v
                f(UnitySurfaceFrameAt(conn, r, u, v))
            end
        end
    end

# The previous method cannot be applied to meshes in AutoCAD, which are created by surface_grid

backend_map_division(b::Unity, f::Function, s::SurfaceGrid, nu::Int, nv::Int) =
    let (u1, u2, v1, v2) = UnitySurfaceDomain(conn, r)
        map_division(u1, u2, nu) do u
            map_division(v1, v2, nv) do v
                f(UnitySurfaceFrameAt(conn, r, u, v))
            end
        end
    end

realize(b::Unity, s::Text) =
  UnityText(
    connection(b),
    s.str, s.corner, vx(1, s.corner.cs), vy(1, s.corner.cs), s.height)
=#

unity"public GameObject Sphere(Vector3 center, float radius)"

realize(b::Unity, s::Sphere) =
  UnitySphere(connection(b), s.center, s.radius)

#=
realize(b::Unity, s::Torus) =
  UnityTorus(connection(b), s.center, vz(1, s.center.cs), s.re, s.ri)
=#

unity"public GameObject Pyramid(Vector3[] ps, Vector3 q)"
unity"public GameObject PyramidFrustum(Vector3[] ps, Vector3[] qs)"

realize(b::Unity, s::Cuboid) =
  UnityPyramidFrustum(connection(b), [s.b0, s.b1, s.b2, s.b3], [s.t0, s.t1, s.t2, s.t3])

realize(b::Unity, s::RegularPyramidFrustum) =
    UnityPyramidFrustum(connection(b),
                        regular_polygon_vertices(s.edges, s.cb, s.rb, s.angle, s.inscribed),
                        regular_polygon_vertices(s.edges, add_z(s.cb, s.h), s.rt, s.angle, s.inscribed))

realize(b::Unity, s::RegularPyramid) =
  UnityPyramid(connection(b),
               regular_polygon_vertices(s.edges, s.cb, s.rb, s.angle, s.inscribed),
               add_z(s.cb, s.h))

realize(b::Unity, s::IrregularPyramid) =
  UnityPyramid(connection(b), s.cbs, s.ct)

realize(b::Unity, s::RegularPrism) =
  let cbs = regular_polygon_vertices(s.edges, s.cb, s.r, s.angle, s.inscribed)
    UnityPyramidFrustum(connection(b),
                        cbs,
                        map(p -> add_z(p, s.h), cbs))
  end

realize(b::Unity, s::IrregularPyramidFustrum) =
    UnityPyramidFrustum(connection(b), s.cbs, s.cts)

realize(b::Unity, s::IrregularPrism) =
  UnityPyramidFrustum(connection(b),
                      s.cbs,
                      map(p -> (p + s.v), s.cbs))

unity"public GameObject RightCuboid(Vector3 position, Vector3 vx, Vector3 vy, float dx, float dy, float dz, float angle)"

realize(b::Unity, s::RightCuboid) =
  UnityRightCuboid(connection(b), s.cb, vz(1, s.cb.cs), vx(1, s.cb.cs), s.height, s.width, s.h, s.angle)

unity"public GameObject Box(Vector3 position, Vector3 vx, Vector3 vy, float dx, float dy, float dz)"

realize(b::Unity, s::Box) =
  UnityBox(connection(b), s.c, vz(1, s.c.cs), vx(1, s.c.cs), s.dy, s.dx, s.dz)

realize(b::Unity, s::Cone) =
  UnityPyramid(connection(b), regular_polygon_vertices(64, s.cb, s.r), add_z(s.cb, s.h))

realize(b::Unity, s::ConeFrustum) =
  UnityPyramidFrustum(connection(b), regular_polygon_vertices(64, cb, s.rb), regular_polygon_vertices(64, s.cb + vz(s.h, s.cb.cs), s.rt))

unity"public GameObject Cylinder(Vector3 bottom, float radius, Vector3 top)"

realize(b::Unity, s::Cylinder) =
  UnityCylinder(connection(b), s.cb, s.r, s.cb + vz(s.h, s.cb.cs))

#=
backend_extrusion(b::Unity, s::Shape, v::Vec) =
    and_mark_deleted(
        map_ref(s) do r
            UnityExtrude(connection(b), r, v)
        end,
        s)

backend_sweep(b::Unity, path::Shape, profile::Shape, rotation::Real, scale::Real) =
  map_ref(profile) do profile_r
    map_ref(path) do path_r
      UnitySweep(connection(b), path_r, profile_r, rotation, scale)
    end
  end

realize(b::Unity, s::Revolve) =
  and_delete_shape(
    map_ref(s.profile) do r
      UnityRevolve(connection(b), r, s.p, s.n, s.start_angle, s.amplitude)
    end,
    s.profile)

backend_loft_curves(b::Unity, profiles::Shapes, rails::Shapes, ruled::Bool, closed::Bool) =
  and_delete_shapes(UnityLoft(connection(b),
                             collect_ref(profiles),
                             collect_ref(rails),
                             ruled, closed),
                    vcat(profiles, rails))

backend_loft_surfaces(b::Unity, profiles::Shapes, rails::Shapes, ruled::Bool, closed::Bool) =
    backend_loft_curves(b, profiles, rails, ruled, closed)

backend_loft_curve_point(b::Unity, profile::Shape, point::Shape) =
    and_delete_shapes(UnityLoft(connection(b),
                               vcat(collect_ref(profile), collect_ref(point)),
                               [],
                               true, false),
                      [profile, point])

backend_loft_surface_point(b::Unity, profile::Shape, point::Shape) =
    backend_loft_curve_point(b, profile, point)

unite_ref(b::Unity, r0::UnityNativeRef, r1::UnityNativeRef) =
    ensure_ref(b, UnityUnite(connection(b), r0.value, r1.value))

intersect_ref(b::Unity, r0::UnityNativeRef, r1::UnityNativeRef) =
    ensure_ref(b, UnityIntersect(connection(b), r0.value, r1.value))

subtract_ref(b::Unity, r0::UnityNativeRef, r1::UnityNativeRef) =
    ensure_ref(b, UnitySubtract(connection(b), r0.value, r1.value))

slice_ref(b::Unity, r::UnityNativeRef, p::Loc, v::Vec) =
    (UnitySlice(connection(b), r.value, p, v); r)

slice_ref(b::Unity, r::UnityUnionRef, p::Loc, v::Vec) =
    map(r->slice_ref(b, r, p, v), r.values)

=#
unite_refs(b::Unity, refs::Vector{<:UnityRef}) =
    UnityUnionRef(tuple(refs...))

#=
realize(b::Unity, s::IntersectionShape) =
    foldl((r0,r1)->intersect_ref(b,r0,r1), map(ref, s.shapes), init=UnityUniversalRef())

realize(b::Unity, s::Slice) =
  slice_ref(b, ref(s.shape), s.p, s.n)

=#

unity"public void Move(GameObject s, Vector3 v)"
unity"public void Scale(GameObject s, Vector3 p, float scale)"
unity"public void Rotate(GameObject s, Vector3 p, Vector3 n, float a)"

realize(b::Unity, s::Move) =
  let r = map_ref(s.shape) do r
            UnityMove(connection(b), r, s.v)
            r
          end
    mark_deleted(s.shape)
    r
  end
#=
realize(b::Unity, s::Transform) =
  let r = map_ref(s.shape) do r
            UnityTransform(connection(b), r, s.xform)
            r
          end
    mark_deleted(s.shape)
    r
  end
=#
realize(b::Unity, s::Scale) =
  let r = map_ref(s.shape) do r
            UnityScale(connection(b), r, s.p, s.s)
            r
          end
    mark_deleted(s.shape)
    r
  end

realize(b::Unity, s::Rotate) =
  let r = map_ref(s.shape) do r
            UnityRotate(connection(b), r, s.p, s.v, s.angle)
            r
          end
    mark_deleted(s.shape)
    r
  end

#=
realize(b::Unity, s::Mirror) =
  and_delete_shape(map_ref(s.shape) do r
                    UnityMirror(connection(b), r, s.p, s.n, false)
                   end,
                   s.shape)

realize(b::Unity, s::UnionMirror) =
  let r0 = ref(s.shape),
      r1 = map_ref(s.shape) do r
            UnityMirror(connection(b), r, s.p, s.n, true)
          end
    UnionRef((r0,r1))
  end

realize(b::Unity, s::SurfaceGrid) =
    UnitySurfaceFromGrid(
        connection(b),
        size(s.points,1),
        size(s.points,2),
        reshape(s.points,:),
        s.closed_u,
        s.closed_v,
        2)

realize(b::Unity, s::Thicken) =
  and_delete_shape(
    map_ref(s.shape) do r
      UnityThicken(connection(b), r, s.thickness)
    end,
    s.shape)

# backend_frame_at
backend_frame_at(b::Unity, s::Circle, t::Real) = add_pol(s.center, s.radius, t)

backend_frame_at(b::Unity, c::Shape1D, t::Real) = UnityCurveFrameAt(connection(b), ref(c).value, t)

#backend_frame_at(b::Unity, s::Surface, u::Real, v::Real) =
    #What should we do with v?
#    backend_frame_at(b, s.frontier[1], u)

#backend_frame_at(b::Unity, s::SurfacePolygon, u::Real, v::Real) =

backend_frame_at(b::Unity, s::Shape2D, u::Real, v::Real) = UnitySurfaceFrameAt(connection(b), ref(s).value, u, v)

=#

# BIM

# Families
#=

Revit families are divided into
1. System Families (for walls, roofs, floors, pipes)
2. Loadable Families (for building components that have an associated file)
3. In-Place Families (for unique elements created just for the current project)

=#

abstract type UnityFamily <: Family end

struct UnityMaterialFamily <: UnityFamily
  name::String
  parameter_map::Dict{Symbol,String}
  ref::Parameter{Int}
end

unity_material_family(name, pairs...) = UnityMaterialFamily(name, Dict(pairs...), Parameter(-1))

backend_get_family(b::Unity, f::UnityMaterialFamily) = UnityLoadMaterial(connection(b), f.name)

backend_get_family(b::Unity, f::Family) =
  let unity_family = f.based_on # This needs to be fixed
    if unity_family == nothing
      error("Missing Unity family for $f")
    else
      backend_get_family(b, unity_family)
    end
  end

#

unity_wall_family = wall_family(based_on=unity_material_family("Materials/Concrete"))
unity_slab_family = slab_family(based_on=unity_material_family("Materials/Concrete"))
unity_beam_family = beam_family(based_on=unity_material_family("Materials/Metal"))
unity_column_family = column_family(based_on=unity_material_family("Materials/Concrete"))
unity_door_family = door_family(based_on=unity_material_family("Materials/Wood1"))

switch_to_backend(from::Backend, to::Unity) =
    let height = 0
        current_backend(to)
        default_slab_family(unity_slab_family)
        default_wall_family(unity_wall_family)
        default_beam_family(unity_beam_family)
        default_column_family(unity_column_family)
        default_door_family(unity_door_family)
        to
    end

unity"public GameObject LoadResource(String name)"
unity"public Material LoadMaterial(String name)"
unity"public void SetCurrentMaterial(Material material)"

unity"public GameObject InstantiateResource(GameObject family, Vector3 pos, Vector3 vx, Vector3 vy, float scale)"
unity"public GameObject InstantiateBIMElement(GameObject family, Vector3 pos, float angle)"

unity"public GameObject Window(Vector3 position, Quaternion rotation, float dx, float dy, float dz)"
unity"public GameObject Shelf(Vector3 position, int rowLength, int lineLength, float cellWidth, float cellHeight, float cellDepth)"


backend_get_family(b::Unity, f::TableFamily) =
    UnityLoadResource(connection(b), "ModernTable")

backend_get_family(b::Unity, f::ChairFamily) =
    UnityLoadResource(connection(b), "ModernChair")

backend_get_family(b::Unity, f::TableChairFamily) =
    UnityLoadResource(connection(b), "ModernTableChair")

backend_rectangular_table(b::Unity, c, angle, family) =
    UnityInstantiateBIMElement(connection(b), ref(family), c, -angle)

backend_chair(b::Unity, c, angle, family) =
    UnityInstantiateBIMElement(connection(b), ref(family), c, -angle)

backend_rectangular_table_and_chairs(b::Khepri.Unity, c, angle, family) =
    UnityInstantiateBIMElement(connection(b), ref(family), c, -angle)

unity"public GameObject Slab(Vector3[] contour, Vector3[][] holes, float h, Material material)"

backend_slab(b::Unity, profile, holes, thickness, family) =
  let bot_vs = path_vertices(profile)
      c = connection(b)
    UnitySlab(c, bot_vs, map(path_vertices, holes), thickness, ref(family))
  end

unity"public GameObject BeamRectSection(Vector3 position, Vector3 vx, Vector3 vy, float dx, float dy, float dz, float angle, Material material)"
unity"public GameObject BeamCircSection(Vector3 bot, float radius, Vector3 top, Material material)"

#Beams are aligned along the top axis.
realize(b::Unity, s::Beam) =
  let c = s.cb #add_y(s.cb, -s.family.height/2)
    UnityBeamRectSection(connection(b), c, vz(1, c.cs), vx(1, c.cs), s.family.height, s.family.width, s.h, s.angle, ref(s.family))
  end

#Columns are aligned along the center axis.
realize(b::Unity, s::Column) =
  let c = s.cb #add_y(s.cb, -s.family.height/2)
    UnityBeamRectSection(connection(b), c, vz(1, c.cs), vx(1, c.cs), s.family.height, s.family.width, s.h, s.angle, ref(s.family))
  end

###

sweep_fractions(b, verts, height, thickness) =
    let p = add_z(verts[1], height/2)
        q = add_z(verts[2], height/2)
        (c, h) = position_and_height(p, q)
        s = UnityNativeRef(UnityRightCuboid(connection(b), c, vz(1, c.cs), vx(1, c.cs), height, thickness, h, 0))
        if length(verts) > 2
          (s, sweep_fractions(b, verts[2:end], height, thickness)...)
        else
          (s, )
        end
    end

backend_wall(b::Unity, path, height, thickness, family) =
  let c = connection(b)
    UnitySetCurrentMaterial(c, ref(family))
    backend_wall_path(b, path, height, thickness)
  end

backend_wall_path(b::Unity, path::OpenPolygonalPath, height, thickness) =
    UnityUnionRef(sweep_fractions(b, path.vertices, height, thickness))

############################################
#=
backend_bounding_box(b::Unity, shapes::Shapes) =
  UnityBoundingBox(connection(b), collect_ref(shapes))
=#

unity"public void SetView(Vector3 position, Vector3 target, float lens)"

set_view(camera::Loc, target::Loc, lens::Real, b::Unity) =
  UnitySetView(connection(b), camera, target, lens)
#=
get_view(b::Unity) =
  let c = connection(b)
    UnityViewCamera(c), UnityViewTarget(c), UnityViewLens(c)
  end

zoom_extents(b::Unity) = UnityZoomExtents(connection(b))

view_top(b::Unity) = UnityViewTop(connection(b))

backend_delete_shapes(b::Unity, shapes::Shapes) =
  UnityDeleteMany(connection(b), collect_ref(shapes))
=#

unity"public void DeleteAll()"

delete_all_shapes(b::Unity) = UnityDeleteAll(connection(b))


#=
set_length_unit(unit::String, b::Unity) = UnitySetLengthUnit(connection(b), unit)

# Dimensions

const UnityDimensionStyles = Dict(:architectural => "_ARCHTICK", :mechanical => "")

dimension(p0::Loc, p1::Loc, p::Loc, scale::Real, style::Symbol, b::Unity=current_backend()) =
    UnityCreateAlignedDimension(connection(b), p0, p1, p,
        scale,
        UnityDimensionStyles[style])

dimension(p0::Loc, p1::Loc, sep::Real, scale::Real, style::Symbol, b::Unity=current_backend()) =
    let v = p1 - p0
        angle = pol_phi(v)
        dimension(p0, p1, add_pol(p0, sep, angle + pi/2), scale, style, b)
    end

# Layers
UnityLayer = Int

current_layer(b::Unity=current_backend())::UnityLayer =
  UnityCurrentLayer(connection(b))

current_layer(layer::UnityLayer, b::Unity=current_backend()) =
  UnitySetCurrentLayer(connection(b), layer)

create_layer(name::String, b::Unity=current_backend()) =
  UnityCreateLayer(connection(b), name)

create_layer(name::String, color::RGB, b::Unity=current_backend()) =
  let layer = UnityCreateLayer(connection(b), name)
    UnitySetLayerColor(connection(b), layer, color.r, color.g, color.b)
    layer
  end
=#

# Materials

UnityMaterial = Int

unity"public Material LoadMaterial(String name)"
unity"public void SetCurrentMaterial(Material material)"
unity"public Material CurrentMaterial()"

current_material(b::Unity=current_backend())::UnityMaterial =
  UnityCurrentMaterial(connection(b))

current_material(material::UnityMaterial, b::Unity=current_backend()) =
  UnitySetCurrentMaterial(connection(b), material)

get_material(name::String, b::Unity=current_backend()) =
  UnityLoadMaterial(connection(b), name)


# Blocks

unity"public GameObject CreateBlockInstance(GameObject block, Vector3 position, Vector3 vx, Vector3 vy, float scale)"
unity"public GameObject CreateBlockFromShapes(String name, GameObject[] objs)"

realize(b::Unity, s::Block) =
    UnityCreateBlockFromShapes(connection(b), s.name, collect_ref(s.shapes))

realize(b::Unity, s::BlockInstance) =
    UnityCreateBlockInstance(
        connection(b),
        ref(s.block).value,
        s.loc, vy(1, s.loc.cs), vz(1, s.loc.cs), s.scale)
#=

# Manual process
@time for i in 1:1000 for r in 1:10 circle(x(i*10), r) end end

# Create block...
Khepri.create_block("Foo", [circle(radius=r) for r in 1:10])

# ...and instantiate it
@time for i in 1:1000 Khepri.instantiate_block("Foo", x(i*10), 0) end

=#
#=
# Lights
Unity"public Entity SpotLight(Point3d position, double hotspot, double falloff, Point3d target)"
Unity"public Entity IESLight(String webFile, Point3d position, Point3d target, Vector3d rotation)"

backend_spotlight(b::Unity, loc::Loc, dir::Vec, hotspot::Real, falloff::Real) =
    UnitySpotLight(connection(b), loc, hotspot, falloff, loc + dir)

backend_ieslight(b::Unity, file::String, loc::Loc, dir::Vec, alpha::Real, beta::Real, gamma::Real) =
    UnityIESLight(connection(b), file, loc, loc + dir, vxyz(alpha, beta, gamma))

# User Selection

shape_from_ref(r, b::Unity=current_backend()) =
    let c = connection(b)
        code = UnityShapeCode(c, r)
        ref = LazyRef(b, UnityNativeRef(r))
        if code == 1 # Point
            point(UnityPointPosition(c, r),
                  backend=b, ref=ref)
        elseif code == 2
            circle(maybe_loc_from_o_vz(UnityCircleCenter(c, r), UnityCircleNormal(c, r)),
                   UnityCircleRadius(c, r),
                   backend=b, ref=ref)
        elseif 3 <= code <= 6
            line(UnityLineVertices(c, r),
                 backend=b, ref=ref)
        elseif code == 7
            spline([xy(0,0)], false, false, #HACK obtain interpolation points
                   backend=b, ref=ref)
        elseif code == 9
            let start_angle = mod(UnityArcStartAngle(c, r), 2pi)
                end_angle = mod(UnityArcEndAngle(c, r), 2pi)
                if end_angle > start_angle
                    arc(maybe_loc_from_o_vz(UnityArcCenter(c, r), UnityArcNormal(c, r)),
                        UnityArcRadius(c, r), start_angle, end_angle - start_angle,
                        backend=b, ref=ref)
                else
                    arc(maybe_loc_from_o_vz(UnityArcCenter(c, r), UnityArcNormal(c, r)),
                        UnityArcRadius(c, r), end_angle, start_angle - end_angle,
                        backend=b, ref=ref)
                end
            end
        elseif code == 10
            let str = UnityTextString(c, r)
                height = UnityTextHeight(c, r)
                loc = UnityTextPosition(c, r)
                text(str, loc, height, backend=b, ref=ref)
            end
        elseif code == 11
            let str = UnityMTextString(c, r)
                height = UnityMTextHeight(c, r)
                loc = UnityMTextPosition(c, r)
                text(str, loc, height, backend=b, ref=ref)
            end
        elseif 12 <= code <= 14
            surface(Shapes1D[], backend=b, ref=ref)
        elseif 103 <= code <= 106
            polygon(UnityLineVertices(c, r),
                    backend=b, ref=ref)
        else
            unknown(backend=b, ref=ref)
            #error("Unknown shape with code $(code)")
        end
    end
#

Unity"public Point3d[] GetPosition(string prompt)"

select_position(prompt::String, b::Unity) =
  begin
    @info "$(prompt) on the $(b) backend."
    let ans = UnityGetPosition(connection(b), prompt)
      length(ans) > 0 && ans[1]
    end
  end

select_with_prompt(prompt::String, b::Backend, f::Function) =
  begin
    @info "$(prompt) on the $(b) backend."
    let ans = f(connection(b), prompt)
      length(ans) > 0 && shape_from_ref(ans[1], b)
    end
  end

Unity"public ObjectId[] GetPoint(string prompt)"

# HACK: The next operations should receive a set of shapes to avoid re-creating already existing shapes

select_point(prompt::String, b::Unity) =
  select_with_prompt(prompt, b, UnityGetPoint)

Unity"public ObjectId[] GetCurve(string prompt)"

select_curve(prompt::String, b::Unity) =
  select_with_prompt(prompt, b, UnityGetCurve)

Unity"public ObjectId[] GetSurface(string prompt)"

select_surface(prompt::String, b::Unity) =
  select_with_prompt(prompt, b, UnityGetSurface)

Unity"public ObjectId[] GetSolid(string prompt)"

select_solid(prompt::String, b::Unity) =
  select_with_prompt(prompt, b, UnityGetSolid)

Unity"public ObjectId[] GetShape(string prompt)"

select_shape(prompt::String, b::Unity) =
  select_with_prompt(prompt, b, UnityGetShape)

Unity"public long GetHandleFromShape(Entity e)"
Unity"public ObjectId GetShapeFromHandle(long h)"

captured_shape(b::Unity, handle) =
  shape_from_ref(UnityGetShapeFromHandle(connection(b), handle),
                 b)

generate_captured_shape(s::Shape, b::Unity) =
    println("captured_shape(autocad, $(UnityGetHandleFromShape(connection(b), ref(s).value)))")

# Register for notification

Unity"public void RegisterForChanges(ObjectId id)"
Unity"public void UnregisterForChanges(ObjectId id)"
Unity"public ObjectId[] ChangedShape()"
Unity"public void DetectCancel()"
Unity"public void UndetectCancel()"
Unity"public bool WasCanceled()"

register_for_changes(s::Shape, b::Unity) =
    let conn = connection(b)
        UnityRegisterForChanges(conn, ref(s).value)
        UnityDetectCancel(conn)
        s
    end

unregister_for_changes(s::Shape, b::Unity) =
    let conn = connection(b)
        UnityUnregisterForChanges(conn, ref(s).value)
        UnityUndetectCancel(conn)
        s
    end

waiting_for_changes(s::Shape, b::Unity) =
    ! UnityWasCanceled(connection(b))

changed_shape(ss::Shapes, b::Unity) =
    let conn = connection(b)
        changed = []
        while length(changed) == 0 && ! UnityWasCanceled(conn)
            changed =  UnityChangedShape(conn)
            sleep(0.1)
        end
        if length(changed) > 0
            shape_from_ref(changed[1], b)
        else
            nothing
        end
    end

Unity"public ObjectId[] GetAllShapes()"
Unity"public ObjectId[] GetAllShapesInLayer(ObjectId layerId)"

# HACK: This should be filtered on the plugin, not here.
all_shapes(b::Unity) =
    let c = connection(b)
        Shape[shape_from_ref(r, b)
              for r in filter(r -> UnityShapeCode(c, r) != 0, UnityGetAllShapes(c))]
    end

all_shapes_in_layer(layer, b::Unity) =
    let c = connection(b)
        Shape[shape_from_ref(r, b) for r in UnityGetAllShapesInLayer(c, layer)]
    end

disable_update(b::Unity) =
    UnityDisableUpdate(connection(b))

enable_update(b::Unity) =
    UnityEnableUpdate(connection(b))
# Render

Unity"public void Render(int width, int height, string path, int levels, double exposure)"
#render exposure: [-3, +3] -> [-6, 21]
convert_render_exposure(b::Unity, v::Real) = -4.05*v + 8.8
#render quality: [-1, +1] -> [+1, +50]
convert_render_quality(b::Unity, v::Real) = round(Int, 25.5 + 24.5*v)

render_view(name::String, b::Unity=current_backend()) =
    UnityRender(connection(b),
               render_width(), render_height(),
               prepare_for_saving_file(render_pathname(name)),
               convert_render_quality(b, render_quality()),
               convert_render_exposure(b, render_exposure()))

export mentalray_render_view
mentalray_render_view(name::String) =
    let conn = connection(current_backend())
        UnitySetSystemVariableInt(conn,"SKYSTATUS", 2) # skystatus:background-and-illumination
        UnityCommand(conn, "._-render P _R $(render_width()) $(render_height()) _yes $(prepare_for_saving_file(render_pathname(name)))\n")
    end

save_as(pathname::String, format::String, b::Unity) =
    UnitySaveAs(connection(b), pathname, format)
=#