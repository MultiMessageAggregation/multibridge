# Local Development
**Pre-requisites:**
- Install the [Foundry](https://github.com/foundry-rs/foundry) toolkit.
- Clone repository:
    ```sh
    $   git clone https://github.com/MultiMessageAggregation/multibridge
    ```
**Step 1:** Install required forge submodules

```sh
$  forge install
```

**Step 2:** Build the project

```sh
$  forge build
```

**Step 3:** Run Tests

To run the tests, you will need a local fork of Ethereum, Polygon, and BSC mainnet states. To accomplish this, you must specify RPC endpoints for each of these networks. You can obtain RPC endpoints to use for Ethereum and Polygon, from Alchemy, Infura, or other infrastructure providers. For BSC, you can choose from a list of public RPC endpoints available [here](https://docs.bscscan.com/misc-tools-and-utilities/public-rpc-nodes).

To set the RPC endpoints, make a copy of the `.env.sample` file and name it `.env`. The file contains a list of parameter names (e.g. `ETH_FORK_URL`) that correspond to each network. Set the respective values of each of these parameters to the RPC endpoints you wish to use.

Once you have set these values, you can run both the unit and integration tests using the following command:

```sh 
$  forge test
```
**note:** We use [pigeon](https://github.com/exp-table/pigeon/tree/docs) to simulate the cross-chain behavior on forked mainnets.
