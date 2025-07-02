// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Deploy on Sepolia

import {FunctionsClient} from "@chainlink/contracts@1.4.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.4.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

interface IWeatherNft {
    function mint(address to, string memory city, string memory weather) external;
    function updateSVG(uint256 tokenId, string memory city, string memory weather) external;
}

contract WeatherFunctions is FunctionsClient  {
    using FunctionsRequest for FunctionsRequest.Request;

    // State variables to store the last request ID, response, and error
    bytes32 public lastRequestId;
    bytes public lastResponse;
    bytes public lastError;

    // Hardcoded for Sepolia
    // Supported networks https://docs.chain.link/chainlink-functions/supported-networks
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 donID =
        0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;

    //Callback gas limit
    uint32 gasLimit = 300000;

    // Your subscription ID.
    uint64 public subscriptionId;

    // JavaScript source code
    string public source =
        "const city = args[0];"
        "const apiResponse = await Functions.makeHttpRequest({"
        "url: `https://wttr.in/${city}?format=1&m`,"
        "responseType: 'text'"
        "});"
        "if (apiResponse.error) {"
        "throw Error('Request failed');"
        "}"
        "const { data } = apiResponse;"
        "return Functions.encodeString(data);";
    string public lastCity;    
    string public lastTemperature;
    address public lastNftAddress;
    address public lastSender;

    // Event to mint NFT
    event MintIt(
        address indexed nftAddress,
        string city,
        string temperature
    );

    constructor(uint64 functionsSubscriptionId) FunctionsClient(router) {
        subscriptionId = functionsSubscriptionId;      
    }

    function getTemperature(
        string memory _city
    ) external returns (bytes32 requestId) {

        string[] memory args = new string[](1);
        args[0] = _city;

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
        lastCity = _city;
        lastSender = msg.sender;
        return lastRequestId;
    }

    // Receive the weather in the city requested
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        lastError = err;
        lastResponse = response;
        lastTemperature = removeLF(string(response));

        emit MintIt(lastNftAddress, lastCity, lastTemperature);
    }

    function setupNFT (address _nftAddress) public {
        lastNftAddress = _nftAddress;
    }

    function mintNFT () public {
        require (lastNftAddress != address(0), "NFT Address not set.");
        IWeatherNft nft = IWeatherNft(lastNftAddress);
        nft.mint(lastSender, lastCity, lastTemperature);
    }

    function updateNFT (uint256 tokenId) public {
        require (lastNftAddress != address(0), "NFT Address not set.");
        IWeatherNft nft = IWeatherNft(lastNftAddress);
        nft.updateSVG(tokenId, lastCity, lastTemperature);
    }

    function removeLF(string memory input) private pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        
        // Count how many non-LF characters
        uint count = 0;
        for (uint i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] != 0x0A) {
                count++;
            }
        }

        // Create new bytes array without LF
        bytes memory result = new bytes(count);
        uint j = 0;
        for (uint i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] != 0x0A) {
                result[j] = inputBytes[i];
                j++;
            }
        }
        return string(result);
    }

}
