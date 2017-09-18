pragma solidity ^0.4.11;


contract LiquidToken {

	uint constant secondsPerPeriod = 2 ;// 60*60*24; // example: one day
	// to avoid race conditions and high-frequency funding and refunding.
	uint constant mandatoryLockinPeriods = 2; // example: funds may stay at
	// least 1 complete period (2
	// period closings)
	uint periodsMovingAverage = 100 ; // Use moving average of control metric.
	// Financial Constants
	uint baseScale = 10^18 ;
	uint constant tokenFundsPerBaseCoin = 1 ; // 1 wei of collateral
	// equivalent in TRDs base
	// subdivision
	// //100000000000000000; //
	// example: 0.1 ETH per 1 TRD
	// for funding
	// Estimate max cost in gas between fund(), refund() and transfer(), using
	// JavaScript
	int constant minCostInGasOfTransaction = 21000 ;
	uint collapseTolerance = baseScale*9/10 ;// ufixed0x128(0.9) ;
	// Options constants
	uint beginOptExecutionDate = 180 ; // team can execute options starting
	// these days after Contract begin.
	uint endOptExecutionDate = 365 ; // team can execute options starting
	// these days after Contract begin.
	uint maxTeamOptAmount = 10000 ; //
	uint teamOptionsMultiplier = 100 ; //        
	// END Constants

	// State Variables
	uint nowDebug = 0 ; 

	uint public currentPeriod ;
	uint public lastUpdateGlobal ;
	uint public creationDate;
	uint public globalRebasement ;
	mapping (address => uint) public fundBalances;
	mapping (address => uint) public lastFundPeriod ; 
	mapping (address => uint) public balances;
	mapping (address => uint) public lastUpdate;
	mapping (uint => uint) public periodRebasements ;
	mapping (address => uint) public rebasements ;
	mapping (uint => uint) public periodTransactions ;
	uint public totalFunds ;
	uint public totalTokenBase ; 
	uint public transactions ; 
	bool public releaseFunds = false ; // release funds if 1

	// Token Options for Team
	address[] public teamWallet =  [0xD630D5D64D9780ae60A0115128181b6327E25dC3, 0x389652727eDb184a18f5fB90862048515d3636A6];
	uint[] public optionsAvailable =  [10000*baseScale, 10000*baseScale];

	// Events
	event Transfer(address indexed _from, address indexed _to, uint256 _value);

	function LiquidToken() {
		creationDate = now / secondsPerPeriod; // alias of block.timestamp,
		// translated to days since
		// epoch
		lastUpdateGlobal = 0 ; // creationDate ; //- 1 ;
		periodRebasements[lastUpdateGlobal] = baseScale; // equivalent to
		// 1.0, so no
		// rebasement
		// initially.
	}

	// MODIFIERS
	modifier updateCurrentPeriod()
	{
		currentPeriod = now / uint(secondsPerPeriod) - creationDate ;
		_;
	}

	// PRIVATE FUNCTIONS

	function updateBalance(address wallet) 
	updateCurrentPeriod()
	private 
	{

		if (lastUpdate[wallet] == 0) {
			rebasements[wallet] = baseScale ; // equivalent to 1.0 in our
			// fixed point scale.
		}
		else {
			if (lastUpdate[wallet] < currentPeriod) {
				uint balance = balances[wallet] ;
				totalTokenBase = totalTokenBase - balance ;
				for (uint period = lastUpdate[wallet]; period < currentPeriod; period++) {
					balance = balance * periodRebasements[period] / baseScale ;
				}
				balances[wallet] = balance ;
				totalTokenBase = totalTokenBase + balance ;
			}
		}
		lastUpdate[wallet] = currentPeriod ;
	}

	function isTeamWallet(address wallet) private returns (int teamIndex) {
		int ret = -1 ;
		for (int w = 0; w < int(teamWallet.length); w++) {
			if (wallet == teamWallet[uint(w)]) {
				ret = w ;
				break ;
			}
		}
		return w ;
	}

	// The rate returned is in baseScale scale (example 1e18 mean 1)
	function updateRebasementGlobal() 
	updateCurrentPeriod()
	private 
	returns (uint rebasement) 
	{
		// update previous day
		uint periods = currentPeriod - creationDate ; 
		// Just an example, of possible bootstrap premiums
		// for early investors = 1 + 1/(periods+10)
		uint earlyAdoptersPremium = baseScale + baseScale / (periods*periods+2) ;
		// Moving Average
		periodTransactions[currentPeriod-1] = periodTransactions[currentPeriod-1] * baseScale / periodsMovingAverage ;
		periodTransactions[currentPeriod-1] += periodTransactions[currentPeriod-2] * baseScale * (periodsMovingAverage-1) / periodsMovingAverage ;
		periodTransactions[currentPeriod-1] /= baseScale ;

		int absRateControl = 0 ;
		int signRateControl = 1 ;
		int rateControl = 0 ;
		if (periodTransactions[currentPeriod-2] == 0)
			rateControl = 0 ;
		else {
			// pT[t-1] / pT[t-2] - 1.0
			rateControl = int(baseScale) * int(periodTransactions[currentPeriod-1]) / int(periodTransactions[currentPeriod-2]) - int(baseScale)  ;
			rateControl *= -1 ;
			if (rateControl < 0) {
				absRateControl = rateControl * -1 ;
				signRateControl = -1 ;
			}
		}
		// Reflective Currency manipulation limit.
		// Worst case scenario, the attacker jumps transactions from 1 to a big
		// number.

		int deltaControl = (int(periodTransactions[currentPeriod-1])-int(periodTransactions[currentPeriod-2])) ; // *
		// maxPriceInGasOfTransaction
		// ;
		// abs(a-b)
		if (deltaControl < 0)
			deltaControl *= -1 ;
		// use opposite direction for rebasement
		int finalRate = 0 ;
		if (rateControl >= 0) {
			// Min Positive
			// min(rvol, costPerTransaction*v/initialSupply )
			int rateProtection = int(baseScale) * int(tx.gasprice) * int(minCostInGasOfTransaction) * deltaControl / int(totalTokenBase) ;
			// min(rvol, costPerTransaction*v/initialSupply )
			if ( absRateControl < rateProtection )
				finalRate = rateControl ;
			else
				finalRate = rateProtection ;
			finalRate *= signRateControl ;
		}
		// do (R + 1.0 ) * earlyAdoptersRebasement
		return uint(finalRate + int(baseScale)) * earlyAdoptersPremium ; // rate
		// +
		// 1.0
	}

	function checkBurstReturnCollateral() private {
		// Probably not necessary.
		// If #TRD in circulation are few than rebasement goes below 1.0
		// (meaning 1 ETH is less worth than 1 TRD)
		// meaning there are very few TRD, small supply, and TRD is appreciating
		// too much.
		// then close the contract and return the collateral to all investors.
		// Only refund() method will work, to withdraw your collateral under
		// any circumstances.
		if (totalTokenBase < totalFunds * collapseTolerance / baseScale ) {
			releaseFunds = true ;
		} else {
			releaseFunds = false ;
		}    	
	}

	// EXTERNAL FUNCTIONS

	function getBaseScale() external returns (uint256 scale) {
		return baseScale;
	}

	function balanceOf(address addr) external returns (uint256 balance) {
		// updateBalance(addr) ;
		return balances[addr];
	}

	function fundBalanceOf() external returns (uint256 balance) {
		// updateBalance(addr) ;
		return fundBalances[msg.sender];
	}

	function nowSeconds() external returns (uint256 nowSeconds) {
		return now ;
	}

	function fund() payable returns (bool success) {
		// updateBalance(msg.sender) ; // to avoid funding of past rebasements
		// in case of price falling.
		// Check team options
		uint fundMultiplier = 1 ;
		uint ageInPeriods = 0 ;
		ageInPeriods = now / secondsPerPeriod - creationDate  ;

		/*
		 * int teamIndex = isTeamWallet(msg.sender) ; if (teamIndex >= 0 &&
		 * ageInPeriods > beginOptExecutionDate && ageInPeriods <
		 * endOptExecutionDate){ // belong to team fundMultiplier =
		 * teamOptionsMultiplier ; // we use return because we have nothing to
		 * revert and also throw is not working in our test deployment. if
		 * (optionsAvailable[uint(teamIndex)]*baseScale <
		 * msg.value*fundMultiplier) return false;
		 * optionsAvailable[uint(teamIndex)] -= msg.value*fundMultiplier ; }
		 */
		fundBalances[msg.sender] += msg.value*fundMultiplier ;
		// one-way peg, for one period there is no incentive to dump the new
		// coins.
		// although we can reimburse the original fund at any time, see refund()
		// In this example the one-way peg is 1 TRD per 1.0 ETH of funding,
		// but there is not minimum a-priori.
		balances[msg.sender] += msg.value * tokenFundsPerBaseCoin ;
		lastFundPeriod[msg.sender] =  now / secondsPerPeriod - creationDate ; 

		// periodTransactions[currentPeriod] = periodTransactions[currentPeriod]
		// + 1 ;
		totalFunds += msg.value ;
		return true ;
	}


	function getLastFundPeriod() external returns (uint256 period) {
		return lastFundPeriod[msg.sender];
	}


	function refund()
	updateCurrentPeriod()
	payable 
	returns (bool success)
	{
		// Minimum Holding period check.
		if (lastFundPeriod[msg.sender] + mandatoryLockinPeriods - 1 >= currentPeriod) {
			return false ;
		}
		if (fundBalances[msg.sender] < msg.value) return false;
		updateBalance(msg.sender) ;
		// Do check for TRD in wallet if fund release is off.
		if (releaseFunds == false) {    	
			// Check balance of TRDs.
			if (balances[msg.sender] < msg.value ) return false;
		}
		fundBalances[msg.sender] = fundBalances[msg.sender] - msg.value ;
		balances[msg.sender] = balances[msg.sender] - msg.value ;
		totalFunds = totalFunds - msg.value ;
		totalTokenBase = totalTokenBase - msg.value ;  
		if (!msg.sender.send(msg.value)) {			
			return false;
		}
		// periodTransactions[currentPeriod] = periodTransactions[currentPeriod]
		// + 1 ;
		return true;
	}

	// function transfer(address _to, uint256 _value) returns (bool success) {
	function sendCoin(address _to, uint _value) 
	updateCurrentPeriod()
	returns(bool success)
	{
		if (_to == msg.sender) return true ;
		updateBalance(msg.sender) ;
		updateBalance(_to) ;
		// Default assumes totalSupply can't be over max (2^256 - 1).
		// If your token leaves out totalSupply and can issue more tokens as
		// time goes on, you need to check if it doesn't wrap.
		// Replace the if with this one instead.
		// if (balances[msg.sender] >= _value && balances[_to] + _value >
		// balances[_to]) {
		if (balances[msg.sender] >= _value && _value > 0) {
			balances[msg.sender] -= _value;
			balances[_to] += _value;
			Transfer(msg.sender, _to, _value);
			periodTransactions[currentPeriod] += 1 ;
			transactions += 1 ;

			return true;
		} else { return false; }
	}

	// A big pool of resilient friends will poll this method
	// , for example, 2 minutes before midnight. Only the first poller
	// will go through.
	// TODO: use Alarm Clock from pipinmerriam
	// (https://github.com/pipermerriam/ethereum-alarm-clock)
	function updateRebasement()
	updateCurrentPeriod()
	external
	{
		// check if token base has collapsed beyond repair.
		checkBurstReturnCollateral();
		// if already updated for current period, abort.
		if (lastUpdateGlobal >= currentPeriod) return ;
		// Compute rebasement
		periodRebasements[currentPeriod] = updateRebasementGlobal() ;
		lastUpdateGlobal = currentPeriod ; 

	}

	function getBalance(address addr) returns(uint) {
		return balances[addr];
	}


}



