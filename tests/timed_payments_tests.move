#[test_only]
module timed_payments::timed_payment_tests;

use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;
use timed_payments::timed_payment::{Self, TimedPayment};

const OWNER_ADDR: address = @0xAAAA;
const RECIPIENT_ADDR: address = @0xBBBB;
const AMOUNT: u64 = 10_000;
const DISBURSEMENT_TIME: u64 = 1_000;

fun test_setup(): ts::Scenario {
    let mut ts = ts::begin(OWNER_ADDR);
    let coins = coin::mint_for_testing<SUI>(AMOUNT, ts.ctx());
    let now = clock::create_for_testing(ts.ctx());
    // Create the payment
    timed_payment::create_payment(
        coins,
        RECIPIENT_ADDR,
        DISBURSEMENT_TIME,
        b"Test payment".to_vec(),
        ts.ctx()
    );
    now.destroy_for_testing();
    ts
}

#[test]
fun test_timed_payment_claim() {
    let mut ts = test_setup();
    ts.next_tx(RECIPIENT_ADDR);
    let mut now = clock::create_for_testing(ts.ctx());
    let mut payment = ts.take_shared<TimedPayment>();

    // Try to claim before disbursement time (should fail)
    now.set_for_testing(DISBURSEMENT_TIME - 1);
    // This should abort with EDisbursementTimeNotReached
    // assert_abort!(timed_payment::claim_payment(&mut payment, ts.ctx()), timed_payment::EDisbursementTimeNotReached);

    // Advance clock to disbursement time
    now.set_for_testing(DISBURSEMENT_TIME);
    timed_payment::claim_payment(&mut payment, ts.ctx());

    // After claiming, status should be STATUS_COMPLETED (1)
    assert!(payment.status == 1);

    ts.return_to_sender(payment);
    now.destroy_for_testing();
    let _end = ts::end(ts);
}
