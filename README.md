## Protocol Core

### Deployment address

#### Base Georli

| Contract Name            | Addresses                                  |
| ------------------------ | ------------------------------------------ |
| Vault Contract           | 0xE2386C5eF4deC9d5815C60168e36c7153ba00D0C |
| Currency Contract (xNGN) | 0xee2bDAE7896910c49BeA25106B9f8e9f4B671c82 |
| Feed Contract            | 0x970066EE55DF2134D1b52451afb49034AE5Fa29a |

#### Base Sepolia

| Contract Name            | Addresses                                  |
| ------------------------ | ------------------------------------------ |
| Vault Contract           | 0x3d35807343CbF4fDb16E42297F2214f62848D032 |
| Currency Contract (xNGN) | 0xB8747e5cce01AA5a51021989BA11aE33097db485 |
| Feed Contract            | 0xFBD26B871D55ba56B7a780eF1fF243Db7A3E81f4 |
| Rate Contract            | 0x00A0BcB0e2099f4a0564c26e24eBfA866D3235D6 |

To install libraries needed, run:

```zsh
forge install
```

To run tests, run:

```zsh
forge test -vvv --gas-report
```

To run slither, run:

```zsh
slither .
```

To start a local node, run:

```zsh
anvil
```

To run deploy the deploy script, (be sure to have the parameters in `./deployConfigs/*.json/` needed for your script populated and also have an anvil instance running), run:

```zsh
forge script script/deploy.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast
```

## Deploy Config

Meaning of parameters of the deploy configs

- baseRate: The base rate of the protocol, should be the per second rate, e.g 1.5% would be `((uint256(1.5e18) / uint256(100)) / uint256(365 days)`, i.e `475646879`.
- collaterals: collateral types
  - collateralAddress: contract address of the given collateral on the given chain.
  - collateralRate: The collateral rate of the given collateral on the given chain, calculated same as baseRate.
  - liquidationThreshold: liquidation threshold of the given collateral, denominated in wad, where `1e18 == 100%` and `0.5e18 == 50%`.
  - liquidationBonus: liquidation bonus of the given collateral, denominated same as liquidationThreshold.
  - debtCeiling: debt ceiling of the currency for the given collateral.
  - collateralFloorPerPosition: minimum amount of collateral allowed to borrow against.
