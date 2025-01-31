/// Implements stable curve math.
module liquidswap::stable_curve {
    // !!!FOR AUDITOR!!!
    // Please, review this file really carefully and detailed.
    // Some of the functions just migrated from Solidly (BaseV1-core).
    // Some we implemented outself, like coin_in.
    // Also look at all places in all contracts where the functions called and check places too and arguments.
    use u256::u256::{Self, U256};

    /// We take 10^8 as we expect most of the coins to have 6-8 decimals.
    const ONE_E_8: u128 = 100000000;

    /// Get LP value for stable curve: x^3*y + x*y^3
    /// * `x_coin` - reserves of coin X.
    /// * `x_scale` - 10 pow X coin decimals amount.
    /// * `y_coin` - reserves of coin Y.
    /// * `y_scale` - 10 pow Y coin decimals amount.
    public fun lp_value(x_coin: u128, x_scale: u64, y_coin: u128, y_scale: u64): U256 {
        let x_u256 = u256::from_u128(x_coin);
        let y_u256 = u256::from_u128(y_coin);
        let u2561e8 = u256::from_u128(ONE_E_8);

        let x_scale_u256 = u256::from_u64(x_scale);
        let y_scale_u256 = u256::from_u64(y_scale);

        let _x = u256::div(
            u256::mul(x_u256, u2561e8),
            x_scale_u256,
        );

        let _y = u256::div(
            u256::mul(y_u256, u2561e8),
            y_scale_u256,
        );

        let _a = u256::mul(_x, _y);

        // ((_x * _x) / 1e18 + (_y * _y) / 1e18)
        let _b = u256::add(
            u256::mul(_x, _x),
            u256::mul(_y, _y),
        );

        u256::mul(_a, _b)
    }

    /// Get coin amount out by passing amount in, returns amount out (we don't take fees into account here).
    /// It probably would eat a lot of gas and better to do it offchain (on your frontend or whatever),
    /// yet if no other way and need blockchain computation we left it here.
    /// * `coin_in` - amount of coin to swap.
    /// * `scale_in` - 10 pow by coin decimals you want to swap.
    /// * `scale_out` - 10 pow by coin decimals you want to get.
    /// * `reserve_in` - reserves of coin to swap coin_in.
    /// * `reserve_out` - reserves of coin to get in exchange.
    public fun coin_out(coin_in: u128, scale_in: u64, scale_out: u64, reserve_in: u128, reserve_out: u128): u128 {
        let u2561e8 = u256::from_u128(ONE_E_8);

        let xy = lp_value(reserve_in, scale_in, reserve_out, scale_out);

        let reserve_in_u256 = u256::div(
            u256::mul(
                u256::from_u128(reserve_in),
                u2561e8,
            ),
            u256::from_u64(scale_in),
        );
        let reserve_out_u256 = u256::div(
            u256::mul(
                u256::from_u128(reserve_out),
                u2561e8,
            ),
            u256::from_u64(scale_out),
        );
        let amount_in = u256::div(
            u256::mul(
                u256::from_u128(coin_in),
                u2561e8
            ),
            u256::from_u64(scale_in)
        );
        let total_reserve = u256::add(amount_in, reserve_in_u256);
        let y = u256::sub(
            reserve_out_u256,
            get_y(total_reserve, xy, reserve_out_u256),
        );

        let r = u256::div(
            u256::mul(
                y,
                u256::from_u64(scale_out),
            ),
            u2561e8
        );

        u256::as_u128(r)
    }

    /// Trying to find suitable `y` value.
    /// * `x0` - total reserve x (include `coin_in`) with transformed decimals.
    /// * `xy` - lp value (see `lp_value` func).
    /// * `y` - reserves out with transformed decimals.
    fun get_y(x0: U256, xy: U256, y: U256): U256 {
        let i = 0;

        let one_u256 = u256::from_u128(1);

        while (i < 255) {
            let k = f(x0, y);

            let _dy = u256::zero();
            let cmp = u256::compare(&k, &xy);
            if (cmp == 1) {
                _dy = u256::add(
                    u256::div(
                        u256::sub(xy, k),
                        d(x0, y),
                    ),
                    one_u256    // Round up
                );
                y = u256::add(y, _dy);
            } else {
                _dy = u256::div(
                    u256::sub(k, xy),
                    d(x0, y),
                );
                y = u256::sub(y, _dy);
            };
            cmp = u256::compare(&_dy, &one_u256);
            if (cmp == 0 || cmp == 1) {
                return y
            };

            i = i + 1;
        };

        y
    }

    /// Implements x0*y^3 + x0^3*y = x0*(y*y/1e18*y/1e18)/1e18+(x0*x0/1e18*x0/1e18)*y/1e18
    fun f(x0_u256: U256, y_u256: U256): U256 {
        // x0*(y*y/1e18*y/1e18)/1e18
        let yy = u256::mul(y_u256, y_u256);
        let yyy = u256::mul(yy, y_u256);

        let a = u256::mul(x0_u256, yyy);

        //(x0*x0/1e18*x0/1e18)*y/1e18
        let xx = u256::mul(x0_u256, x0_u256);
        let xxx = u256::mul(xx, x0_u256);
        let b = u256::mul(xxx, y_u256);

        // a + b
        u256::add(a, b)
    }

    /// Implements 3 * x0 * y^2 + x0^3 = 3 * x0 * (y * y / 1e8) / 1e8 + (x0 * x0 / 1e8 * x0) / 1e8
    fun d(x0_u256: U256, y_u256: U256): U256 {
        let three_u256 = u256::from_u128(3);

        // 3 * x0 * (y * y / 1e8) / 1e8
        let x3 = u256::mul(three_u256, x0_u256);
        let yy = u256::mul(y_u256, y_u256);
        let xyy3 = u256::mul(x3, yy);
        let xx = u256::mul(x0_u256, x0_u256);

        // x0 * x0 / 1e8 * x0 / 1e8
        let xxx = u256::mul(xx, x0_u256);

        u256::add(xyy3, xxx)
    }


}
