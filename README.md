# Solidity Synthetic Asset & CDP Protocol

A decentralized finance (DeFi) smart contract implementation in Solidity for managing **Collateralized Debt Positions (CDPs)** and minting synthetic assets ($\text{sAssets}$). This protocol enables users to lock stablecoin collateral ($\text{EUSD}$), maintain strict Minimum Collateral Ratios ($\text{MCR}$), and mint, burn, or trade synthetic assets.

## Architecture & Core Components

The protocol is built around two primary smart contracts:
- **`Mint.sol`**: The core protocol logic managing CDP creation, collateral management, synthetic asset issuance, and position state transitions.
- **`IMint.sol`**: The interface defining standard external functions for position lifecycle management.

### State Variables
* `_assetMap`: Mapping from sAsset token addresses to `Asset` structs (recording token metadata, price feeds, and $\text{MCR}$).
* `_currentPositionIndex`: Incremental integer tracking total positions.
* `_idxPositionMap`: Mapping from position index to `Position` structs (storing owner address, collateral balances, and minted asset details).
* `_collateralToken`: Address of the accepted collateral token ($\text{EUSD}$).

---

## Core Invariants & Mathematical Mechanics

To prevent protocol insolvency and systemic debt risk, positions are governed by the **Collateral Ratio (CR)** invariant:

$$\text{CR} = \frac{\text{Collateral Value}}{\text{Minted Asset Value}} \ge \text{MCR}$$

- **Minimum Collateral Ratio ($\text{MCR}$):** Enforced at $\text{MCR} = 2.0$ in this implementation.
- **Safety Checks:** Functions like `openPosition`, `withdraw`, and `mint` enforce that any state change maintaining or creating a CDP does not violate the $\text{MCR}$ threshold.

---

## Position Lifecycle Functions

1. **`openPosition`**: Locks $\text{EUSD}$ collateral from the sender, verifies asset registration, validates the initial $\text{MCR}$, and mints $\text{sAsset}$ tokens.
2. **`closePosition`**: Burns all associated $\text{sAsset}$ debt, unlocks and returns locked $\text{EUSD}$ collateral to the position owner, and deletes the position index.
3. **`deposit`**: Adds $\text{EUSD}$ collateral to an existing CDP owned by the message sender.
4. **`withdraw`**: Withdraws $\text{EUSD}$ collateral from an existing position, conditional upon the resulting $\text{CR}$ remaining above the $\text{MCR}$.
5. **`mint`**: Issues additional $\text{sAsset}$ tokens against existing collateral, bounded by the $\text{MCR}$ safety check.
6. **`burn`**: Repays and burns $\text{sAsset}$ debt within a specified position.

---

## Getting Started & Testing

### Prerequisites
- Node.js (LTS version recommended)
- Truffle & Ganache CLI

### Installation

1. Clone the repository:
   ```bash
   git clone [https://github.com/your-username/solidity-synthetic-cdp.git](https://github.com/your-username/solidity-synthetic-cdp.git)
   cd solidity-synthetic-cdp
