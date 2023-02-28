// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 * @title Stork contract - ETHDenver Hackathon Project
 * @notice This contract is used for allowing users to send and claim assets trustlessly to/from twitter handles
 */
contract Stork is FunctionsClient, ConfirmedOwner {
  using Functions for Functions.Request;

  mapping(bytes32 => address) public requestAddresses;
  mapping(bytes32 => string) public requestExpectedTwitterHandles;
  mapping(string => uint256) public twitterBalances;
  mapping(address => string) public addressTwitterHandles;

  uint64 internal constant SUBSCRIPTION_ID = 159;
  uint32 internal constant GAS_LIMIT = 100000;
  string internal constant FUNCTION_CODE =
    "const twitterAccessToken = args[0];\n"
    "if (!twitterAccessToken) {\n"
    "  throw Error('AccessToken is required.');\n"
    "}\n"
    "const twitterRequest = {\n"
    "    identityByAccessToken: () =>\n"
    "      Functions.makeHttpRequest({\n"
    "        url: 'https://api.twitter.com/2/users/me',\n"
    "        headers: { Authorization: `Bearer ${twitterAccessToken}` },\n"
    "      }),\n"
    "  };\n"
    "const handleRes = await new Promise((resolve, reject) => {\n"
    "    twitterRequest.identityByAccessToken().then((res) => {\n"
    "      if (!res.error) {\n"
    "        resolve(res);\n"
    "      } else {\n"
    "        reject(res);\n"
    "      }\n"
    "    });\n"
    "  });\n"
    "  if (handleRes.error) {\n"
    "    throw Error('Twitter API error.');\n"
    "  }\n"
    "const twitterHandle = handleRes.data.data.username || null;\n"
    "if (!twitterHandle) {\n"
    "  throw Error('Username null.');\n"
    "}\n"
    "return Functions.encodeString(twitterHandle);\n";

  event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

  /**
   * @notice Executes once when a contract is created to initialize state variables
   *
   * @param oracle - The FunctionsOracle contract
   */
  constructor(address oracle) FunctionsClient(oracle) ConfirmedOwner(msg.sender) {}

  /**
   * @notice Callback that is invoked once the DON has resolved the request or hit an error
   *
   * @param requestId The request ID, returned by sendRequest()
   * @param response Aggregated response from the user code
   * @param err Aggregated error from the user code or from the execution pipeline
   * Either response or error parameter will be set, but never both
   */
  function fulfillRequest(
    bytes32 requestId,
    bytes memory response,
    bytes memory err
  ) internal override {
    emit OCRResponse(requestId, response, err);
    // Make sure that oracles returned the handle that user was expecting
    assert(keccak256(bytes(requestExpectedTwitterHandles[requestId])) == keccak256(response));
    addressTwitterHandles[requestAddresses[requestId]] = string(response);
  }

  /**
   * @notice Allows the Functions oracle address to be updated
   *
   * @param oracle New oracle address
   */
  function updateOracleAddress(address oracle) public onlyOwner {
    setOracle(oracle);
  }

  /**
   * @notice Sends funds to twitter handle
   *
   * @param handle Twitter handle to send funds to
   */
  function sendToTwitterHandle(string calldata handle) public payable {
    twitterBalances[handle] += msg.value;
  }

  /**
   * @notice Reads balance of Twitter handle
   *
   * @param handle Twitter handle to check balance.
   */
  function balanceOfTwitterHandle(string calldata handle) public view returns (uint256) {
    return twitterBalances[handle];
  }

  /**
   * @notice Reads claimed address of Twitter handle
   *
   * @param addr Address to check claimed Twitter handle.
   */
  function twitterHandleOfAddress(address addr) public view returns (string memory) {
    return addressTwitterHandles[addr];
  }

  /**
   * @notice Claims twitter handle to sender.
   *
   * @param expectedTwitterHandle Expected Twitter handle.
   * @param accessToken OAuth2 User Context Twitter access token.
   */
  function claimTwitterHandle(string calldata expectedTwitterHandle, string calldata accessToken)
    public
    returns (bytes32)
  {
    Functions.Request memory req;
    req.initializeRequest(Functions.Location.Inline, Functions.CodeLanguage.JavaScript, FUNCTION_CODE);
    string[] memory args = new string[](1);
    args[0] = accessToken;
    req.addArgs(args);
    bytes32 assignedReqID = sendRequest(req, SUBSCRIPTION_ID, GAS_LIMIT);
    requestAddresses[assignedReqID] = msg.sender;
    requestExpectedTwitterHandles[assignedReqID] = expectedTwitterHandle;
    return assignedReqID;
  }

  /**
   * @notice Claim funds
   *
   */
  function claimFunds() public {
    uint256 balance = twitterBalances[addressTwitterHandles[msg.sender]];
    assert(balance > 0);
    twitterBalances[addressTwitterHandles[msg.sender]] = 0;
    payable(msg.sender).transfer(balance);
  }
}
