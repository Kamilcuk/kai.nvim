#!/usr/bin/env python3

import json
from dataclasses import dataclass
from pathlib import Path

from jinja2 import StrictUndefined, Template


@dataclass
class Symbol:
    name: str
    desc: str
    # type
    view: str
    orig: dict

    @classmethod
    def mk(cls, i):
        return cls(
            name=i["name"],
            desc=i.get("desc", ""),
            view=i["extends"]["view"],
            orig=i,
        )


class Doc:
    def __init__(self, path: Path):
        with path.open() as f:
            self.data = json.load(f)
        self.name_to_data = {x["name"]: x for x in self.data}

    def find(self, x: str):
        return self.name_to_data[x]

    def commands(self):
        return sorted(
            (Symbol.mk(i) for i in self.find("Commands")["fields"]),
            key=lambda x: x.name,
        )

    def configs(self):
        return sorted(
            (Symbol.mk(i) for i in self.find("Config")["fields"]), key=lambda x: x.name
        )

    def fields(self, x: str):
        return sorted(
            (Symbol.mk(i) for i in self.find(x)["fields"]), key=lambda x: x.name
        )


if __name__ == "__main__":
    doc = Doc(Path("_build/doc.json"))
    with Path("README.jinja.md").open() as f:
        t = Template(
            f.read(),
            undefined=StrictUndefined,
            lstrip_blocks=True,
            trim_blocks=True,
        )
    res = t.render(
        configs=doc.fields("Config"),
        commands=doc.fields("Commands"),
    )
    with Path("README.md").open("w") as f:
        f.write(res)
