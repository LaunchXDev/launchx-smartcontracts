// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./Roles.sol";
import "./Token_interface.sol";


contract AdminRole is Context, Ownable {
    using Roles for Roles.Role;
    using SafeMath for uint256;

    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

    uint256 private _qty_admins = 0;
    Roles.Role private _admins;
    address[] private _signatures;

    modifier onlyAdmin() {
        require(isAdmin(_msgSender()), "AdminRole: you don�t have permissions to call this method");
        _;
    }

    modifier onlyOwnerOrAdmin() {
      require(isAdminOrOwner(_msgSender()), "This method can be called either by Owner or Admin");
      _;
    }

    function isAdminOrOwner(address account) public view returns (bool) {
        return isAdmin(account) || isOwner();
    }

    function isAdmin(address account) public view returns (bool) {
        return _admins.has(account);
    }

    function _addAdmin(address account) internal {

        require(!isAdmin(account) && account != owner(), "Admin already exists");

        _admins.add(account);
        _qty_admins = _qty_admins.add(1);
        emit AdminAdded(account);
    }

    function addSignature4NextOperation() public onlyOwnerOrAdmin {
      bool exist = false;
      for(uint256 i=0; i<_signatures.length; i++){
        if(_signatures[i] == _msgSender()){
          exist = true;
          break;
        }
      }
      require(!exist, "Signature already exists");
      _signatures.push(_msgSender());
    }

    function cancelSignature4NextOperation() public onlyOwnerOrAdmin {
      for(uint256 i=0; i<_signatures.length; i++){
        if(_signatures[i] == _msgSender()){
          _remove_signatures(i);
          return;
        }
      }
      require(false, "Signature is not found");
      
    }

    function checkValidMultiSignatures() public view returns(bool){
      uint256 all_signatures = _qty_admins.add(1); // 1 for owner
      if(all_signatures <= 2){
        return all_signatures == _signatures.length;
      }
      uint256 approved_signatures = all_signatures.mul(2).div(3);
      return _signatures.length >= approved_signatures;
    }

    function cancelAllMultiSignatures() public onlyOwnerOrAdmin{
      uint256 l = _signatures.length;
      for(uint256 i=0; i<l; i++){
        _signatures.pop();
      }
    }

    function checkExistSignature(address account) public view returns(bool){
      bool exist = false;
      for(uint256 i=0; i<_signatures.length; i++){
        if(_signatures[i] == account){
          exist = true;
          break;
        }
      }
      return exist;
    }

    function m_signaturesTransferOwnership(address newOwner) public onlyOwnerOrAdmin {
      require(isOwner() || checkValidMultiSignatures(), "There is no required number of signatures");
      transferOwnership(newOwner);
      cancelAllMultiSignatures();
    }

    function _remove_signatures(uint index) private {
      if (index >= _signatures.length) return;
      for (uint i = index; i<_signatures.length-1; i++){
        _signatures[i] = _signatures[i+1];
      }
      _signatures.pop();
    }

}

// https://solidity-by-example.org/signature/

contract VerifySignature{
    
    function getMessageHash(address holder, uint _maxvalue) public pure returns (bytes32){
        return keccak256(abi.encodePacked(holder, _maxvalue));
    }

    function getSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function verify(address _signer, address holder, uint _maxvalue, bytes memory signature) public pure returns (bool) {
        bytes32 messageHash = getMessageHash(holder, _maxvalue);
        bytes32 signedMessageHash = getSignedMessageHash(messageHash);
        return recoverSigner(signedMessageHash, signature) == _signer;
    }

    function recoverSigner(bytes32 _signedMessageHash, bytes memory _signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_signedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            // the first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // the second 32 bytes
            s := mload(add(sig, 64))
            // the final 32 bytes (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }
}


contract ProjectName is AdminRole, VerifySignature{
  using SafeMath for uint256;

  event TokensaleInfo(address indexed signer, uint256 coinsvalue, uint256 tokensvalue, uint256 holder_max_project_tokens, uint256 allowed_coinsvalue, uint256 allowed_tokensvalue);

  // sales status id
  uint8 private _tokensale_status;

  address public currency_token_address;
  Token_interface private _currency_token;

  address public project_token_address;
  Token_interface private _project_token;

  uint256 private _token_price;

  address private _signer_address;

  mapping(address => uint256) private _sold_amounts;
  uint256 private _totalsold = 0;
  address[] private _participants;

  constructor () public {

    // set the sales status id as: "disabled"
    _tokensale_status = 2;

    //set the sale price for 1 token
    _token_price = 100000000000000000; //0.10 USDT * (10**18) = 100000000000000000 wei, where 18 are decimals of USDT

    // set the address that stores Tokens and signs data from the white list
    _signer_address = address(0xb9FDFCb83dD73d1d8d0EdCa62B3eAC14acCCDD60);

    // set the address of a currency smart contract
    // e.g. Token Tether (USDT) address is 0xdAC17F958D2ee523a2206206994597C13D831ec7
    // mainnet url https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7
    currency_token_address = address(0x74321312E77534E8bABBA368dba9De73e150F1A6);
    _currency_token = Token_interface(currency_token_address);
    
    // set the address of the smart contract of the project token
    project_token_address = address(0x0CAa60FB124fF9542C1bDA0db35C1807021fF97b);
    _project_token = Token_interface(project_token_address);
    
    // set the administrators
    _addAdmin(address(0x1bDC2fEf5A09A864b081A1ECBB4441D978a131E1));
    _addAdmin(address(0x812747ef2a2e6E86f235972Bfc8400216aC5e6Ac));
    _addAdmin(address(0xe1FA2B957a2c61345d49d69430Cd5b79FfA228Ed));
  }

  // This method returns the current sales status
  function saleStatus() public view returns(string memory){
    if(_tokensale_status == 0){
      return "Closed";
    }else if(_tokensale_status == 1){
      return "Active";
    }else if(_tokensale_status == 2){
      return "Disabled";
    }
    return "Unknown"; //impossible
  }

  // block the reception of a standard coin of network
  receive() external payable {
    require(false, "The contract does not accept the base coin of network.");
  }

  // This method allows the admin of the smart contract to withdraw tokens
  // from the smart contract. This can be done before or after stopTokensale()
  function tokenWithdrawal(address token_address, address recipient, uint256 value) public onlyOwnerOrAdmin {
    require(checkValidMultiSignatures(), "There is no required number of signatures");

    Token_interface ct = Token_interface(token_address);
    ct.transfer(recipient, value);

    cancelAllMultiSignatures();
  }

  // This method allows the admin of the smart contract to withdraw USDT
  // from the smart contract. This can be done before or after stopTokensale()
  function USDTWithdrawal(address recipient, uint256 value) public onlyOwnerOrAdmin {
    tokenWithdrawal(currency_token_address, recipient, value);
  }

  // get the price of 1 token in USDT
  function getTokenPrice() public view returns(uint256){
    return _token_price;
  }

  // Total number of tokens sold to the specified address.
  function totalTokensSoldByAddress(address holder) public view returns(uint256){
    return _sold_amounts[holder];
  }

  // The amount of tokens sold so far.
  function totalTokensSold() public view returns (uint256) {
      return _totalsold;
  }

  // Get the participant address by index (indexing starts from 0).
  function getParticipantAddressByIndex(uint256 index) public view returns(address){
    return _participants[index];
  }
  
  // Get the number of participants that have purchased more than 0 tokens.
  function getNumberOfParticipants() public view returns(uint256){
    return _participants.length;
  }


  function setWhitelistAuthorityAddress(address signer) public onlyOwnerOrAdmin {
      // Set a different address of whitelist authority. This address will be used to sign "Purchase Certificates".
      // Purchase certificates are items of the white list indicating that the client has the right
      // to buy the stated amount of tokens.
    require(checkValidMultiSignatures(), "There is no required number of signatures");

    require(_tokensale_status > 0, "Sales closed");

    _signer_address = signer;
    
    cancelAllMultiSignatures();
  }


  //function get_holder_available_token_value(address _holder, uint256 _maxProjectTokens, bytes memory _signedData) public view returns (uint256) {
  function getRemainingBalance(address holder, uint256 holder_max_project_tokens, bytes memory signature) public view returns (uint256) {      
    // The msg.sender has the right to purchase the remaining amount of tokens. This takes into account the
    // previously purchased tokens. 
    require(verify(_signer_address, holder, holder_max_project_tokens, signature), "The incoming data have been incorrectly signed");
    uint256 c = totalSoldByAddress(holder);
    return holder_max_project_tokens.sub(c);
  }

  // function is_holder_available_token_value(address _holder, uint256 _needed_project_token_value, uint256 _maxProjectTokens, bytes memory _signedData) public view returns (bool){
  function checkEligibility(address holder, uint256 require_token_value, uint256 holder_max_project_tokens, bytes memory signature) public view returns (bool){
    // Check if msg.sender is eligible to buy the stated amount of tokens.
    uint256 v = getRemainingBalance(holder, holder_max_project_tokens, signature);
    if(v == 0 || require_token_value == 0){ return false; }
    return v >= require_token_value;
  }


  // function burn_allowanced_value(uint256 _projectTokens, uint256 _maxProjectTokens, bytes memory _signedData) public{
  // the main method of the smart contract that allows to purchase the project tokens 
  // for USDT. 
  function tokenPurchase(uint256 require_token_value, uint256 holder_max_project_tokens, bytes memory signature) public{
    // check that sales are open
    require(_tokensale_status==1, "Sales are not allowed");
    require(require_token_value > 0, "The requested amount of tokens for purchase must be greater than 0 (zero)");

    address sender = _msgSender();

    // check the customer's permitted limits to purchase tokens
    require(checkEligibility(sender, require_token_value, holder_max_project_tokens, signature), "The customer's purchase amount is limited by the max value");
    
    // calculate the price for the specified purchase tokens value
    uint256 topay_value = require_token_value.mul(_token_price).div(10**_currency_token.decimals());

    // check the customer's USDT balance
    uint256 c_value = _currency_token.balanceOf(sender);
    require(c_value >= topay_value, "The customer does not have enough USDT");

    // check the allowed USDT value for transfer from the customer
    c_value = _currency_token.allowance(sender, address(this));
    require(c_value >= topay_value, "Smart contract is not entitled to such USDT amount");

    // check the balance of project tokens for sale
    uint256 p_value = _project_token.balanceOf(_signer_address);
    require(p_value >= require_token_value, "The holder does not have enough project tokens");

    // check allowed project tokens value for transfer to the customer
    p_value = _project_token.allowance(_signer_address, address(this));
    require(p_value >= require_token_value, "Smart contract is not entitled to such a project token amount");

    // write the information about the purchase to events
    emit TokensaleInfo(_signer_address, topay_value, require_token_value, holder_max_project_tokens, c_value, p_value);

    // withdraw USDT from the customer
    require(_currency_token.transferFrom(sender, address(this), topay_value), "USDT withdrawal error");
    // transfer project tokens to the customer
    require(_project_token.transferFrom(_signer_address, sender, require_token_value), "Project Token transfer error");

    // add the customer's address to the list of participants
    if(_sold_amounts[sender] == 0){
      _participants.push(sender);
    }

    // calculate the total amount of purchased tokens by the customer
    _sold_amounts[sender] = _sold_amounts[sender].add(require_token_value);
    // calculate the total amount of purchased tokens by smart contract
    _totalsold = _totalsold.add(require_token_value);
  }

  // This method stops the sales. After this method is called, no further purchases are possible.
  // This can be reverted. If there are unsold tokens, they can be sold later.
  function stopSales() public onlyOwnerOrAdmin{

    require(checkValidMultiSignatures(), "There is no required number of signatures");

    require(_tokensale_status > 0, "Sales are closed");

    _tokensale_status = 2;

    cancelAllMultiSignatures();
  }

  // This method starts the sales. After this method is called, smart contracts are open for sales.
  // This can be reverted.
  function startSales() public onlyOwnerOrAdmin{

    require(checkValidMultiSignatures(), "There is no required number of signatures");

    require(_tokensale_status > 0, "Sales is close");

    _tokensale_status = 1;

    cancelAllMultiSignatures();
  }


  // Close the sales. After this method is called, no further purchases are possible.
  // This CANNOT be reverted. If there are unsold tokens, they will remain with the
  // original holder that had issued allowence for this contract to 
  // sell them.
  function stopTokensale() public onlyOwnerOrAdmin{
    require(checkValidMultiSignatures(), "There is no required number of signatures");

    // reset the address of the signature and the holder of the tokens for sale
    _signer_address = address(0);

    // set the sales status index to "Closed"
    _tokensale_status = 0;
  }

}
