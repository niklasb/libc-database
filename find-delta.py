from sys import argv
import os, re


def usage():
    print("%-7s %s %s" % ("usage:", argv[0], "[func1] [func2] [delta]"))
    exit()


def find_matches(arguments):
    results = []
    root_dir = "db" if len(os.path.dirname(argv[0])) == 0 else os.path.dirname(argv[0]) + "/db"

    func1 = arguments[0]
    func2 = arguments[1]
    delta = int(arguments[2],16)

    print("Looking for {} - {} = 0x{:x}".format(func1, func2, delta))

    # Loop through all files and add files that match ALL arguments to results
    for filename in os.listdir(root_dir):
        if filename.endswith(".symbols"):
            lines = open(root_dir + "/" + filename, "r").read().strip().split("\n")
            offsets = {}
            for line in lines:
                split_line = line.split(" ")
                offsets[split_line[0]] = int(split_line[1],16)
            file_delta = offsets[func1] - offsets[func2]
            if file_delta == delta:
                print("{} {} - {} = 0x{:x}".format(filename, func1, func2, file_delta))
                

    return results


if len(argv) < 4:
    usage()

for result in find_matches(argv[1:]):
    print(result[0])
    for line in result[1]:
        print("  " + line.strip())
