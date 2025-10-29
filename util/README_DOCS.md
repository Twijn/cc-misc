# Documentation Generator

This directory contains a custom Python-based documentation generator that extracts documentation from EmmyLua annotations in Lua files.

## Usage

### Generate Documentation Locally

```bash
cd util
python3 generate_docs.py
```

This will generate both HTML and Markdown documentation in the `../docs` directory.

### View Documentation

Open `../docs/index.html` in your browser to view the generated documentation.

## Features

- **EmmyLua Compatible**: Parses standard EmmyLua annotations (`@param`, `@return`, `@class`, `@field`)
- **Multiple Formats**: Generates both HTML and Markdown documentation
- **Clean Design**: Modern, responsive HTML with dark mode support
- **Zero Dependencies**: Pure Python 3, no external packages required
- **Fast**: Generates documentation in seconds

## Supported Annotations

- `@param name type description` - Function parameters
- `@return type description` - Return values
- `@class ClassName` - Class definitions
- `@field name type description` - Class fields

## CI/CD

Documentation is automatically generated and deployed to GitHub Pages on every push to the `main` branch that modifies files in the `util/` directory.
