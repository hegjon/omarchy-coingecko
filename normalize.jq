# Turn a CoinGecko /coins/markets response into the model the widget renders.
#
# Inputs (via --arg / --argjson):
#   $currency  quote currency code, lower-case
#   $ids       array of requested coin ids, in the user's order
#   $now       epoch seconds of the fetch
#
# CoinGecko orders by market cap; the user's order is kept instead, because the
# first coin is the one on the bar. Ids the API does not know come back in
# `missing` rather than vanishing.

if type != "array" then
  {error: "CoinGecko returned something unexpected"}
else
  (map({(.id): .}) | add // {}) as $byId
  | {
      currency: $currency,
      fetchedAt: $now,
      coins: [ $ids[] | $byId[.] // empty | {
        id: .id,
        symbol: (.symbol // "" | ascii_upcase),
        name: (.name // .id),
        rank: .market_cap_rank,
        price: .current_price,
        change1h: .price_change_percentage_1h_in_currency,
        change24h: (.price_change_percentage_24h_in_currency // .price_change_percentage_24h),
        change7d: .price_change_percentage_7d_in_currency,
        high24h: .high_24h,
        low24h: .low_24h,
        marketCap: .market_cap,
        volume24h: .total_volume,
        ath: .ath,
        athChange: .ath_change_percentage,
        image: .image,
        lastUpdated: .last_updated
      } ],
      missing: [ $ids[] | select($byId[.] == null) ]
    }
end
