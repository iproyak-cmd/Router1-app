# Router1 Figma MCP Notes

Do not store Figma tokens in this repository.

## What MCP Should Provide

Codex should use Figma MCP to read:

- frame dimensions;
- component hierarchy;
- Auto Layout;
- fills and strokes;
- text styles;
- effects;
- exported asset references.

## Required From Project Owner

- Figma Team or file access.
- Dev Mode access if using official Figma Dev Mode MCP.
- Figma file URL.
- Approved frame/node links.
- Personal access token only if using REST/API-based MCP.

## Local Template

Use a local MCP config outside the repo. Example only:

```json
{
  "mcpServers": {
    "figma": {
      "command": "npx",
      "args": ["-y", "figma-developer-mcp", "--stdio"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "set-outside-repo"
      }
    }
  }
}
```

Prefer the official Figma Dev Mode MCP server when available in the active Figma Desktop/Dev Mode setup.

