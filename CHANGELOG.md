# Changelog

# Version 0.1.0

## Compiler settings

Solidity compiler: [0.8.21]

### contracts
- Vault Contract: `0xc93d667F5381CF2E41722829DF14E016bBb33A6A`
- Currency Contract(xNGN):    `0xED68D8380ED16ad69b861aDFae3Bf8fF75Acc25f`
- Feed Contract     `0xEA263AD21E04d695a750D8Dc04d2b952dF7405aa`

## Changes
- Add tests for liquidation
- Add burnCurrency tests
- Add default permit2 support for currencies
- Allow deny to vault

# Version 0.1.1

## Compiler settings

Solidity compiler: [0.8.21]

### contracts
- Vault Contract: `0xCaC650a8F8E71BDE3d60f0B020A4AA3874974705`
- Currency Contract(xNGN):    `0xC8A88052006142d7ae0B56452e1f153BF480E341`
- Feed Contract     `0xEdC725Db7e54C3C85EB551E859b90489d076a9Ca`

## Changes
- Replace use of health factor with collateral ratio
- Fix wrong emitted event data and add tests for it
- Add more natspec and use GPL-3.0 license