#!/usr/bin/env bash
### Override the launcher scripts assumption that the command we're going to
### run lives inside the virtualenv bin dir in the container
cmd_to_run[0]='make'