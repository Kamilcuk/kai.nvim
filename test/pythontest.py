#!/usr/bin/env python3
import sys

import tiktoken

m = tiktoken.get_encoding("cl100k_base")
if False:
    for v in sys.argv[1:]:
        res = m.encode(v)
        print(v, res, [m.decode([x]) for x in res], len(res))
else:
    a = [
        " a",
        "a ",
        "a b",
        "a b ",
        "a b c",
        "12345647657",
        ", ",
        "as ",
        "llo",
        "',.",
        "abcdef 12345647657 ;',./pl[flewq'l abc'l",
        "You miss 100% of the shots you don't take",
        "You miss 100% of the shots you don’t take",
        "system",
        "user",
        "You are a helpful, pattern-following assistant that translates corporate jargon into plain English.",
        "synergies",
        "New synergies will help drive top-line growth.",
        "Things working well together will increase revenue.",
        "Let's circle back when we have more bandwidth to touch base on opportunities for increased leverage.",
        "Let's talk later when we're less busy about how to do better.",
        "This late pivot means we don't have time to boil the ocean for the client deliverable.",
    ]
    for i in a:
        print('{ "%s", { %s } }' % (i, ",".join(str(x) for x in m.encode(i))))
