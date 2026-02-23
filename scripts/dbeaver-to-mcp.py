#!/usr/bin/env python3
"""
Convert DBeaver data-sources.json to MCP server configurations and environment variables.
"""

import json
import re
from pathlib import Path
from typing import Dict, List, Tuple

def sanitize_name(name: str) -> str:
    """Convert connection name to valid MCP server name."""
    # Remove special characters, convert to lowercase, replace spaces with hyphens
    sanitized = re.sub(r'[^a-zA-Z0-9\s-]', '', name)
    sanitized = sanitized.strip().lower().replace(' ', '-')
    # Remove consecutive hyphens
    sanitized = re.sub(r'-+', '-', sanitized)
    return sanitized

def parse_postgres_connection(conn_id: str, conn: Dict) -> Tuple[str, Dict, Dict]:
    """Parse PostgreSQL connection into MCP config and env vars."""
    config = conn['configuration']
    host = config.get('host', 'localhost')
    port = config.get('port', '5432')
    database = config.get('database', '')
    name = conn.get('name', conn_id)
    safe_name = sanitize_name(name)

    # Create MCP server config
    mcp_name = f"postgres-{safe_name}"
    env_var = f"POSTGRES_{safe_name.upper().replace('-', '_')}_CONNECTION"

    mcp_config = {
        "command": "${pkgs.nodejs}/bin/npx",
        "args": ["-y", "@modelcontextprotocol/server-postgres"],
        "env": {
            "POSTGRES_CONNECTION_STRING": f"${{{env_var}:-}}"
        }
    }

    # Create environment variable value
    env_value = f"postgresql://USERNAME:PASSWORD@{host}:{port}/{database}"

    return mcp_name, mcp_config, {env_var: env_value}

def parse_mysql_connection(conn_id: str, conn: Dict) -> Tuple[str, Dict, Dict]:
    """Parse MySQL connection into MCP config and env vars."""
    config = conn['configuration']
    host = config.get('host', 'localhost')
    # Remove IPv6 brackets if present
    host = host.strip('[]')
    port = config.get('port', '3306')
    database = config.get('database', '')
    name = conn.get('name', conn_id)
    safe_name = sanitize_name(name)

    # Create MCP server config
    mcp_name = f"mysql-{safe_name}"
    env_prefix = f"MYSQL_{safe_name.upper().replace('-', '_')}"

    mcp_config = {
        "command": "${pkgs.nodejs}/bin/npx",
        "args": ["-y", "@instructlab/mcp-mysql-server"],
        "env": {
            "MYSQL_HOST": f"${{{env_prefix}_HOST:-{host}}}",
            "MYSQL_PORT": f"${{{env_prefix}_PORT:-{port}}}",
            "MYSQL_USER": f"${{{env_prefix}_USER:-}}",
            "MYSQL_PASSWORD": f"${{{env_prefix}_PASSWORD:-}}",
            "MYSQL_DATABASE": f"${{{env_prefix}_DATABASE:-{database}}}"
        }
    }

    # Create environment variables
    env_vars = {
        f"{env_prefix}_HOST": host,
        f"{env_prefix}_PORT": port,
        f"{env_prefix}_USER": "your_username",
        f"{env_prefix}_PASSWORD": "your_password",
        f"{env_prefix}_DATABASE": database
    }

    return mcp_name, mcp_config, env_vars

def process_dbeaver_config(dbeaver_file: Path) -> Tuple[Dict[str, Dict], Dict[str, str]]:
    """Process DBeaver data-sources.json file."""
    with open(dbeaver_file) as f:
        data = json.load(f)

    mcp_servers = {}
    env_vars = {}

    for conn_id, conn in data.get('connections', {}).items():
        provider = conn.get('provider', '')

        try:
            if provider == 'postgresql':
                mcp_name, mcp_config, conn_env = parse_postgres_connection(conn_id, conn)
                mcp_servers[mcp_name] = mcp_config
                env_vars.update(conn_env)
            elif provider == 'mysql':
                mcp_name, mcp_config, conn_env = parse_mysql_connection(conn_id, conn)
                mcp_servers[mcp_name] = mcp_config
                env_vars.update(conn_env)
        except Exception as e:
            print(f"Warning: Failed to process {conn.get('name', conn_id)}: {e}")

    return mcp_servers, env_vars

def generate_nix_config(mcp_servers: Dict[str, Dict]) -> str:
    """Generate Nix configuration for MCP servers."""
    lines = ["  # DBeaver imported connections"]

    for mcp_name, config in sorted(mcp_servers.items()):
        lines.append(f"  {mcp_name} = {{")
        lines.append(f'    command = "{config["command"]}";')
        lines.append(f'    args = {json.dumps(config["args"])};')
        lines.append(f'    env = {{')
        for env_key, env_val in config['env'].items():
            lines.append(f'      {env_key} = "{env_val}";')
        lines.append(f'    }};')
        lines.append(f"  }};")

    return '\n'.join(lines)

def generate_env_file(env_vars: Dict[str, str], workspace_name: str) -> str:
    """Generate shell environment file."""
    lines = [
        f"# DBeaver connections from {workspace_name}",
        "# Copy relevant connections to your ~/.zshrc or use with direnv",
        ""
    ]

    # Group by prefix
    grouped = {}
    for key, value in sorted(env_vars.items()):
        prefix = key.split('_')[0]
        if prefix not in grouped:
            grouped[prefix] = []
        grouped[prefix].append((key, value))

    for prefix, vars in grouped.items():
        lines.append(f"# {prefix}")
        for key, value in vars:
            # Mask passwords
            if 'PASSWORD' in key or 'CONNECTION' in key:
                lines.append(f'export {key}="{value}"  # TODO: Add real credentials')
            else:
                lines.append(f'export {key}="{value}"')
        lines.append("")

    return '\n'.join(lines)

def main():
    """Main function."""
    dbeaver_base = Path.home() / '.local/share/DBeaverData/workspace6'

    workspaces = [
        ('General', dbeaver_base / 'General/.dbeaver/data-sources.json'),
        ('General-laptop', dbeaver_base / 'General-laptop/.dbeaver/data-sources.json')
    ]

    output_dir = Path.home() / 'programming/flakm/nix_dots/generated'
    output_dir.mkdir(exist_ok=True)

    for workspace_name, config_file in workspaces:
        if not config_file.exists():
            print(f"Skipping {workspace_name}: file not found")
            continue

        print(f"\nProcessing {workspace_name}...")
        mcp_servers, env_vars = process_dbeaver_config(config_file)

        print(f"  Found {len(mcp_servers)} database connections")

        # Generate Nix config
        nix_config = generate_nix_config(mcp_servers)
        nix_file = output_dir / f'mcp-servers-{workspace_name.lower()}.nix'
        with open(nix_file, 'w') as f:
            f.write(nix_config)
        print(f"  Wrote Nix config to: {nix_file}")

        # Generate env file
        env_content = generate_env_file(env_vars, workspace_name)
        env_file = output_dir / f'env-{workspace_name.lower()}.sh'
        with open(env_file, 'w') as f:
            f.write(env_content)
        print(f"  Wrote environment file to: {env_file}")

    print(f"\n✅ Done! Check {output_dir} for generated files")
    print("\nNext steps:")
    print("1. Review generated files")
    print("2. Add relevant MCP servers to home-manager/modules/ai.nix")
    print("3. Add credentials to environment files")
    print("4. Source the env file or add to ~/.zshrc")

if __name__ == '__main__':
    main()
