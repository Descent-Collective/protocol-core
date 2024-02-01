# Delete the current artifacts
abis=./abis
rm -rf $abis

# Create the new artifacts directories
mkdir $abis \

# Generate the artifacts with Forge
FOUNDRY_PROFILE=optimized forge build

# Copy the production abis
cp out/vault.sol/Vault.json $abis
cp out/currency.sol/Currency.json $abis
cp out/feed.sol/Feed.json $abis
cp out/rate.sol/SimpleInterestRate.json $abis