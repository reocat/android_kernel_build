import os
import pathlib
import re
import sys


def sanitize(input: pathlib.Path, output: pathlib.Path):
    with open(input) as f:
        content = f.read()
    replaced = re.sub(r"/out/\S+?/execroot/__main__", "", content)
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, "w") as f:
        f.write(replaced)


if __name__ == "__main__":
    input = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])

    for root, dirs, files in os.walk(input):
        root_path = pathlib.Path(root)
        for file in files:
            file_path = root_path / file

            sanitize(file_path, output / file_path.relative_to(input))
