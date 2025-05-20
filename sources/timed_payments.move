module timed_payments::timed_payment;
    use sui::balance::{Self, Balance};
    use std::string::String;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::event;
    
    /// Error codes
    const EInsufficientBalance: u64 = 0;
    const EInvalidDisbursementTime: u64 = 1;
    const ENotOwner: u64 = 2;
    const ENotRecipient: u64 = 3;
    const EDisbursementTimeNotReached: u64 = 4;
    const EAlreadyCompleted: u64 = 5;
    const EAlreadyCancelled: u64 = 6;

    /// Status codes for the TimedPayment
    const STATUS_ACTIVE: u8 = 0;
    const STATUS_COMPLETED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    /// Stores funds with a disbursement schedule
    public struct TimedPayment has key, store {
        id: UID,
        balance: Balance<SUI>,
        owner: address,
        recipient: address,
        disbursement_time: u64, // Timestamp in milliseconds
        description: String,
        status: u8
    }

    /// Events for tracking actions
    public struct PaymentCreated has copy, drop {
        payment_id: ID,
        owner: address,
        recipient: address,
        amount: u64,
        disbursement_time: u64
    }

    public struct PaymentFunded has copy, drop {
        payment_id: ID,
        funder: address,
        amount: u64,
        new_balance: u64
    }

    public struct PaymentDisbursed has copy, drop {
        payment_id: ID,
        recipient: address,
        amount: u64
    }

    public struct PaymentCancelled has copy, drop {
        payment_id: ID,
        owner: address,
        amount: u64
    }

    public struct ScheduleUpdated has copy, drop {
        payment_id: ID,
        old_time: u64,
        new_time: u64
    }

    /// Create a new timed payment
    public entry fun create_payment(
        coin: Coin<SUI>,
        recipient: address,
        disbursement_time: u64,
        description: String,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Validate the disbursement time is in the future
        assert!(disbursement_time > current_time, EInvalidDisbursementTime);
        
        // Extract balance from the coin
        let balance = coin::into_balance(coin);
        let balance_value = balance::value(&balance);
        
        // Create the payment object
        let payment = TimedPayment {
            id: object::new(ctx),
            balance,
            owner: sender,
            recipient,
            disbursement_time,
            description,
            status: STATUS_ACTIVE
        };
        
        // Emit creation event
        let payment_id = object::uid_to_inner(&payment.id);
        event::emit(PaymentCreated {
            payment_id,
            owner: sender,
            recipient,
            amount: balance_value,
            disbursement_time
        });
        
        // Transfer the payment object to shared
        transfer::share_object(payment);
    }
    
    /// Add more funds to an existing payment
    public entry fun add_funds(
        payment: &mut TimedPayment,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Ensure payment is still active
        assert!(payment.status == STATUS_ACTIVE, EAlreadyCompleted);
        
        // Add funds to the payment
        let added_balance = coin::into_balance(coin);
        let added_amount = balance::value(&added_balance);
        balance::join(&mut payment.balance, added_balance);
        
        // Get new total balance
        let new_balance = balance::value(&payment.balance);
        
        // Emit funding event
        let payment_id = object::uid_to_inner(&payment.id);
        event::emit(PaymentFunded {
            payment_id,
            funder: sender,
            amount: added_amount,
            new_balance
        });
    }
    
    /// Owner can update the disbursement time
    public entry fun update_schedule(
        payment: &mut TimedPayment,
        new_disbursement_time: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Ensure sender is the owner
        assert!(sender == payment.owner, ENotOwner);
        
        // Ensure payment is still active
        assert!(payment.status == STATUS_ACTIVE, EAlreadyCompleted);
        
        // Validate the new disbursement time is in the future
        assert!(new_disbursement_time > current_time, EInvalidDisbursementTime);
        
        // Store old time for the event
        let old_time = payment.disbursement_time;
        
        // Update the disbursement time
        payment.disbursement_time = new_disbursement_time;
        
        // Emit schedule update event
        let payment_id = object::uid_to_inner(&payment.id);
        event::emit(ScheduleUpdated {
            payment_id,
            old_time,
            new_time: new_disbursement_time
        });
    }
    
    /// Recipient claims funds after disbursement time
    public entry fun claim_payment(
        payment: &mut TimedPayment,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Ensure sender is the recipient
        assert!(sender == payment.recipient, ENotRecipient);
        
        // Ensure payment is still active
        assert!(payment.status == STATUS_ACTIVE, EAlreadyCompleted);
        
        // Check if disbursement time has been reached
        assert!(current_time >= payment.disbursement_time, EDisbursementTimeNotReached);
        
        // Get the amount to transfer
        let amount = balance::value(&payment.balance);
        
        // Create a coin to transfer
        let coin = coin::from_balance(balance::split(&mut payment.balance, amount), ctx);
        
        // Update payment status
        payment.status = STATUS_COMPLETED;
        
        // Emit disbursement event
        let payment_id = object::uid_to_inner(&payment.id);
        event::emit(PaymentDisbursed {
            payment_id,
            recipient: sender,
            amount
        });
        
        // Transfer the coin to the recipient
        transfer::public_transfer(coin, sender);
    }
    
    /// Owner cancels payment before disbursement time
    public entry fun cancel_payment(
        payment: &mut TimedPayment,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Ensure sender is the owner
        assert!(sender == payment.owner, ENotOwner);
        
        // Ensure payment is still active
        assert!(payment.status == STATUS_ACTIVE, EAlreadyCancelled);
        
        // Owners can only cancel before disbursement time
        assert!(current_time < payment.disbursement_time, EDisbursementTimeNotReached);
        
        // Get the amount to return
        let amount = balance::value(&payment.balance);
        
        // Create a coin to transfer
        let coin = coin::from_balance(balance::split(&mut payment.balance, amount), ctx);
        
        // Update payment status
        payment.status = STATUS_CANCELLED;
        
        // Emit cancellation event
        let payment_id = object::uid_to_inner(&payment.id);
        event::emit(PaymentCancelled {
            payment_id,
            owner: sender,
            amount
        });
        
        // Return the funds to the owner
        transfer::public_transfer(coin, sender);
    }
    
    /// Get information about a payment (view function)
    public fun get_payment_info(payment: &TimedPayment): (address, address, u64, u64, u8) {
        (
            payment.owner,
            payment.recipient,
            balance::value(&payment.balance),
            payment.disbursement_time,
            payment.status
        )
    }
    
    /// Check if a payment is available for claiming (view function)
    public fun is_payment_claimable(payment: &TimedPayment, ctx: &TxContext): bool {
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        payment.status == STATUS_ACTIVE && current_time >= payment.disbursement_time
    }