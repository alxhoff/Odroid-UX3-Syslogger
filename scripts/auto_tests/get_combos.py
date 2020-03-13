#1/bin/python
import sys
from itertools import combinations_with_replacement

if len(sys.argv) == 1:
    utils = [0,10, 25, 50, 75, 100]
else:
    utils = sys.argv[1:]

combos = combinations_with_replacement(utils, 4)

print (list(combos))
