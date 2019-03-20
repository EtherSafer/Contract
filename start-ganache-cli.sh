#!/bin/bash

#ganache-cli --port 55311 --mnemonic 'garden bone enrich melody traffic beyond inhale slender muffin protect wreck vote' --defaultBalanceEther 9999999 --accounts 25 --secure --deterministic --db ~/test-chain/ | grep -v "eth_\|personal\|net_\|web3_"

ganache-cli --host 0.0.0.0 --port 55311 --mnemonic 'garden bone enrich melody traffic beyond inhale slender muffin protect wreck vote' --defaultBalanceEther 9999999 --accounts 25 --secure --deterministic --db ~/test-chain/
