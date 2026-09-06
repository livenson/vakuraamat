#!/bin/sh
# The Sketchfab MCP server (gregkop/sketchfab-mcp-server, ISC) for Claude Code: search, model
# details and glTF downloads. Reads the API token from sketchfab.token in the project root (not
# in git). Build first: make mcp.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TOKEN="$(tr -d '\n\r ' < "$ROOT/sketchfab.token")"
exec node "$DIR/sketchfab-mcp-server/build/index.js" --api-key "$TOKEN"
