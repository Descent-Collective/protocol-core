## Protocol Core

### Deployment address

#### Base Goerli

| Contract Name            | Addresses                                  |
| ------------------------ | ------------------------------------------ |
| Vault Contract           | 0xCaC650a8F8E71BDE3d60f0B020A4AA3874974705 |
| Currency Contract (xNGN) | 0xC8A88052006142d7ae0B56452e1f153BF480E341 |
| Feed Contract            | 0xEdC725Db7e54C3C85EB551E859b90489d076a9Ca |

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
