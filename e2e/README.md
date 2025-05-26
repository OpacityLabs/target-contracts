## E2E Test
The purpose of the e2e test is to test fully the usage of the SP1Helios bridge, from deployment to verifying signatures on an L2

## TODO
> **Note:** This TODO list is a temporary placeholder and not comprehensive. It will be replaced by GitHub issues once we have a working e2e

- [ ] Use GHCR instead of submodule for docker dependancies

## Scrambled Notes
Collecting noteworthy information to later organize

- We can't run e2e on local environemnt because running anvil on a fork does not produce real state roots
- When running `TESTNET` mode, fork urls don't matter
- there is logic duplication between scripts (e.g. logic of handling local vs testnet environments when it comes to deployer)

A design choice I made I don't like is to read the env files in each script - there has to be a better way to do it

Also when something goes wrong in `eigenlayer-bls-local` it's not debugable because everything is piped into /dev/null
