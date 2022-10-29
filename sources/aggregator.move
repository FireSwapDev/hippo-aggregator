module hippo_aggregator::aggregator {
    use aptos_framework::coin;
    use aptos_framework::account;
    use std::signer;
    use std::option;
    use std::option::{Option, is_some, borrow};
    // use econia::market;
    use aptos_std::event::EventHandle;
    use aptos_framework::timestamp;
    use aptos_std::event;
    use aptos_std::type_info::{TypeInfo, type_of};
    use aptos_framework::aptos_coin::AptosCoin;
    // use ditto::staked_coin;
    // use tortuga::staked_aptos_coin;

    const HI_64: u64 = 0xffffffffffffffff;

    const DEX_HIPPO: u8 = 1;
    const DEX_ECONIA: u8 = 2;
    const DEX_PONTEM: u8 = 3;
    const DEX_BASIQ: u8 = 4;
    const DEX_DITTO: u8 = 5;
    const DEX_TORTUGA: u8 = 6;
    const DEX_APTOSWAP: u8 = 7;
    const DEX_AUX: u8 = 8;
    const DEX_ANIMESWAP: u8 = 9;
    const DEX_CETUS: u8 = 9;
    const DEX_FIRESWAP: u8 = 11;

    const HIPPO_CONSTANT_PRODUCT:u64 = 1;
    const HIPPO_PIECEWISE:u64 = 3;
    const AUX_TYPE_AMM:u64 = 0;
    const AUX_TYPE_MARKET:u64 = 1;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_OUTPUT_LESS_THAN_MINIMUM: u64 = 2;
    const E_UNKNOWN_DEX: u64 = 3;
    const E_NOT_ADMIN: u64 = 4;
    const E_INVALID_PAIR_OF_DITTO: u64 = 5;
    const E_INVALID_PAIR_OF_TORTUGA: u64 = 6;
    const E_TYPE_NOT_EQUAL: u64 = 7;
    const E_COIN_STORE_NOT_EXITES: u64 = 8;
    const E_UNSUPPORTED_NUM_STEPS: u64 = 9;


    struct EventStore has key {
        swap_step_events: EventHandle<SwapStepEvent>,
    }

    struct CoinStore<phantom CoinType> has key {
        balance: coin::Coin<CoinType>
    }

    struct AuxSigner has key {
        signerCapability: account::SignerCapability
    }

    struct SwapStepEvent has drop, store {
        dex_type: u8,
        pool_type: u64,
        // input coin type
        x_type_info: TypeInfo,
        // output coin type
        y_type_info: TypeInfo,
        input_amount: u64,
        output_amount: u64,
        time_stamp: u64
    }

    entry fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @hippo_aggregator, E_NOT_ADMIN);
        init_coin_store_all(admin);
        move_to(admin, EventStore {
            swap_step_events: account::new_event_handle<SwapStepEvent>(admin)
        });
        create_aux_signer(admin);
    }

    #[cmd]
    public entry fun create_aux_signer(admin: &signer){
        assert!(signer::address_of(admin) == @hippo_aggregator, E_NOT_ADMIN);
        let (_signer, signerCapability) = account::create_resource_account(admin,b"aux_signer");
        move_to(admin,AuxSigner{
            signerCapability
        });
    }

    #[cmd]
    public entry fun init_coin_store<X>(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @hippo_aggregator, E_NOT_ADMIN);
        move_to(admin, CoinStore<X>{
            balance: coin::zero<X>()
        });
    }

    #[cmd]
    public entry fun init_coin_store_all(admin: &signer){
        init_coin_store<AptosCoin>(admin);
        // init_coin_store<staked_coin::StakedAptos>(admin);
        // init_coin_store<staked_aptos_coin::StakedAptosCoin>(admin);
    }

    #[test_only]
    public fun init_module_test(admin: &signer) {
        init_module(admin);
    }

    fun emit_swap_step_event<Input, Output>(
        dex_type:u8,
        pool_type:u64,
        input_amount:u64,
        output_amount: u64
    ) acquires EventStore {
        let event_store = borrow_global_mut<EventStore>(@hippo_aggregator);
        event::emit_event<SwapStepEvent>(
            &mut event_store.swap_step_events,
            SwapStepEvent {
                dex_type,
                pool_type,
                x_type_info: type_of<coin::Coin<Input>>(),
                y_type_info: type_of<coin::Coin<Output>>(),
                input_amount,
                output_amount,
                time_stamp: timestamp::now_microseconds()
            },
        );
    }

    fun change_coin_type<X, Y>(x_coin: coin::Coin<X>): coin::Coin<Y> acquires CoinStore {
        assert!(type_of<X>() == type_of<Y>(), E_TYPE_NOT_EQUAL);
        assert!(exists<CoinStore<X>>(@hippo_aggregator), 0);
        let amount = coin::value(&x_coin);
        let x_coin_store = borrow_global_mut<CoinStore<X>>(@hippo_aggregator);
        coin::merge(&mut x_coin_store.balance, x_coin);

        let y_coin_store = borrow_global_mut<CoinStore<Y>>(@hippo_aggregator);
        coin::extract(&mut y_coin_store.balance, amount)
    }

    #[test(admin = @hippo_aggregator)]
    fun test_change_coin_type(admin: &signer) acquires CoinStore {
        init_coin_store_all(admin);
        let coin = change_coin_type<AptosCoin, AptosCoin>(coin::zero<AptosCoin>());
        coin::destroy_zero(coin)
    }

    public fun get_intermediate_output<X, Y, E>(
        dex_type: u8,
        pool_type: u64,
        is_x_to_y: bool,
        x_in: coin::Coin<X>
    ): (Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        let coin_in_value = coin::value(&x_in);
        let (x_out_opt, y_out) = if (dex_type == DEX_HIPPO) {
            abort E_UNKNOWN_DEX
        }
        /*
        else if (dex_type == DEX_ECONIA) {
            // deposit into temporary wallet!
            let y_out = coin::zero<Y>();
            let x_value = coin::value(&x_in);
            let market_id = pool_type;
            if (is_x_to_y) {
                // sell
                market::swap_coins<X, Y>(@hippo_aggregator, market_id, false, 0, x_value, 0, HI_64, 0, &mut x_in, &mut y_out);
            }
            else {
                // buy
                market::swap_coins<Y, X>(@hippo_aggregator, market_id, true, 0, HI_64, 0, x_value, HI_64, &mut y_out, &mut x_in);
            };
            if (coin::value(&x_in) == 0) {
                coin::destroy_zero(x_in);
                (option::none(), y_out)
            }
            else {
                (option::some(x_in), y_out)
            }
        }*/
        else if (dex_type == DEX_PONTEM) {
            use liquidswap::router;
            (option::none(), router::swap_exact_coin_for_coin<X, Y, E>(x_in, 0))
        }
        /*
        else if (dex_type == DEX_BASIQ) {
            use basiq::dex;
            (option::none(), dex::swap<X, Y>(x_in))
        }
        */
        else if (dex_type == DEX_APTOSWAP) {
            use Aptoswap::pool;
            if (is_x_to_y) {
                let y_out = pool::swap_x_to_y_direct<X, Y>(x_in);
                (option::none(), y_out)
            }
            else {
                let y_out = pool::swap_y_to_x_direct<Y, X>(x_in);
                (option::none(), y_out)
            }
        }
        else if (dex_type == DEX_AUX) {
            if (pool_type == AUX_TYPE_AMM){
                use aux::amm;
                let y_out = coin::zero<Y>();
                amm::swap_exact_coin_for_coin_mut(
                    @hippo_aggregator,
                    &mut x_in,
                    &mut y_out,
                    coin_in_value,
                    0,
                    false,
                    0,
                    0
                );
                (option::some(x_in),y_out)
            } else if (pool_type == AUX_TYPE_MARKET){
                use aux::clob_market;
                let y_out = coin::zero<Y>();
                clob_market::place_market_order_mut(
                    @hippo_aggregator,
                    &mut x_in,
                    &mut y_out,
                    false,
                    102,// IMMEDIATE_OR_CANCEL in aux::router,
                    0,
                    coin_in_value,
                    0
                );
                (option::some(x_in),y_out)
            } else {
                abort E_UNKNOWN_POOL_TYPE
            }
        }
        else if (dex_type == DEX_ANIMESWAP) {
            use SwapDeployer::AnimeSwapPoolV1;
            (option::none(), AnimeSwapPoolV1::swap_coins_for_coins(x_in))
        }
        else if (dex_type == DEX_CETUS){
            use cetus_amm::amm_router;
            let y_out = amm_router::swap<X, Y>(@hippo_aggregator, x_in);
            (option::none(),y_out)
        }
        else if (dex_type == DEX_FIRESWAP) {
            use SwapDeployer::FireSwapPoolV1;
            (option::none(), FireSwapPoolV1::swap_coins_for_coins<X, Y>(x_in))
        }
        else {
            abort E_UNKNOWN_DEX
        };

        let coin_in_value = if (is_some(&x_out_opt)) {
            coin_in_value - coin::value(borrow(&x_out_opt))
        } else {
            coin_in_value
        };
        emit_swap_step_event<X, Y>(
            dex_type,
            pool_type,
            coin_in_value,
            coin::value(&y_out)
        );
        (x_out_opt, y_out)
    }

    fun check_and_deposit_opt<X>(sender: &signer, coin_opt: Option<coin::Coin<X>>) {
        if (option::is_some(&coin_opt)) {
            let coin = option::extract(&mut coin_opt);
            let sender_addr = signer::address_of(sender);
            if (!coin::is_account_registered<X>(sender_addr)) {
                coin::register<X>(sender);
            };
            coin::deposit(sender_addr, coin);
        };
        option::destroy_none(coin_opt)
    }

    fun check_and_deposit<X>(sender: &signer, coin: coin::Coin<X>) {
        let sender_addr = signer::address_of(sender);
        if (!coin::is_account_registered<X>(sender_addr)) {
            coin::register<X>(sender);
        };
        coin::deposit(sender_addr, coin);
    }

    public fun one_step_direct<X, Y, E>(
        dex_type: u8,
        pool_type: u64,
        is_x_to_y: bool,
        x_in: coin::Coin<X>
    ):(Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        get_intermediate_output<X, Y, E>(dex_type, pool_type, is_x_to_y, x_in)
    }

    #[cmd]
    public entry fun one_step_route<X, Y, E>(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        x_in: u64,
        y_min_out: u64,
    ) acquires EventStore {
        let coin_in = coin::withdraw<X>(sender, x_in);
        let (coin_remain_opt, coin_out) = one_step_direct<X, Y, E>(first_dex_type, first_pool_type, first_is_x_to_y, coin_in);
        assert!(coin::value(&coin_out) >= y_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_remain_opt);
        check_and_deposit(sender, coin_out);
    }

    public fun two_step_direct<
        X, Y, Z, E1, E2,
    >(
      first_dex_type: u8,
      first_pool_type: u64,
      first_is_x_to_y: bool, // first trade uses normal order
      second_dex_type: u8,
      second_pool_type: u64,
      second_is_x_to_y: bool, // second trade uses normal order
      x_in: coin::Coin<X>
    ):(Option<coin::Coin<X>>, Option<coin::Coin<Y>>, coin::Coin<Z>) acquires EventStore {
        let (coin_x_remain, coin_y) = get_intermediate_output<X, Y, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
        let (coin_y_remain, coin_z) = get_intermediate_output<Y, Z, E2>(second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
        (coin_x_remain, coin_y_remain, coin_z)
    }

    #[cmd]
    public entry fun two_step_route<
        X, Y, Z, E1, E2,
    >(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        x_in: u64,
        z_min_out: u64,
    ) acquires EventStore {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let (
            coin_x_remain,
            coin_y_remain,
            coin_z
        ) = two_step_direct<X, Y, Z, E1, E2>(
            first_dex_type,
            first_pool_type,
            first_is_x_to_y,
            second_dex_type,
            second_pool_type,
            second_is_x_to_y,
            coin_x
        );
        assert!(coin::value(&coin_z) >= z_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_x_remain);
        check_and_deposit_opt(sender, coin_y_remain);
        check_and_deposit(sender, coin_z);
    }

    public fun three_step_direct<
        X, Y, Z, M, E1, E2, E3
    >(
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        third_dex_type: u8,
        third_pool_type: u64,
        third_is_x_to_y: bool, // second trade uses normal order
        x_in: coin::Coin<X>
    ):(Option<coin::Coin<X>>, Option<coin::Coin<Y>>, Option<coin::Coin<Z>>, coin::Coin<M>) acquires EventStore {
        let (coin_x_remain, coin_y) = get_intermediate_output<X, Y, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
        let (coin_y_remain, coin_z) = get_intermediate_output<Y, Z, E2>(second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
        let (coin_z_remain, coin_m) = get_intermediate_output<Z, M, E3>(third_dex_type, third_pool_type, third_is_x_to_y, coin_z);
        (coin_x_remain, coin_y_remain, coin_z_remain, coin_m)
    }

    #[cmd]
    public entry fun three_step_route<
        X, Y, Z, M, E1, E2, E3
    >(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        third_dex_type: u8,
        third_pool_type: u64,
        third_is_x_to_y: bool, // second trade uses normal order
        x_in: u64,
        m_min_out: u64,
    ) acquires EventStore {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let (
            coin_x_remain,
            coin_y_remain,
            coin_z_remain ,
            coin_m
        ) = three_step_direct<X, Y, Z, M, E1, E2, E3>(
            first_dex_type,
            first_pool_type,
            first_is_x_to_y,
            second_dex_type,
            second_pool_type,
            second_is_x_to_y,
            third_dex_type,
            third_pool_type,
            third_is_x_to_y,
            coin_x
        );
        assert!(coin::value(&coin_m) >= m_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_x_remain);
        check_and_deposit_opt(sender, coin_y_remain);
        check_and_deposit_opt(sender, coin_z_remain);
        check_and_deposit(sender, coin_m);
    }

    public fun swap_direct<
        X, Y, Z, OutCoin, E1, E2, E3
    >(
        num_steps: u8,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        third_dex_type: u8,
        third_pool_type: u64,
        third_is_x_to_y: bool, // second trade uses normal order
        x_in: coin::Coin<X>
    ):(Option<coin::Coin<X>>, Option<coin::Coin<Y>>, Option<coin::Coin<Z>>, coin::Coin<OutCoin>) acquires EventStore {
        if (num_steps == 1) {
            let (coin_x_remain, coin_m) = get_intermediate_output<X, OutCoin, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            (coin_x_remain, option::some(coin::zero<Y>()), option::some(coin::zero<Z>()), coin_m)
        }
        else if (num_steps == 2) {
            let (coin_x_remain, coin_y) = get_intermediate_output<X, Y, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            let (coin_y_remain, coin_m) = get_intermediate_output<Y, OutCoin, E2>(second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
            (coin_x_remain, coin_y_remain, option::some(coin::zero<Z>()), coin_m)
        }
        else if (num_steps == 3) {
            let (coin_x_remain, coin_y) = get_intermediate_output<X, Y, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            let (coin_y_remain, coin_z) = get_intermediate_output<Y, Z, E2>(second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
            let (coin_z_remain, coin_m) = get_intermediate_output<Z, OutCoin, E3>(third_dex_type, third_pool_type, third_is_x_to_y, coin_z);
            (coin_x_remain, coin_y_remain, coin_z_remain, coin_m)
        }
        else {
            abort E_UNSUPPORTED_NUM_STEPS
        }
    }

    #[cmd]
    public entry fun swap<
        X, Y, Z, OutCoin, E1, E2, E3
    >(
        sender: &signer,
        num_steps: u8,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        third_dex_type: u8,
        third_pool_type: u64,
        third_is_x_to_y: bool, // second trade uses normal order
        x_in: u64,
        m_min_out: u64,
    ) acquires EventStore {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let (x_remain, y_remain, z_remain, coin_m) = swap_direct<X, Y, Z, OutCoin, E1, E2, E3>(
            num_steps,
            first_dex_type,
            first_pool_type,
            first_is_x_to_y,
            second_dex_type,
            second_pool_type,
            second_is_x_to_y,
            third_dex_type,
            third_pool_type,
            third_is_x_to_y,
            coin_x
        );

        assert!(coin::value(&coin_m) >= m_min_out, E_OUTPUT_LESS_THAN_MINIMUM);

        check_and_deposit_opt(sender, x_remain);
        check_and_deposit_opt(sender, y_remain);
        check_and_deposit_opt(sender, z_remain);
        check_and_deposit(sender, coin_m);
    }


}
