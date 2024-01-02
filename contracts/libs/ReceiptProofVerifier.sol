// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {MerklePatriciaProofVerifier} from "./MerklePatriciaProofVerifier.sol";
import {RLPReader} from "hamdiallam/Solidity-RLP@2.0.7/contracts/RLPReader.sol";

library ReceiptProofVerifier {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    uint256 constant HEADER_RECEIPTS_ROOT_INDEX = 5;
    uint256 constant HEADER_NUMBER_INDEX = 8;
    uint256 constant HEADER_TIMESTAMP_INDEX = 11;

    struct BlockHeader {
        bytes32 hash;
        bytes32 receiptsRootHash;
        uint256 number;
        uint256 timestamp;
    }

    struct Receipt {
        bool status;
        uint256 cumulativeGasUsed;
        bytes bloom;
        Log[] logs;
    }

    struct Log {
        address logger;
        bytes32[] topics;
        bytes data;
    }

    /**
     * @notice Parses block header and verifies its presence onchain within the latest 256 blocks.
     * @param headerRlpBytes RLP-encoded block header.
     */
    function verifyBlockHeader(
        bytes memory headerRlpBytes
    ) internal view returns (BlockHeader memory) {
        BlockHeader memory header = parseBlockHeader(headerRlpBytes);
        // ensure that the block is actually in the blockchain
        require(header.hash == blockhash(header.number), "blockhash mismatch");
        return header;
    }

    /**
     * @notice Parses RLP-encoded block header.
     * @param headerRlpBytes RLP-encoded block header.
     */
    function parseBlockHeader(
        bytes memory headerRlpBytes
    ) internal pure returns (BlockHeader memory) {
        RLPReader.RLPItem[] memory headerFields = headerRlpBytes
            .toRlpItem()
            .toList();

        require(headerFields.length > HEADER_TIMESTAMP_INDEX);

        BlockHeader memory result;

        result.receiptsRootHash = bytes32(
            headerFields[HEADER_RECEIPTS_ROOT_INDEX].toUint()
        );
        result.number = headerFields[HEADER_NUMBER_INDEX].toUint();
        result.timestamp = headerFields[HEADER_TIMESTAMP_INDEX].toUint();
        result.hash = keccak256(headerRlpBytes);

        return result;
    }

    /**
     * @notice Verifies Merkle Patricia proof of a receipt and extracts the receipt fields.
     *
     * @param receiptIndex Index of the receipt the provided proof corresponds to.
     * @param receiptsRootHash MPT root hash of the receipts trie containing the receipt of interest.
     */
    function extractReceiptFromProof(
        uint256 receiptIndex,
        bytes32 receiptsRootHash,
        RLPReader.RLPItem[] memory proof
    ) internal pure returns (Receipt memory) {
        bytes memory receiptRlpBytes = MerklePatriciaProofVerifier
            .extractProofValue(
                receiptsRootHash,
                _rlpEncode(receiptIndex),
                proof
            );

        Receipt memory receipt;

        if (receiptRlpBytes.length == 0) return receipt;

        // discard the transaction type prepended to the receipt payload (EIP-2718)
        if (uint256(bytes32(receiptRlpBytes[0])) >> 248 <= 0x7f) {
            assembly {
                let len := sub(mload(receiptRlpBytes), 1)
                receiptRlpBytes := add(receiptRlpBytes, 1)
                mstore(receiptRlpBytes, len)
            }
        }

        RLPReader.RLPItem[] memory receiptFields = receiptRlpBytes
            .toRlpItem()
            .toList();
        require(receiptFields.length == 4);

        receipt.status = receiptFields[0].toBoolean();
        receipt.cumulativeGasUsed = receiptFields[1].toUint();
        receipt.bloom = receiptFields[2].toBytes();

        RLPReader.RLPItem[] memory logs = receiptFields[3].toList();
        if (logs.length != 0) {
            receipt.logs = new Log[](logs.length);

            for (uint256 i = 0; i < logs.length; i++) {
                Log memory log;

                RLPReader.RLPItem[] memory logFields = logs[i].toList();

                log.logger = logFields[0].toAddress();
                log.data = logFields[2].toBytes();

                RLPReader.RLPItem[] memory topics = logFields[1].toList();
                if (topics.length != 0) {
                    log.topics = new bytes32[](topics.length);

                    for (uint256 j = 0; j < topics.length; j++) {
                        log.topics[j] = bytes32(topics[j].toUintStrict());
                    }
                }
                receipt.logs[i] = log;
            }
        }
        return receipt;
    }

    function _rlpEncode(uint256 value) private pure returns (bytes memory) {
        if (value == 0) return "\x80";
        if (value <= 0x7f) return abi.encodePacked(uint8(value));
        if (value <= type(uint8).max)
            return abi.encodePacked("\x81", uint8(value));
        if (value <= type(uint16).max)
            return abi.encodePacked("\x82", uint16(value));
        if (value <= type(uint24).max)
            return abi.encodePacked("\x83", uint24(value));
        revert();
    }
}
