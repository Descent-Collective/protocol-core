## Protocol Core

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

To run deploy the deploy script, (be sure to have the parameters in `./deployParameters.json` needed for your script populated and also have an anvil instance running), run:

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
