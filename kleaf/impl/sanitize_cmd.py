import os
import pathlib
import re
import shutil
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
            input_file_path = root_path / file
            output_file_path = output / input_file_path.relative_to(input)
            if input_file_path.suffix != ".cmd":
                shutil.copy(input_file_path, output_file_path)
            else:
                sanitize(input_file_path, output_file_path)
