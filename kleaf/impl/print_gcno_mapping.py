# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Print gcno/mapping.json"""

import json
import sys

result = []
for arg in sys.argv[1:]:
    tup = arg.split(":")
    assert len(tup) == 2, "%s is not a valid argument" % arg

    result.append({
        "from": tup[0],
        "to": tup[1],
    })

print(json.dumps(result, sort_keys=True, indent=2))

