// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {RLPReader} from "hamdiallam/Solidity-RLP@2.0.7/contracts/RLPReader.sol";
import {ReceiptProofVerifier as Verifier} from "../libs/ReceiptProofVerifier.sol";

interface IBlockHashOracle {
    // a null value signifies block hash has not yet been set
    function get_block_hash(
        uint256 _block_number
    ) external view returns (bytes32);
}

contract XProxy {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    struct ExecutionData {
        address target;
        bytes data;
        uint256 value;
    }

    bytes32 constant EXECUTE_TOPIC = keccak256("Execute(bytes32)");

    address public immutable BLOCK_HASH_ORACLE;

    mapping(uint256 => bool) public completed;

    constructor(address _block_hash_oracle) {
        BLOCK_HASH_ORACLE = _block_hash_oracle;
    }

    function submit(
        ExecutionData[] memory _execution_data,
        uint256 _receipt_index,
        bytes memory _block_header_rlp,
        bytes memory _proof_rlp
    ) external {
        require(_execution_data.length >= 1);

        Verifier.BlockHeader memory block_header = Verifier.parseBlockHeader(
            _block_header_rlp
        );
        require(block_header.hash != bytes32(0)); // dev: invalid blockhash
        require(!completed[block_header.number]); // dev: already completed
        require(
            block_header.hash ==
                IBlockHashOracle(BLOCK_HASH_ORACLE).get_block_hash(
                    block_header.number
                )
        ); // dev: blockhash mismatch


        // convert _proof_rlp into a list of `RLPItem`s
        RLPReader.RLPItem[] memory proof = _proof_rlp.toRlpItem().toList();

        Verifier.Receipt memory receipt = Verifier.extractReceiptFromProof(
            _receipt_index,
            block_header.receiptsRootHash,
            proof
        );

        uint256 i = 0; // execution data pointer
        for (uint256 j = 0; j < receipt.logs.length; j++) {
            if (_execution_data.length == i) break;

            if (receipt.logs[j].logger != address(this)) continue;
            if (receipt.logs[j].topics[0] != EXECUTE_TOPIC) continue;

            ExecutionData memory execution_data = _execution_data[i++];

            // match the fingerprint
            require(
                keccak256(
                    abi.encode(
                        execution_data.target,
                        keccak256(execution_data.data),
                        execution_data.value
                    )
                ) == receipt.logs[j].topics[1]
            );

            execution_data.target.call{value: execution_data.value}(execution_data.data);
        }

        completed[block_header.number] = true;
    }
}
