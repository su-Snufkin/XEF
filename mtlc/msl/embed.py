#!/usr/bin/env python3
# embed.py IN OUT: C array with the contents of IN
import sys
d = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    f.write("static const char k_metal_stdlib[] = {\n")
    for i in range(0, len(d), 32):
        f.write(",".join(str(b) for b in d[i:i + 32]) + ",\n")
    f.write("0};\nstatic const unsigned long k_metal_stdlib_size = %d;\n" % len(d))
