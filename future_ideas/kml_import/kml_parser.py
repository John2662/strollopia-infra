# https://automating-gis-processes.github.io/CSC/notebooks/L4/Point-in-polygon.html

from shapely.geometry import Point, Polygon


def point_array_to_point(d_array):
    return Point(tuple(d_array))


def point_string_to_point(p, dimension=2):
    p_array = p.split(',')
    d_array = []
    for dim, c in enumerate(p_array):
        if dim >= dimension:
            break
        try:
            f = float(c)
            d_array.append(f)
        except ValueError:
            raise
    return point_array_to_point(d_array)


# might need to check tha tthe polygon is "closed"
def coord_string_to_polygon(poly_coords):
    poly_coords_as_str = str(poly_coords).strip()
    coord_array = poly_coords_as_str.split(' ')
    boundary = []
    for p in coord_array:
        boundary.append(point_string_to_point(p))
    return Polygon(boundary)


# https://stackoverflow.com/questions/67454345/google-kml-file-to-python
# return an array of Polygons
def parse_for_boundaries(root):
    import re
    boundaries_found = []
    for elt in root.getchildren():
        # strip the namespace
        tag = re.sub(r'^.*\}', '', elt.tag)
        if tag in ["Document", "Folder"]:
            # recursively iterate over child elements
            boundaries_found += parse_for_boundaries(elt)
        elif tag == "Placemark":
            if hasattr(elt, 'Point'):
                print("Point:", elt.Point.coordinates)
            elif hasattr(elt, 'LineString'):
                print("LineString:", elt.LineString.coordinates)
            elif hasattr(elt, 'Polygon'):
                # print("Polygon:", elt.Polygon.outerBoundaryIs.LinearRing.coordinates)
                boundary = coord_string_to_polygon(elt.Polygon.outerBoundaryIs.LinearRing.coordinates)
                boundaries_found.append(boundary)

            elif hasattr(elt, 'MultiGeometry'):
                print("MultiGeometry")
                for gg in elt.MultiGeometry.getchildren():
                    tag = re.sub(r'^.*\}', '', gg.tag)
                    if tag == "Polygon":
                        print(gg.outerBoundaryIs.LinearRing.coordinates)

    return boundaries_found


def kml_file_parser(file_path_name):
    with open(file_path_name, 'r') as kml_data:
        from pykml import parser
        print(f'{type(kml_data)=}')
        root = parser.parse(kml_data).getroot()
        return parse_for_boundaries(root)
