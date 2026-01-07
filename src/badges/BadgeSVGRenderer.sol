// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ILoyaltyBadge} from "./interfaces/ILoyaltyBadge.sol";

/// @title BadgeSVGRenderer
/// @notice On-chain SVG generation for loyalty badges
/// @dev Generates unique, tier-specific badge artwork
library BadgeSVGRenderer {
    using Strings for uint256;
    using Strings for address;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    string private constant SVG_HEADER = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">';
    string private constant SVG_FOOTER = '</svg>';

    // ═══════════════════════════════════════════════════════════════════════════
    // MAIN RENDER FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate complete SVG for a badge
    /// @param info Badge information
    /// @param tokenId Token ID for uniqueness
    /// @return Complete SVG string
    function renderSVG(
        ILoyaltyBadge.BadgeInfo memory info,
        uint256 tokenId
    ) internal pure returns (string memory) {
        string memory tierName = _getTierName(info.tier);
        (string memory bgGradient, string memory accentColor) = _getTierColors(info.tier);

        return string(abi.encodePacked(
            SVG_HEADER,
            _renderBackground(bgGradient),
            _renderDiamond(accentColor, info.tier),
            _renderTierText(tierName, accentColor),
            _renderStats(info),
            _renderTokenId(tokenId),
            _renderShimmer(info.tier),
            SVG_FOOTER
        ));
    }

    /// @notice Generate token URI with base64 encoded SVG
    /// @param info Badge information
    /// @param tokenId Token ID
    /// @param holderAddress Badge holder address
    /// @return Complete data URI
    function renderTokenURI(
        ILoyaltyBadge.BadgeInfo memory info,
        uint256 tokenId,
        address holderAddress
    ) internal pure returns (string memory) {
        string memory svg = renderSVG(info, tokenId);
        string memory tierName = _getTierName(info.tier);

        string memory json = string(abi.encodePacked(
            '{"name":"Diamond Vault ',
            tierName,
            ' Badge #',
            tokenId.toString(),
            '","description":"Soulbound loyalty badge for Diamond Dividend Vault holders. Tier: ',
            tierName,
            '. Held for ',
            (info.holdingDuration / 1 days).toString(),
            ' days.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[',
            _renderAttributes(info, holderAddress),
            ']}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SVG COMPONENTS
    // ═══════════════════════════════════════════════════════════════════════════

    function _renderBackground(string memory gradient) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<defs>',
            '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
            gradient,
            '</linearGradient>',
            '<filter id="glow"><feGaussianBlur stdDeviation="3" result="blur"/>',
            '<feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
            '</defs>',
            '<rect width="400" height="400" fill="url(#bg)"/>'
        ));
    }

    function _renderDiamond(string memory color, ILoyaltyBadge.BadgeTier tier) private pure returns (string memory) {
        string memory filter = tier == ILoyaltyBadge.BadgeTier.Diamond ? ' filter="url(#glow)"' : '';
        return string(abi.encodePacked(
            '<polygon points="200,60 280,200 200,340 120,200" fill="',
            color,
            '" opacity="0.9"',
            filter,
            '/>',
            '<polygon points="200,80 260,200 200,320 140,200" fill="none" stroke="#fff" stroke-width="2" opacity="0.6"/>'
        ));
    }

    function _renderTierText(string memory tierName, string memory color) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="200" y="200" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="#fff">',
            tierName,
            '</text>',
            '<text x="200" y="230" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" fill="',
            color,
            '">HOLDER</text>'
        ));
    }

    function _renderStats(ILoyaltyBadge.BadgeInfo memory info) private pure returns (string memory) {
        string memory days_ = (info.holdingDuration / 1 days).toString();
        return string(abi.encodePacked(
            '<text x="200" y="370" text-anchor="middle" font-family="monospace" font-size="12" fill="#888">',
            days_,
            ' days | ',
            _formatBalance(info.balanceAtMint),
            ' tokens</text>'
        ));
    }

    function _renderTokenId(uint256 tokenId) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="380" y="390" text-anchor="end" font-family="monospace" font-size="10" fill="#555">#',
            tokenId.toString(),
            '</text>'
        ));
    }

    function _renderShimmer(ILoyaltyBadge.BadgeTier tier) private pure returns (string memory) {
        if (tier != ILoyaltyBadge.BadgeTier.Diamond) return '';

        return string(abi.encodePacked(
            '<animate attributeName="opacity" values="0.8;1;0.8" dur="2s" repeatCount="indefinite"/>',
            '<circle cx="200" cy="120" r="5" fill="#fff" opacity="0.8">',
            '<animate attributeName="opacity" values="0;1;0" dur="1.5s" repeatCount="indefinite"/></circle>'
        ));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // JSON ATTRIBUTES
    // ═══════════════════════════════════════════════════════════════════════════

    function _renderAttributes(
        ILoyaltyBadge.BadgeInfo memory info,
        address holder
    ) private pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"Tier","value":"',
            _getTierName(info.tier),
            '"},{"trait_type":"Days Held","value":',
            (info.holdingDuration / 1 days).toString(),
            '},{"trait_type":"Balance at Mint","value":',
            (info.balanceAtMint / 1 ether).toString(),
            '},{"trait_type":"Soulbound","value":"Yes"},{"trait_type":"Holder","value":"',
            Strings.toHexString(holder),
            '"}'
        ));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _getTierName(ILoyaltyBadge.BadgeTier tier) private pure returns (string memory) {
        if (tier == ILoyaltyBadge.BadgeTier.Bronze) return "Bronze";
        if (tier == ILoyaltyBadge.BadgeTier.Silver) return "Silver";
        if (tier == ILoyaltyBadge.BadgeTier.Gold) return "Gold";
        if (tier == ILoyaltyBadge.BadgeTier.Diamond) return "Diamond";
        return "None";
    }

    function _getTierColors(ILoyaltyBadge.BadgeTier tier) private pure returns (string memory gradient, string memory accent) {
        if (tier == ILoyaltyBadge.BadgeTier.Bronze) {
            return (
                '<stop offset="0%" stop-color="#2D1810"/><stop offset="100%" stop-color="#8B4513"/>',
                "#CD7F32"
            );
        }
        if (tier == ILoyaltyBadge.BadgeTier.Silver) {
            return (
                '<stop offset="0%" stop-color="#1a1a2e"/><stop offset="100%" stop-color="#4a4a6a"/>',
                "#C0C0C0"
            );
        }
        if (tier == ILoyaltyBadge.BadgeTier.Gold) {
            return (
                '<stop offset="0%" stop-color="#1a1a0a"/><stop offset="100%" stop-color="#4a4a2a"/>',
                "#FFD700"
            );
        }
        // Diamond
        return (
            '<stop offset="0%" stop-color="#0a0a1a"/><stop offset="100%" stop-color="#1a1a4a"/>',
            "#B9F2FF"
        );
    }

    function _formatBalance(uint256 balance) private pure returns (string memory) {
        uint256 whole = balance / 1 ether;
        if (whole >= 1_000_000) {
            return string(abi.encodePacked((whole / 1_000_000).toString(), "M"));
        }
        if (whole >= 1_000) {
            return string(abi.encodePacked((whole / 1_000).toString(), "K"));
        }
        return whole.toString();
    }
}
