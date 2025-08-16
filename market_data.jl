using HTTP
using JSON
using Statistics
using Dates
using DataStructures: OrderedDict

include("item_list.jl")  # this file contains the generate_items function

function calculate_avg_volume(data)
    # Calculate the average volume from the historical data
    if isempty(data)
        return 0.0
    end

    volumes = [item["item_count"] for item in data if haskey(item, "item_count")]
    
    if isempty(volumes)
        return 0.0
    end

    return mean(volumes)
end

function calculate_avg_price(data)
    # Calculate the average price from the historical data
    if isempty(data)
        return 0.0
    end

    total_weight = sum(item["item_count"] for item in data if haskey(item, "item_count") && haskey(item, "avg_price"))
    if total_weight == 0
        return 0.0
    end

    weighted_sum = sum(item["avg_price"] * item["item_count"] for item in data if haskey(item, "avg_price") && haskey(item, "item_count"))
    return weighted_sum / total_weight
end

function fetch_data(itemList::String, locations::String)
    format = "json"
    api_base_url = "https://europe.albion-online-data.com"

    # API endpoint for fetching prices
    price_endpoint = "/api/v2/stats/Prices/$(itemList).$(format)?locations=$(locations)"
    
    # For historical data, to approximate the volume we can buy and sell
    time_scale = "24" # 24 hours - daily trading # TODO: try hourly, it should work even better
    time_span = Dates.Day(7)
    today = Dates.now()
    one_week_ago = today - time_span
    date_str = Dates.format(one_week_ago, "yyyy-mm-ddTHH:MM:SSZ")
    end_date_str = Dates.format(today, "yyyy-mm-ddTHH:MM:SSZ")
    historic_endpoint = "/api/v2/stats/History/$(itemList).$(format)?locations=$(locations)&time-scale=$(time_scale)&date=$(date_str)&end_date=$(end_date_str)"

    price_url = "$(api_base_url)$(price_endpoint)"
    historic_url = "$(api_base_url)$(historic_endpoint)"

    response = HTTP.get(price_url)
    price_data = JSON.parse(String(response.body))

    # Filter the data to include only specific fields
    price_data = [
        Dict(
            "item_id" => item["item_id"],
            # "quality" => item["quality"], # Would only be useful for equipment items, which we probably won't use
            "price" => haskey(item, "sell_price_min") ? item["sell_price_min"] : 0,
            "city" => item["city"]
        )
        for item in price_data
    ]

    # Transform the data to be accesed as price[city][item_id]
    transformed_data = Dict{String, Dict{String, Float64}}()

    for item in price_data
        # println("Processing item: ", item["item_id"], " in city: ", item["city"], " with price: ", item["price"])
        city = item["city"]
        item_id = item["item_id"]
        price = item["price"]

        if !haskey(transformed_data, city)
            transformed_data[city] = Dict{String, Float64}()
        end

        if !haskey(transformed_data[city], item_id)
            transformed_data[city][item_id] = price
        elseif price != 0
            if transformed_data[city][item_id] != 0.0
                error("Duplicate item found: $(item_id) in city $(city) with different prices: $(transformed_data[city][item_id]) and $(price)")
            end

            transformed_data[city][item_id] = price
        end
    end

    price_data = copy(transformed_data)
    update_hardcoded_prices!(price_data) # for Luxury Goods
                
    # Print the price_data
    # println("Prices:\n", price_data)

    # Fetch historical data if needed
    historic_response = HTTP.get(historic_url)
    historic_data = JSON.parse(String(historic_response.body))

    # println("Historic data:\n", historic_data)

    # Filter the data to include only specific fields
    historic_data = [
        Dict(
            "item_id" => item["item_id"],
            # "quality" => item["quality"], # Would only be useful for equipment items, which we probably won't use
            "city" => item["location"],
            "avg_volume" => calculate_avg_volume(item["data"]),
            "avg_price" => calculate_avg_price(item["data"])
        )
        for item in historic_data
    ]

    historic_volumes = Dict{String, Dict{String, Float64}}()
    historic_prices = Dict{String, Dict{String, Float64}}()

    for item in historic_data
        item_id = item["item_id"]
        city = item["city"]
        avg_volume = item["avg_volume"]
        avg_price = item["avg_price"] # TODO: use it 

        if !haskey(historic_volumes, city)
            historic_volumes[city] = Dict{String, Float64}()
            historic_prices[city] = Dict{String, Float64}()
        end

        historic_volumes[city][item_id] = avg_volume
        historic_prices[city][item_id] = avg_price
    end

    # Set default volume to 0 for every (city, item) tuple in price_data
    for (city, items) in price_data
        if !haskey(historic_volumes, city)
            historic_volumes[city] = Dict{String, Float64}()
            historic_prices[city] = Dict{String, Float64}()
        end

        for item_id in keys(items)
            if !haskey(historic_volumes[city], item_id)
                historic_volumes[city][item_id] = 0.0
                historic_prices[city][item_id] = 0.0
            end
        end
    end

    final_historic_volumes = copy(historic_volumes)
    final_historic_prices = copy(historic_prices)

    return price_data, final_historic_volumes, final_historic_prices
end

function update_hardcoded_prices!(price_data)
    home_city = Dict(
        "KNOWLEDGE" => "Martlock",
        "CEREMONIAL" => "Thetford",
        "SILVERWARE" => "Lymhurst",
        "DECORATIVE" => "Fort Sterling",
        "TRIBAL" => "Bridgewatch",
        "RITUAL" => "Caerleon"
    )

    sell_prices = [1000.0, 5000.0, 25000.0]

    # We add 6.5 percent but subtract 4 percent to artificially alter the tax.
    # These Luxury Items are sold using Quicksell for only 4% tax, but our "trade_optimizer.jl"
    # assumes we're using Sell Orders with a fixed 6.5% tax rate.

    for (item, city) in home_city
        for rarity in 1:3
            item_id = "TREASURE_$(item)_RARITY$(rarity)"
            if haskey(price_data, city) && haskey(price_data[city], item_id)
                price = sell_prices[rarity]
                # Apply the tax adjustments
                # TODO: make this 6.5% tax globally configurable
                price *= (1 - 0.04) # Apply 4% tax to sell_price
                price /= (1 - 0.065) # Apply -6.5% tax to offset trade_optimizer's tax
                price_data[city][item_id] = price
            end
        end
    end

    return
end

# will also save the data locally to reuse it later if needed
function get_data_online()
    itemList, weights = generate_items()
    
    # TODO: dont hardcore locations
    locations = "Thetford,Lymhurst,Fort%20Sterling,Martlock,Bridgewatch,Caerleon" # %20 is a space used in URLs
    current_prices, historic_volumes, historic_prices = fetch_data(itemList, locations)

    if length(current_prices) != length(historic_volumes)
        error("Price data and historic data have different lengths!")
    end

    # save data to files
    open("data/current_prices.json", "w") do file
        JSON.print(file, current_prices, 2)
    end

    open("data/historic_volumes.json", "w") do file
        JSON.print(file, historic_volumes, 2)
    end

    open("data/historic_prices.json", "w") do file
        JSON.print(file, historic_prices, 2)
    end

    return current_prices, historic_volumes, historic_prices
end

function assert_file_exists(filename)
    if !isfile(filename)
        error("Required data file '$(filename)' does not exist. Please run get_data_online() first.")
    end
end

function get_data_local()
    assert_file_exists("data/current_prices.json")
    assert_file_exists("data/historic_volumes.json")
    assert_file_exists("data/historic_prices.json")

    # Read the data from the files
    current_prices = JSON.parsefile("data/current_prices.json")
    historic_volumes = JSON.parsefile("data/historic_volumes.json")
    historic_prices = JSON.parsefile("data/historic_prices.json")

    return current_prices, historic_volumes, historic_prices
end

# get_data_online() # Uncomment to fetch data online
# current_prices, historic_volumes, historic_prices = get_data_local()


