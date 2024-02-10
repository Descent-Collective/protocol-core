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

# Version 0.1.2

## Compiler settings

Solidity compiler: [0.8.21]

### contracts
- Vault Contract: `0xE2386C5eF4deC9d5815C60168e36c7153ba00D0C`
- Currency Contract(xNGN):    `0xee2bDAE7896910c49BeA25106B9f8e9f4B671c82`
- Feed Contract     `0x970066EE55DF2134D1b52451afb49034AE5Fa29a`

## Changes
- Fix wrong calculation of withdrawable collateral
- Fix typos


# Sepolia Version 0.1.0

## Compiler settings

Solidity compiler: [0.8.21]

### contracts
- Vault Contract: `0x18196CCaA8C2844c82B40a8bDCa27349C7466280`
- Currency Contract(xNGN):    `0x5d0583Ef20884C0b175046d515Ec227200C12C89`
- Feed Contract     `0x970066EE55DF2134D1b52451afb49034AE5Fa29a`
- Rate Contract     `0x774843f6Baa4AAE62F026a8aF3c1C6FF3e55Ca39`

## Changes
- Use 18 decimlas for rate and liquidation threshold
- Abstract the rate calculation to a different contract to make it modular
- Add global debt ceiling and add check for global and collateral debt ceiling when minting, also update deploy script and tests
- Enable users to be able to repay and withdraw during paused
- Added invariant tests and fix noticed bugs
- Added fuzzed unit test for currency contract
- Integrate the OSM, Median and Feed into the invariant tests
- Replace open zeppelin with solady.
- Use rounding down for liquidation reward calculation
- Added invariant tests and fix noticed bugs

# Sepolia Version 0.1.1

## Compiler settings

Solidity compiler: [0.8.21]

### contracts
- Vault Contract: `0x3d35807343CbF4fDb16E42297F2214f62848D032`
- Currency Contract(xNGN):    `0xB8747e5cce01AA5a51021989BA11aE33097db485`
- Feed Contract     `0xFBD26B871D55ba56B7a780eF1fF243Db7A3E81f4`
- Rate Contract     `0x00A0BcB0e2099f4a0564c26e24eBfA866D3235D6`

## Changes
- Fix rate config bug