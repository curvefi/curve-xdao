// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {RLPReader} from "hamdiallam/Solidity-RLP@2.0.7/contracts/RLPReader.sol";
import {StateProofVerifier as Verifier} from "../libs/StateProofVerifier.sol";

interface IBlockHashOracle {
    function get_block_hash(uint256 _number) external view returns (bytes32);
}

interface IRelayer {
    struct Message {
        address target;
        bytes data;
    }

    function relay(uint256 agent, Message[] calldata messages) external;
}

/// @title Message Digest Prover
/// @author Curve Finance
contract MessageDigestProver {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    address constant BROADCASTER = 0xC03544C4C2216ea5e01F066FE402AB9040F56Fe5;
    bytes32 constant BROADCASTER_HASH =
        keccak256(abi.encodePacked(BROADCASTER));

    uint256 constant OWNERSHIP_AGENT = 1;
    uint256 constant PARAMETER_AGENT = 2;
    uint256 constant EMERGENCY_AGENT = 4;

    address public immutable BLOCK_HASH_ORACLE;
    address public immutable RELAYER;

    uint256 public nonce;

    constructor(address _block_hash_oracle, address _relayer) {
        BLOCK_HASH_ORACLE = _block_hash_oracle;
        RELAYER = _relayer;
    }

    /// Prove a message digest and optionally execute.
    /// @param _agent The agent which produced the execution digest. (1 = OWNERSHIP, 2 = PARAMETER, 4 = EMERGENCY)
    /// @param _messages The sequence of messages to execute.
    /// @param _block_header_rlp The block header of any block in which the gauge has its type set.
    /// @param _proof_rlp The state proof of the gauge types.
    function prove(
        uint256 _agent,
        IRelayer.Message[] memory _messages,
        bytes memory _block_header_rlp,
        bytes memory _proof_rlp
    ) external {
        require(
            _agent == OWNERSHIP_AGENT ||
                _agent == PARAMETER_AGENT ||
                _agent == EMERGENCY_AGENT
        );
        require(_messages.length != 0);

        Verifier.BlockHeader memory block_header = Verifier.parseBlockHeader(
            _block_header_rlp
        );
        require(block_header.hash != bytes32(0)); // dev: invalid blockhash
        require(
            block_header.hash ==
                IBlockHashOracle(BLOCK_HASH_ORACLE).get_block_hash(
                    block_header.number
                )
        ); // dev: blockhash mismatch

        // convert _proof_rlp into a list of `RLPItem`s
        RLPReader.RLPItem[] memory proofs = _proof_rlp.toRlpItem().toList();
        require(proofs.length == 2); // dev: invalid number of proofs

        // 0th proof is the account proof for the Broadcaster contract
        Verifier.Account memory account = Verifier.extractAccountFromProof(
            BROADCASTER_HASH, // position of the account is the hash of its address
            block_header.stateRootHash,
            proofs[0].toList()
        );
        require(account.exists); // dev: Broadcaster account does not exist

        Verifier.SlotValue memory slot = Verifier.extractSlotValueFromProof(
            keccak256(
                abi.encode(
                    keccak256( // self.digest[_agent][_chain_id][_nonce]
                        abi.encode(
                            keccak256( // self.digest[_agent][_chain_id]
                                abi.encode(
                                    keccak256(abi.encode(8, _agent)), // self.digest[_agent]
                                    block.chainid
                                )
                            ),
                            nonce++
                        )
                    )
                )
            ),
            account.storageRoot,
            proofs[1].toList()
        );

        require(slot.exists && slot.value != 0);
        require(keccak256(abi.encode(_messages)) == bytes32(slot.value));

        IRelayer(RELAYER).relay(_agent, _messages);
    }
}
