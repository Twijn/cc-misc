#!/usr/bin/env python3
"""
Simple EmmyLua documentation generator
Parses EmmyLua annotations and generates clean HTML/Markdown documentation
"""

import re
import os
import json
from pathlib import Path
from typing import List, Dict, Any

class LuaDocGenerator:
    def __init__(self, input_dir: str, output_dir: str):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.modules = []
        
    def parse_file(self, filepath: Path) -> Dict[str, Any]:
        """Parse a Lua file and extract documentation"""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        module = {
            'name': filepath.stem,
            'path': str(filepath.relative_to(self.input_dir)),
            'description': '',
            'examples': [],
            'functions': [],
            'classes': [],
            'fields': []
        }
        
        # Extract module description (first block of comments before any code)
        # Stop at @usage or other tags
        desc_lines = []
        in_description = False
        for line in content.split('\n'):
            if line.startswith('---'):
                cleaned = line[3:].strip()
                if cleaned.startswith('@'):
                    break  # Stop at first @ tag
                if cleaned:
                    desc_lines.append(cleaned)
                    in_description = True
            elif in_description:
                break  # Stop at first non-comment line
        module['description'] = ' '.join(desc_lines)
        
        # Extract examples from @usage blocks
        example_pattern = r'---@usage\s*\n((?:---[^@].*?\n)+)'
        for match in re.finditer(example_pattern, content, re.MULTILINE):
            example_block = match.group(1)
            example_lines = []
            for line in example_block.split('\n'):
                if line.startswith('---'):
                    # Remove the --- prefix and exactly one space after it (if present)
                    cleaned = line[3:]
                    if cleaned.startswith(' '):
                        cleaned = cleaned[1:]
                    # Skip empty lines and lines starting with @ tags
                    if cleaned and not cleaned.lstrip().startswith('@'):
                        example_lines.append(cleaned)
            if example_lines:
                module['examples'].append('\n'.join(example_lines))
        
        # Extract functions with their documentation
        # Match both standalone functions and methods (function name.method or name:method)
        # Also match module.function patterns, including indented ones
        func_pattern = r'((?:[ \t]*---.*?\n)+)[ \t]*(local\s+)?function\s+([\w.:]+)\s*\((.*?)\)'
        for match in re.finditer(func_pattern, content, re.MULTILINE):
            doc_block, is_local, func_name, params = match.groups()
            
            # Skip local functions that don't have a module/class prefix
            if is_local and '.' not in func_name and ':' not in func_name:
                continue
            
            # Calculate line number
            line_num = content[:match.start()].count('\n') + 1
            
            func_info = {
                'name': func_name,
                'params': [],
                'returns': '',
                'description': '',
                'line': line_num
            }
            
            # Parse documentation block
            desc_lines = []
            for line in doc_block.split('\n'):
                line = line.strip()
                if line.startswith('---'):
                    line = line[3:].strip()
                    if line.startswith('@param'):
                        param_match = re.match(r'@param\s+(\w+\??)\s+(\S+)(?:\s+(.+))?', line)
                        if param_match:
                            func_info['params'].append({
                                'name': param_match.group(1),
                                'type': param_match.group(2),
                                'description': param_match.group(3) or ''
                            })
                    elif line.startswith('@return'):
                        func_info['returns'] = line.replace('@return', '').strip()
                    elif not line.startswith('@'):
                        desc_lines.append(line)
            
            func_info['description'] = ' '.join(desc_lines)
            # Only add functions that have documentation
            if func_info['description'] or func_info['params'] or func_info['returns']:
                module['functions'].append(func_info)
        
        # Extract classes
        class_pattern = r'((?:---.*?\n)+)---@class\s+(\w+)'
        for match in re.finditer(class_pattern, content, re.MULTILINE):
            doc_block, class_name = match.groups()
            
            class_info = {
                'name': class_name,
                'description': '',
                'fields': []
            }
            
            desc_lines = []
            for line in doc_block.split('\n'):
                line = line.strip()
                if line.startswith('---'):
                    line = line[3:].strip()
                    if line.startswith('@field'):
                        field_match = re.match(r'@field\s+(\w+\??)\s+(\S+)(?:\s+(.+))?', line)
                        if field_match:
                            class_info['fields'].append({
                                'name': field_match.group(1),
                                'type': field_match.group(2),
                                'description': field_match.group(3) or ''
                            })
                    elif not line.startswith('@'):
                        desc_lines.append(line)
            
            class_info['description'] = ' '.join(desc_lines)
            if class_info['description'] or class_info['fields']:
                module['classes'].append(class_info)
        
        return module
    
    def generate_markdown(self, module: Dict[str, Any]) -> str:
        """Generate Markdown documentation for a module"""
        md = f"# {module['name']}\n\n"
        
        if module['description']:
            md += f"{module['description']}\n\n"
        
        # Examples
        if module['examples']:
            md += "## Examples\n\n"
            for example in module['examples']:
                md += "```lua\n"
                md += example + "\n"
                md += "```\n\n"
        
        # Classes
        if module['classes']:
            md += "## Classes\n\n"
            for cls in module['classes']:
                md += f"### {cls['name']}\n\n"
                if cls['description']:
                    md += f"{cls['description']}\n\n"
                
                if cls['fields']:
                    md += "**Fields:**\n\n"
                    for field in cls['fields']:
                        md += f"- `{field['name']}` ({field['type']})"
                        if field['description']:
                            md += f": {field['description']}"
                        md += "\n"
                    md += "\n"
        
        # Functions
        if module['functions']:
            md += "## Functions\n\n"
            for func in module['functions']:
                # Function signature
                params_str = ', '.join([p['name'] for p in func['params']])
                md += f"### `{func['name']}({params_str})`\n\n"
                
                if func['description']:
                    md += f"{func['description']}\n\n"
                
                # Parameters
                if func['params']:
                    md += "**Parameters:**\n\n"
                    for param in func['params']:
                        md += f"- `{param['name']}` ({param['type']})"
                        if param['description']:
                            md += f": {param['description']}"
                        md += "\n"
                    md += "\n"
                
                # Returns
                if func['returns']:
                    md += f"**Returns:** {func['returns']}\n\n"
        
        return md
    
    def generate_html_index(self, modules: List[Dict[str, Any]]) -> str:
        """Generate HTML index page"""
        html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CC-Misc Utilities Documentation</title>
    <style>
        :root {
            --bg: #ffffff;
            --text: #1a1a1a;
            --link: #0066cc;
            --border: #e0e0e0;
            --code-bg: #f5f5f5;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1a1a1a;
                --text: #e0e0e0;
                --link: #4d9fff;
                --border: #333333;
                --code-bg: #2a2a2a;
            }
        }
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            padding: 2rem;
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid var(--border);
        }
        h2 {
            margin-top: 2rem;
            margin-bottom: 1rem;
        }
        ul {
            list-style: none;
        }
        li {
            padding: 0.5rem 0;
        }
        a {
            color: var(--link);
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .module {
            padding: 1rem;
            margin: 0.5rem 0;
            border: 1px solid var(--border);
            border-radius: 4px;
        }
        .module h3 {
            margin: 0 0 0.5rem 0;
        }
        .module p {
            color: var(--text);
            opacity: 0.8;
        }
        code {
            background: var(--code-bg);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <h1>CC-Misc Utilities Documentation</h1>
    <p>A collection of utility modules for ComputerCraft development</p>
    
    <h2>Modules</h2>
    <div class="modules">
"""
        
        for module in modules:
            html += f"""        <div class="module">
            <h3><a href="{module['name']}.html">{module['name']}</a></h3>
            <p>{module['description'][:200]}{'...' if len(module['description']) > 200 else ''}</p>
        </div>
"""
        
        html += """    </div>
</body>
</html>
"""
        return html
    
    def generate_html_module(self, module: Dict[str, Any]) -> str:
        """Generate HTML documentation for a module"""
        # Escape HTML in description
        description = module['description'].replace('<', '&lt;').replace('>', '&gt;')
        
        # GitHub raw URL for installation
        github_raw_url = f"https://raw.githubusercontent.com/Twijn/cc-misc/main/util/{module['name']}.lua"
        github_repo_url = f"https://github.com/Twijn/cc-misc/blob/main/util/{module['name']}.lua"
        
        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{module['name']} - CC-Misc Utilities</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
    <style>
        :root {{
            --bg: #ffffff;
            --text: #1a1a1a;
            --link: #0066cc;
            --border: #e0e0e0;
            --code-bg: #f5f5f5;
        }}
        @media (prefers-color-scheme: dark) {{
            :root {{
                --bg: #1a1a1a;
                --text: #e0e0e0;
                --link: #4d9fff;
                --border: #333333;
                --code-bg: #2a2a2a;
            }}
        }}
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            padding: 2rem;
            max-width: 1200px;
            margin: 0 auto;
        }}
        .header {{
            border-bottom: 2px solid var(--border);
            padding-bottom: 1.5rem;
            margin-bottom: 2rem;
        }}
        .header h1 {{
            margin-bottom: 1rem;
            font-size: 2.5rem;
        }}
        .header p {{
            font-size: 1.1rem;
            line-height: 1.8;
            opacity: 0.9;
        }}
        h2 {{
            margin-top: 3rem;
            margin-bottom: 1.5rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.8rem;
        }}
        h3 {{
            margin-top: 1.5rem;
            margin-bottom: 0.75rem;
            font-size: 1.3rem;
        }}
        code {{
            background: var(--code-bg);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{
            padding: 1rem;
            border-radius: 4px;
            overflow-x: auto;
            margin: 1rem 0;
            border: 1px solid var(--border);
        }}
        pre code {{
            background: none;
            padding: 0;
            font-size: 0.95em;
        }}
        .function:not(.token) {{
            margin: 2rem 0;
            padding: 1.5rem;
            border: 1px solid var(--border);
            border-radius: 6px;
        }}
        .function h3 {{
            margin-top: 0;
        }}
        .function > p {{
            margin: 1rem 0;
            line-height: 1.7;
        }}
        .params, .returns {{
            margin-top: 1rem;
        }}
        .params ul, .returns ul {{
            list-style: none;
            padding-left: 0;
        }}
        .params li, .returns li {{
            padding: 0.5rem 0;
            padding-left: 1rem;
            border-left: 3px solid var(--border);
            margin: 0.25rem 0;
        }}
        a {{
            color: var(--link);
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        .back-link {{
            margin-bottom: 1.5rem;
            font-size: 0.95rem;
        }}
        .install-section {{
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 1.5rem;
            margin: 2rem 0;
        }}
        .install-section h2 {{
            margin-top: 0;
            margin-bottom: 1rem;
            font-size: 1.5rem;
            border-bottom: none;
        }}
        .install-cmd {{
            background: var(--bg);
            border: 1px solid var(--border);
            padding: 0.75rem;
            border-radius: 4px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
            margin: 0.5rem 0;
            word-break: break-all;
        }}
        .github-link {{
            display: inline-block;
            padding: 0.5rem 1rem;
            background: var(--link);
            color: white;
            border: 1px solid var(--link);
            border-radius: 4px;
            text-decoration: none;
            font-size: 0.9em;
            transition: all 0.2s;
            font-family: inherit;
            line-height: 1.5;
            text-align: center;
            vertical-align: middle;
        }}
        .github-link:hover {{
            opacity: 0.85;
            text-decoration: none;
        }}
        .install-controls {{
            display: flex;
            gap: 0.5rem;
            align-items: center;
            flex-wrap: wrap;
            margin-top: 1rem;
        }}
        .copy-btn {{
            display: inline-block;
            background: transparent;
            color: var(--link);
            border: 1px solid var(--link);
            padding: 0.5rem 1rem;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.9em;
            transition: all 0.2s;
            font-family: inherit;
            line-height: 1.5;
            text-align: center;
            vertical-align: middle;
            text-decoration: none;
        }}
        .copy-btn:hover {{
            background: var(--link);
            color: white;
        }}
        .copy-btn.copied {{
            background: #28a745;
            border-color: #28a745;
            color: white;
        }}
    </style>
</head>
<body>
    <div class="back-link"><a href="index.html">← Back to index</a></div>
    <div class="header">
        <h1>{module['name']}</h1>
        <p>{description}</p>
    </div>
    
    <div class="install-section">
        <h2>Installation</h2>
        <p>Quick install via wget:</p>
        <div class="install-cmd" id="install-cmd">wget {github_raw_url} {module['name']}.lua</div>
        <div class="install-controls">
            <button class="copy-btn" onclick="copyInstallCommand(this)">Copy Command</button>
            <a href="{github_repo_url}" class="github-link" target="_blank">View on GitHub →</a>
        </div>
    </div>
    
    <script>
        function copyInstallCommand(btn) {{
            const cmd = document.getElementById('install-cmd').textContent;
            navigator.clipboard.writeText(cmd).then(() => {{
                const originalText = btn.textContent;
                btn.textContent = '✓ Copied!';
                btn.classList.add('copied');
                setTimeout(() => {{
                    btn.textContent = originalText;
                    btn.classList.remove('copied');
                }}, 2000);
            }}).catch(err => {{
                console.error('Failed to copy:', err);
                btn.textContent = '✗ Failed';
                setTimeout(() => {{
                    btn.textContent = 'Copy Command';
                }}, 2000);
            }});
        }}
    </script>
"""
        
        # Examples
        if module['examples']:
            html += "    <h2>Examples</h2>\n"
            for example in module['examples']:
                escaped_example = example.replace('<', '&lt;').replace('>', '&gt;')
                html += f"""    <pre><code class="language-lua">{escaped_example}</code></pre>\n"""
        
        # Classes
        if module['classes']:
            html += "    <h2>Classes</h2>\n"
            for cls in module['classes']:
                html += f"    <div class='function'>\n"
                html += f"        <h3>{cls['name']}</h3>\n"
                if cls['description']:
                    html += f"        <p>{cls['description']}</p>\n"
                
                if cls['fields']:
                    html += "        <div class='params'>\n"
                    html += "            <strong>Fields:</strong>\n"
                    html += "            <ul>\n"
                    for field in cls['fields']:
                        html += f"                <li><code>{field['name']}</code> ({field['type']})"
                        if field['description']:
                            html += f": {field['description']}"
                        html += "</li>\n"
                    html += "            </ul>\n"
                    html += "        </div>\n"
                html += "    </div>\n"
        
        # Functions
        if module['functions']:
            html += "    <h2>Functions</h2>\n"
            for func in module['functions']:
                html += "    <div class='function'>\n"
                params_str = ', '.join([p['name'] for p in func['params']])
                html += f"        <h3><code>{func['name']}({params_str})</code></h3>\n"
                
                # Add GitHub link for this function with line number
                func_github_url = f"{github_repo_url}#L{func.get('line', 1)}"
                html += f"        <a href='{func_github_url}' target='_blank' style='font-size: 0.85em; opacity: 0.7;'>View source on GitHub</a>\n"
                
                if func['description']:
                    html += f"        <p>{func['description']}</p>\n"
                
                if func['params']:
                    html += "        <div class='params'>\n"
                    html += "            <strong>Parameters:</strong>\n"
                    html += "            <ul>\n"
                    for param in func['params']:
                        html += f"                <li><code>{param['name']}</code> ({param['type']})"
                        if param['description']:
                            html += f": {param['description']}"
                        html += "</li>\n"
                    html += "            </ul>\n"
                    html += "        </div>\n"
                
                if func['returns']:
                    html += f"        <div class='returns'><strong>Returns:</strong> {func['returns']}</div>\n"
                
                html += "    </div>\n"
        
        html += """</body>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-lua.min.js"></script>
</html>
"""
        return html
    
    def generate(self):
        """Generate documentation for all Lua files"""
        # Create output directory
        self.output_dir.mkdir(exist_ok=True, parents=True)
        
        # Find all Lua files in the util directory (excluding subdirectories)
        lua_files = list(self.input_dir.glob('*.lua'))
        
        # Parse each file
        for lua_file in lua_files:
            module = self.parse_file(lua_file)
            self.modules.append(module)
            
            # Generate Markdown
            md_content = self.generate_markdown(module)
            md_path = self.output_dir / f"{module['name']}.md"
            with open(md_path, 'w', encoding='utf-8') as f:
                f.write(md_content)
            
            # Generate HTML
            html_content = self.generate_html_module(module)
            html_path = self.output_dir / f"{module['name']}.html"
            with open(html_path, 'w', encoding='utf-8') as f:
                f.write(html_content)
        
        # Generate index
        index_html = self.generate_html_index(self.modules)
        with open(self.output_dir / 'index.html', 'w', encoding='utf-8') as f:
            f.write(index_html)
        
        print(f"Generated documentation for {len(self.modules)} modules")
        print(f"Output directory: {self.output_dir}")

if __name__ == '__main__':
    generator = LuaDocGenerator('.', '../docs')
    generator.generate()
