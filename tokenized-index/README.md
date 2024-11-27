# Decentralized Index Fund Smart Contract

A robust Clarity smart contract implementation for managing a decentralized index fund on the Stacks blockchain. This contract enables automated portfolio management with features like token weighting, rebalancing, and fee collection.

## Features

### Core Functionality
- Multi-token portfolio management (up to 10 tokens)
- Automated weight-based portfolio rebalancing
- Management fee collection (0.3% annual)
- Deposit and withdrawal mechanisms
- Emergency pause functionality

### Security Features
- Owner-only administrative functions
- Balance and allowance checks
- Comprehensive error handling
- Portfolio rebalancing thresholds
- Pausable operations

## Technical Specifications

### Constants
```clarity
ANNUAL-MANAGEMENT-FEE-BASIS-POINTS: u30 (0.3%)
PORTFOLIO-REBALANCE-THRESHOLD-BPS: u500 (5%)
MAXIMUM_SUPPORTED_TOKENS: u10
```

### Error Codes
- `ERROR-NOT-AUTHORIZED (u100)`: Unauthorized access attempt
- `ERROR-INVALID-DEPOSIT-AMOUNT (u101)`: Invalid deposit amount
- `ERROR-INSUFFICIENT-USER-BALANCE (u102)`: Insufficient balance for withdrawal
- `ERROR-UNSUPPORTED-TOKEN (u103)`: Token not supported by the index
- `ERROR-REBALANCE-THRESHOLD-NOT-MET (u104)`: Rebalancing threshold not reached

## Usage

### Administrative Functions

#### Adding a Token to the Index
```clarity
(contract-call? .index-fund add-token-to-index "TOKEN-A" u2500)
```

#### Updating Token Price
```clarity
(contract-call? .index-fund update-token-market-price "TOKEN-A" u100000)
```

#### Pausing/Resuming Operations
```clarity
(contract-call? .index-fund pause-contract-operations)
(contract-call? .index-fund resume-contract-operations)
```

### User Functions

#### Depositing Tokens
```clarity
(contract-call? .index-fund deposit-tokens "TOKEN-A" u1000)
```

#### Withdrawing Tokens
```clarity
(contract-call? .index-fund withdraw-tokens "TOKEN-A" u500)
```

### Read-Only Functions

#### Checking User Balance
```clarity
(contract-call? .index-fund get-user-balance tx-sender)
```

#### Getting Token Weight
```clarity
(contract-call? .index-fund get-token-allocation-weight "TOKEN-A")
```

## Contract Architecture

### Data Storage
- `user-token-balances`: Maps user principals to their token balances
- `target-token-allocation-weights`: Stores target weights for each token
- `supported-token-list`: Tracks supported tokens
- `current-token-market-prices`: Stores current token prices

### Key Mechanisms

#### Fee Calculation
The management fee is calculated based on:
- Annual rate of 0.3%
- Time elapsed since last rebalance
- Withdrawal amount

#### Rebalancing
Portfolio rebalancing is triggered when:
- Total deviation exceeds 5%
- Called by contract owner
- Contract is not paused

## Security Considerations

1. Access Control
   - Only contract owner can add tokens
   - Only owner can update prices
   - Only owner can trigger rebalancing

2. Input Validation
   - Non-zero amounts for deposits/withdrawals
   - Valid token identifiers
   - Sufficient balances

3. State Management
   - Atomic operations
   - Proper balance updates
   - Accurate fee calculations

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Create pull request
5. Wait for review