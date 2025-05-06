// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title LiquidToken
 * @dev Implementation of a token with dynamic burn and mint rates
 * Features:
 * - ICO-like bootstrap period with early adopter incentives
 * - Dynamic period with rate-based mint and burn
 * - Burn and mint rates based on transaction volume
 * - CEX-friendly balance calculation
 */
contract LiquidToken is ERC20Capped {
	using Math for uint256;

	// Token metadata
	string private constant NAME = "Liquid Token";
	string private constant SYMBOL = "LQD";
	uint8 private constant DECIMALS = 18;
	
	// Cap of 1 million tokens
	uint256 private constant CAP = 1_000_000 * (10**18);
	
	// Burn and mint rate parameters
	uint256 private constant SECONDS_PER_DAY = 86400;
	uint256 private constant SECONDS_PER_YEAR = 31536000; // 365 days
	uint256 private constant BOOTSTRAP_DURATION = 90 days; // 3 month bootstrap period
	
	// Base annual rates (in basis points, 1/10000)
	uint256 private constant BASE_ANNUAL_BURN_RATE = 400; // 4% annual burn
	uint256 private constant BASE_ANNUAL_MINT_RATE = 500; // 5% annual mint
	uint256 private constant BASIS_POINTS = 10000;
	
	// Period types
	enum PeriodType { BOOTSTRAP, DYNAMIC }
	
	// Period tracking
	PeriodType private _currentPeriod = PeriodType.BOOTSTRAP;
	uint256 private _bootstrapStartTime;
	uint256 private _lastRebaseTimestamp;
	
	// Airdrop amounts during bootstrap period
	uint256 private constant DROP_MINT = 6 * (10**18);     // 6 tokens per mint
	uint256 private constant DROP_TRANSFER = 12 * (10**18); // 12 tokens per transfer to new holder
	
	// Transaction metrics
	uint256 private _transactionCount; // Transactions in the current period
	uint256 private _prevPeriodTxCount; // Transactions in the previous period
	
	// Moving average parameters
	uint256 private constant MOVING_AVG_PERIODS = 100; // Use 100 period moving average
	uint256 private _movingAverageTxCount; // Stored as scaled by BASIS_POINTS
	
	// Dynamic rate calculation variables
	int256 private _currentDynamicRate; // Can be positive (mint) or negative (burn)
	uint256 private _accumulatedMintRate; // Accumulated mint rate in basis points
	uint256 private _lastRateUpdateTime; // Last time dynamic rate was updated
	
	// Account data tracking
	struct AccountData {
		uint256 lastUpdated;
		uint256 lastMintUpdate; // Last time mint was applied to this account
		uint256 accumulatedMintRate; // Mint rate accumulated for this account
		uint256 effectiveBalance;
	}
	
	mapping(address => AccountData) private _accountData;
	
	// Events
	event MintRateApplied(address indexed account, uint256 amount);
	event BurnRateApplied(address indexed account, uint256 amount);
	event BootstrapPeriodEnded(uint256 timestamp);
	event DynamicPeriodStarted(uint256 timestamp);
	event DynamicRateUpdated(uint256 timestamp, int256 newRate, uint256 txCount);
	event MintRateAccumulated(uint256 timestamp, uint256 rate);
	
	/**
	 * @dev Constructor
	 */
	constructor() 
		ERC20(NAME, SYMBOL)
		ERC20Capped(CAP) 
	{
		_bootstrapStartTime = block.timestamp;
		_lastRebaseTimestamp = block.timestamp;
		_lastRateUpdateTime = block.timestamp;
		_currentDynamicRate = 0;
		_accumulatedMintRate = 0;
		
		// Mint initial supply to deployer
		uint256 initialSupply = 100_000 * (10**18); // 100,000 tokens
		_mint(msg.sender, initialSupply);
		
		// Initialize account data for deployer
		_accountData[msg.sender] = AccountData({
			lastUpdated: block.timestamp,
			lastMintUpdate: block.timestamp,
			accumulatedMintRate: 0,
			effectiveBalance: initialSupply
		});
		
		// Initialize moving average
		_movingAverageTxCount = 0;
	}
	
	/**
	 * @dev Returns the current period type (BOOTSTRAP or DYNAMIC)
	 */
	function getCurrentPeriod() public view returns (uint8) {
		return uint8(_currentPeriod);
	}
	
	/**
	 * @dev Returns whether the current rate is a mint rate (positive) or burn rate (negative)
	 */
	function isMintRate() public view returns (bool) {
		return _currentDynamicRate > 0;
	}
	
	/**
	 * @dev Returns the current dynamic rate (positive for mint, negative for burn)
	 */
	function getCurrentDynamicRate() public view returns (int256) {
		return _currentDynamicRate;
	}
	
	/**
	 * @dev Returns the absolute value of the current dynamic rate
	 */
	function getCurrentRateAbsolute() public view returns (uint256) {
		return _currentDynamicRate > 0 ? uint256(_currentDynamicRate) : uint256(-_currentDynamicRate);
	}
	
	/**
	 * @dev Returns the accumulated mint rate (in basis points)
	 */
	function getAccumulatedMintRate() public view returns (uint256) {
		return _accumulatedMintRate;
	}
	
	/**
	 * @dev Returns the current period's transaction count
	 */
	function getCurrentPeriodTxCount() public view returns (uint256) {
		return _transactionCount;
	}
	
	/**
	 * @dev Returns the previous period's transaction count
	 */
	function getPreviousPeriodTxCount() public view returns (uint256) {
		return _prevPeriodTxCount;
	}
	
	/**
	 * @dev Returns the moving average transaction count
	 */
	function getMovingAverageTxCount() public view returns (uint256) {
		return _movingAverageTxCount / BASIS_POINTS;
	}
	
	/**
	 * @dev Returns when the next rebase will occur
	 */
	function getNextRebaseTimestamp() public view returns (uint256) {
		return _lastRebaseTimestamp + SECONDS_PER_DAY;
	}
	
	/**
	 * @dev Returns when the bootstrap period will end
	 */
	function getBootstrapEndTimestamp() public view returns (uint256) {
		return _bootstrapStartTime + BOOTSTRAP_DURATION;
	}
	
	/**
	 * @dev Checks if bootstrap period is over
	 */
	function isBootstrapPeriodOver() public view returns (bool) {
		return block.timestamp >= _bootstrapStartTime + BOOTSTRAP_DURATION;
	}
	
	/**
	 * @dev Calculates the early adopter premium during bootstrap period
	 * Premium decreases over time to incentivize early participation
	 */
	function _calculateEarlyAdopterPremium() internal view returns (uint256) {
		if (_currentPeriod != PeriodType.BOOTSTRAP) {
			return BASIS_POINTS; // No premium after bootstrap (1.0)
		}
		
		// Calculate days since bootstrap start
		uint256 daysSinceStart = (block.timestamp - _bootstrapStartTime) / SECONDS_PER_DAY;
		if (daysSinceStart == 0) daysSinceStart = 1;
		
		// Premium decreases quadratically: 1 + 1/(days*days+2)
		uint256 premium = BASIS_POINTS + (BASIS_POINTS / (daysSinceStart*daysSinceStart+2));
		return premium;
	}
	
	/**
	 * @dev Calculates the dynamic rate based on transaction volume
	 * Returns a positive value for mint rate or negative value for burn rate
	 */
	function _calculateDynamicRate() internal view returns (int256) {
		if (_currentPeriod != PeriodType.DYNAMIC) {
			return 0;
		}
		
		// Base daily rate (annual rate divided by 365)
		uint256 baseDailyMintRate = BASE_ANNUAL_MINT_RATE * SECONDS_PER_DAY / SECONDS_PER_YEAR;
		uint256 baseDailyBurnRate = BASE_ANNUAL_BURN_RATE * SECONDS_PER_DAY / SECONDS_PER_YEAR;
		
		// Calculate transaction activity factor based on moving average
		int256 txActivityFactor = 0;
		if (_movingAverageTxCount > 0) {
			// Compare current tx count to moving average
			uint256 avgTx = _movingAverageTxCount / BASIS_POINTS;
			if (avgTx == 0) avgTx = 1; // Avoid division by zero
			
			if (_transactionCount > avgTx) {
				// Above average transaction activity - tend toward mint
				uint256 txRatio = (_transactionCount * BASIS_POINTS) / avgTx;
				
				// Cap the maximum factor
				if (txRatio > 300) txRatio = 300; // Max 3x factor
				
				unchecked {
					txActivityFactor = int256(txRatio - BASIS_POINTS);
				}
			} else if (_transactionCount < avgTx) {
				// Below average transaction activity - tend toward burn
				// Avoid division by zero if transaction count is 0
				uint256 txRatio;
				if (_transactionCount == 0) {
					txRatio = 300; // Max factor if no transactions
				} else {
					txRatio = (avgTx * BASIS_POINTS) / _transactionCount;
					// Cap the maximum factor
					if (txRatio > 300) txRatio = 300; // Max 3x factor
				}
				
				unchecked {
					txActivityFactor = -int256(txRatio - BASIS_POINTS);
				}
			}
			// If equal to average, factor remains 0
		}
		
		// Base rate plus activity adjustment
		if (txActivityFactor >= 0) {
			// Positive factor (high activity) - apply mint rate
			uint256 adjustedRate = baseDailyMintRate;
			if (txActivityFactor > 0) {
				adjustedRate = baseDailyMintRate + 
					((baseDailyMintRate * uint256(txActivityFactor)) / BASIS_POINTS);
			}
			unchecked {
				return int256(adjustedRate);
			}
		} else {
			// Negative factor (low activity) - apply burn rate
			uint256 adjustedRate = baseDailyBurnRate;
			if (txActivityFactor < 0) {
				unchecked {
					adjustedRate = baseDailyBurnRate + 
						((baseDailyBurnRate * uint256(-txActivityFactor)) / BASIS_POINTS);
				}
			}
			unchecked {
				return -int256(adjustedRate);
			}
		}
	}
	
	/**
	 * @dev Updates the account data for an account
	 * @param account The account to update
	 */
	function _updateAccountData(address account) internal {
		AccountData storage data = _accountData[account];
		uint256 balance = ERC20.balanceOf(account);
		
		if (data.lastUpdated == 0) {
			// Initialize new account
			_accountData[account] = AccountData({
				lastUpdated: block.timestamp,
				lastMintUpdate: block.timestamp,
				accumulatedMintRate: 0,
				effectiveBalance: balance
			});
			return;
		}
		
		data.lastUpdated = block.timestamp;
		data.effectiveBalance = balance;
	}
	
	/**
	 * @dev Updates the accumulated mint rate for an account
	 * If global mint rate has been updated since the account's last update,
	 * add that accumulated rate to the account's rate
	 * @param account The account to update
	 */
	function _updateAccountMintRate(address account) internal {
		AccountData storage data = _accountData[account];
		
		// If account has never been updated or no new mint rate accumulated
		if (data.lastMintUpdate == 0 || _lastRateUpdateTime == 0 || data.lastMintUpdate >= _lastRateUpdateTime || _accumulatedMintRate == 0) {
			return;
		}
		
		// Add the global accumulated rate to the account's rate
		data.accumulatedMintRate += _accumulatedMintRate;
		data.lastMintUpdate = block.timestamp;
	}
	
	/**
	 * @dev Applies the accumulated mint rate to an account balance
	 * @param account The account to apply the mint rate to
	 * @return minted The amount of tokens minted
	 */
	function _applyMintRate(address account) internal returns (uint256 minted) {
		AccountData storage data = _accountData[account];
		uint256 balance = data.effectiveBalance;
		
		if (balance == 0 || data.accumulatedMintRate == 0) {
			return 0;
		}
		
		// Calculate mint amount based on accumulated rate
		minted = (balance * data.accumulatedMintRate) / BASIS_POINTS;
		
		// Reset accumulated rate after applying
		data.accumulatedMintRate = 0;
		
		if (minted > 0) {
			_mint(account, minted);
			data.effectiveBalance += minted;
			emit MintRateApplied(account, minted);
		}
		
		return minted;
	}
	
	/**
	 * @dev Applies the burn rate to a transfer based on the current dynamic burn rate
	 * @param account The account to apply the burn rate to
	 * @param amount The transfer amount to calculate burn on
	 * @return burned The amount of tokens burned
	 */
	function _applyBurnRate(address account, uint256 amount) internal returns (uint256 burned) {
		// No burn during bootstrap period or if dynamic rate is positive (mint)
		if (_currentPeriod == PeriodType.BOOTSTRAP || _currentDynamicRate >= 0) {
			return 0;
		}
		
		// Convert negative rate to positive burn rate
		uint256 burnRate = uint256(-_currentDynamicRate);
		
		// Apply burn rate as a small commission on transfer
		burned = (amount * burnRate) / (BASIS_POINTS * 10); // Dividing by 10 to make it smaller
		
		// Ensure burn doesn't exceed transfer amount
		if (burned > amount) {
			burned = amount;
		}
		
		if (burned > 0) {
			_burn(account, burned);
			emit BurnRateApplied(account, burned);
		}
		
		return burned;
	}
	
	/**
	 * @dev Rebase function to update periods and rates
	 * Called internally but can also be called manually
	 */
	function rebase() public {
		require(block.timestamp >= _lastRebaseTimestamp + SECONDS_PER_DAY, "Rebase: Too early");
		
		// Check for transition from bootstrap to dynamic period
		if (_currentPeriod == PeriodType.BOOTSTRAP && isBootstrapPeriodOver()) {
			_currentPeriod = PeriodType.DYNAMIC;
			emit BootstrapPeriodEnded(block.timestamp);
			emit DynamicPeriodStarted(block.timestamp);
		}
		
		// Update moving average of transaction count
		_movingAverageTxCount = _movingAverageTxCount == 0 ? 
			_transactionCount * BASIS_POINTS : 
			((_movingAverageTxCount * (MOVING_AVG_PERIODS - 1) / MOVING_AVG_PERIODS) + 
			 (_transactionCount * BASIS_POINTS / MOVING_AVG_PERIODS));
		
		// Update transaction counts for next period
		_prevPeriodTxCount = _transactionCount;
		_transactionCount = 0;
		
		// In dynamic period, calculate new rate
		if (_currentPeriod == PeriodType.DYNAMIC) {
			// Calculate new dynamic rate
			_currentDynamicRate = _calculateDynamicRate();
			
			// If rate is positive, it's a mint rate - accumulate it
			if (_currentDynamicRate > 0) {
				uint256 mintRate = uint256(_currentDynamicRate);
				_accumulatedMintRate += mintRate;
				_lastRateUpdateTime = block.timestamp;
				
				emit MintRateAccumulated(block.timestamp, mintRate);
			}
			
			emit DynamicRateUpdated(block.timestamp, _currentDynamicRate, _prevPeriodTxCount);
		}
		
		_lastRebaseTimestamp = block.timestamp;
	}
	
	/**
	 * @dev Mint function for the bootstrap period
	 * Anyone can call to receive tokens during the initial distribution
	 */
	function mint() public {
		require(_currentPeriod == PeriodType.BOOTSTRAP, "Mint: Bootstrap period has ended");
		
		uint256 dropAmount = DROP_MINT;
		
		// Apply early adopter premium
		uint256 premium = _calculateEarlyAdopterPremium();
		dropAmount = (dropAmount * premium) / BASIS_POINTS;
		
		// Mint tokens to the caller
		_mint(msg.sender, dropAmount);
		
		// Initialize or update account data
		_updateAccountData(msg.sender);
		
		// Increment transaction count
		_transactionCount++;
	}
	
	/**
	 * @dev Return the visible balance including projected mint returns
	 * This is a view function that doesn't modify state but shows what the balance
	 * would be if mint rate was applied now
	 */
	function balanceOf(address account) public view override returns (uint256) {
		uint256 rawBalance = ERC20.balanceOf(account);
		
		// If in bootstrap period or account not initialized, return raw balance
		if (_currentPeriod == PeriodType.BOOTSTRAP || _accountData[account].lastUpdated == 0) {
			return rawBalance;
		}
		
		// Get account data
		AccountData storage data = _accountData[account];
		
		// Calculate accumulated mint rate for this account
		uint256 accountRate = data.accumulatedMintRate;
		
		// If account hasn't been updated since last rate update and rate is positive (mint)
		if (data.lastMintUpdate < _lastRateUpdateTime && _accumulatedMintRate > 0) {
			accountRate += _accumulatedMintRate;
		}
		
		// If no accumulated rate, return raw balance
		if (accountRate == 0) {
			return rawBalance;
		}
		
		// Calculate projected mint
		uint256 projectedMint = (rawBalance * accountRate) / BASIS_POINTS;
		
		return rawBalance + projectedMint;
	}
	
	/**
	 * @dev Returns the effective balance that would be used for transfers
	 * This differs from balanceOf as it represents the actual balance without projected mints
	 */
	function effectiveBalanceOf(address account) public view returns (uint256) {
		return _accountData[account].effectiveBalance;
	}
	
	/**
	 * @dev Returns the accumulated mint rate for a specific account
	 */
	function getAccountMintRate(address account) public view returns (uint256) {
		return _accountData[account].accumulatedMintRate;
	}
	
	/**
	 * @dev Override transfer function to implement burn on transfer
	 * and airdrop for new holders during bootstrap period
	 */
	function transfer(address to, uint256 amount) public override returns (bool) {
		require(amount > 0, "Transfer: Amount must be positive");
		
		address from = msg.sender;
		
		// Update account data for sender
		_updateAccountData(from);
		
		// If not in bootstrap period, update mint rates and apply them
		if (_currentPeriod != PeriodType.BOOTSTRAP) {
			// Update accumulated mint rate for sender
			_updateAccountMintRate(from);
			
			// Apply accumulated mint rate (actually mints tokens)
			_applyMintRate(from);
		}
		
		// Handle bootstrap period airdrop to new holders
		if (_currentPeriod == PeriodType.BOOTSTRAP && ERC20.balanceOf(to) == 0) {
			uint256 dropAmount = DROP_TRANSFER;
			
			// Apply early adopter premium
			uint256 premium = _calculateEarlyAdopterPremium();
			dropAmount = (dropAmount * premium) / BASIS_POINTS;
			
			if (dropAmount > 0) {
				_mint(to, dropAmount);
			}
		}
		
		// Apply burn rate to transfer if rate is negative (burns tokens)
		uint256 burned = _applyBurnRate(from, amount);
		
		// Increment transaction count for rate calculations
		_transactionCount++;
		
		// Transfer amount minus burned
		uint256 netAmount = amount - burned;
		bool success = super.transfer(to, netAmount);
		
		// Update account data for recipient
		_updateAccountData(to);
		
		// If not in bootstrap period, update mint rates for recipient
		if (_currentPeriod != PeriodType.BOOTSTRAP) {
			_updateAccountMintRate(to);
		}
		
		// Trigger rebase if enough time has passed
		if (block.timestamp >= _lastRebaseTimestamp + SECONDS_PER_DAY) {
			rebase();
		}
		
		return success;
	}
	
	/**
	 * @dev Override transferFrom function to implement burn on transfer
	 * and airdrop for new holders during bootstrap period
	 */
	function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
		require(amount > 0, "Transfer: Amount must be positive");
		
		// Update account data for sender
		_updateAccountData(from);
		
		// If not in bootstrap period, update mint rates and apply them
		if (_currentPeriod != PeriodType.BOOTSTRAP) {
			// Update accumulated mint rate for sender
			_updateAccountMintRate(from);
			
			// Apply accumulated mint rate (actually mints tokens)
			_applyMintRate(from);
		}
		
		// Handle bootstrap period airdrop to new holders
		if (_currentPeriod == PeriodType.BOOTSTRAP && ERC20.balanceOf(to) == 0) {
			uint256 dropAmount = DROP_TRANSFER;
			
			// Apply early adopter premium
			uint256 premium = _calculateEarlyAdopterPremium();
			dropAmount = (dropAmount * premium) / BASIS_POINTS;
			
			if (dropAmount > 0) {
				_mint(to, dropAmount);
			}
		}
		
		// Apply burn rate to transfer if rate is negative (burns tokens)
		uint256 burned = _applyBurnRate(from, amount);
		
		// Increment transaction count for rate calculations
		_transactionCount++;
		
		// Transfer amount minus burned
		uint256 netAmount = amount - burned;
		
		// Check allowance against original amount
		uint256 currentAllowance = allowance(from, msg.sender);
		require(currentAllowance >= amount, "ERC20: insufficient allowance");
		
		// Reduce allowance by original amount, not net amount
		unchecked {
			_approve(from, msg.sender, currentAllowance - amount);
		}
		
		bool success = super.transferFrom(from, to, netAmount);
		
		// Update account data for recipient
		_updateAccountData(to);
		
		// If not in bootstrap period, update mint rates for recipient
		if (_currentPeriod != PeriodType.BOOTSTRAP) {
			_updateAccountMintRate(to);
		}
		
		// Trigger rebase if enough time has passed
		if (block.timestamp >= _lastRebaseTimestamp + SECONDS_PER_DAY) {
			rebase();
		}
		
		return success;
	}
	
	/**
	 * @dev Destroy tokens from the caller's account
	 * @param amount The amount to burn
	 */
	function burn(uint256 amount) public {
		_burn(msg.sender, amount);
		
		// Update account data
		_updateAccountData(msg.sender);
		
		// Increment transaction count
		_transactionCount++;
	}
	
	/**
	 * @dev Destroy tokens from another account (requires allowance)
	 * @param account The account to burn from
	 * @param amount The amount to burn
	 */
	function burnFrom(address account, uint256 amount) public {
		uint256 currentAllowance = allowance(account, msg.sender);
		require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
		
		unchecked {
			_approve(account, msg.sender, currentAllowance - amount);
		}
		
		_burn(account, amount);
		
		// Update account data
		_updateAccountData(account);
		
		// Increment transaction count
		_transactionCount++;
	}
}



