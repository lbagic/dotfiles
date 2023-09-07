#!/bin/bash

find ./path/to/folder -type f | xargs sed -i '' "s/THING_TO_BE_REPLACED/NEW_THING/g"
