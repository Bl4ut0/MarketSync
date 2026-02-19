# MarketSync Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0-beta] - 2026-02-19
### Initial Public Beta Release
First major release for testing. Introduces the core Guild Sync functionality and Offline Browsing.

### Added
- **Passive Guild Sync**: Automatically shares Auctionator scan data between guild members in the background.
- **Offline Auction House**: Browse the entire synced database anywhere in the world via `/ms` or the minimap button.
- **Chat Price Checks**: 
    - Type `? [Item Link]` in chat to query the network for the latest price.
    - Added **Anti-Flood System**: Randomized response delay (0.5s - 2.0s) to prevent chat spam when multiple users have the addon.
    - Added suppression logic: If another user replies first, your addon cancels its pending message.
- **History & Analytics**:
    - "History" button in Browse tab opens a detailed graph of price trends.
    - View individual scan data points (Price, Quantity, Scanner Name).
- **Settings Panel**:
    - **Lock Minimap Button**: Prevent accidental drags.
    - **Enable/Disable Chat Replies**: Toggle the `?` query feature.
    - **Passive Sync**: Turn background data sharing on/off.
    - **Debug Mode**: View verbose sync logs.
- **UI & Aesthetics**:
    - Custom "Paper Doll" style 2D Character Portrait in the main window.
    - Clean, tabbed interface (Browse, Personal Scan, Guild Sync, Leaderboard, Settings).
    - Minimap Button: Left-Click to open window, Right-Click to jump straight to Settings.
    - Custom Icon integration (support for `icon.tga` or `.blp` in addon folder).
    
### Changed
- Rebranded from "AuctionatorAnnouncer" to **MarketSync**.
- Moved "Lock Minimap Button" option from Interface Options to the main addon Settings tab for better accessibility.
- Optimized item cache building to run in the background without freezing the game client.
- Standardized background textures to official Blizzard `Browse` styling for seamless integration.

### Fixed
- Fixed "hard edge" visual artifacts on the main window background.
- Fixed overlapping text in the Settings tab layout.

## [0.3.0] - 2026-02-18 (Internal)
### Added
- Basic chat query functionality.
- Initial implementation of the Browse tab.

## [0.2.0] - 2026-02-17 (Internal)
### Added
- Core sync protocol (`ADV` / `REQ` / `PULL` / `RES`).
- Database structure for storing multi-realm data.

## [0.1.0] - 2026-02-15 (Internal)
### Added
- Project initialization.
- Auctionator API integration.
