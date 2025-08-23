using JuMP
using GLPK
using Dates # for timing

# TODO: make it so the user doesn't have to manually add all these Packages with Pkg

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

struct TradeConfig
    budget::Float64 # 1 million default, in silvers
    max_weight::Float64 # 3900 default, in kg, T8 Ox + Bag + Pie
    volume_limit::Float64 # 2% default
    sell_tax::Float64 # 6.5% default, would be 4% extra for non-premium accounts
    speed::Float64 # factor, 1.0 default, T8 Ox 100% speed 
    buy_sell_duration_min::Float64 # 5 min default, how long it takes to buy/sell items when arriving in a City Market before you can leave

    function TradeConfig()
        new(1e6, 3900, 0.02, 0.065, 1.0, 5.0)
    end

    function TradeConfig(budget::Number, max_weight::Number, volume_limit::Number, sell_tax::Number, speed::Number, buy_sell_duration_min::Number)
        new(Float64(budget), Float64(max_weight), Float64(volume_limit), Float64(sell_tax), Float64(speed), Float64(buy_sell_duration_min))
    end

    function TradeConfig(budget::Number, max_weight::Number)
        cfg = TradeConfig()
        cfg.budget = Float64(budget)
        cfg.max_weight = Float64(max_weight)
        return cfg
    end
end

function to_encumbered(cfg::TradeConfig)
    return TradeConfig(cfg.budget, cfg.max_weight * 1.3, cfg.volume_limit, cfg.sell_tax, cfg.speed * 0.8, cfg.buy_sell_duration_min)
end

# Filter out items that earn below 1% or have low buy quantities
function filter_relevant_items(items, profits, x)
    min_qty = 5
    total_profit = sum(profits[item] for item in items)
    min_profit = 0.01 * total_profit
    return [item for item in items if value(x[item]) >= min_qty && profits[item] >= min_profit]
end

# 10% is how much above the historic price people are still willing to buy our items
function calc_sell_prices(item_prices, historic_prices, city, items, max_historic_factor = 1.10)
    return Dict(
        item => min(
            item_prices[city][item],
            round(historic_prices[city][item] * max_historic_factor)
        )
        for item in items
    )
end

function trade_oneway(source_city::String, dest_city::String, cfg::TradeConfig, io::IO = stdout)
    global items, weights, item_prices, historic_volumes, historic_prices

    # Extract buy and sell prices for each item
    buy_prices = Dict(item => item_prices[source_city][item] for item in items)
    sell_prices = calc_sell_prices(item_prices, historic_prices, dest_city, items)

    # Extract average volumes for each item in the source city from historic_data
    volumes_source = Dict(item => get(historic_volumes[source_city], item, 0.0) for item in items)
    volumes_dest = Dict(item => get(historic_volumes[dest_city], item, 0.0) for item in items)

    # Filter out items with buy or sell price equal to 0
    items = [item for item in items if buy_prices[item] != 0 && sell_prices[item] != 0]

    budget = cfg.budget
    max_weight = cfg.max_weight
    volume_limit = cfg.volume_limit
    sell_tax = cfg.sell_tax

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

    start_time = now()

    optimize!(model)

    end_time = now() # Finishes in 0.00 seconds flat, so we stopped printing it
    # duration = end_time - start_time
    # myprintln(stdout, "Optimizing... Solution found in ", Dates.value(duration) / 1000, " seconds")

    profits = Dict(item => (sell_prices[item] * (1 - sell_tax) - buy_prices[item]) * value(x[item]) for item in items)
    sorted_items = sort(items, by = item -> profits[item], rev = true) # sort by profits
    filtered_items = filter_relevant_items(sorted_items, profits, x)

    total_profit = sum(profits[item] for item in filtered_items)
    total_weight = sum(value(x[item]) * weights[item] for item in filtered_items)
    total_cost = sum(value(x[item]) * buy_prices[item] for item in filtered_items)
    time_required = travel_time[(source_city, dest_city)] / cfg.speed

    myprintln(io, repeat("-", 100)) # big separator
    myprintln(io, "Optimal trade quantities for $(source_city) to $(dest_city):")
    myprintln(io)
    for item in filtered_items
        qty = round(Int, value(x[item]))
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

# Three-city trade optimizer
function trade_oneway(cityA::String, cityB::String, cityC::String, cfg::TradeConfig, io::IO = stdout)
    global items, weights, item_prices, historic_volumes, historic_prices

    # println("Initiating trade from $(cityA) to $(cityB) to $(cityC)...")

    # Prices and volumes
    buy_prices_A = Dict(item => item_prices[cityA][item] for item in items)
    buy_prices_B = Dict(item => item_prices[cityB][item] for item in items)

    sell_prices_B = calc_sell_prices(item_prices, historic_prices, cityB, items)
    sell_prices_C = calc_sell_prices(item_prices, historic_prices, cityC, items)

    volumes_A = Dict(item => get(historic_volumes[cityA], item, 0.0) for item in items)
    volumes_B = Dict(item => get(historic_volumes[cityB], item, 0.0) for item in items)
    volumes_C = Dict(item => get(historic_volumes[cityC], item, 0.0) for item in items)

    # Filter out items with buy or sell price equal to 0
    items = [
        item for item in items
        if buy_prices_A[item] != 0 && sell_prices_B[item] != 0 && sell_prices_C[item] != 0
    ]

    # TODO: we dont need these 4 variables, can just use cfg.whatever
    budget = cfg.budget
    max_weight = cfg.max_weight
    volume_limit = cfg.volume_limit
    sell_tax = cfg.sell_tax

    model = Model(GLPK.Optimizer)
    set_optimizer_attribute(model, "tm_lim", 60_000)  # 1 minute

    # Decision variables
    @variable(model, x[item in items] >= 0, Int)  # buy in A, sell in B
    @variable(model, y[item in items] >= 0, Int)  # buy in A, sell in C
    @variable(model, z[item in items] >= 0, Int)  # buy in B, sell in C

    # Objective: maximize total profit
    @objective(model, Max,
        sum(x[item] * (sell_prices_B[item] * (1 - sell_tax) - buy_prices_A[item]) for item in items) +
        sum(y[item] * (sell_prices_C[item] * (1 - sell_tax) - buy_prices_A[item]) for item in items) +
        sum(z[item] * (sell_prices_C[item] * (1 - sell_tax) - buy_prices_B[item]) for item in items)
    )

    # Budget and weight constraints at city A (initial purchase)
    @constraint(model, sum((x[item] + y[item]) * buy_prices_A[item] for item in items) <= budget)
    @constraint(model, sum((x[item] + y[item]) * weights[item] for item in items) <= max_weight)
    # Volume constraints at city A
    for item in items
        @constraint(model, x[item] + y[item] <= volumes_A[item] * volume_limit)
    end

    # After selling x in B and buying z in B
    # Budget constraint at B: can only spend what you have left after buying in A
    @constraint(
        model,
        sum(z[item] * buy_prices_B[item] for item in items) <=
        budget - sum((x[item] + y[item]) * buy_prices_A[item] for item in items)
    )

    # Weight constraint at B: y (from A) + z (bought in B)
    @constraint(model, sum((y[item] + z[item]) * weights[item] for item in items) <= max_weight)
    
    # Volume constraints at B
    for item in items
        @constraint(model, z[item] <= volumes_B[item] * volume_limit)
        @constraint(model, x[item] <= volumes_B[item] * volume_limit)
    end

    # At city C: sell y and z
    # Volume constraints at C
    for item in items
        @constraint(model, y[item] + z[item] <= volumes_C[item] * volume_limit)
    end

    start_time = now()

    optimize!(model)

    end_time = now()
    # duration = end_time - start_time
    # myprintln(stdout, "Optimizing... Solution found in ", Dates.value(duration) / 1000, " seconds")

    # TODO: calculate profits, sort, filter, print nicely like in 2city trade_between

    # Print results
    myprintln(io, repeat("-", 100)) # big separator
    myprintln(io, "Optimal trade quantities for $(cityA) → $(cityB) → $(cityC):")
    myprintln(io)

    for item in items
        qty_x = round(Int, value(x[item]))
        qty_y = round(Int, value(y[item]))
        qty_z = round(Int, value(z[item]))
        if qty_x > 0 || qty_y > 0 || qty_z > 0
            myprintln(io, "$(item): AB = $(qty_x), AC = $(qty_y), BC = $(qty_z)")
        end
    end

    max_profit = objective_value(model)
    time_required = travel_time[(cityA, cityB)] / cfg.speed + cfg.buy_sell_duration_min + travel_time[(cityB, cityC)] / cfg.speed

    myprintln(io, "Maximum profit: ", max_profit)
    myprintln(io, "Time required: ", time_required)
    myprintln(io)

    return max_profit, time_required
end

# TODO: study liquidity filters

function trade_cycle(city_a::String, city_b::String, cfg::TradeConfig, io::IO = stdout)
    profit, time = trade_oneway(city_a, city_b, cfg, io) .+ trade_oneway(city_b, city_a, cfg, io)
    time += cfg.buy_sell_duration_min
    return profit, time
end

function trade_cycle(city_a::String, city_b::String, city_c::String, cfg::TradeConfig, io::IO = stdout)
    profit, time = trade_oneway(city_a, city_b, city_c, cfg, io) .+ trade_oneway(city_c, city_b, city_a, cfg, io)
    time += cfg.buy_sell_duration_min
    return profit, time
end

function cyclical_scenarios(royal_cities, start_city)
    n = length(royal_cities)
    scenarios = Vector{Vector{String}}()

    for i in 1:n
        curr = royal_cities[i]
        prev = royal_cities[mod1(i - 1, n)]
        next = royal_cities[mod1(i + 1, n)]

        if curr != start_city
            push!(scenarios, [start_city, curr])
        end

        # 2-city scenarios: current city with next and previous neighbors
        push!(scenarios, [curr, next])
        push!(scenarios, [curr, prev])

        # 3-city scenario: previous, current, next
        push!(scenarios, [prev, curr, next])
        push!(scenarios, [next, curr, prev])
    end

    # Remove duplicates and scenarios not starting at start_city
    scenarios = unique(scenarios)
    scenarios = [s for s in scenarios if s[1] == start_city]

    return scenarios
end

# TODO: add scenarios where you buy a mount, then sell it back afterwards, and calculate the loss of that
#       This will be more useful later on when we support dynamic mounts, and the optimizer to recommend which mount to use

trade_cfg = TradeConfig(2e6, 4000, 0.02, 0.065, 1.0, 5) # defaults, pretty arbitrary
trade_cfg_130 = to_encumbered(trade_cfg) # slower but more capacity, usually better

royal_cities = [Thetford, FortSterling, Lymhurst, Bridgewatch, Martlock]
start_city = Thetford

scenarios = cyclical_scenarios(royal_cities, start_city)

results = Vector{Tuple{Float64, Float64, Vector{String}}}()
nullstream = IOBuffer()

for cities in scenarios
    if cities[1] == start_city
        profit, time = trade_cycle(cities..., trade_cfg_130, nullstream)
        
        myprintln(
            "Trading scenario $(cities): ",
            profit / 1e6, " million silver profit, ", time, " minutes"
        )

        push!(results, (profit, time, cities))
    end
end

# Sort scenarios by profit per hour
sort!(results, by = x -> x[1] / x[2] * 60)
best_scenario = results[end]
best_cities = best_scenario[3]

open("best_trade_details.txt", "w") do fio
    global best_scenario

    slow_p, slow_t = best_scenario[1:2]
    # Dispatch correct trade_cfg for best scenario
    fast_p, fast_t = trade_cycle(best_cities..., trade_cfg, nullstream)
    best_cfg = TradeConfig()

    # Try both 100% and 130% of weight capacity, just in case
    if fast_p / fast_t * 60 > slow_p / slow_t * 60
        myprintln(fio, "INFO: Fast trade is better - Transport at 100% weight capacity!")
        best_cfg = trade_cfg
    else
        myprintln(fio, "INFO: Slow trade is better - Transport at 130% weight capacity!")
        best_cfg = trade_cfg_130
    end

    best_profit, best_time = trade_cycle(best_cities..., best_cfg, fio)
    best_scenario = (best_profit, best_time, best_cities)
end

myprintln("\nBest trade is between $(join(best_cities, " → ")) with profit per hour: ", best_scenario[1] / best_scenario[2] * 60 / 1e6, " million silver")
myprintln("\nBest trade details saved to file \"best_trade_details.txt\"")

return 0