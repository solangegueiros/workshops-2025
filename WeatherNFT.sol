// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Importing OpenZeppelin contracts
import "@openzeppelin/contracts@4.6.0/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.6.0/utils/Counters.sol";
import "@openzeppelin/contracts@4.6.0/utils/Base64.sol";

contract WeatherNFT is ERC721, ERC721URIStorage {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter public tokenIdCounter;

    constructor() ERC721("Weather Functions NFT", "WEAT") {
    }

    function mint(address to, string memory city, string memory weather) public {
        uint256 tokenId = tokenIdCounter.current();
        tokenIdCounter.increment();
        _safeMint(to, tokenId);
        updateSVG(tokenId, city, weather);
    }

    // Update the SVG
    function updateSVG(uint256 tokenId, string memory city, string memory weather) public {
        // Create the SVG string        
        string memory icon = getFirstChar(weather);
        string memory finalSVG = buildSVG(icon);
        // Base64 encode the SVG
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', city, '",',
                        '"description": "weather in the city",',
                        '"image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(finalSVG)), '",',
                        '"attributes": [',
                            '{"trait_type": "city",',
                            '"value": "', city ,'"},',
                            '{"trait_type": "weather",',
                            '"value": "', weather ,'"}',
                        ']}'
                    )
                )
            )
        );
        // Create token URI
        string memory finalTokenURI = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        // Set token URI
        _setTokenURI(tokenId, finalTokenURI);
    }

    // Build the SVG string
    function buildSVG(string memory icon) private pure returns (string memory) {

        // Create SVG rectangle with another color
        string memory fillColor = "#D7BDE2";
        string memory headSVG = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' version='1.1' xmlns:xlink='http://www.w3.org/1999/xlink' xmlns:svgjs='http://svgjs.com/svgjs' width='500' height='500' preserveAspectRatio='none' viewBox='0 0 500 500'> <rect width='100%' height='100%' fill='",
                fillColor,
                "' />"
            )
        );
        // Update emoji based on price
        string memory bodySVG = string(
            abi.encodePacked(
                "<text x='50%' y='50%' font-size='128' dominant-baseline='middle' text-anchor='middle'>",
                icon,
                "</text>"
            )
        );
        // Close SVG
        string memory tailSVG = "</svg>";

        // Concatenate SVG strings
        string memory _finalSVG = string(
            abi.encodePacked(headSVG, bodySVG, tailSVG)
        );
        return _finalSVG;
    }

    function getFirstChar(string memory aux) private pure returns (string memory) {
        bytes memory iconBytes = bytes(aux);
        uint i = 0;

        if (iconBytes.length == 0) return "";
        uint8 b = uint8(iconBytes[0]);

        if (b >> 7 == 0x0) {
            i = 1; // 1-byte ASCII
        } else if (b >> 5 == 0x6) {
            i = 2; // 2-byte character
        } else if (b >> 4 == 0xE) {
            i = 3; // 3-byte character
        } else if (b >> 3 == 0x1E) {
            i = 4; // 4-byte character
        } else {
            revert("Invalid UTF-8 encoding");
        }

        bytes memory firstChar = new bytes(i);
        for (uint j = 0; j < i; j++) {
            firstChar[j] = iconBytes[j];
        }
        return string(firstChar);
    }

    // The following function is an override required by Solidity.
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage) returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
