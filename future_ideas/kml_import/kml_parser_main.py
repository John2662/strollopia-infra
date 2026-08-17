import argparse

from kml_parser import kml_file_parser, point_array_to_point
from shapely.geometry import Point, Polygon

def get_arg_parser():
    parser = argparse.ArgumentParser(description='Process a kml file')
    parser.add_argument('file', type=argparse.FileType('r'),
                    help='path to kml file')
    parser.add_argument('y', type=float, help='y coord')
    parser.add_argument('x', type=float, help='x coord')
    return parser

def main():
    parser = get_arg_parser()
    # parser.print_help()
    args = parser.parse_args()
    #print(f'{args.file=}')
    #print(f'OK\n{args.file.name=}')
    x = args.x
    y = args.y

    read_point = Point(point_array_to_point([x,y]))
    print(f'{read_point=}')
    boundaries_found = kml_file_parser(args.file.name)
    print(f'found {len(boundaries_found)} boundaries')
    for boundary in boundaries_found:
        b_points = boundary.exterior.coords
        for p in b_points:
            print(f'POI: {p}')
        print(f'{read_point.within(boundary)=}')


if __name__ == "__main__":
    main()


