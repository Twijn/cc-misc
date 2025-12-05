# SignShop

CC: Tweaked program that creates plugin-like SignShops with automated item dispensing and Krist payment processing.

## Installation

Install SignShop on a disk drive to enable automatic startup for connected computers and turtles:

```text
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/signshop/install.lua
```

## Components

- **Server** - Runs on a regular computer, manages inventory, products, and Krist payments
- **Aisle** - Runs on turtles, handles item dispensing from storage to customers

## Updating

To update SignShop and its libraries, run:

```text
update            # Update all components
update libs       # Update only libraries  
update signshop   # Update only SignShop files
```

## Features

- Automatic item dispensing via networked turtles
- Krist payment integration via ShopK
- ShopSync broadcasting for shop directories
- Interactive form-based setup using FormUI
- Persistent data storage with automatic recovery

## Requirements

- Wired modems for inventory and turtle communication
- Wireless modem for Krist/ShopSync
- Signs with product information formatted as:
  - Line 1: Product name (part 1)
  - Line 2: Product name (part 2)
  - Line 3: `<price> <aisle-name>`
  - Line 4: Product meta identifier

