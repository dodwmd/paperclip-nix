# MCP server definitions for Paperclip agents.
#
# Each server lives in its own <name>.nix file with npm source in <name>/.
# To add a new server:
#   1. Create mcp-servers/<name>/package.json with the npm dependency
#   2. cd mcp-servers/<name> && npm install --package-lock-only --ignore-scripts
#   3. Get the hash: prefetch-npm-deps <name>/package-lock.json
#   4. Copy <name>.nix from an existing server, update pkg name, version, hash, bin path
#   5. Add the import below
{ ... }:

{
  imports = [
    ./context7.nix
    ./sequential-thinking.nix
    ./mermaid.nix
    ./rss-mcp.nix
    ./free-crypto-news.nix
    ./crypto-rss-mcp.nix
    ./yahoo-finance-mcp.nix
    ./edgartools-mcp.nix
    # --- servers from agent config ---
    ./fetch-mcp.nix
    ./time-mcp.nix
    ./duckduckgo-mcp.nix
    ./reddit-mcp.nix
    ./twitter-mcp.nix
    ./hn-mcp.nix
    ./sqlite-mcp.nix
    ./postgres-mcp.nix
    ./desktop-commander-mcp.nix
    ./playwright-mcp.nix
    ./chart-mcp.nix
    ./wcag-mcp.nix
    ./color-palette-mcp.nix
    ./yfinance-mcp.nix
  ];
}
