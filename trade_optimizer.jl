using JuMP
using GLPK

include("market_data.jl")
include("item_list.jl")
include("myprintln.jl")

# TODO: this script shouldn't be included by other files until we put all the top-level code in functions

# Load real market data
items, weights = generate_items() 
item_prices, historic_volumes, historic_prices = get_data_online()
# TODO: check cmd argument to determine online or offline, we have get_data_local() too

items = split(items, ",")
items = [strip(item) for item in items]

# TODO: extract global constants to seperate header
const Thetford = "Thetford"
const FortSterling = "Fort Sterling"
const Lymhurst = "Lymhurst"
const Bridgewatch = "Bridgewatch"
const Martlock = "Martlock"
const Caerleon = "Caerleon"
const Brecelean = "Brecilien"

# TODO: make everything const in the whole project - helps the compiler precompile types much better

# TODO: Add other distances
const travel_time = Dict(
    (Thetford, FortSterling) => 8,
    (Thetford, Lymhurst) => 15,
    (Thetford, Bridgewatch) => 15,
    (Thetford, Martlock) => 8,
    # (Thetford, Caerleon) => 12,
    (FortSterling, Thetford) => 8,
    (FortSterling, Lymhurst) => 8,
    (FortSterling, Bridgewatch) => 15,
    (FortSterling, Martlock) => 15,
    # (FortSterling, Caerleon) => 12,
    (Lymhurst, Thetford) => 15,
    (Lymhurst, Bridgewatch) => 8,
    (Lymhurst, Martlock) => 15,
    (Lymhurst, FortSterling) => 8
    # (FortSterling, Caerleon) => 12,
)

function trade_between(source_city, dest_city)
    global items, weights, item_prices, historic_volumes, historic_prices

    # Extract buy and sell prices for each item
    buy_prices = Dict(item => item_prices[source_city][item] for item in items)
    max_historic_factor = 1.10 # how much percent above the historic price will people still be willing to buy the items ?
    sell_prices = Dict(
        item => min(
            item_prices[dest_city][item],
            round(historic_prices[dest_city][item] * max_historic_factor)
        )
        for item in items
    )

    # Extract average volumes for each item in the source city from historic_data
    volumes_source = Dict(item => get(historic_volumes[source_city], item, 0.0) for item in items)
    volumes_dest = Dict(item => get(historic_volumes[dest_city], item, 0.0) for item in items)

    # Filter out items with buy or sell price equal to 0
    items = [item for item in items if buy_prices[item] != 0 && sell_prices[item] != 0]

    budget = 2e6
    max_weight = 3900 # kg
    volume_limit = 0.05  # 5%
    sell_tax = 0.065 # 6.5% sales tax, would be 4% extra for non-premium accounts

    model = Model(GLPK.Optimizer)
    set_optimizer_attribute(model, "tm_lim", 60_000)  # Time limit in milliseconds (1 minute)

    # Decision variables: how many units of each item to trade
    @variable(model, x[item in items] >= 0, Int)

    # TODO: can also add selling to fullfill Buy Orders here. This is rarely better, but is only taxed 4%,
    #       and can be done instantly without waiting for the Sell Order to complete. Worth investigating

    # Objective: maximize profit
    @objective(model, Max, sum(x[item] * (sell_prices[item] * (1 - sell_tax) - buy_prices[item]) for item in items))

    # Budget constraint
    @constraint(model, sum(x[item] * buy_prices[item] for item in items) <= budget)

    # Weight constraint
    @constraint(model, sum(x[item] * weights[item] for item in items) <= max_weight)

    # Volume constraints - dont buy/sell more than 5% of the market (both source and destination)
    for item in items
        @constraint(model, x[item] <= min(volumes_source[item], volumes_dest[item]) * volume_limit)
    end

    optimize!(model)

    profits = Dict(item => (sell_prices[item] * (1 - sell_tax) - buy_prices[item]) * value(x[item]) for item in items)
    total_weight = sum(value(x[item]) * weights[item] for item in items)
    total_cost = sum(value(x[item]) * buy_prices[item] for item in items)
    sorted_items = sort(items, by = item -> profits[item], rev = true) # sort by profits

    # TODO: maybe cut out the "irrelevant" items to not even bother with them

    myprintln("Optimal trade quantities for $(source_city) to $(dest_city):\n")
    for item in sorted_items
        qty = value(x[item])
        profit = profits[item]
        if qty > 0
            # TODO: tiny bug with "sell at" output with Luxury goods - they're actually being quicksold to avoid the tax for a fixed, slightly different price than what is shown, but who cares
            myprintln("$(item): ", qty, " units for ", profit, " profit",
                      " (buy at ", buy_prices[item], ", sell at ", sell_prices[item],
                      ", profit per unit is ", profit / qty, ")")
        end
    end

    myprintln()
    myprintln("Maximum profit: ", objective_value(model))
    myprintln("Profit margin: ", objective_value(model) / total_cost * 100., "%")
    myprintln("Total cost: ", total_cost)
    myprintln("Total weight: ", total_weight, " / ", max_weight)
    myprintln()

    return objective_value(model)
end

# TODO: study liquidity filters

function trade_ab(city_a, city_b)
    time = travel_time[(city_a, city_b)] + 3 + travel_time[(city_b, city_a)]
    profit = (trade_between(city_a, city_b) + trade_between(city_b, city_a))
    return profit, time
end

function trade_abc(city_a, city_b, city_c)
    # TODO: this sucks, improve it with a trade_between(a, b, c) new model
    time = travel_time[(city_a, city_b)] + 3 + travel_time[(city_b, city_c)] + 3 + travel_time[(city_c, city_a)]
    profit = (trade_between(city_a, city_b) + trade_between(city_b, city_c) + trade_between(city_c, city_a))
    return profit, time
end

tf_ly, tf_ly_time = trade_ab(Thetford, Lymhurst)
tf_fs, tf_fs_time = trade_ab(Thetford, FortSterling)
# tf_lyfs, tf_lyfs_time = trade_abc(Thetford, Lymhurst, FortSterling)
tf_lyfs, tf_lyfs_time = 0, 1

tf_ly_profit_per_hour = tf_ly / tf_ly_time * 60
tf_fs_profit_per_hour = tf_fs / tf_fs_time * 60
tf_lyfs_profit_per_hour = tf_lyfs / tf_lyfs_time * 60

if tf_ly_profit_per_hour > tf_fs_profit_per_hour
    if tf_ly_profit_per_hour > tf_lyfs_profit_per_hour
        myprintln("Trade from Thetford to Lymhurst is the most profitable: ", tf_ly_profit_per_hour, " profit/hour")
    else
        myprintln("Trade from Thetford to Lymhurst and then to Fort Sterling is the most profitable: ", tf_lyfs_profit_per_hour, " profit/hour")
    end
else
    if tf_fs_profit_per_hour > tf_lyfs_profit_per_hour
        myprintln("Trade from Thetford to Fort Sterling is the most profitable: ", tf_fs_profit_per_hour, " profit/hour")
    else
        myprintln("Trade from Thetford to Fort Sterling and then to Lymhurst is the most profitable: ", tf_lyfs_profit_per_hour, " profit/hour")
    end
end

return 0