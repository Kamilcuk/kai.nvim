#!/usr/bin/env python3
import tiktoken
import sys
m = tiktoken.get_encoding("cl100k_base")
for v in sys.argv[1:]:
	print(v, [m.decode([x]) for x in m.encode(v)])
