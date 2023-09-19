gen: README.md
doc/kai.txt: README.md

README.md: _build/doc.json ./README.jinja.md
	./gen_doc.py
_build/doc.json: $(shell find lua -type f)
	lua-language-server --doc lua --logpath _build

