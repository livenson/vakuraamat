//! Pure economy arithmetic shared by the reducers and the scheduled tick. No database access here so
//! `cargo test` covers it without a server.

/// Monthly rent in whole euros for a parcel: `land_value * yield_permille / 1000 / 12`, at least 1 when the
/// parcel has a value and a yield.
pub fn rent_month(land_value: u64, yield_permille: u32) -> u64 {
    if land_value == 0 || yield_permille == 0 {
        return 0;
    }
    ((land_value * yield_permille as u64) / 1000 / 12).max(1)
}

/// Monthly land tax: `land_value * tax_rate_year_permille / 1000 / 12`, rounded down, can be 0 for cheap plots.
pub fn tax_month(land_value: u64, tax_rate_year_permille: u32) -> u64 {
    (land_value * tax_rate_year_permille as u64) / 1000 / 12
}

/// Asking price of an unowned parcel: land value scaled by the town's price index (1000 = par).
pub fn list_price(land_value: u64, price_index_permille: u32) -> u64 {
    ((land_value * price_index_permille as u64) / 1000).max(1)
}

/// Next price index after one month of drift: `roll` is uniform in 0..1000, `drift_permille` the max step.
/// Clamped to 700..1500 so a town never runs away.
pub fn drift_index(index: u32, drift_permille: u32, roll: u32) -> u32 {
    let step = (drift_permille as i64 * (roll as i64 - 500)) / 500;
    ((index as i64 + step).clamp(700, 1500)) as u32
}

/// Penalty added to an overdue obligation.
pub fn penalty(amount: u64, penalty_permille: u32) -> u64 {
    (amount * penalty_permille as u64) / 1000
}

/// An AI family's bid on a player parcel: 85..115 % of the asking price, `roll` uniform in 0..300.
pub fn family_bid(price: u64, roll: u32) -> u64 {
    (price * (850 + roll as u64)) / 1000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rent_is_monthly_and_never_zero_when_valued() {
        assert_eq!(rent_month(120_000, 45), 450);
        assert_eq!(rent_month(100, 45), 1);
        assert_eq!(rent_month(0, 45), 0);
        assert_eq!(rent_month(1000, 0), 0);
    }

    #[test]
    fn tax_and_price() {
        assert_eq!(tax_month(120_000, 5), 50);
        assert_eq!(list_price(120_000, 1000), 120_000);
        assert_eq!(list_price(120_000, 1100), 132_000);
    }

    #[test]
    fn drift_stays_in_band() {
        assert_eq!(drift_index(1000, 10, 500), 1000);
        assert_eq!(drift_index(1000, 10, 1000), 1010);
        assert_eq!(drift_index(1000, 10, 0), 990);
        assert_eq!(drift_index(1499, 10, 1000), 1500);
        assert_eq!(drift_index(701, 10, 0), 700);
    }

    #[test]
    fn bids_and_penalties() {
        assert_eq!(family_bid(100_000, 0), 85_000);
        assert_eq!(family_bid(100_000, 300), 115_000);
        assert_eq!(penalty(1000, 100), 100);
    }
}
