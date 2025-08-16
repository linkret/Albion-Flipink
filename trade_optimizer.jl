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

# This is an approximation in minutes for a T8 Ox mount
# TODO: add const, but its throwing an annoying warning
travel_time = Dict(
    (Thetford, FortSterling) => 8,
    (Thetford, Lymhurst) => 15,
    (Thetford, Bridgewatch) => 15,
    (Thetford, Martlock) => 8,
    (Thetford, Caerleon) => 12,
    (FortSterling, Thetford) => 8,
    (FortSterling, Lymhurst) => 8,
    (FortSterling, Bridgewatch) => 15,
    (FortSterling, Martlock) => 15,
    (FortSterling, Caerleon) => 12,
    (Lymhurst, Thetford) => 15,
    (Lymhurst, Bridgewatch) => 8,
    (Lymhurst, Martlock) => 15,
    (Lymhurst, FortSterling) => 8,
    (FortSterling, Caerleon) => 12,
    (Bridgewatch, Thetford) => 15,
    (Bridgewatch, Lymhurst) => 8,
    (Bridgewatch, FortSterling) => 15,
    (Bridgewatch, Martlock) => 8,
    (Bridgewatch, Caerleon) => 12,
    (Martlock, Thetford) => 8,
    (Martlock, Lymhurst) => 15,
    (Martlock, FortSterling) => 15,
    (Martlock, Bridgewatch) => 8,
    (Martlock, Caerleon) => 12,
    (Caerleon, Thetford) => 12,
    (Caerleon, Lymhurst) => 12,
    (Caerleon, FortSterling) => 12,
    (Caerleon, Bridgewatch) => 12,
    (Caerleon, Martlock) => 12
) # Travel time is in minutes

struct trade_config
    budget::Float64 # in silvers
    max_weight::Float64 # in kg
    volume_limit::Float64 # 5% default
    sell_tax::Float64 # 6.5% default, would be 4% extra for non-premium accounts
    speed::Float64 # factor, 1.0 default

    function trade_config()
        new(1e6, 3900, 0.05, 0.065, 1.0)
    end

    function trade_config(budget::Number, max_weight::Number, volume_limit::Number, sell_tax::Number, speed::Number)
        new(Float64(budget), Float64(max_weight), Float64(volume_limit), Float64(sell_tax), Float64(speed))
    end

    function trade_config(budget::Number, max_weight::Number)
        new(budget, max_weight, 0.05, 0.065, 1.0)
    end
end

function to_encumbered(cfg::trade_config)
    return trade_config(cfg.budget, cfg.max_weight * 1.3, cfg.volume_limit, cfg.sell_tax, cfg.speed * 0.8)
end

function trade_between(source_city, dest_city, trade_config = trade_config(), io = stdout)
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

    budget = trade_config.budget
    max_weight = trade_config.max_weight
    volume_limit = trade_config.volume_limit
    sell_tax = trade_config.sell_tax

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
    total_profit = objective_value(model)
    total_weight = sum(value(x[item]) * weights[item] for item in items)
    total_cost = sum(value(x[item]) * buy_prices[item] for item in items)
    time_required = travel_time[(source_city, dest_city)] / trade_cfg.speed
    sorted_items = sort(items, by = item -> profits[item], rev = true) # sort by profits

    # For clarity we cut out the "irrelevant" items to not even bother with them
    # An item is irrelevant if we only buy a few units, or the total profit is below 1% etc.
    # TODO: extract this filter to new function
    # TODO: maybe just keep top 5 items and call it a day lol

    min_qty = 5
    min_profit = 0.01 * total_profit

    filtered_items = [item for item in sorted_items if value(x[item]) >= min_qty && profits[item] >= min_profit]
    
    myprintln(io, repeat("-", 100)) # big separator
    myprintln(io, "Optimal trade quantities for $(source_city) to $(dest_city):")
    myprintln(io)
    for item in filtered_items
        qty = value(x[item])
        profit = profits[item]
        if qty > 0
            # TODO: tiny bug with "sell at" output with Luxury goods - they're actually being quicksold to avoid the tax for a fixed, slightly different price than what is shown, but who cares
            myprintln(io, "$(item): ", qty, " units for ", profit, " profit",
                      " (buy at ", buy_prices[item], ", sell at ", sell_prices[item],
                      ", profit per unit is ", profit / qty, ")")
        end
    end

    myprintln(io)
    myprintln(io, "Maximum profit: ", total_profit)
    myprintln(io, "Profit margin: ", total_profit / total_cost * 100., "%")
    myprintln(io, "Total cost: ", total_cost)
    myprintln(io, "Total weight: ", total_weight, " / ", max_weight)
    myprintln(io, "Total time: ", time_required)
    myprintln(io)

    return objective_value(model), time_required
end

# TODO: study liquidity filters

function trade_ab(city_a, city_b, trade_cfg = trade_config(), io = stdout)
    profit, time = trade_between(city_a, city_b, trade_cfg, io) .+ trade_between(city_b, city_a, trade_cfg, io)
    time += 3 # how long to buy/sell
    return profit, time
end

function trade_abc(city_a, city_b, city_c, trade_cfg = trade_config(), io = stdout)
    # TODO: this sucks, improve it with a trade_between(a, b, c) new model
    time = travel_time[(city_a, city_b)] + 3 + travel_time[(city_b, city_c)] + 3 + travel_time[(city_c, city_a)]
    profit = (trade_between(city_a, city_b, trade_cfg, io) .+ trade_between(city_b, city_c, trade_cfg, io) + trade_between(city_c, city_a, trade_cfg, io))
    return profit, time
end

trade_cfg = trade_config(2e6, 4000, 0.05, 0.065, 1.0)
trade_cfg_130 = to_encumbered(trade_cfg) # slower but more capacity, usually better

royal_cities = [Thetford, Lymhurst, FortSterling, Martlock, Bridgewatch]
start_city = Thetford

scenarios = Vector{Tuple{Float64, Float64, String}}()

nullstream = IOBuffer()

for destination in royal_cities
    if destination != start_city
        profit, time = trade_ab(start_city, destination, trade_cfg_130, nullstream)
        myprintln(
            "Trading from $(start_city) to $(destination) and back: ",
            profit, " profit, ", time, " minutes"
        )
        push!(scenarios, (profit, time, destination))
    end
end

# Sort scenarios by profit per hour
sort!(scenarios, by = x -> x[1] / x[2] * 60)
best_scenario = scenarios[end]
best_city = best_scenario[3]

open("best_trade_details.txt", "w") do fio
    global best_scenario

    slow_p, slow_t = best_scenario[1:2]
    fast_p, fast_t = trade_ab(start_city, best_city, trade_cfg, nullstream)
    best_cfg = trade_config()

    # Try both 100% and 130% of weight capacity, just in case
    if fast_p / fast_t * 60 > slow_p / slow_t * 60
        myprintln(fio, "INFO: Fast trade is better - Transport at 100% weight capacity!")
        best_cfg = trade_cfg
    else
        myprintln(fio, "INFO: Slow trade is better - Transport at 130% weight capacity!")
        best_cfg = trade_cfg_130
    end

    best_profit, best_time = trade_ab(start_city, best_city, best_cfg, fio)
    best_scenario = (best_profit, best_time, best_city)
end

myprintln("\nBest trade is between $(start_city) and $(best_city) with profit per hour: ", best_scenario[1] / best_scenario[2] * 60)

return 0