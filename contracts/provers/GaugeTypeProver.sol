// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {RLPReader} from "hamdiallam/Solidity-RLP@2.0.7/contracts/RLPReader.sol";
import {StateProofVerifier as Verifier} from "../libs/StateProofVerifier.sol";

interface IBlockHashOracle {
    function get_block_hash(uint256 _number) external view returns (bytes32);
}

interface IGaugeTypeOracle {
    function set_gauge_type(address _gauge, uint256 _type) external;
}

/// @title Gauge Type Prover
/// @author Curve Finance
contract GaugeTypeProver {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    address constant GAUGE_CONTROLLER =
        0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
    bytes32 constant GAUGE_CONTROLLER_HASH =
        keccak256(abi.encodePacked(GAUGE_CONTROLLER));

    address public immutable BLOCK_HASH_ORACLE;
    address public immutable GAUGE_TYPE_ORACLE;

    constructor(address _block_hash_oracle, address _gauge_type_oracle) {
        BLOCK_HASH_ORACLE = _block_hash_oracle;
        GAUGE_TYPE_ORACLE = _gauge_type_oracle;
    }

    /// Prove the type of a gauge.
    /// @param _gauges List of gauges to prove the type of.
    /// @param _block_header_rlp The block header of any block in which the gauge has its type set.
    /// @param _proof_rlp The state proof of the gauge types.
    function prove(
        address[] memory _gauges,
        bytes memory _block_header_rlp,
        bytes memory _proof_rlp
    ) external {
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
        require(proofs.length >= 2 && proofs.length - 1 == _gauges.length); // dev: invalid number of proofs

        // 0th proof is the account proof for the Gauge Controller contract
        Verifier.Account memory account = Verifier.extractAccountFromProof(
            GAUGE_CONTROLLER_HASH, // position of the account is the hash of its address
            block_header.stateRootHash,
            proofs[0].toList()
        );
        require(account.exists); // dev: Gauge Controller account does not exist

        // iterate through each proof and set the gauge type of each gauge
        Verifier.SlotValue memory slot;
        for (uint256 idx = 1; idx < proofs.length; idx++) {
            slot = Verifier.extractSlotValueFromProof(
                keccak256(
                    abi.encode(keccak256(abi.encode(8, _gauges[idx - 1])))
                ),
                account.storageRoot,
                proofs[idx].toList()
            );
            require(slot.exists && slot.value != 0);

            IGaugeTypeOracle(GAUGE_TYPE_ORACLE).set_gauge_type(
                _gauges[idx - 1],
                slot.value - 1 // the true gauge type is the slot value - 1
            );
        }
    }
}
