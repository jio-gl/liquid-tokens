var sleep = require('sleep');

var LiquidToken = artifacts.require("./LiquidToken.sol");

var periodsHolding = 2 ;
var periodSeconds = 2 ;

contract('LiquidToken', function(accounts) {
	// new tests for LiquidToken


// TEST 1
  it("should send coin correctly", function() {
    var meta;

    // Get initial balances of first and second account.
    var account_one = accounts[0];
    var account_two = accounts[1];

    var account_one_starting_balance;
    var account_two_starting_balance;
    var account_one_ending_balance;
    var account_two_ending_balance;

    var amount = 1;

    return LiquidToken.deployed().then(function(instance) {
      meta = instance;
      return meta.fund({from: account_one, value: 1});
    }).then(function(balance) {
      return meta.balanceOf.call(account_one);
    }).then(function(balance) {
      account_one_starting_balance = balance.toNumber();
      return meta.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_starting_balance = balance.toNumber();
      return meta.transfer(account_two, amount, {from: account_one});
    }).then(function() {
      return meta.balanceOf.call(account_one);
    }).then(function(balance) {
      account_one_ending_balance = balance.toNumber();
      return meta.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_ending_balance = balance.toNumber();

      assert.equal(account_one_ending_balance, account_one_starting_balance - amount, "Amount wasn't correctly taken from the sender");
      assert.equal(account_two_ending_balance, account_two_starting_balance + amount, "Amount wasn't correctly sent to the receiver");
    });
  });

// TEST 3
	// original Metacoin tests below
	it("should put 1 LiquidToken in the first account", function() {
    return LiquidToken.deployed().then(function(instance) {
      return instance.balanceOf.call(accounts[0]);
    }).then(function(balance) {
      assert.equal(balance.valueOf(), 0, "0 wasn't in the first account");
    });
  });

// TEST 4
  // test, refund too much
	it("should I refund more than available", function() {
		  var account_zero = accounts[2];	
	    var account_three = accounts[3];
	    var account_four = accounts[4];
			var amount = 1;
   	  return LiquidToken.deployed().then(function(instance) {
	    trd = instance;
		  trd.fund({from: account_zero, value: 9});
      return trd.fundBalanceOf.call({from: account_zero});
	    }).then(function(availableEther) {
		  return trd.refund({from: account_zero, value: 10});
	    }).then(function() {
			// Throw some events to upate blockchain state (needed for testrpc)
		  return trd.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
      return trd.transfer(account_four, amount, {from: account_three});
	    }).then(function() {
			// end of event throwing
      return trd.fundBalanceOf.call({from: account_zero});
	    }).then(function(availableEther) {
      assert.equal(availableEther.valueOf(), 9, "9 wei left, having 9 wei after trying to refund 10 wei");
	    });
	  });

// TEST 5
    // test, should I refund available after 0 periods
	it("should I refund available after 0 periods (no)", function() {
	    var account_one = accounts[5];
	    var account_three = accounts[3];
	    var account_four = accounts[4];
			var amount = 1;
   	  return LiquidToken.deployed().then(function(instance) {
		  meta = instance;
	      return instance.fund({from: account_one, value: 10});
	    }).then(function() {
			// Throw some events to upate blockchain state (needed for testrpc)
		  return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
      return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function() {
			// end of event throwing
      return meta.fundBalanceOf({from: account_one});
	    }).then(function(availableEther) {
      return meta.currentPeriod ({from: account_one});
      }).then(function(currentPeriod) {
	    return meta.getLastFundPeriod ({from: account_one});
	    }).then(function(getLastFundPeriod) {
		  return meta.refund({from: account_one, value: 10});
	    }).then(function() {
			// Throw some events to upate blockchain state (needed for testrpc)
		  return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
      return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function() {
			// end of event throwing
      return meta.fundBalanceOf.call({from: account_one});
	    }).then(function(availableEther) {
      assert.equal(availableEther.valueOf(), 10, "10 wei left, having 10 wei after trying to refund 10 wei after only 0 time periods");
	    });
	  });

// TEST 6
	// test, should I refund available after 1 periods
	it("should I refund available after 1 periods (no)", function() {
	    var account_one = accounts[6];
	    var account_two = accounts[7];
	    var account_three = accounts[3];
	    var account_four = accounts[4];
	    var amount = 1;
   	  return LiquidToken.deployed().then(function(instance) {
		  meta = instance;
      return meta.fund({from: account_one, value: 10});
	    }).then(function(goodFund) {
      sleep.sleep( periodSeconds );	
		  return meta.fundBalanceOf ({from: account_one});
	    }).then(function(availableEther) {
      return meta.transfer(account_two, amount, {from: account_one});
      }).then(function() {
	    return meta.transfer(account_one, amount, {from: account_two});
	    }).then(function(success) {
	    return meta.transfer(account_two, amount, {from: account_one});
	    }).then(function(success) {
	    return meta.transfer(account_one, amount, {from: account_two});
	    }).then(function(success) {

		  return meta.nowSeconds ();
	    }).then(function(nowSeconds) {
		  sleep.sleep( 2 );	

		  return meta.transfer(account_two, amount, {from: account_one});
	    }).then(function(success) {
	        return meta.transfer(account_one, amount, {from: account_two});
	    }).then(function(success) {
			  return meta.transfer(account_two, amount, {from: account_one});
	    }).then(function(success) {
	        return meta.transfer(account_one, amount, {from: account_two});
	    }).then(function(success) {

	    	return meta.nowSeconds ();
	    }).then(function(nowSeconds) {
		
		  return meta.refund({from: account_one, value: 10});
	    }).then(function() {
			// Throw some events to upate blockchain state (needed for testrpc)
		  return trd.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
      return trd.transfer(account_four, amount, {from: account_three});
	    }).then(function() {
			// end of event throwing

	      return trd.fundBalanceOf.call({from: account_one});
	    }).then(function(availableEther) {
	    assert.equal(availableEther.valueOf(), 10, "10 wei left, having 10 wei after trying to refund 10 wei after only 1 time periods");
	    });
			
	  });



// TEST 7
	// test, should I refund available after 2 periods? Yes
	it("should I refund available after 2 periods (yes)", function() {
		    var account_one = accounts[8];
		    var account_two = accounts[9];
		    var account_three = accounts[3];
		    var account_four = accounts[4];
		    var amount = 0;
	   	  return LiquidToken.deployed().then(function(instance) {
		  meta = instance;
	      return meta.fund({from: account_one, value: 10});
	    }).then(function(goodFund) {
		  return meta.fundBalanceOf ({from: account_one});
	    }).then(function(availableEther) {
	
      return meta.currentPeriod ({from: account_one});
	    }).then(function(currentPeriod) {
	
          return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function() {
	        return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function(success) {
	          return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
	        return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function(success) {

		  return meta.nowSeconds ();
	    }).then(function(nowSeconds) {
	      sleep.sleep( 4 );	

		  return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
	        return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function(success) {
			  return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
	        return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function(success) {

	    	return meta.nowSeconds ();
	    }).then(function(nowSeconds) {
	
			return meta.currentPeriod ({from: account_one});
	    }).then(function(currentPeriod) {
	
		  return meta.fundBalanceOf ({from: account_one});
	    }).then(function(availableEther) {
	
		  return meta.refund({from: account_one, value: 10});
	    }).then(function() {

			// Throw some events to upate blockchain state (needed for testrpc)
		  return meta.transfer(account_three, amount, {from: account_four});
	    }).then(function(success) {
      return meta.transfer(account_four, amount, {from: account_three});
	    }).then(function() {
			// end of event throwing

		  return meta.fundBalanceOf.call({from: account_one});
	    }).then(function(availableEther) {
	    assert.equal(availableEther.valueOf(), 0, "0 wei left, having 10 wei after refunding 10 wei after 2 periods");
	    });
	  });




});
