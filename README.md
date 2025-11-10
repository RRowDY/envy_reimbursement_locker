# Envy Reimbursement Locker

A reimbursement locker system for ESX Legacy servers.

## Features

- Multiple locker locations with configurable props
- Virtual locker support (no prop required)
- Admin UI for searching players by license
- Integration with ox_inventory
- ESX Legacy compatible

## Installation

1. Place this resource in your `resources/[envy]` folder
2. Add `ensure envy_reimbursement_locker` to your `server.cfg`
3. Configure locker locations in `config.lua`

## Dependencies

- es_extended (ESX Legacy)
- ox_inventory
- oxmysql

## Configuration

Edit `config.lua` to customize:
- Locker locations and props
- Stash settings
- Allowed admin groups
- Command name

## License

See LICENSE file for details.

