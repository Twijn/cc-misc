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

try:
    import markdown
    HAS_MARKDOWN = True
except ImportError:
    HAS_MARKDOWN = False

class LuaDocGenerator:
    def __init__(self, input_dir: str, output_dir: str):
        self.input_dir = Path(input_dir).resolve()
        self.output_dir = Path(output_dir).resolve()
        self.modules = []
        self.programs = []
        
        # Programs to include from parent directory
        self.program_dirs = ['signshop', 'autocrafter', 'farm', 'netherite', 'roadbuilder', 'router', 'spleef', 'brewery']
        
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
            'fields': [],
            'dependencies': [],
            'version': None
        }
        
        # Extract version from VERSION constant or @version tag
        version_const_match = re.search(r'VERSION\s*=\s*["\']([^"\']+)["\']', content)
        if version_const_match:
            module['version'] = version_const_match.group(1)
        else:
            version_tag_match = re.search(r'---@version\s+([^\s]+)', content)
            if version_tag_match:
                module['version'] = version_tag_match.group(1)
        
        # Extract dependencies from require() calls
        # Look for require("lib") or require('/lib/lib')
        require_pattern = r'require\s*\(\s*["\'](?:/lib/)?(\w+)["\']'
        for match in re.finditer(require_pattern, content):
            dep = match.group(1)
            # Only add if it's one of our modules (avoid system modules)
            if dep not in module['dependencies'] and dep != filepath.stem:
                module['dependencies'].append(dep)
        
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
        # Match --- lines including empty ones, but stop at @tags (except @usage itself)
        example_pattern = r'---@usage\s*\n((?:---(?:[^@\n].*?)?\n)+)'
        for match in re.finditer(example_pattern, content, re.MULTILINE):
            example_block = match.group(1)
            example_lines = []
            for line in example_block.split('\n'):
                if line.startswith('---'):
                    # Remove the --- prefix and exactly one space after it (if present)
                    cleaned = line[3:]
                    if cleaned.startswith(' '):
                        cleaned = cleaned[1:]
                    # Skip lines starting with @ tags, but keep empty lines
                    if not cleaned.lstrip().startswith('@'):
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
    
    def parse_program_readme(self, program_dir: Path) -> Dict[str, Any] | None:
        """Parse a program's README.md and extract documentation"""
        readme_path = program_dir / 'README.md'
        if not readme_path.exists():
            return None
        
        with open(readme_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        program = {
            'name': program_dir.name,
            'title': '',
            'description': '',
            'features': [],
            'installation': '',
            'components': [],
            'requirements': [],
            'content': content  # Store full markdown content
        }
        
        lines = content.split('\n')
        
        # Extract title from first heading
        for line in lines:
            if line.startswith('# '):
                program['title'] = line[2:].strip()
                break
        
        # Extract description (text after title, before first ## or feature list or code block or install instructions)
        in_description = False
        desc_lines = []
        for line in lines:
            if line.startswith('# '):
                in_description = True
                continue
            if in_description:
                stripped = line.strip().lower()
                if (line.startswith('##') or line.startswith('- **') or 
                    line.startswith('```') or stripped.startswith('install')):
                    break
                if line.strip():
                    desc_lines.append(line.strip())
        program['description'] = ' '.join(desc_lines)
        
        # Extract features section
        in_features = False
        for line in lines:
            if '## Features' in line or '## features' in line:
                in_features = True
                continue
            if in_features:
                if line.startswith('##'):
                    break
                if line.startswith('- '):
                    # Extract feature text, strip bold markers
                    feature = line[2:].strip()
                    feature = re.sub(r'\*\*([^*]+)\*\*', r'\1', feature)
                    program['features'].append(feature)
        
        # Extract installation command
        install_pattern = r'```(?:text|lua)?\s*\n(wget run [^\n]+)\n```'
        install_match = re.search(install_pattern, content)
        if install_match:
            program['installation'] = install_match.group(1).strip()
        
        # Extract components section
        in_components = False
        for line in lines:
            if '## Components' in line:
                in_components = True
                continue
            if in_components:
                if line.startswith('##'):
                    break
                if line.startswith('- **') or line.startswith('### '):
                    component = line.lstrip('- #').strip()
                    component = re.sub(r'\*\*([^*]+)\*\*', r'\1', component)
                    program['components'].append(component)
        
        # Extract requirements
        in_requirements = False
        for line in lines:
            if '## Requirements' in line:
                in_requirements = True
                continue
            if in_requirements:
                if line.startswith('##'):
                    break
                if line.startswith('- '):
                    req = line[2:].strip()
                    req = re.sub(r'\*\*([^*]+)\*\*', r'\1', req)
                    program['requirements'].append(req)
        
        return program
    
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
    
    def generate_html_index(self, modules: List[Dict[str, Any]], programs: List[Dict[str, Any]] = None) -> str:
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
            margin-bottom: 0.5rem;
            font-size: 2rem;
        }
        h2 {
            margin-top: 2.5rem;
            margin-bottom: 0.75rem;
            padding-bottom: 0.4rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.3rem;
            letter-spacing: 0.01em;
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
        .module, .program {
            padding: 1rem 1.25rem;
            margin: 0.75rem 0;
            border: 1px solid var(--border);
            border-radius: 6px;
        }
        .module:hover, .program:hover {
            border-color: var(--link);
        }
        .module h3, .program h3 {
            margin: 0 0 0.4rem 0;
            font-size: 1.05rem;
        }
        .module p, .program p {
            color: var(--text);
            opacity: 0.75;
            font-size: 0.95rem;
            line-height: 1.5;
        }
        .version-badge {
            display: inline-block;
            background: #2a3540;
            color: #8b949e;
            padding: 0.15rem 0.4rem;
            border-radius: 3px;
            font-size: 0.7em;
            font-weight: 500;
            margin-left: 0.5rem;
            vertical-align: middle;
        }
        .program-badge {
            display: inline-block;
            background: #1a4d1a;
            color: #7fcc7f;
            padding: 0.15rem 0.4rem;
            border-radius: 3px;
            font-size: 0.7em;
            font-weight: 500;
            margin-left: 0.5rem;
            vertical-align: middle;
        }
        code {
            background: var(--code-bg);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
        }
        .section-intro {
            margin-bottom: 1rem;
            opacity: 0.8;
            font-size: 0.95rem;
        }
    </style>
</head>
<body>
    <h1>CC-Misc Documentation</h1>
    <p style="opacity: 0.75; font-size: 0.95rem; margin-top: 0.4rem;">A collection of utility modules and programs for ComputerCraft development</p>
"""
        
        # Programs section first
        if programs:
            html += """
    <h2>Programs</h2>
    <p class="section-intro">Complete applications and systems for ComputerCraft</p>
    <div class="programs">
"""
            for program in programs:
                html += f"""        <div class="program">
            <h3><a href="programs/{program['name']}.html">{program['title'] or program['name']}</a><span class="program-badge">Program</span></h3>
            <p>{program['description'][:200]}{'...' if len(program['description']) > 200 else ''}</p>
        </div>
"""
            html += """    </div>
"""
        
        # Libraries section
        html += """
    <h2>Libraries</h2>
    <p class="section-intro">Utility libraries for building ComputerCraft applications</p>
    <div class="modules">
"""
        
        for module in modules:
            version_badge = f'<span class="version-badge">v{module["version"]}</span>' if module.get('version') else ''
            html += f"""        <div class="module">
            <h3><a href="{module['name']}.html">{module['name']}</a>{version_badge}</h3>
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
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
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
            margin-bottom: 1.25rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.6rem;
        }}
        h3 {{
            margin-top: 1.5rem;
            margin-bottom: 0.5rem;
            font-size: 1.2rem;
        }}
        code {{
            background: var(--code-bg);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'JetBrains Mono', 'Fira Code', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{
            padding: 0;
            border-radius: 0 0 8px 8px;
            overflow-x: auto;
            margin: 0;
            border: none;
            background: #1e1e1e;
        }}
        pre code {{
            background: none;
            padding: 1rem 1.25rem;
            font-size: 0.9em;
            display: block;
            line-height: 1.6;
            tab-size: 4;
        }}
        .code-block {{
            border-radius: 8px;
            overflow: hidden;
            margin: 1.5rem 0;
            border: 1px solid var(--border);
            background: #1e1e1e;
        }}
        .code-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.6rem 1rem;
            background: #2d2d2d;
            border-bottom: 1px solid #3d3d3d;
        }}
        .code-lang {{
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: #a0a0a0;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }}
        .code-lang::before {{
            content: '';
            width: 12px;
            height: 12px;
            background: #51a8ff;
            border-radius: 50%;
        }}
        .code-copy-btn {{
            background: transparent;
            border: 1px solid #555;
            color: #a0a0a0;
            padding: 0.35rem 0.75rem;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.75rem;
            font-family: inherit;
            transition: all 0.15s ease;
            display: flex;
            align-items: center;
            gap: 0.4rem;
        }}
        .code-copy-btn:hover {{
            background: #3d3d3d;
            color: #e0e0e0;
            border-color: #666;
        }}
        .code-copy-btn.copied {{
            background: #28a745;
            border-color: #28a745;
            color: white;
        }}
        .code-copy-btn svg {{
            width: 14px;
            height: 14px;
        }}
        pre code .line-numbers {{
            display: inline-block;
            width: 2.5em;
            padding-right: 1em;
            margin-right: 1em;
            text-align: right;
            color: #555;
            border-right: 1px solid #3d3d3d;
            user-select: none;
        }}
        .function:not(.token) {{
            margin: 2.5rem 0;
            padding: 1.5rem;
            border: 1px solid var(--border);
            border-radius: 6px;
        }}
        .function h3 {{
            margin-top: 0;
            margin-bottom: 0.25rem;
        }}
        .function .source-link {{
            display: block;
            font-size: 0.85em;
            opacity: 0.6;
            margin-bottom: 1rem;
        }}
        .function > p {{
            margin: 0.75rem 0 1.25rem;
            line-height: 1.75;
        }}
        .params, .returns {{
            margin-top: 1.25rem;
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
        .collapsible {{
            background: transparent;
            color: var(--link);
            cursor: pointer;
            padding: 0.75rem 1rem;
            width: 100%;
            border: 1px solid var(--border);
            text-align: left;
            outline: none;
            font-size: 0.95em;
            border-radius: 4px;
            margin-top: 1rem;
            transition: all 0.2s;
            font-family: inherit;
        }}
        .collapsible:hover {{
            background: var(--code-bg);
        }}
        .collapsible:after {{
            content: '\\25B6';
            float: right;
            margin-left: 5px;
            font-size: 0.8em;
        }}
        .collapsible.active:after {{
            content: '\\25BC';
        }}
        .collapsible-content {{
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.2s ease-out;
            border-left: 3px solid var(--border);
            padding-left: 1rem;
            margin-top: 0.5rem;
        }}
        .collapsible-content.active {{
            margin-bottom: 1rem;
        }}
        .version-badge {{
            display: inline-block;
            background: #2a3540;
            color: #8b949e;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.75em;
            font-weight: 500;
            margin-left: 1rem;
            vertical-align: middle;
        }}
        .toc {{
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 1.25rem 1.5rem;
            margin: 2rem 0;
        }}
        .toc h2 {{
            margin: 0 0 0.75rem;
            padding: 0;
            border: none;
            font-size: 0.8rem;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            opacity: 0.5;
        }}
        .toc ul {{
            list-style: none;
            padding: 0;
            margin: 0;
            columns: 2;
            column-gap: 2rem;
        }}
        @media (max-width: 600px) {{
            .toc ul {{ columns: 1; }}
        }}
        .toc li {{
            padding: 0.2rem 0;
            break-inside: avoid;
        }}
        .toc a {{
            font-size: 0.9em;
        }}
        .toc a code {{
            background: none;
            padding: 0;
            font-size: 1em;
        }}
    </style>
</head>
<body>
    <div class="back-link"><a href="index.html">← Back to index</a></div>
    <div class="header">
        <h1>{module['name']}{' <span class="version-badge">v' + module['version'] + '</span>' if module.get('version') else ''}</h1>
        <p>{description}</p>
    </div>
    
    <div class="install-section">
        <h2>Installation</h2>
"""
        
        # Add dependency warning if there are dependencies
        if module['dependencies']:
            html += f'''        <div style="background: #3b362f; border: 1px solid #d89a3a; padding: 1rem; border-radius: 4px; margin-bottom: 1rem;">
            <strong>⚠️ Dependencies:</strong> This library requires: {', '.join([f'<code style="background: #3b362f; border: 1px solid #c6ac83;">{dep}</code>' for dep in module['dependencies']])}
            <br><em>Using installer will automatically install all dependencies.</em>
        </div>\n'''

        html += f'''        <p><strong>Recommended:</strong> Install via installer (handles dependencies automatically):</p>
        <div class="install-cmd" id="installer-cmd">wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua {module['name']}</div>
            <div class="install-controls">
                <button class="copy-btn" onclick="copyCommand(this, 'installer-cmd')">Copy Command</button>
                <a href="{github_repo_url}" class="github-link" target="_blank">View on GitHub →</a>
            </div>
            
            <button class="collapsible" onclick="toggleCollapsible(this)">Advanced: Runtime Download with wget run</button>
            <div class="collapsible-content">
                <p style="margin-top: 0.5rem;">This pattern downloads and runs libraries at runtime, automatically installing any that are missing:</p>
                <div class="code-block" style="margin: 1rem 0;">
                    <div class="code-header">
                        <span class="code-lang">Lua</span>
                        <button class="code-copy-btn" onclick="copyCodeBlock(this, 'advanced-usage')">
                            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                            Copy
                        </button>
                    </div>
                    <pre><code class="language-lua" id="advanced-usage">-- Auto-install and require libraries
local libs = {{"{module['name']}"}} -- Add more libraries as needed
local libDir = (fs.exists("disk") and "disk/lib/" or "/lib/")
local allExist = true

for _, lib in ipairs(libs) do
    if not fs.exists(libDir .. lib .. ".lua") then
        allExist = false
        break
    end
end

if not allExist then
    shell.run("wget", "run", "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua", table.unpack(libs))
end

local {module['name']} = require(libDir .. "{module['name']}")

-- Use the library
-- (your code here)
</code></pre>
                </div>
            </div>\n'''

        # Only show direct wget option if there are no dependencies
        if not module['dependencies']:
            html += f'''        <p style="margin-top: 1.5rem;"><strong>Alternative:</strong> Direct download via wget:</p>
            <div class="install-cmd" id="wget-cmd">wget {github_raw_url}</div>
            <div class="install-controls">
                <button class="copy-btn" onclick="copyCommand(this, 'wget-cmd')">Copy Command</button>
            </div>\n'''
        
        html += """    </div>
    
    <script>
        function copyCommand(btn, cmdId) {
            const cmd = document.getElementById(cmdId).textContent;
            navigator.clipboard.writeText(cmd).then(() => {
                const originalText = btn.textContent;
                btn.textContent = '✓ Copied!';
                btn.classList.add('copied');
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
                btn.textContent = '✗ Failed';
                setTimeout(() => {
                    btn.textContent = 'Copy Command';
                }, 2000);
            });
        }
        
        function copyCode(btn, codeId) {
            const code = document.getElementById(codeId).textContent;
            navigator.clipboard.writeText(code).then(() => {
                const originalText = btn.textContent;
                btn.textContent = '✓ Copied!';
                btn.classList.add('copied');
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
                btn.textContent = '✗ Failed';
                setTimeout(() => {
                    btn.textContent = 'Copy Code';
                }, 2000);
            });
        }
        
        function copyCodeBlock(btn, codeId) {
            const code = document.getElementById(codeId).textContent;
            navigator.clipboard.writeText(code).then(() => {
                const svg = btn.querySelector('svg');
                const originalHTML = btn.innerHTML;
                btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg> Copied!';
                btn.classList.add('copied');
                setTimeout(() => {
                    btn.innerHTML = originalHTML;
                    btn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
            });
        }
        
        function toggleCollapsible(btn) {
            btn.classList.toggle('active');
            const content = btn.nextElementSibling;
            content.classList.toggle('active');
            if (content.style.maxHeight) {
                content.style.maxHeight = null;
            } else {
                content.style.maxHeight = content.scrollHeight + 'px';
            }
        }
    </script>
"""
        
        # Table of contents
        if module['functions']:
            html += "    <nav class='toc'>\n"
            html += "        <h2>Functions</h2>\n"
            html += "        <ul>\n"
            for func in module['functions']:
                params_str = ', '.join([p['name'] for p in func['params']])
                anchor = 'func-' + re.sub(r'[^a-zA-Z0-9]', '-', func['name']).lower()
                html += f"            <li><a href='#{anchor}'><code>{func['name']}({params_str})</code></a></li>\n"
            html += "        </ul>\n"
            html += "    </nav>\n"

        # Examples
        if module['examples']:
            html += "    <h2>Examples</h2>\n"

            for idx, example in enumerate(module['examples']):
                escaped_example = example.replace('<', '&lt;').replace('>', '&gt;')
                example_id = f"example-{idx}"
                html += f'''    <div class="code-block">
        <div class="code-header">
            <span class="code-lang">Lua</span>
            <button class="code-copy-btn" onclick="copyCodeBlock(this, '{example_id}')">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                Copy
            </button>
        </div>
        <pre><code class="language-lua" id="{example_id}">{escaped_example}</code></pre>
    </div>\n'''

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
                anchor = 'func-' + re.sub(r'[^a-zA-Z0-9]', '-', func['name']).lower()
                html += f"    <div class='function' id='{anchor}'>\n"
                params_str = ', '.join([p['name'] for p in func['params']])
                html += f"        <h3><code>{func['name']}({params_str})</code></h3>\n"

                # Add GitHub link for this function with line number
                func_github_url = f"{github_repo_url}#L{func.get('line', 1)}"
                html += f"        <a href='{func_github_url}' target='_blank' class='source-link'>View source on GitHub</a>\n"

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
    
    def generate_html_program(self, program: Dict[str, Any]) -> str:
        """Generate HTML documentation for a program from its README"""
        title = program['title'] or program['name']
        description = program['description'].replace('<', '&lt;').replace('>', '&gt;')
        github_repo_url = f"https://github.com/Twijn/cc-misc/tree/main/{program['name']}"
        
        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} - CC-Misc Programs</title>
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
            margin-top: 2.5rem;
            margin-bottom: 1rem;
            padding-bottom: 0.4rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.4rem;
        }}
        h3 {{
            margin-top: 1.75rem;
            margin-bottom: 0.5rem;
            font-size: 1.15rem;
        }}
        h4 {{
            margin-top: 1.25rem;
            margin-bottom: 0.4rem;
            font-size: 1.05rem;
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
            background: var(--code-bg);
        }}
        pre code {{
            background: none;
            padding: 0;
            font-size: 0.95em;
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
        .program-badge {{
            display: inline-block;
            background: #1a4d1a;
            color: #7fcc7f;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.75em;
            font-weight: 500;
            margin-left: 1rem;
            vertical-align: middle;
        }}
        ul {{
            margin: 0.5rem 0;
            padding-left: 1.5rem;
        }}
        li {{
            margin: 0.25rem 0;
        }}
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 1rem 0;
        }}
        th, td {{
            border: 1px solid var(--border);
            padding: 0.5rem;
            text-align: left;
        }}
        th {{
            background: var(--code-bg);
        }}
        .content {{
            line-height: 1.8;
        }}
        .content p {{
            margin: 1.1rem 0;
        }}
        .feature-list {{
            list-style: disc;
            padding-left: 1.5rem;
            margin: 1rem 0;
        }}
        .feature-list li {{
            margin: 0.6rem 0;
            line-height: 1.6;
        }}
    </style>
</head>
<body>
    <div class="back-link"><a href="../index.html">← Back to index</a></div>
    <div class="header">
        <h1>{title}<span class="program-badge">Program</span></h1>
        <p>{description}</p>
    </div>
"""
        
        # Installation section
        if program['installation']:
            html += f"""    <div class="install-section">
        <h2>Installation</h2>
        <div class="install-cmd" id="install-cmd">{program['installation']}</div>
        <div class="install-controls">
            <button class="copy-btn" onclick="copyCommand(this, 'install-cmd')">Copy Command</button>
            <a href="{github_repo_url}" class="github-link" target="_blank">View on GitHub →</a>
        </div>
    </div>
    
    <script>
        function copyCommand(btn, cmdId) {{
            const cmd = document.getElementById(cmdId).textContent;
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
        
        # Features section
        if program['features']:
            html += "    <h2>Features</h2>\n"
            html += "    <ul class='feature-list'>\n"
            for feature in program['features']:
                html += f"        <li>{feature}</li>\n"
            html += "    </ul>\n"
        
        # Components section
        if program['components']:
            html += "    <h2>Components</h2>\n"
            html += "    <ul class='feature-list'>\n"
            for component in program['components']:
                html += f"        <li>{component}</li>\n"
            html += "    </ul>\n"
        
        # Requirements section
        if program['requirements']:
            html += "    <h2>Requirements</h2>\n"
            html += "    <ul class='feature-list'>\n"
            for req in program['requirements']:
                html += f"        <li>{req}</li>\n"
            html += "    </ul>\n"
        
        # Full README content (rendered as markdown)
        # Convert markdown to HTML for the full content
        if HAS_MARKDOWN:
            md_content = program['content']
            # Remove the first heading since we already displayed it
            md_content = re.sub(r'^#\s+[^\n]+\n+', '', md_content)
            # Remove installation section since we displayed it specially
            md_content = re.sub(r'## Installation\n+```[^`]+```\n*', '', md_content)
            
            html_content = markdown.markdown(md_content, extensions=['fenced_code', 'tables'])
            html += f"""
    <div class="content">
        <h2>Full Documentation</h2>
        {html_content}
    </div>
"""
        else:
            # Fallback: just show basic content
            html += """
    <div class="content">
        <p><em>Full documentation available in the README on GitHub.</em></p>
    </div>
"""
        
        html += """</body>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-lua.min.js"></script>
</html>
"""
        return html
    
    def generate(self):
        """Generate documentation for all Lua files and programs"""
        # Create output directory
        self.output_dir.mkdir(exist_ok=True, parents=True)
        
        # Create programs subdirectory
        programs_dir = self.output_dir / 'programs'
        programs_dir.mkdir(exist_ok=True)
        
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
        
        # Parse and generate documentation for programs
        parent_dir = self.input_dir.parent
        for program_name in self.program_dirs:
            program_dir = parent_dir / program_name
            if program_dir.exists():
                program = self.parse_program_readme(program_dir)
                if program:
                    self.programs.append(program)
                    
                    # Generate HTML for program
                    html_content = self.generate_html_program(program)
                    html_path = programs_dir / f"{program['name']}.html"
                    with open(html_path, 'w', encoding='utf-8') as f:
                        f.write(html_content)
        
        # Sort modules and programs alphabetically before generating index
        self.modules.sort(key=lambda m: m['name'].lower())
        self.programs.sort(key=lambda p: (p['title'] or p['name']).lower())

        # Generate index
        index_html = self.generate_html_index(self.modules, self.programs)
        with open(self.output_dir / 'index.html', 'w', encoding='utf-8') as f:
            f.write(index_html)
        
        # Generate JSON API
        self.generate_api()
        
        print(f"Generated documentation for {len(self.modules)} modules and {len(self.programs)} programs")
        print(f"Output directory: {self.output_dir}")
    
    def generate_api(self):
        """Generate JSON API files for programmatic access"""
        # Create api directory inside docs
        api_dir = self.output_dir / 'api'
        api_dir.mkdir(exist_ok=True)

        # Exclude installer from API
        EXCLUDE_FROM_API = {"installer"}

        # Generate libraries.json with all module info
        libraries = []
        for module in self.modules:
            # Skip excluded modules
            if module['name'] in EXCLUDE_FROM_API:
                continue

            lib_info = {
                'name': module['name'],
                'version': module.get('version'),
                'description': module['description'],
                'dependencies': module['dependencies'],
                'download_url': f"https://raw.githubusercontent.com/Twijn/cc-misc/main/util/{module['name']}.lua",
                'documentation_url': f"https://ccmisc.twijn.dev/{module['name']}.html",
                'functions': [f['name'] for f in module['functions']],
                'classes': [c['name'] for c in module['classes']]
            }
            libraries.append(lib_info)

            # Generate individual library JSON files
            lib_file = api_dir / f"{module['name']}.json"
            with open(lib_file, 'w', encoding='utf-8') as f:
                json.dump(lib_info, f, indent=2)
        
        libraries.sort(key=lambda l: l['name'].lower())

        # Generate main libraries.json
        api_data = {
            'libraries': libraries,
            'updated': os.popen('date -u +"%Y-%m-%dT%H:%M:%SZ"').read().strip()
        }
        
        with open(api_dir / 'libraries.json', 'w', encoding='utf-8') as f:
            json.dump(api_data, f, indent=2)
        
        # Generate all.json with complete library details
        all_data = {
            'libraries': {},
            'updated': api_data['updated']
        }
        
        for module in self.modules:
            if module['name'] in EXCLUDE_FROM_API:
                continue
            
            all_data['libraries'][module['name']] = {
                'name': module['name'],
                'version': module.get('version'),
                'description': module['description'],
                'dependencies': module['dependencies'],
                'download_url': f"https://raw.githubusercontent.com/Twijn/cc-misc/main/util/{module['name']}.lua",
                'documentation_url': f"https://ccmisc.twijn.dev/{module['name']}.html",
                'functions': module['functions'],
                'classes': module['classes']
            }
        
        with open(api_dir / 'all.json', 'w', encoding='utf-8') as f:
            json.dump(all_data, f, indent=2)
        
        print(f"Generated API files in {api_dir}")

if __name__ == '__main__':
    generator = LuaDocGenerator('.', '../docs')
    generator.generate()
