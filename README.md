# DexalotRouter-ulnerabilities
DexRouterМulnerabilities

Hello, I found some vulnerabilities in the DexalotRouter.sol contract, here they are: In multiPartialSwap there was an incorrect check destTraderA == address(this) — fixed to destTraderA == msg.sender. In fallback, handling of msg.value > 0 for native ETH was added. A gas limit {gas: gasleft()} was added to all calls. In setAllowedRFQ, a duplicate check was added when adding a new RFQ. Using abi.encodePacked to add msg.sender to calldata can lead to collisions — make sure there is no additional data in msg.data. Here is the code that solves these issues.there is also a test for Foundry in the code
