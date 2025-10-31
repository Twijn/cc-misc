# installergen

Installer Generator for CC-Misc Utilities Interactive tool to install ComputerCraft libraries with dependency management This tool provides a user-friendly interface to select and install libraries from the cc-misc repository directly to your ComputerCraft computer. Library information is loaded from the online API at https://ccmisc.twijn.dev/api/all.json with automatic fallback to offline mode. Features: - Dynamic library loading from API with detailed information - Press RIGHT arrow to view library details (functions, version, dependencies) - Automatic dependency resolution - Visual indicators for selections and requirements - Install/update or generate installer scripts

## Examples

```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installergen.lua
Or pre-select libraries:
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installergen.lua cmd s
```

