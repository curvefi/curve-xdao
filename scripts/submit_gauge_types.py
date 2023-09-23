import eth_abi
import rlp
from brownie import GaugeTypeOracleProxyOwner, accounts, web3
from hexbytes import HexBytes

BLOCK_NUMBER = 18160000
GAUGES = [
    "0xd662908ADA2Ea1916B3318327A97eB18aD588b5d",
    "0x7ca5b0a2910B33e9759DC7dDB0413949071D7575",
    "0xB1F2cdeC61db658F091671F5f199635aEF202CAC",
]
GAUGE_CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"

# avax addys
SUBMISSION_ACCT = "0xF6154eb3495A38931c5A1554cAfC2B87b7D7d468"
ORACLE = "0x95ae66886274eA66Fc44B02Da59320e9384bD507"


# https://github.com/ethereum/go-ethereum/blob/master/core/types/block.go#L69
BLOCK_HEADER = (
    "parentHash",
    "sha3Uncles",
    "miner",
    "stateRoot",
    "transactionsRoot",
    "receiptsRoot",
    "logsBloom",
    "difficulty",
    "number",
    "gasLimit",
    "gasUsed",
    "timestamp",
    "extraData",
    "mixHash",
    "nonce",
    "baseFeePerGas",  # added by EIP-1559 and is ignored in legacy headers
    "withdrawalsRoot",  # added by EIP-4895 and is ignored in legacy headers
    "blobGasUsed",  # added by EIP-4844 and is ignored in legacy headers
    "excessBlobGas",  # added by EIP-4844 and is ignored in legacy headers
    "parentBeaconBlockRoot",  # added by EIP-4788 and is ignored in legacy headers
)


def serialize_block(block):
    block_header = [
        HexBytes("0x") if isinstance((v := block[k]), int) and v == 0 else HexBytes(v)
        for k in BLOCK_HEADER
        if k in block
    ]
    return rlp.encode(block_header)


def serialize_proofs(proofs):
    account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
    storage_proofs = [
        list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
    ]
    return rlp.encode([account_proof, *storage_proofs])


def generate_proof():
    block_header_rlp = serialize_block(web3.eth.get_block(BLOCK_NUMBER))
    keys = [web3.keccak(eth_abi.encode_single("(uint256,address)", [8, gauge])) for gauge in GAUGES]
    proof_rlp = serialize_proofs(web3.eth.get_proof(GAUGE_CONTROLLER, keys, BLOCK_NUMBER))

    with open("header.txt", "w") as f:
        f.write(block_header_rlp.hex())

    with open("proof.txt", "w") as f:
        f.write(proof_rlp.hex())


def submit_proof():
    dev = accounts.load("dev")
    submitter = GaugeTypeOracleProxyOwner.at(SUBMISSION_ACCT)

    with open("header.txt") as f:
        block_header_rlp = f.read()

    with open("proof.txt") as f:
        proof_rlp = f.read()

    submitter.submit(ORACLE, GAUGES, block_header_rlp, proof_rlp, {"from": dev})
