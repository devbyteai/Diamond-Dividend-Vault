// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILayerZeroEndpoint
/// @notice Minimal interface for LayerZero cross-chain messaging endpoint
/// @dev Based on LayerZero V1 endpoint interface for cross-chain dividend distribution
interface ILayerZeroEndpoint {
    /// @notice Send a cross-chain message to the specified destination
    /// @param dstChainId The destination chain identifier
    /// @param destination The destination address encoded as bytes
    /// @param payload The message payload to send
    /// @param refundAddress Address to refund excess native gas fees
    /// @param zroPaymentAddress Address for ZRO token payment (address(0) to pay in native)
    /// @param adapterParams Additional adapter parameters for the message
    function send(
        uint16 dstChainId,
        bytes calldata destination,
        bytes calldata payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable;

    /// @notice Estimate fees for sending a cross-chain message
    /// @param dstChainId The destination chain identifier
    /// @param userApplication The user application address
    /// @param payload The message payload
    /// @param payInZRO Whether to pay fees in ZRO token
    /// @param adapterParams Additional adapter parameters
    /// @return nativeFee The estimated fee in native token
    /// @return zroFee The estimated fee in ZRO token
    function estimateFees(
        uint16 dstChainId,
        address userApplication,
        bytes calldata payload,
        bool payInZRO,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    /// @notice Get the inbound nonce for a source chain and address
    /// @param srcChainId The source chain identifier
    /// @param srcAddress The source address
    /// @return The current inbound nonce
    function getInboundNonce(
        uint16 srcChainId,
        bytes calldata srcAddress
    ) external view returns (uint64);

    /// @notice Get the outbound nonce for a destination chain and address
    /// @param dstChainId The destination chain identifier
    /// @param srcAddress The source address
    /// @return The current outbound nonce
    function getOutboundNonce(
        uint16 dstChainId,
        address srcAddress
    ) external view returns (uint64);

    /// @notice Retry a failed payload
    /// @param srcChainId The source chain identifier
    /// @param srcAddress The source address
    /// @param payload The payload to retry
    function retryPayload(
        uint16 srcChainId,
        bytes calldata srcAddress,
        bytes calldata payload
    ) external;

    /// @notice Check if there is a stored payload for an address
    /// @param srcChainId The source chain identifier
    /// @param srcAddress The source address
    /// @return True if there is a stored payload
    function hasStoredPayload(
        uint16 srcChainId,
        bytes calldata srcAddress
    ) external view returns (bool);

    /// @notice Get the send library address
    /// @param userApplication The user application address
    /// @return The send library address
    function getSendLibraryAddress(address userApplication) external view returns (address);

    /// @notice Get the receive library address
    /// @param userApplication The user application address
    /// @return The receive library address
    function getReceiveLibraryAddress(address userApplication) external view returns (address);

    /// @notice Check if the endpoint is sending
    /// @return True if currently sending a message
    function isSendingPayload() external view returns (bool);

    /// @notice Check if the endpoint is receiving
    /// @return True if currently receiving a message
    function isReceivingPayload() external view returns (bool);

    /// @notice Get the chain ID of this endpoint
    /// @return The LayerZero chain ID
    function getChainId() external view returns (uint16);
}

/// @title ILayerZeroReceiver
/// @notice Interface for contracts that can receive LayerZero messages
interface ILayerZeroReceiver {
    /// @notice Receive a cross-chain message
    /// @param srcChainId The source chain identifier
    /// @param srcAddress The source address encoded as bytes
    /// @param nonce The message nonce
    /// @param payload The message payload
    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64 nonce,
        bytes calldata payload
    ) external;
}

/// @title ILayerZeroUserApplicationConfig
/// @notice Interface for configuring LayerZero user applications
interface ILayerZeroUserApplicationConfig {
    /// @notice Set the configuration for the application
    /// @param version The messaging library version
    /// @param chainId The chain to configure
    /// @param configType The type of configuration
    /// @param config The configuration data
    function setConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType,
        bytes calldata config
    ) external;

    /// @notice Set the send messaging library version
    /// @param version The version to set
    function setSendVersion(uint16 version) external;

    /// @notice Set the receive messaging library version
    /// @param version The version to set
    function setReceiveVersion(uint16 version) external;

    /// @notice Force resume receiving if blocked
    /// @param srcChainId The source chain identifier
    /// @param srcAddress The source address
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress) external;
}
