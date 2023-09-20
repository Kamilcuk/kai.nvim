MAKEFLAGS = -rR --warn-undefined-variables

all: doc/tags

doc/tags: doc/kai.txt
	vim --cmd ':helptags doc' --cmd ':exit'
doc/kai.txt: _build/panvimdoc README.md
	_build/panvimdoc/panvimdoc.sh \
		--project-name kai \
		--input-file README.md \
		--toc true \
		--doc-mapping true
_build/panvimdoc:
	mkdir -vp _build
	git clone https://github.com/kdheepak/panvimdoc.git _build/panvimdoc
README.md: _build/doc.json ./README.jinja.md ./gen_README.py
	./gen_README.py
_build/doc.json: $(shell find lua -type f)
	mkdir -vp _build
	lua-language-server --doc lua --logpath _build

clean:
	rm -rf _build
